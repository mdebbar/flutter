// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as pathlib;
// TODO(yjbanov): remove hacks when this is fixed:
//                https://github.com/dart-lang/test/issues/1521
import 'package:skia_gold_client/skia_gold_client.dart';
import 'package:test_api/backend.dart' as hack;
import 'package:test_core/src/executable.dart' as test;
import 'package:test_core/src/runner/hack_register_platform.dart' as hack;

import '../browser.dart';
import '../common.dart';
import '../environment.dart';
import '../exceptions.dart';
import '../felt_config.dart';
import '../pipeline.dart';
import '../test_platform.dart';
import '../utils.dart';

/// Runs a test suite.
///
/// Assumes the artifacts from previous steps are available, either from
/// running them prior to this step locally, or by having the build graph copy
/// them from another bot.
class RunSuiteStep implements PipelineStep {
  RunSuiteStep(
    this.suite, {
    required this.startPaused,
    required this.isVerbose,
    required this.doUpdateScreenshotGoldens,
    required this.requireSkiaGold,
    required this.overridePathToCanvasKit,
    required this.useDwarf,
    this.testFiles,
    this.isOffline = false,
    this.refreshGoldens = false,
  });

  /// The test suite to run.
  final TestSuite suite;

  /// Whether to start the test in paused mode.
  final bool startPaused;

  /// Whether to output verbose diagnostic logs.
  final bool isVerbose;

  /// Whether to update screenshots in golden directory instead of comparing.
  final bool doUpdateScreenshotGoldens;

  /// Require Skia Gold to be available and reachable.
  final bool requireSkiaGold;

  /// An optional override path to CanvasKit artifacts.
  final String? overridePathToCanvasKit;

  /// Whether to use DWARF stack traces.
  final bool useDwarf;

  /// Specific test files to run within the suite.
  final Set<FilePath>? testFiles;

  /// Whether to run tests offline using cached baselines.
  final bool isOffline;

  /// Whether to force refresh cached goldens from Skia Gold.
  final bool refreshGoldens;

  @override
  String get description => 'run_suite';

  @override
  bool get isSafeToInterrupt => true;

  @override
  Future<void> interrupt() async {}

  @override
  Future<void> run() async {
    final io.Directory resultsDirectory = _prepareTestResultsDirectory();
    // Machine-readable results, used to print the failure summary below (and
    // kept next to the screenshots for post-mortem inspection).
    final jsonReport = io.File(pathlib.join(resultsDirectory.path, 'test_results.json'));
    final BrowserEnvironment browserEnvironment = getBrowserEnvironment(
      suite.runConfig.browser,
      useDwarf: useDwarf,
      browserFlags: suite.runConfig.browserFlags,
    );
    await browserEnvironment.prepare();

    final SkiaGoldClient? skiaClient = await _createSkiaClient();
    final String configurationFilePath = pathlib.join(
      environment.webUiRootDir.path,
      browserEnvironment.packageTestConfigurationYamlFile,
    );
    final String bundleBuildPath = getBundleBuildDirectory(suite.testBundle).path;
    final testArgs = <String>[
      // The compact reporter overwrites lines with `\r`, which is unreadable in
      // CI logs; use the expanded reporter when not attached to a terminal.
      '-r',
      if (io.stdout.hasTerminal) 'compact' else 'expanded',
      '--file-reporter=json:${jsonReport.path}',
      // Disable concurrency. Running with concurrency proved to be flaky.
      '--concurrency=1',
      if (startPaused) '--pause-after-load',
      '--platform=${browserEnvironment.packageTestRuntime.identifier}',
      '--precompiled=$bundleBuildPath',
      '--configuration=$configurationFilePath',
      if (AnsiColors.shouldEscape) '--color' else '--no-color',

      // TODO(jacksongardner): Set the default timeout to five minutes when
      // https://github.com/dart-lang/test/issues/2006 is fixed.
      '--',
      ..._collectTestPaths(),
    ];

    hack.registerPlatformPlugin(<hack.Runtime>[browserEnvironment.packageTestRuntime], () {
      return BrowserPlatform.start(
        suite,
        browserEnvironment: browserEnvironment,
        doUpdateScreenshotGoldens: doUpdateScreenshotGoldens,
        skiaClient: skiaClient,
        overridePathToCanvasKit: overridePathToCanvasKit,
        isVerbose: isVerbose,
        isOffline: isOffline,
        refreshGoldens: refreshGoldens,
      );
    });

    print('[${suite.name.ansiCyan}] Running...');

    // We want to run tests with the test set's directory as a working directory.
    final testSetDirectory = io.Directory(
      pathlib.join(environment.webUiTestDir.path, suite.testBundle.testSet.directory),
    );
    final dynamic originalCwd = io.Directory.current;
    io.Directory.current = testSetDirectory;
    try {
      await test.main(testArgs);
    } finally {
      io.Directory.current = originalCwd;
      await browserEnvironment.cleanup();
    }

    // Since we are just calling `main()` on the test executable, it will modify
    // the exit code. We use this as a signal that there were some tests that failed.
    if (io.exitCode != 0) {
      print('[${suite.name.ansiCyan}] ${'Some tests failed.'.ansiRed}');
      final List<FailedTest> failedTests = _readFailedTests(jsonReport);
      _printFailureSummary(failedTests);
      // Change the exit code back to 0 when we're done. Failures will be bubbled up
      // at the end of the pipeline and we'll exit abnormally if there were any
      // failures in the pipeline.
      io.exitCode = 0;
      throw ToolExit(
        failedTests.isEmpty
            ? 'Some unit tests failed in suite ${suite.name.ansiCyan}.'
            : '${failedTests.length} unit test(s) failed in suite ${suite.name.ansiCyan}.',
      );
    } else {
      print('[${suite.name.ansiCyan}] ${'All tests passed!'.ansiGreen}');
    }
  }

  /// Maximum number of failing tests listed in the failure summary.
  static const int _maxListedFailures = 10;

  /// Delimiters of the failure summary block.
  ///
  /// The CI recipes (`test_utils.run_test` in flutter/recipes) extract the text
  /// between these two lines and surface it as the LUCI build summary. Keep in
  /// sync with `kFailureSummaryBegin`/`kFailureSummaryEnd` in
  /// `dev/bots/utils.dart` of the framework.
  static const String _failureSummaryBegin = '===== BEGIN FAILURE SUMMARY =====';
  static const String _failureSummaryEnd = '===== END FAILURE SUMMARY =====';

  /// Prints one line per failing test (plus the first lines of its first
  /// error) inside the failure summary delimiters.
  void _printFailureSummary(List<FailedTest> failedTests) {
    print(_failureSummaryBegin);
    if (failedTests.isEmpty) {
      print('[${suite.name}] Some tests failed (no per-test results available).');
    } else {
      print('[${suite.name}] ${failedTests.length} test(s) failed:');
      for (final FailedTest test in failedTests.take(_maxListedFailures)) {
        print('  ${test.suitePath}: ${test.name}');
        for (final String errorLine in test.errorLines) {
          print('    $errorLine');
        }
      }
      if (failedTests.length > _maxListedFailures) {
        print('  ... and ${failedTests.length - _maxListedFailures} more');
      }
    }
    print(_failureSummaryEnd);
  }

  /// Parses the `package:test` JSON reporter output and returns the tests that
  /// did not succeed, in the order they finished.
  static List<FailedTest> _readFailedTests(io.File jsonReport) {
    if (!jsonReport.existsSync()) {
      return const <FailedTest>[];
    }
    final suitePaths = <int, String>{};
    final tests = <int, FailedTest>{};
    final failed = <FailedTest>[];
    for (final String line in jsonReport.readAsLinesSync()) {
      final Object? event;
      try {
        event = json.decode(line);
      } on FormatException {
        continue;
      }
      switch (event) {
        case {'type': 'suite', 'suite': {'id': final int id, 'path': final String path}}:
          suitePaths[id] = pathlib.basename(path);
        case {
          'type': 'testStart',
          'test': {'id': final int id, 'name': final String name, 'suiteID': final int suiteID},
        }:
          tests[id] = FailedTest(suitePath: suitePaths[suiteID] ?? '<unknown>', name: name);
        case {'type': 'error', 'testID': final int testID, 'error': final Object? error}:
          tests[testID]?.recordError('$error');
        case {'type': 'testDone', 'testID': final int testID, 'result': final String result}:
          final FailedTest? test = tests[testID];
          final hidden = event['hidden'] == true;
          if (test != null && result != 'success' && !hidden) {
            failed.add(test);
          }
      }
    }
    return failed;
  }

  io.Directory _prepareTestResultsDirectory() {
    final resultsDirectory = io.Directory(
      pathlib.join(environment.webUiTestResultsDirectory.path, suite.name),
    );
    if (resultsDirectory.existsSync()) {
      resultsDirectory.deleteSync(recursive: true);
    }
    resultsDirectory.createSync(recursive: true);
    return resultsDirectory;
  }

  List<String> _collectTestPaths() {
    final io.Directory bundleBuild = getBundleBuildDirectory(suite.testBundle);
    final resultsJsonFile = io.File(pathlib.join(bundleBuild.path, 'results.json'));
    if (!resultsJsonFile.existsSync()) {
      throw ToolExit(
        'Could not find built bundle ${suite.testBundle.name.ansiMagenta} for suite ${suite.name.ansiCyan}.',
      );
    }
    final String jsonString = resultsJsonFile.readAsStringSync();
    final jsonContents = const JsonDecoder().convert(jsonString) as Map<String, Object?>;
    final results = jsonContents['results']! as Map<String, Object?>;
    final testPaths = <String>[];
    results.forEach((Object? k, Object? v) {
      final result = v! as String;
      final testPath = k! as String;
      if (testFiles != null) {
        if (!testFiles!.contains(FilePath.fromTestSet(suite.testBundle.testSet, testPath))) {
          return;
        }
      }
      if (result == 'success') {
        testPaths.add(testPath);
      }
    });
    return testPaths;
  }

  Future<SkiaGoldClient?> _createSkiaClient() async {
    if (suite.testBundle.compileConfigs.length > 1) {
      // Multiple compile configs are only used for our fallback tests, which
      // do not collect goldens.
      print('Did not create SkiaGoldClient. Reason: Multiple compile configs.');
      return null;
    }
    if (suite.runConfig.browser == BrowserName.safari) {
      // Goldens from Safari produce too many diffs, disabled for now.
      // See https://github.com/flutter/flutter/issues/143591
      print('Did not create SkiaGoldClient. Reason: Safari browser.');
      return null;
    }

    final Renderer renderer = suite.testBundle.compileConfigs.first.renderer;
    final CanvasKitVariant? variant = suite.runConfig.variant;
    final io.Directory workDirectory = getSkiaGoldDirectoryForSuite(suite);
    if (workDirectory.existsSync()) {
      workDirectory.deleteSync(recursive: true);
    }
    final isWasm = suite.testBundle.compileConfigs.first.compiler == Compiler.dart2wasm;
    final bool singleThreaded =
        suite.runConfig.forceSingleThreadedSkwasm || !suite.runConfig.crossOriginIsolated;
    String rendererName = renderer.name;
    if (renderer == Renderer.skwasm) {
      if (suite.runConfig.enableWimp) {
        rendererName = singleThreaded ? 'wimp_st' : 'wimp';
      } else {
        rendererName = singleThreaded ? 'skwasm_st' : 'skwasm';
      }
    }
    final bool isWebParagraph = suite.runConfig.enableWebParagraph;

    final dimensions = <String, String>{
      // All Flutter Web Engine screenshot tryjobs run on Linux on CI (LUCI).
      // Hardcoding 'Platform': 'linux' ensures that local test runs on macOS
      // and Windows query and match the official Linux CI golden baselines
      // stored in Skia Gold.
      'Platform': 'linux',
      'Browser': suite.runConfig.browser.name,
      if (isWasm) 'Wasm': 'true',
      'Renderer': rendererName,
      'CanvasKitVariant': ?variant?.name,
      if (isWebParagraph) 'WebParagraph': 'true',
    };
    final skiaClient = SkiaGoldClient(workDirectory, dimensions: dimensions);

    final (bool success, String? reason) = await _checkSkiaClient(skiaClient);
    if (success) {
      print('Created SkiaGoldClient. Dimensions: $dimensions');
      return skiaClient;
    }

    print('Did not create SkiaGoldClient. Reason: $reason.');
    if (requireSkiaGold) {
      throw ToolExit('Skia Gold is required but is unavailable.');
    }

    return null;
  }

  /// Checks whether the Skia Client is usable in this environment.
  Future<(bool, String?)> _checkSkiaClient(SkiaGoldClient skiaClient) async {
    // When offline, we don't attempt network connectivity to Skia Gold, but we still
    // return true so SkiaGoldClient is instantiated for local offline baseline comparisons.
    if (isOffline) {
      return (true, null);
    }
    // Now let's check whether Skia Gold is reachable or not.
    if (isLuci) {
      if (SkiaGoldClient.isAvailable()) {
        try {
          await skiaClient.auth();
          return (true, null);
        } catch (error) {
          print(error);
        }
      }
    } else {
      try {
        // Check if we can reach Gold.
        await skiaClient.getExpectationForTest('');
        return (true, null);
      } on io.OSError catch (error) {
        return (false, 'OSError occurred, could not reach Gold: $error');
      } on io.SocketException catch (error) {
        return (false, 'SocketException occurred, could not reach Gold: $error');
      } on io.IOException catch (error) {
        return (false, 'Network error occurred, could not reach Gold: $error');
      } on FormatException catch (error) {
        return (false, 'Format error occurred, could not parse Gold response: $error');
      }
    }

    return (false, 'Unknown');
  }
}

/// A test that did not succeed, as reported by the `package:test` JSON reporter.
class FailedTest {
  FailedTest({required this.suitePath, required this.name});

  /// Base name of the test file.
  final String suitePath;

  /// Full test name, including group prefixes.
  final String name;

  /// Maximum number of lines kept from the first error message. Matcher
  /// failures span several lines (Expected/Actual/Which).
  static const int maxErrorLines = 3;

  List<String> _errorLines = const <String>[];

  /// The first [maxErrorLines] lines of the first error reported for this
  /// test, trimmed; empty if no error was reported.
  List<String> get errorLines => _errorLines;

  void recordError(String error) {
    if (_errorLines.isNotEmpty) {
      return;
    }
    _errorLines = error
        .trim()
        .split('\n')
        .take(maxErrorLines)
        .map((String line) => line.trim())
        .toList();
  }
}
