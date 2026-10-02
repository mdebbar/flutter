// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert' show json, utf8;
import 'dart:io' as io;

import 'browser.dart';
import 'process_diagnostics.dart';

/// Logs what is needed to diagnose a web benchmark run that stalls when the
/// page reloads between two benchmarks.
///
/// Lines are tagged and stamped with the seconds since the clock started:
///
///  * `[DIAG/RES]`: process, system, and socket resources at every page load,
///    and the peak number of file descriptors while the page loaded. Shows
///    trends (for example, file descriptors growing with each reload).
///  * `[DIAG/PAGE]`: how the page booted (DDC loader retries, load timings,
///    document and DOM node counts) at every page load.
///  * `[DIAG/STALL]`: a detailed dump once no `/next-benchmark` request arrives
///    soon enough after a `/profile-data` request (or no request arrives at
///    all for a long time), repeated every minute: page and loader state,
///    process and system resources, and probes that show whether the page, a
///    fresh tab, and the app server can still load resources.
///
/// This only logs. It never changes the state of the benchmark run, except for
/// opening and closing a probe tab after a stall was detected.
class WebBenchmarkDiagnostics {
  WebBenchmarkDiagnostics({
    required this.clock,
    required this.sampler,
    required this.getChrome,
    required this.getFlutterRunExitCode,
    required this.appUrl,
    required this.browserDebugPort,
  });

  /// The time since the start of the run.
  final Stopwatch clock;

  final ProcessResourceSampler sampler;

  /// Returns the connection to the browser, or null while it is not connected.
  final Chrome? Function() getChrome;

  /// Returns the exit code of `flutter run`, or null while it is running.
  final int? Function() getFlutterRunExitCode;

  /// The URL of the server that serves the app to the browser.
  final Uri appUrl;

  final int browserDebugPort;

  /// A page reload takes a few seconds when healthy.
  static const Duration _reloadStallThreshold = Duration(seconds: 45);

  /// The longest benchmark takes a little over two minutes, during which the
  /// app only sends the occasional request.
  static const Duration _idleThreshold = Duration(minutes: 4);

  static const Duration _checkInterval = Duration(seconds: 5);

  /// How often file descriptors are counted while a page reloads.
  static const Duration _peakSampleInterval = Duration(milliseconds: 500);
  static const Duration _dumpInterval = Duration(seconds: 60);

  /// Only the first dumps are detailed. Later ones are a single line.
  static const int _maxDetailedDumps = 6;

  String _lastRequest = 'none';
  Duration _lastRequestAt = Duration.zero;

  /// Whether a `/profile-data` request arrived, but no `/next-benchmark`
  /// request has followed yet.
  bool _awaitingNextBenchmark = false;
  Duration _profileDataAt = Duration.zero;

  String _lastBenchmark = 'none';
  int _launches = 0;
  int _totalBenchmarks = 0;

  Timer? _watchdog;
  Timer? _peakSampler;
  bool _dumping = false;
  Duration _lastDumpAt = -_dumpInterval;
  int _dumps = 0;

  /// Starts watching for stalls.
  void start() {
    _lastRequestAt = clock.elapsed;
    _watchdog = Timer.periodic(_checkInterval, (_) => unawaited(_check()));
    // Only while the page reloads, so that benchmarks run undisturbed.
    _peakSampler = Timer.periodic(_peakSampleInterval, (_) {
      if (_awaitingNextBenchmark) {
        sampler.samplePeaks();
      }
    });
  }

  /// Stops watching for stalls.
  void stop() {
    _watchdog?.cancel();
    _watchdog = null;
    _peakSampler?.cancel();
    _peakSampler = null;
  }

  /// Records a request from the app to the benchmark server.
  void onRequest(String path) {
    _lastRequest = path;
    _lastRequestAt = clock.elapsed;
  }

  /// Records that the benchmark [benchmarkName] finished, after which the app
  /// reloads the page to run the next one.
  void onProfileData(String benchmarkName) {
    _awaitingNextBenchmark = true;
    _profileDataAt = clock.elapsed;
    _lastBenchmark = benchmarkName;
  }

  /// Logs the state of the machine and the page right after the page loaded to
  /// run [benchmarkName], before the benchmark starts.
  ///
  /// Never throws.
  Future<void> onNextBenchmark({
    required Chrome chrome,
    required int totalBenchmarks,
    required String benchmarkName,
  }) async {
    final Duration now = clock.elapsed;
    final String reloadSeconds = _awaitingNextBenchmark ? _seconds(now - _profileDataAt) : 'n/a';
    _awaitingNextBenchmark = false;
    _launches++;
    _totalBenchmarks = totalBenchmarks;
    _lastBenchmark = benchmarkName;
    final benchmark = '#$_launches/$totalBenchmarks "$benchmarkName"';
    final String peaks = sampler.takePeaks();
    _log('RES', '$benchmark reload=${reloadSeconds}s $peaks ${sampler.summarize()}');
    await _logDescription(
      'PAGE',
      '$benchmark boot',
      chrome.describeBoot,
      timeout: const Duration(seconds: 20),
    );
  }

  Future<void> _check() async {
    if (_dumping) {
      return;
    }
    final Duration now = clock.elapsed;
    final bool reloadStalled =
        _awaitingNextBenchmark && now - _profileDataAt >= _reloadStallThreshold;
    final bool idle = now - _lastRequestAt >= _idleThreshold;
    if (!reloadStalled && !idle) {
      return;
    }
    if (now - _lastDumpAt < _dumpInterval) {
      return;
    }
    _dumping = true;
    try {
      final reason = reloadStalled
          ? 'no /next-benchmark request ${_seconds(now - _profileDataAt)}s after the '
                '/profile-data request of "$_lastBenchmark"'
          : 'no request from the app for ${_seconds(now - _lastRequestAt)}s';
      await _dump(reason);
    } on Object catch (error, stackTrace) {
      _log('STALL', 'Failed to dump the diagnostics: $error\n$stackTrace');
    } finally {
      _lastDumpAt = clock.elapsed;
      _dumping = false;
    }
  }

  Future<void> _dump(String reason) async {
    _dumps++;
    final Chrome? chrome = getChrome();
    final int? flutterRunExitCode = getFlutterRunExitCode();
    _log(
      'STALL',
      'dump #$_dumps: $reason. Last request: $_lastRequest '
          '(${_seconds(clock.elapsed - _lastRequestAt)}s ago). '
          'Launched $_launches of $_totalBenchmarks benchmarks. '
          'flutter run: ${flutterRunExitCode == null ? 'running' : 'exited with code $flutterRunExitCode'}.',
    );
    if (_dumps > _maxDetailedDumps) {
      return;
    }
    var pageResponds = false;
    if (chrome == null) {
      _log('STALL', 'Chrome is not connected.');
    } else {
      pageResponds = await chrome.isResponsive(timeout: const Duration(seconds: 5));
      if (pageResponds) {
        await _logDescription(
          'STALL',
          'page',
          chrome.describeState,
          timeout: const Duration(seconds: 30),
        );
        await _logDescription(
          'STALL',
          'renderer memory',
          chrome.describeMemory,
          timeout: const Duration(seconds: 15),
        );
      } else {
        _log(
          'STALL',
          'The page does not answer Runtime.evaluate within 5s: its renderer main thread is '
              'blocked, or a navigation has started but not committed.',
        );
      }
      _log('STALL', 'page log counts: ${chrome.describePageLogCounts()}');
    }
    sampler.describe().forEach((String line) => _log('STALL', line));
    await _logDescription(
      'STALL',
      'browser targets',
      _describeBrowserTargets,
      timeout: const Duration(seconds: 15),
    );
    await _logDescription(
      'STALL',
      'app server probe',
      _probeAppServer,
      timeout: const Duration(seconds: 15),
    );
    if (chrome != null) {
      if (pageResponds) {
        await _logDescription(
          'STALL',
          'page fetch probe',
          () => chrome.probePageFetch(appUrl.resolve('/index.html')),
          timeout: const Duration(seconds: 30),
        );
      }
      await _logDescription(
        'STALL',
        'fresh tab probe',
        () => Chrome.probeFreshTab(
          debugPort: browserDebugPort,
          fetchUrl: appUrl.resolve('/index.html'),
          describeProcesses: sampler.summarize,
        ),
        timeout: const Duration(seconds: 60),
      );
    }
  }

  Future<String> _describeBrowserTargets() async {
    final client = io.HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final Map<String, dynamic> version = await _getJson<Map<String, dynamic>>(
        client,
        Uri.parse('http://localhost:$browserDebugPort/json/version'),
      );
      final List<dynamic> targets = await _getJson<List<dynamic>>(
        client,
        Uri.parse('http://localhost:$browserDebugPort/json/list'),
      );
      final String described = targets
          .map((dynamic target) {
            final map = target as Map<String, dynamic>;
            return '${map['type']} ${map['url']}';
          })
          .join(', ');
      return '${version['Browser']}; ${targets.length} targets: [$described]';
    } finally {
      client.close(force: true);
    }
  }

  static Future<T> _getJson<T extends Object>(io.HttpClient client, Uri uri) async {
    final io.HttpClientRequest request = await client.getUrl(uri);
    final io.HttpClientResponse response = await request.close();
    return json.decode(await utf8.decodeStream(response)) as T;
  }

  /// Requests the app's `index.html` from outside the browser, to show whether
  /// the server that serves the app still responds.
  Future<String> _probeAppServer() async {
    final client = io.HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final stopwatch = Stopwatch()..start();
    try {
      final io.HttpClientRequest request = await client.getUrl(appUrl.resolve('/index.html'));
      final io.HttpClientResponse response = await request.close();
      final int bytes = await response.fold<int>(
        0,
        (int total, List<int> chunk) => total + chunk.length,
      );
      return 'GET /index.html returned ${response.statusCode} with $bytes bytes '
          'in ${stopwatch.elapsedMilliseconds}ms';
    } finally {
      client.close(force: true);
    }
  }

  /// Logs the result of [describe], or the error it fails or times out with.
  Future<void> _logDescription(
    String tag,
    String label,
    Future<String> Function() describe, {
    required Duration timeout,
  }) async {
    try {
      _log(tag, '$label: ${await describe().timeout(timeout)}');
    } on Object catch (error) {
      _log(tag, '$label failed: $error');
    }
  }

  void _log(String tag, String message) {
    final String timestamp = _seconds(clock.elapsed);
    for (final String line in message.split('\n')) {
      print('[DIAG/$tag] t=${timestamp}s $line');
    }
  }

  static String _seconds(Duration duration) => (duration.inMilliseconds / 1000).toStringAsFixed(1);
}
