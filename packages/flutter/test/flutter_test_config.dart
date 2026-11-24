// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

import '_goldens_io.dart' if (dart.library.js_interop) '_goldens_web.dart' as flutter_goldens;

/// If true, leak tracking is enabled for all `testWidgets`.
///
/// By default it is false.
/// To enable the leak tracking, either pass the compilation flag
/// `--dart-define LEAK_TRACKING=true` or invoke `export LEAK_TRACKING=true`.
///
/// On the web only `--dart-define LEAK_TRACKING=true` is supported because
/// `Platform.environment` is unavailable in the browser.
///
/// See documentation for [testWidgets] on how to except individual tests.
bool _isLeakTrackingEnabled() {
  if (kIsWeb) {
    return const bool.fromEnvironment('LEAK_TRACKING');
  }
  // The values can be different, one is compile time, another is run time.
  return const bool.fromEnvironment('LEAK_TRACKING') ||
      (bool.tryParse(Platform.environment['LEAK_TRACKING'] ?? '') ?? false);
}

/// Test configuration for each test library in this directory.
///
/// See https://api.flutter.dev/flutter/flutter_test/flutter_test-library.html.
Future<void> testExecutable(FutureOr<void> Function() testMain) {
  // Enable checks because there are many implementations of [RenderBox] in this
  // package can benefit from the additional validations.
  debugCheckIntrinsicSizes = true;

  // Make tap() et al fail if the given finder specifies a widget that would not
  // receive the event.
  WidgetController.hitTestWarningShouldBeFatal = true;

  if (_isLeakTrackingEnabled()) {
    LeakTesting.enable();
    LeakTracking.warnForUnsupportedPlatforms = false;
    // Customized link to documentation on how to troubleshoot leaks,
    // to print in the error message.
    LeakTracking.troubleshootingDocumentationLink =
        'https://github.com/flutter/flutter/blob/main/docs/contributing/testing/Leak-tracking.md';
    // `createdByTestHelpers` makes leak_tracker capture `StackTrace.current`
    // for every tracked object. Under DDC, `_StackTrace` holds an unformatted
    // V8 `Error` whose internal call-site frames retain every frame's receiver
    // (including the tracked object itself). Because `ObjectRecord` is the
    // `Finalizer` held value, that creates a retention cycle that blocks GC and
    // exhausts the browser heap. The heuristic also matches VM-only stack frame
    // syntax (`(package:flutter_test/`, `/test/`), so it is inert on both DDC
    // and dart2wasm.
    LeakTesting.settings = LeakTesting.settings.withIgnored(createdByTestHelpers: !kIsWeb);
  }

  // Enable golden file testing using Skia Gold.
  return flutter_goldens.testExecutable(testMain);
}
