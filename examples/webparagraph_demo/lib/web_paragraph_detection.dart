import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

bool isWebParagraphEnabled() {
  try {
    // Check if CodeUnits API is present in the loaded CanvasKit.
    // This is the most reliable way to know if the correct variant is actually running.
    final canvaskit = window['flutterCanvasKit'] as JSObject?;
    if (canvaskit != null && canvaskit.has('CodeUnits')) {
      return true;
    }
  } catch (e) {
    // Ignore errors in detection
  }

  return false;
}

bool browserSupportsTextClusters() {
  try {
    final canvas = HTMLCanvasElement();
    final ctx = canvas.context2D;
    // The Text Clusters API is currently experimental and might be behind a flag
    // or under a different name, but 'getTextClusters' is the spec name.
    final metrics = ctx.measureText('a');
    return metrics['getTextClusters'] != null;
  } catch (e) {
    return false;
  }
}
