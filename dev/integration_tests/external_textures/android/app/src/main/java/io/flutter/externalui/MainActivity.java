// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.externalui;

import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.SurfaceTexture;
import android.os.Build;
import android.os.Bundle;
import android.os.Debug;
import android.os.Process;
import android.util.Log;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.View;
import androidx.annotation.NonNull;

import java.util.Locale;
import java.util.Timer;
import java.util.TimerTask;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.android.FlutterSurfaceView;
import io.flutter.embedding.android.FlutterView;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.view.TextureRegistry;
import io.flutter.view.TextureRegistry.SurfaceTextureEntry;
import io.flutter.plugins.GeneratedPluginRegistrant;

public class MainActivity extends FlutterActivity {
  private Surface surface;
  private SurfaceTexture texture;
  private Timer producerTimer;
  private Timer consumerTimer;
  private long startTime;
  private long endTime;
  private int lastTargetFps;
  private AtomicInteger framesProduced = new AtomicInteger(0);
  private AtomicInteger framesConsumed = new AtomicInteger(0);
  private AtomicInteger producerTicks = new AtomicInteger(0);
  private AtomicInteger skippedByCap = new AtomicInteger(0);
  private AtomicInteger skippedZeroElapsed = new AtomicInteger(0);
  private AtomicInteger consumerTicks = new AtomicInteger(0);
  private AtomicLong drawTotalNs = new AtomicLong(0);
  private AtomicLong drawMaxNs = new AtomicLong(0);
  private FrameRenderer lastRenderer;
  private volatile long producerMaxLagMs;
  private volatile long producerLastLagMs;
  private volatile int producerLateTicks;
  private volatile long tickBodyTotalNs;
  private volatile long consumerMaxLagMs;
  private long procCpuStartMs;

  @Override
  public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    final MethodChannel channel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "texture");
    channel.setMethodCallHandler(new MethodCallHandler() {
      @Override
      public void onMethodCall(MethodCall methodCall, Result result) {
        switch (methodCall.method) {
          case "start":
            framesProduced.set(0);
            framesConsumed.set(0);
            producerTicks.set(0);
            skippedByCap.set(0);
            skippedZeroElapsed.set(0);
            consumerTicks.set(0);
            drawTotalNs.set(0);
            drawMaxNs.set(0);
            final int fps = methodCall.arguments();
            lastTargetFps = fps;
            final FrameRenderer renderer = new FrameRenderer(surface);
            lastRenderer = renderer;
            producerMaxLagMs = 0;
            producerLastLagMs = 0;
            producerLateTicks = 0;
            tickBodyTotalNs = 0;
            consumerMaxLagMs = 0;
            procCpuStartMs = Process.getElapsedCpuTime();
            producerTimer = new Timer();
            producerTimer.scheduleAtFixedRate(new TimerTask() {
              @Override
              public void run() {
                final long tickStartNs = System.nanoTime();
                producerTicks.incrementAndGet();
                final long time = System.currentTimeMillis();
                // Timer backlog: how far behind its fixed-rate schedule this tick runs.
                final long lag = time - scheduledExecutionTime();
                producerLastLagMs = lag;
                producerMaxLagMs = Math.max(producerMaxLagMs, lag);
                if (lag >= 1000 / fps) {
                  producerLateTicks++;
                }
                if (time <= startTime) {
                  skippedZeroElapsed.incrementAndGet();
                }
                if (frameRate(framesProduced, startTime, time) < fps) {
                  final long t0 = System.nanoTime();
                  renderer.drawFrame();
                  final long dt = System.nanoTime() - t0;
                  drawTotalNs.addAndGet(dt);
                  long prevMax;
                  while (dt > (prevMax = drawMaxNs.get()) && !drawMaxNs.compareAndSet(prevMax, dt)) {}
                  framesProduced.incrementAndGet();
                } else {
                  skippedByCap.incrementAndGet();
                }
                tickBodyTotalNs += System.nanoTime() - tickStartNs;
              }
            }, 0, 1000 / fps);
            consumerTimer = new Timer();
            consumerTimer.scheduleAtFixedRate(new TimerTask() {
              private long lastTimestamp = -1L;

              @Override
              public void run() {
                consumerTicks.incrementAndGet();
                consumerMaxLagMs = Math.max(consumerMaxLagMs, System.currentTimeMillis() - scheduledExecutionTime());
                final long timestamp = texture.getTimestamp();
                // The texture's timestamp is updated on consumption.
                // We detect the change by asking very frequently.
                if (timestamp != lastTimestamp) {
                  lastTimestamp = timestamp;
                  framesConsumed.incrementAndGet();
                }
              }
            }, 0, 1);
            startTime = System.currentTimeMillis();
            result.success(null);
            break;
          case "stop":
            producerTimer.cancel();
            consumerTimer.cancel();
            endTime = System.currentTimeMillis();
            final long elapsedMs = endTime - startTime;
            final int produced = framesProduced.get();
            final double drawTotalMs = drawTotalNs.get() / 1_000_000.0;
            final double drawMeanMs = produced > 0 ? drawTotalMs / produced : 0.0;
            final double drawMaxMs = drawMaxNs.get() / 1_000_000.0;
            Log.i("flutter", String.format(
                Locale.US,
                "[DEFLAKE_STATS] targetFps=%d periodMs=%d elapsedMs=%d producerTicks=%d "
                    + "produced=%d skippedByCap=%d skippedZeroElapsed=%d producedFps=%.2f "
                    + "unthrottledTickFps=%.2f drawMeanMs=%.2f drawMaxMs=%.2f drawTotalMs=%.1f "
                    + "consumerTicks=%d consumed=%d consumedFps=%.2f",
                lastTargetFps, 1000 / lastTargetFps, elapsedMs, producerTicks.get(),
                produced, skippedByCap.get(), skippedZeroElapsed.get(),
                frameRate(framesProduced, startTime, endTime),
                producerTicks.get() * 1000.0 / (double) elapsedMs,
                drawMeanMs, drawMaxMs, drawTotalMs,
                consumerTicks.get(), framesConsumed.get(),
                frameRate(framesConsumed, startTime, endTime)));
            final FrameRenderer r = lastRenderer;
            final double n = Math.max(1, r.frames);
            Log.i("flutter", String.format(
                Locale.US,
                "[DEFLAKE_STATS2] canvas=%s targetFps=%d nproc=%d procCpuMs=%d elapsedMs=%d tickBodyTotalMs=%.1f "
                    + "producerMaxLagMs=%d producerLastLagMs=%d producerLateTicks=%d consumerMaxLagMs=%d "
                    + "frames=%d lockMeanMs=%.2f lockCpuMeanMs=%.2f lockMaxMs=%.2f drawMeanMs=%.2f "
                    + "drawCpuMeanMs=%.2f postMeanMs=%.2f postCpuMeanMs=%.2f postMaxMs=%.2f "
                    + "framesOver16ms=%d",
                "hw", lastTargetFps, Runtime.getRuntime().availableProcessors(),
                Process.getElapsedCpuTime() - procCpuStartMs, elapsedMs, tickBodyTotalNs / 1e6,
                producerMaxLagMs, producerLastLagMs, producerLateTicks, consumerMaxLagMs,
                r.frames, r.lockNs / n / 1e6, r.lockCpuNs / n / 1e6, r.lockMaxNs / 1e6,
                r.drawNs / n / 1e6, r.drawCpuNs / n / 1e6, r.postNs / n / 1e6,
                r.postCpuNs / n / 1e6, r.postMaxNs / 1e6, r.framesOver16ms));
            result.success(null);
            break;
          case "getProducedFrameRate":
            result.success(frameRate(framesProduced, startTime, endTime));
            break;
          case "getConsumedFrameRate":
            result.success(frameRate(framesConsumed, startTime, endTime));
            break;
          default: result.notImplemented();
        }
      }
    });
  }

  @Override
  public void onFlutterSurfaceViewCreated(@NonNull FlutterSurfaceView flutterSurfaceView) {
    flutterSurfaceView.getHolder().addCallback(new SurfaceHolder.Callback() {
      @Override
      public void surfaceCreated(SurfaceHolder holder) {
        final SurfaceTextureEntry textureEntry = flutterSurfaceView.getAttachedRenderer().createSurfaceTexture();
        texture = textureEntry.surfaceTexture();
        texture.setDefaultBufferSize(300, 200);
        surface = new Surface(texture);
      }

      @Override
      public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
      }

      @Override
      public void surfaceDestroyed(SurfaceHolder holder) {
      }
    });
  }

  double frameRate(AtomicInteger frameCounter, long startTime, long endTime) {
    return frameCounter.get() * 1000 / (double) (endTime - startTime);
  }

  @Override
  protected void onDestroy() {
    if (surface != null) {
      surface.release();
    }
    super.onDestroy();
  }
}

class FrameRenderer {
  private final Surface surface;
  private final Paint paint;
  private int frameCount = 0;
  // Diagnostic per-segment wall/thread-CPU totals (written on the producer timer thread only).
  volatile long frames, lockNs, lockCpuNs, lockMaxNs, drawNs, drawCpuNs, postNs, postCpuNs, postMaxNs, framesOver16ms;

  FrameRenderer(Surface surface) {
    this.surface = surface;
    this.paint = new Paint();
    paint.setColor(0xffff0000);
    paint.setTextSize(48.0f);
    paint.setAntiAlias(true);
  }

  void drawFrame() {
    final long c0 = Debug.threadCpuTimeNanos();
    final long t0 = System.nanoTime();
    final Canvas canvas = surface.lockHardwareCanvas();
    final long c1 = Debug.threadCpuTimeNanos();
    final long t1 = System.nanoTime();
    canvas.drawColor(0xff000000);
    canvas.drawText(String.valueOf(++frameCount), 20, 120, paint);
    final long c2 = Debug.threadCpuTimeNanos();
    final long t2 = System.nanoTime();
    surface.unlockCanvasAndPost(canvas);
    final long c3 = Debug.threadCpuTimeNanos();
    final long t3 = System.nanoTime();
    frames++;
    lockNs += t1 - t0;
    lockCpuNs += c1 - c0;
    lockMaxNs = Math.max(lockMaxNs, t1 - t0);
    drawNs += t2 - t1;
    drawCpuNs += c2 - c1;
    postNs += t3 - t2;
    postCpuNs += c3 - c2;
    postMaxNs = Math.max(postMaxNs, t3 - t2);
    if (t3 - t0 > 16_000_000L) {
      framesOver16ms++;
    }
  }
}
