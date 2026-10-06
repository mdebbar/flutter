// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

class TestSpecs {
  TestSpecs({required this.path, required this.startTime});

  final String path;
  int startTime;
  int? _endTime;

  int get milliseconds => endTime - startTime;

  set endTime(int value) {
    _endTime = value;
  }

  int get endTime => _endTime ?? 0;

  String toJson() {
    return json.encode(<String, String>{'path': path, 'runtime': milliseconds.toString()});
  }
}

/// The parsed result of a single test case as reported by the `dart test`
/// JSON file reporter.
class TestResult {
  TestResult({required this.name, required this.suiteID, required this.startTime});

  /// The full name of the test (including any group prefixes).
  final String name;

  /// The id of the suite (test file) that this test belongs to.
  final int suiteID;

  /// The time (in milliseconds, relative to the start of the run) at which the
  /// test started.
  final int startTime;

  /// The time (in milliseconds, relative to the start of the run) at which the
  /// test finished, or null if it never finished.
  int? endTime;

  /// The raw result reported by `dart test`: one of `success`, `failure`, or
  /// `error`.
  String result = 'success';

  /// Whether the test was skipped.
  bool skipped = false;

  /// Whether the test is a "hidden" bookkeeping test (for example, the
  /// synthetic "loading <suite>" test that `dart test` emits for each suite).
  ///
  /// Hidden tests are excluded from the reported results.
  bool hidden = false;

  /// The duration of the test, in seconds.
  double get seconds => ((endTime ?? startTime) - startTime) / 1000.0;

  /// Maps the `dart test` [result]/[skipped] to a `PASS`/`FAIL`/`SKIP` result
  /// type.
  String get actual => switch (this) {
    TestResult(skipped: true) => 'SKIP',
    TestResult(result: 'success') => 'PASS',
    _ => 'FAIL',
  };

  /// The expected result type for this test.
  ///
  /// `dart test` has no concept of expected failures, so every non-skipped
  /// test is expected to pass.
  String get expected => skipped ? 'SKIP' : 'PASS';

  /// The error messages (without stack traces) reported for this test, in
  /// the order they were emitted.
  final List<String> errors = <String>[];

  /// The `EXCEPTION CAUGHT BY ...` reports printed by `flutter_test` while
  /// this test ran, in the order they were emitted.
  ///
  /// For `testWidgets`, the `error` event only says "Test failed. See
  /// exception logs above."; the actual failure (matcher output, thrown
  /// exception) is in these reports, which the JSON reporter delivers as
  /// `print` events attributed to the test.
  final List<String> exceptionReports = <String>[];

  /// The first line of the exception-report banner printed by `flutter_test`.
  static final RegExp _exceptionBanner = RegExp(r'^══╡ EXCEPTION CAUGHT BY .* ╞═*$');

  /// The line introducing the thrown object inside an exception report, e.g.
  /// `The following TestFailure was thrown running a test:`.
  static final RegExp _exceptionIntro = RegExp(r'^The following .* was thrown.*:$');

  /// The most useful lines describing why this test failed.
  ///
  /// Prefers the body of the first exception report (the lines following the
  /// `The following ... was thrown ...:` intro, up to the blank line that
  /// precedes the stack trace); falls back to the first `error` message.
  List<String> get failureLines {
    for (final String report in exceptionReports) {
      final List<String> lines = report.trim().split('\n');
      if (lines.isEmpty || !_exceptionBanner.hasMatch(lines.first)) {
        continue;
      }
      final int intro = lines.indexWhere(_exceptionIntro.hasMatch);
      if (intro == -1) {
        continue;
      }
      final body = <String>[];
      for (final String line in lines.skip(intro + 1)) {
        if (line.trim().isEmpty) {
          break;
        }
        body.add(line);
      }
      if (body.isNotEmpty) {
        return body;
      }
    }
    if (errors.isEmpty) {
      return const <String>[];
    }
    return errors.first.trim().split('\n');
  }
}

class TestFileReporterResults {
  TestFileReporterResults._({
    required this.allTestSpecs,
    required this.testResults,
    required this.hasFailedTests,
    required this.errors,
  });

  /// Intended to parse the output file of `dart test --file-reporter json:file_name
  factory TestFileReporterResults.fromFile(File metrics) {
    if (!metrics.existsSync()) {
      throw Exception('${metrics.path} does not exist');
    }

    final testSpecs = <int, TestSpecs>{};
    final testResults = <int, TestResult>{};
    var hasFailedTests = true;
    final errors = <String>[];

    for (final String metric in metrics.readAsLinesSync()) {
      /// Using print within a test adds the printed content to the json file report
      /// as \u0000 making the file parsing step fail. The content of the json file
      /// is expected to be a json dictionary per line and the following line removes
      /// all the additional content at the beginning of the line until it finds the
      /// first opening curly bracket.
      // TODO(godofredoc): remove when https://github.com/flutter/flutter/issues/145553 is fixed.
      final String sanitizedMetric = metric.replaceAll(RegExp(r'$.*{'), '{');
      final entry = json.decode(sanitizedMetric) as Map<String, Object?>;
      switch (entry) {
        case {'suite': final Map<String, Object?> suite, 'time': final int time}:
          addTestSpec(suite, time, testSpecs);
        case {'type': 'group', 'group': {'suiteID': final int suiteID}, 'time': final int time}
            when testSpecs.containsKey(suiteID):
          addMetricDone(suiteID, time, testSpecs);
        case {'type': 'testStart', 'test': final Map<String, Object?> test, 'time': final int time}:
          addTestStart(test, time, testResults);
        case {'type': 'testDone'}:
          addTestDone(entry, testResults);
        case {'type': 'error', 'testID': final int testID, 'error': final Object? error}:
          final String stackTrace = entry['stackTrace'] as String? ?? '';
          errors.add('$error\n $stackTrace');
          testResults[testID]?.errors.add('$error');
        case {'type': 'print', 'testID': final int testID, 'message': final String message}
            when message.startsWith('══╡ EXCEPTION CAUGHT BY'):
          testResults[testID]?.exceptionReports.add(message);
        case {'error': final Object? error}:
          final String stackTrace = entry['stackTrace'] as String? ?? '';
          errors.add('$error\n $stackTrace');
        case {'success': true}:
          hasFailedTests = false;
      }
    }

    return TestFileReporterResults._(
      allTestSpecs: testSpecs,
      testResults: testResults,
      hasFailedTests: hasFailedTests,
      errors: errors,
    );
  }

  final Map<int, TestSpecs> allTestSpecs;
  final Map<int, TestResult> testResults;
  final bool hasFailedTests;
  final List<String> errors;

  /// Maximum number of failing tests listed by [failedTestLines].
  static const int maxListedFailures = 10;

  /// Maximum number of lines of the first error message included per failing
  /// test by [failedTestLines].
  static const int maxErrorLines = 3;

  /// One line per failing test: `<suite path>: <test name>` followed by the
  /// first [maxErrorLines] lines of its first error message, indented.
  /// Suite paths are made relative to [workingDirectory].
  ///
  /// At most [maxListedFailures] tests are listed; the remainder is summarized
  /// as a count. Intended for the error block printed at the end of the run,
  /// which LUCI surfaces as the build summary.
  List<String> failedTestLines({required String workingDirectory}) {
    final List<TestResult> failed = testResults.values
        .where((TestResult test) => !test.hidden && !test.skipped && test.result != 'success')
        .toList();
    if (failed.isEmpty) {
      return const <String>[];
    }
    final lines = <String>['Failing tests (${failed.length}):'];
    for (final TestResult test in failed.take(maxListedFailures)) {
      final TestSpecs? spec = allTestSpecs[test.suiteID];
      final String suite = spec == null
          ? '<unknown suite>'
          : path.relative(spec.path, from: workingDirectory);
      lines.add('  $suite: ${test.name}');
      // Matcher failures span several lines (Expected/Actual/Which); keep the
      // first few so the summary is actionable without the full log.
      for (final String errorLine in test.failureLines.take(maxErrorLines)) {
        lines.add('    ${errorLine.trim()}');
      }
    }
    if (failed.length > maxListedFailures) {
      lines.add('  ... and ${failed.length - maxListedFailures} more');
    }
    return lines;
  }

  static void addTestSpec(Map<String, Object?> suite, int time, Map<int, TestSpecs> allTestSpecs) {
    if (suite case {'id': final int id, 'path': final String path}) {
      allTestSpecs[id] = TestSpecs(path: path, startTime: time);
    }
  }

  static void addMetricDone(int suiteID, int time, Map<int, TestSpecs> allTestSpecs) {
    allTestSpecs[suiteID]?.endTime = time;
  }

  static bool isMetricDone(Map<String, Object?> entry, Map<int, TestSpecs> allTestSpecs) =>
      switch (entry) {
        {'type': 'group', 'group': {'suiteID': final int suiteID}} => allTestSpecs.containsKey(
          suiteID,
        ),
        _ => false,
      };

  static void addTestStart(Map<String, Object?> test, int time, Map<int, TestResult> testResults) {
    if (test case {'id': final int id, 'name': final String name, 'suiteID': final int suiteID}) {
      testResults[id] = TestResult(name: name, suiteID: suiteID, startTime: time);
    }
  }

  static void addTestDone(Map<String, Object?> entry, Map<int, TestResult> testResults) {
    if (entry case {'testID': final int testID, 'time': final int time}) {
      if (testResults[testID] case final testResult?) {
        testResult
          ..endTime = time
          ..result = entry['result'] as String? ?? testResult.result
          ..skipped = entry['skipped'] as bool? ?? false
          ..hidden = entry['hidden'] as bool? ?? false;
      }
    }
  }
}
