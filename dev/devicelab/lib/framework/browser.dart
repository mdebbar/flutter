// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert' show JsonEncoder, LineSplitter, json, utf8;
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:path/path.dart' as path;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// Flags passed to Chrome to disable GCM (Google Cloud Messaging) and MCS
/// (Mobile Connection Server) background network registration calls and
/// prevent deprecation error logs.
const kGcmDisabledFlags = <String>[
  '--disable-features=GCM',
  '--gcm-checkin-url=http://127.0.0.1',
  '--gcm-registration-url=http://127.0.0.1',
  '--gcm-mcs-endpoint=127.0.0.1:0',
];

/// The number of samples used to extract metrics, such as noise, means,
/// max/min values.
///
/// Keep this constant in sync with the same constant defined in `dev/benchmarks/macrobenchmarks/lib/src/web/recorder.dart`.
const int _kMeasuredSampleCount = 10;

/// Options passed to Chrome when launching it.
class ChromeOptions {
  ChromeOptions({
    this.userDataDirectory,
    this.url,
    this.windowWidth = 1024,
    this.windowHeight = 1024,
    this.headless,
    this.debugPort,
    this.enableWasmGC = false,
    this.silent = false,
  });

  /// If not null passed as `--user-data-dir`.
  final String? userDataDirectory;

  /// If not null launches a Chrome tab at this URL.
  final String? url;

  /// The width of the Chrome window.
  ///
  /// This is important for screenshots and benchmarks.
  final int windowWidth;

  /// The height of the Chrome window.
  ///
  /// This is important for screenshots and benchmarks.
  final int windowHeight;

  /// Launches code in "headless" mode, which allows running Chrome in
  /// environments without a display, such as LUCI.
  final bool? headless;

  /// The port Chrome will use for its debugging protocol.
  ///
  /// If null, Chrome is launched without debugging. When running in headless
  /// mode without a debug port, Chrome quits immediately. For most tests it is
  /// typical to set [headless] to true and set a non-null debug port.
  final int? debugPort;

  /// Whether to enable experimental WasmGC flags
  final bool enableWasmGC;

  /// Disables Chrome stdio outputs.
  final bool silent;
}

/// A function called when the Chrome process encounters an error.
typedef ChromeErrorCallback = void Function(String);

/// Manages a single Chrome process.
class Chrome {
  Chrome._(this._chromeProcess, this._onError, this._debugConnection) {
    // If the Chrome process quits before it was asked to quit, notify the
    // error listener.
    _chromeProcess.exitCode.then((int exitCode) {
      if (!_isStopped && exitCode != 0) {
        _onError('Chrome process exited prematurely with exit code $exitCode');
      }
    });
  }

  /// Launches Chrome with the given [options].
  ///
  /// The [onError] callback is called with an error message when the Chrome
  /// process encounters an error. In particular, [onError] is called when the
  /// Chrome process exits prematurely, i.e. before [stop] or [disconnect] is called.
  static Future<Chrome> launch(
    ChromeOptions options, {
    String? workingDirectory,
    required ChromeErrorCallback onError,
  }) async {
    if (!io.Platform.isWindows) {
      final io.ProcessResult versionResult = io.Process.runSync(
        _findSystemChromeExecutable(),
        const <String>['--version'],
      );
      print('Launching ${versionResult.stdout}');
    } else {
      print('Launching Chrome...');
    }

    final String jsFlags = options.enableWasmGC
        ? <String>['--experimental-wasm-gc', '--experimental-wasm-type-reflection'].join(' ')
        : '';
    final withDebugging = options.debugPort != null;
    final args = <String>[
      if (options.userDataDirectory != null) '--user-data-dir=${options.userDataDirectory}',
      ?options.url,
      if (io.Platform.environment['CHROME_NO_SANDBOX'] == 'true') '--no-sandbox',
      if (options.headless ?? false) ...<String>[
        '--headless',
        if (io.Platform.isLinux) ...<String>[
          '--use-gl=angle',
          '--use-angle=swiftshader',
          '--enable-unsafe-swiftshader',
          '--disable-gpu-sandbox',
        ],
      ],
      if (withDebugging) '--remote-debugging-port=${options.debugPort}',
      '--window-size=${options.windowWidth},${options.windowHeight}',
      '--disable-extensions',
      '--disable-popup-blocking',
      '--disable-background-timer-throttling',
      '--disable-renderer-backgrounding',
      '--disable-background-networking',
      '--disable-sync',
      '--disable-client-side-phishing-detection',
      '--disable-notifications',
      ...kGcmDisabledFlags,
      // Indicates that the browser is in "browse without sign-in" (Guest session) mode.
      '--bwsi',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-default-apps',
      '--disable-translate',
      '--password-store=basic',
      '--disable-search-engine-choice-screen',
      if (io.Platform.isMacOS) '--use-mock-keychain',
      if (jsFlags.isNotEmpty) '--js-flags=$jsFlags',
    ];

    final io.Process chromeProcess = await _spawnChromiumProcess(
      _findSystemChromeExecutable(),
      args,
      silent: options.silent,
      workingDirectory: workingDirectory,
    );

    WipConnection? debugConnection;
    if (withDebugging) {
      debugConnection = await _connectToChromeDebugPort(options.debugPort!, options.url);
    }

    return Chrome._(chromeProcess, onError, debugConnection);
  }

  /// Connects to an existing Chrome process with the given [options].
  ///
  /// The [onError] callback is called with an error message when the Chrome
  /// process encounters an error. In particular, [onError] is called when the
  /// Chrome process exits prematurely, i.e. before [stop] or [disconnect] is called.
  static Future<Chrome> connect(
    io.Process chromeProcess,
    ChromeOptions options, {
    String? workingDirectory,
    required ChromeErrorCallback onError,
  }) async {
    final withDebugging = options.debugPort != null;

    WipConnection? debugConnection;
    if (withDebugging) {
      debugConnection = await _connectToChromeDebugPort(options.debugPort!, options.url);
    }

    return Chrome._(chromeProcess, onError, debugConnection);
  }

  final io.Process _chromeProcess;
  final ChromeErrorCallback _onError;
  final WipConnection? _debugConnection;
  bool _isStopped = false;

  Completer<void>? _tracingCompleter;
  StreamSubscription<WipEvent>? _tracingSubscription;
  List<Map<String, dynamic>>? _tracingData;

  /// Starts recording a performance trace.
  ///
  /// If there is already a tracing session in progress, throws an error. Call
  /// [endRecordingPerformance] before starting a new tracing session.
  ///
  /// The [label] is for debugging convenience.
  Future<void> beginRecordingPerformance(String label) async {
    if (_tracingCompleter != null) {
      throw StateError(
        'Cannot start a new performance trace. A tracing session labeled '
        '"$label" is already in progress.',
      );
    }
    _tracingCompleter = Completer<void>();
    _tracingData = <Map<String, dynamic>>[];

    // Subscribe to tracing events prior to calling "Tracing.start". Otherwise,
    // we'll miss tracing data.
    _tracingSubscription = _debugConnection?.onNotification.listen((WipEvent event) {
      // We receive data as a sequence of "Tracing.dataCollected" followed by
      // "Tracing.tracingComplete" at the end. Until "Tracing.tracingComplete"
      // is received, the data may be incomplete.
      if (event.method == 'Tracing.tracingComplete') {
        _tracingCompleter!.complete();
        _tracingSubscription!.cancel();
        _tracingSubscription = null;
      } else if (event.method == 'Tracing.dataCollected') {
        final dynamic value = event.params?['value'];
        if (value is! List) {
          throw FormatException(
            '"Tracing.dataCollected" returned malformed data. '
            'Expected a List but got: ${value.runtimeType}',
          );
        }
        _tracingData?.addAll(
          (event.params?['value'] as List<dynamic>).cast<Map<String, dynamic>>(),
        );
      }
    });
    await _debugConnection?.sendCommand('Tracing.start', <String, dynamic>{
      // The choice of categories is as follows:
      //
      // blink:
      //   provides everything on the UI thread, including scripting,
      //   style recalculations, layout, painting, and some compositor
      //   work.
      // blink.user_timing:
      //   provides marks recorded using window.performance. We use marks
      //   to find frames that the benchmark cares to measure.
      // gpu:
      //   provides tracing data from the GPU data
      //   disabled due to https://bugs.chromium.org/p/chromium/issues/detail?id=1068259
      // TODO(yjbanov): extract useful GPU data
      'traceConfig': <String, dynamic>{
        'includedCategories': <String>['blink', 'blink.user_timing'],
        'enableThreadCpuTime': true,
      },
      'transferMode': 'SendAsStream',
    });
  }

  /// Stops a performance tracing session started by [beginRecordingPerformance].
  ///
  /// Returns all the collected tracing data unfiltered.
  Future<List<Map<String, dynamic>>?> endRecordingPerformance() async {
    await _debugConnection!.sendCommand('Tracing.end');
    await _tracingCompleter!.future;
    final List<Map<String, dynamic>>? data = _tracingData;
    _tracingCompleter = null;
    _tracingData = null;
    return data;
  }

  Future<void> reloadPage({bool ignoreCache = false}) async {
    await _debugConnection?.page.reload(ignoreCache: ignoreCache);
  }

  StreamSubscription<WipEvent>? _pageEventSubscription;
  final _PageLogLimiter _pageLogLimiter = _PageLogLimiter();

  /// Logs page navigations, load events, console output, uncaught JS
  /// exceptions, resource loading errors (such as `net::ERR_*`), and renderer
  /// crashes, so that a page load that never completes can be diagnosed from
  /// the logs.
  ///
  /// This enables the Page, Runtime, Log, and Inspector DevTools domains, which
  /// adds instrumentation overhead to the page. Only use it for diagnosing
  /// uncalibrated runs.
  ///
  /// Each line is stamped with the elapsed time of [clock].
  Future<void> logPageEvents({required Stopwatch clock}) async {
    final WipConnection debugConnection = _debugConnection!;
    _pageEventSubscription = debugConnection.onNotification.listen((WipEvent event) {
      try {
        _logPageEvent(event, clock);
      } on Object catch (error) {
        print('[CHROME PAGE] Failed to log ${event.method}: $error');
      }
    });
    for (final domain in <String>['Page', 'Runtime', 'Log', 'Inspector']) {
      await debugConnection.sendCommand('$domain.enable');
    }
    // DDC loads 1000+ library scripts per reload, which overflows the default
    // 250-entry Resource Timing buffer.
    await debugConnection.sendCommand('Page.addScriptToEvaluateOnNewDocument', <String, dynamic>{
      'source': 'performance.setResourceTimingBufferSize(3000);',
    });
  }

  void _logPageEvent(WipEvent event, Stopwatch clock) {
    final Map<String, dynamic> params = event.params ?? const <String, dynamic>{};
    final (String, String)? entry = switch (event.method) {
      // Frames that have a parent are not the page itself.
      'Page.frameNavigated' when (params['frame'] as Map<String, dynamic>)['parentId'] == null => (
        'navigation',
        'navigated to ${(params['frame'] as Map<String, dynamic>)['url']}',
      ),
      'Page.frameRequestedNavigation' => (
        'navigation',
        'navigation requested by the page (${params['reason']}) to ${params['url']}',
      ),
      'Page.frameStartedNavigating' => (
        'navigation',
        'navigation started (${params['navigationType']}) to ${params['url']}',
      ),
      'Page.frameStartedLoading' => ('navigation', 'frame started loading'),
      'Page.frameStoppedLoading' => ('navigation', 'frame stopped loading'),
      'Page.domContentEventFired' => ('navigation', 'DOMContentLoaded event fired'),
      'Page.loadEventFired' => ('navigation', 'load event fired'),
      'Runtime.consoleAPICalled' => (
        'console',
        'console.${params['type']}: ${_describeConsoleArgs(params['args'] as List<dynamic>)}',
      ),
      'Runtime.exceptionThrown' => (
        'exception',
        'uncaught exception: ${_describeException(params['exceptionDetails'] as Map<String, dynamic>)}',
      ),
      'Log.entryAdded' => ('log', _describeLogEntry(params['entry'] as Map<String, dynamic>)),
      'Inspector.targetCrashed' => ('fatal', 'renderer process crashed'),
      'Inspector.detached' => ('fatal', 'DevTools session detached: ${params['reason']}'),
      _ => null,
    };
    if (entry == null) {
      return;
    }
    final String timestamp = (clock.elapsedMilliseconds / 1000).toStringAsFixed(1);
    final (String category, String message) = entry;
    if (event.method == 'Page.frameNavigated') {
      final String? suppressed = _pageLogLimiter.takeSuppressedSummary();
      if (suppressed != null) {
        print('[CHROME PAGE] t=${timestamp}s (previous document) $suppressed');
      }
    }
    if (_pageLogLimiter.allow(category, message)) {
      print('[CHROME PAGE] t=${timestamp}s $message');
    }
  }

  /// Describes the console and log messages of the current document, including
  /// those that [logPageEvents] did not print individually.
  String describePageLogCounts() => _pageLogLimiter.describeCounts();

  static String _describeConsoleArgs(List<dynamic> args) {
    return args
        .map((dynamic arg) {
          final map = arg as Map<String, dynamic>;
          return '${map['value'] ?? map['description'] ?? map['type']}';
        })
        .join(' ');
  }

  static String _describeException(Map<String, dynamic> exceptionDetails) {
    final exception = exceptionDetails['exception'] as Map<String, dynamic>?;
    // The description of a JS Error includes its stack trace.
    return '${exception?['description'] ?? exceptionDetails['text']}';
  }

  static String _describeLogEntry(Map<String, dynamic> entry) {
    final url = entry['url'] as String?;
    final suffix = url != null && url.isNotEmpty ? ' ($url)' : '';
    return 'log.${entry['level']}: ${entry['text']}$suffix';
  }

  /// Evaluates [expression] in the page behind [connection] and returns the
  /// result as a string.
  ///
  /// Throws a [TimeoutException] if the page does not respond within
  /// [timeout], e.g. because its main thread is blocked.
  static Future<String> _evaluate(
    WipConnection connection,
    String expression, {
    required bool awaitPromise,
    required Duration timeout,
  }) async {
    final WipResponse response = await connection
        .sendCommand('Runtime.evaluate', <String, dynamic>{
          'expression': expression,
          'returnByValue': true,
          'awaitPromise': awaitPromise,
        })
        .timeout(timeout);
    final result = response.result!['result'] as Map<String, dynamic>;
    return '${result['value'] ?? result['description']}';
  }

  /// Returns whether the page answers `Runtime.evaluate` within [timeout].
  ///
  /// It does not while its renderer main thread is blocked, nor while a
  /// navigation has started but not committed yet.
  Future<bool> isResponsive({required Duration timeout}) async {
    try {
      await _evaluate(_debugConnection!, '1', awaitPromise: false, timeout: timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  /// Describes the state of the page, for diagnosing a stalled page load.
  ///
  /// Distinguishes three cases: the page responds and its timers fire (the
  /// app is idle, e.g. waiting on a request); the page responds but timers
  /// don't fire (JavaScript is paused in the debugger, which DWDS keeps
  /// attached under `flutter run`); the page doesn't respond at all (see
  /// [isResponsive]).
  Future<String> describeState() async {
    const timeout = Duration(seconds: 10);
    final WipConnection debugConnection = _debugConnection!;
    const pageState = r'''
(() => {
  try {
    const resources = performance.getEntriesByType('resource');
    const loaded = new Set(resources.map((e) => e.name));
    const scripts = document.head ? Array.from(document.head.querySelectorAll('script')) : [];
    const pending = scripts.map((s) => s.src).filter((src) => src && !loaded.has(src));
    const loader = window.$dartLoader?.loader;
    return JSON.stringify({
      href: location.href,
      readyState: document.readyState,
      msSinceNavigationStart: Math.round(performance.now()),
      dwdsInitialized: Boolean(window.$dwdsInitialized),
      dartMainExecuted: Boolean(window.$dartMainExecuted),
      dartAppInstanceId: window.$dartAppInstanceId ?? null,
      resourceCount: loaded.size,
      scriptTagCount: scripts.length,
      registeredModules: window.$dartLoader?.moduleIdToUrl?.size ?? null,
      pendingScriptCount: pending.length,
      pendingScripts: pending.slice(0, 3),
      lastLoadedResources: resources.slice(-3).map((e) => e.name),
      loader: loader ? {
        attemptCount: loader.attemptCount,
        numToLoad: loader.numToLoad,
        numLoaded: loader.numLoaded,
        numFailed: loader.numFailed,
        queueLength: loader.queue?.length ?? null,
      } : null,
    });
  } catch (error) {
    return JSON.stringify({scriptError: String(error)});
  }
})()''';
    final lines = <String>[];
    try {
      lines.add(
        'Page: ${await _evaluate(debugConnection, pageState, awaitPromise: false, timeout: timeout)}',
      );
      await _evaluate(
        debugConnection,
        'new Promise((resolve) => setTimeout(resolve, 100))',
        awaitPromise: true,
        timeout: timeout,
      );
      lines.add('Event loop: running.');
    } on TimeoutException {
      lines.add(
        lines.isEmpty
            ? 'Page did not respond within ${timeout.inSeconds}s.'
            : 'Event loop: a 100ms timer did not fire within ${timeout.inSeconds}s; '
                  'JavaScript is likely paused in the debugger.',
      );
    }
    return lines.join(' ');
  }

  /// Describes how the page booted, for logging after every page load.
  ///
  /// The DDC loader counters show whether any script load had to be retried
  /// or failed, even when the page eventually started.
  Future<String> describeBoot() async {
    const timeout = Duration(seconds: 5);
    const bootState = r'''
(() => {
  const loader = window.$dartLoader?.loader;
  const navigation = performance.getEntriesByType('navigation')[0];
  return JSON.stringify({
    loader: loader ? {
      attempts: loader.attemptCount,
      loaded: loader.numLoaded,
      failed: loader.numFailed,
    } : null,
    resources: performance.getEntriesByType('resource').length,
    scriptTags: document.scripts.length,
    domContentLoadedMs: navigation ? Math.round(navigation.domContentLoadedEventEnd) : null,
    loadMs: navigation ? Math.round(navigation.loadEventEnd) : null,
    msSinceNavigationStart: Math.round(performance.now()),
  });
})()''';
    final String state = await _evaluate(
      _debugConnection!,
      bootState,
      awaitPromise: false,
      timeout: timeout,
    );
    return '$state ${await describeMemory()}';
  }

  /// Describes the number of documents, DOM nodes, and event listeners that
  /// exist in the page's renderer process, and its JavaScript heap size.
  ///
  /// The number of documents grows with every reload when old documents leak.
  Future<String> describeMemory() async {
    const timeout = Duration(seconds: 5);
    final WipConnection debugConnection = _debugConnection!;
    final WipResponse counters = await debugConnection
        .sendCommand('Memory.getDOMCounters')
        .timeout(timeout);
    final WipResponse heap = await debugConnection
        .sendCommand('Runtime.getHeapUsage')
        .timeout(timeout);
    final Map<String, dynamic> counterValues = counters.result!;
    final int heapUsedBytes = (heap.result!['usedSize'] as num).toInt();
    return 'documents=${counterValues['documents']} nodes=${counterValues['nodes']} '
        'jsEventListeners=${counterValues['jsEventListeners']} '
        'jsHeapUsed=${heapUsedBytes ~/ (1024 * 1024)}M';
  }

  /// Fetches [url] once and then 50 times concurrently from within the page,
  /// to find out whether the page can still load resources.
  ///
  /// The requests are `no-cors`, like the requests of `<script>` elements, so
  /// that they only fail when the browser fails to load them (for example with
  /// `net::ERR_INSUFFICIENT_RESOURCES`). If this fails with `TypeError: Failed
  /// to fetch` while [probeFreshTab] succeeds, the state that blocks requests
  /// is specific to this page's renderer process.
  Future<String> probePageFetch(Uri url) {
    return _evaluate(
      _debugConnection!,
      _fetchProbeScript(url),
      awaitPromise: true,
      timeout: const Duration(seconds: 20),
    );
  }

  /// Opens a new blank tab, fetches [fetchUrl] once and then 50 times
  /// concurrently from it, and closes the tab again.
  ///
  /// A new tab gets its own renderer process, so a success here combined with
  /// a failure of [probePageFetch] shows that the failure is specific to the
  /// original page's renderer. [describeProcesses] is called while the tab is
  /// open to show the new renderer process.
  ///
  /// The tab stays blank on purpose. Loading the app in it would start a second
  /// instance of the app, which would take part in the benchmark run.
  static Future<String> probeFreshTab({
    required int debugPort,
    required Uri fetchUrl,
    required String Function() describeProcesses,
  }) async {
    final client = io.HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final chromeConnection = ChromeConnection('localhost', debugPort);
    WipConnection? connection;
    String? tabId;
    try {
      final io.HttpClientRequest request = await client.openUrl(
        'PUT',
        Uri.parse('http://localhost:$debugPort/json/new?about:blank'),
      );
      final io.HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final newTab = json.decode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      final newTabId = newTab['id'] as String;
      tabId = newTabId;
      final ChromeTab? tab = await chromeConnection.getTab(
        (ChromeTab tab) => tab.id == newTabId,
        retryFor: const Duration(seconds: 5),
      );
      if (tab == null) {
        return 'the new tab $newTabId is not listed';
      }
      final WipConnection tabConnection = await tab.connect();
      connection = tabConnection;
      const evaluateTimeout = Duration(seconds: 10);
      var readyState = '?';
      for (var attempt = 0; attempt < 40 && readyState != 'complete'; attempt++) {
        readyState = await _evaluate(
          tabConnection,
          'document.readyState',
          awaitPromise: false,
          timeout: evaluateTimeout,
        );
        if (readyState != 'complete') {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      final String location = await _evaluate(
        tabConnection,
        'location.href',
        awaitPromise: false,
        timeout: evaluateTimeout,
      );
      final String fetches = await _evaluate(
        tabConnection,
        _fetchProbeScript(fetchUrl),
        awaitPromise: true,
        timeout: const Duration(seconds: 20),
      );
      return 'readyState=$readyState location=$location fetch=$fetches processes: ${describeProcesses()}';
    } on Exception catch (error) {
      return 'failed: $error';
    } finally {
      await connection?.close();
      final closingTabId = tabId;
      if (closingTabId != null) {
        try {
          final io.HttpClientRequest closeRequest = await client.getUrl(
            Uri.parse('http://localhost:$debugPort/json/close/$closingTabId'),
          );
          await (await closeRequest.close()).drain<void>();
        } on Exception catch (error) {
          print('[DIAG] Failed to close the probe tab $closingTabId: $error');
        }
      }
      chromeConnection.close();
      client.close(force: true);
    }
  }

  static String _fetchProbeScript(Uri url) {
    return '''
(async () => {
  const base = ${json.encode(url.toString())};
  const timed = async (suffix) => {
    const start = performance.now();
    try {
      const options = {cache: 'no-store', mode: 'no-cors'};
      const response = await fetch(base + suffix, options);
      await response.arrayBuffer();
      return {ok: true, status: response.status, ms: Math.round(performance.now() - start)};
    } catch (error) {
      return {ok: false, error: String(error), ms: Math.round(performance.now() - start)};
    }
  };
  const single = await timed('?diag=single');
  const burst = await Promise.all(Array.from({length: 50}, (_, i) => timed('?diag=burst' + i)));
  const failures = burst.filter((r) => !r.ok);
  return JSON.stringify({
    single,
    burst: {
      count: burst.length,
      failed: failures.length,
      firstError: failures.length ? failures[0].error : null,
      maxMs: Math.max(...burst.map((r) => r.ms)),
    },
  });
})()''';
  }

  /// Disconnects from the Chrome process without killing it.
  void disconnect() {
    _isStopped = true;
    _tracingSubscription?.cancel();
    _pageEventSubscription?.cancel();
  }

  /// Stops the Chrome process.
  void stop() {
    disconnect();
    _chromeProcess.kill();
  }
}

/// Limits how many messages of each category [Chrome.logPageEvents] prints for
/// each document.
///
/// A page that fails to load 1000+ scripts reports one error per script, which
/// would bury the rest of the log. The first messages of each category are
/// printed; the others are only counted, by category and by `net::ERR_*` code.
class _PageLogLimiter {
  static const int _maxPrintedPerCategory = 40;
  static final RegExp _networkErrorPattern = RegExp(r'net::ERR_[A-Z_]+');

  /// Messages seen in the current document by category.
  final Map<String, int> _seen = <String, int>{};

  /// Messages seen in the current document by `net::ERR_*` code.
  final Map<String, int> _networkErrors = <String, int>{};

  /// Counts a message of [category] and returns whether it should be printed.
  bool allow(String category, String message) {
    final int seen = (_seen[category] ?? 0) + 1;
    _seen[category] = seen;
    final String? networkError = _networkErrorPattern.firstMatch(message)?.group(0);
    if (networkError != null) {
      _networkErrors[networkError] = (_networkErrors[networkError] ?? 0) + 1;
    }
    return category == 'fatal' || category == 'navigation' || seen <= _maxPrintedPerCategory;
  }

  /// Describes the messages seen in the current document.
  String describeCounts() {
    final String seen = _seen.entries
        .map((MapEntry<String, int> e) => '${e.key}=${e.value}')
        .join(' ');
    final String networkErrors = _networkErrors.entries
        .map((MapEntry<String, int> e) => '${e.key}=${e.value}')
        .join(' ');
    return 'messages{$seen} networkErrors{$networkErrors}';
  }

  /// Describes the messages that were counted but not printed for the current
  /// document, then starts counting for a new document.
  ///
  /// Returns null if all messages were printed.
  String? takeSuppressedSummary() {
    final bool suppressed = _seen.values.any((int seen) => seen > _maxPrintedPerCategory);
    final summary = 'suppressed after $_maxPrintedPerCategory per category: ${describeCounts()}';
    _seen.clear();
    _networkErrors.clear();
    return suppressed ? summary : null;
  }
}

String _findSystemChromeExecutable() {
  // On some environments, such as the Dart HHH tester, Chrome resides in a
  // non-standard location and is provided via the following environment
  // variable.
  final String? envExecutable = io.Platform.environment['CHROME_EXECUTABLE'];
  if (envExecutable != null) {
    return envExecutable;
  }

  if (io.Platform.isLinux) {
    final io.ProcessResult which = io.Process.runSync('which', <String>['google-chrome']);

    if (which.exitCode != 0) {
      throw Exception('Failed to locate system Chrome installation.');
    }

    return (which.stdout as String).trim();
  } else if (io.Platform.isMacOS) {
    return '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  } else if (io.Platform.isWindows) {
    const kWindowsExecutable = r'Google\Chrome\Application\chrome.exe';
    final List<String> kWindowsPrefixes = <String?>[
      io.Platform.environment['LOCALAPPDATA'],
      io.Platform.environment['PROGRAMFILES'],
      io.Platform.environment['PROGRAMFILES(X86)'],
    ].whereType<String>().toList();
    final String windowsPrefix = kWindowsPrefixes.firstWhere((String prefix) {
      final String expectedPath = path.join(prefix, kWindowsExecutable);
      return io.File(expectedPath).existsSync();
    }, orElse: () => '.');
    return path.join(windowsPrefix, kWindowsExecutable);
  } else {
    throw Exception('Web benchmarks cannot run on ${io.Platform.operatingSystem}.');
  }
}

/// Waits for Chrome to print DevTools URI and connects to it.
Future<WipConnection> _connectToChromeDebugPort(int port, String? tabUrl) async {
  final Uri devtoolsUri = await _getRemoteDebuggerUrl(Uri.parse('http://localhost:$port'));
  print('Connecting to DevTools: $devtoolsUri');

  final String url = tabUrl ?? 'http://localhost';
  final chromeConnection = ChromeConnection('localhost', port);
  final ChromeTab? tab = await chromeConnection.getTab(
    (ChromeTab tab) => tab.url.startsWith(url),
    retryFor: const Duration(seconds: 5),
  );
  if (tab == null) {
    throw Exception('Chrome failed to open a tab for $url');
  }
  final WipConnection debugConnection = await tab.connect();
  print('Connected to Chrome tab: ${tab.title} (${tab.url})');
  return debugConnection;
}

/// Gets the Chrome debugger URL for the web page being benchmarked.
Future<Uri> _getRemoteDebuggerUrl(Uri base) async {
  final client = io.HttpClient();
  final io.HttpClientRequest request = await client.getUrl(base.resolve('/json/list'));
  final io.HttpClientResponse response = await request.close();
  final jsonObject = await json.fuse(utf8).decoder.bind(response).single as List<dynamic>?;
  if (jsonObject == null || jsonObject.isEmpty) {
    return base;
  }
  return base.resolve((jsonObject.first as Map<String, dynamic>)['webSocketDebuggerUrl'] as String);
}

/// Summarizes a Blink trace down to a few interesting values.
class BlinkTraceSummary {
  BlinkTraceSummary._({
    required this.averageBeginFrameTime,
    required this.averageUpdateLifecyclePhasesTime,
  }) : averageTotalUIFrameTime = averageBeginFrameTime + averageUpdateLifecyclePhasesTime;

  static BlinkTraceSummary? fromJson(List<Map<String, dynamic>> traceJson) {
    try {
      // Convert raw JSON data to BlinkTraceEvent objects sorted by timestamp.
      List<BlinkTraceEvent> events =
          traceJson.map<BlinkTraceEvent>(BlinkTraceEvent.fromJson).toList()
            ..sort((BlinkTraceEvent a, BlinkTraceEvent b) => a.ts! - b.ts!);

      Exception noMeasuredFramesFound() => Exception(
        'No measured frames found in benchmark tracing data. This likely '
        'indicates a bug in the benchmark. For example, the benchmark failed '
        "to pump enough frames. It may also indicate a change in Chrome's "
        'tracing data format. Check if Chrome version changed recently and '
        'adjust the parsing code accordingly.',
      );

      // Use the pid from the first "measured_frame" event since the event is
      // emitted by the script running on the process we're interested in.
      //
      // We previously tried using the "CrRendererMain" event. However, for
      // reasons unknown, Chrome in the devicelab refuses to emit this event
      // sometimes, causing to flakes.
      final BlinkTraceEvent firstMeasuredFrameEvent = events.firstWhere(
        (BlinkTraceEvent event) => event.isBeginMeasuredFrame,
        orElse: () => throw noMeasuredFramesFound(),
      );

      final int tabPid = firstMeasuredFrameEvent.pid!;

      // Filter out data from unrelated processes
      events = events.where((BlinkTraceEvent element) => element.pid == tabPid).toList();

      // Extract frame data.
      final frames = <BlinkFrame>[];
      var skipCount = 0;
      var frame = BlinkFrame();
      for (final event in events) {
        if (event.isBeginFrame) {
          frame.beginFrame = event;
        } else if (event.isUpdateAllLifecyclePhases) {
          frame.updateAllLifecyclePhases = event;
          if (frame.endMeasuredFrame != null) {
            frames.add(frame);
          } else {
            skipCount += 1;
          }
          frame = BlinkFrame();
        } else if (event.isBeginMeasuredFrame) {
          frame.beginMeasuredFrame = event;
        } else if (event.isEndMeasuredFrame) {
          frame.endMeasuredFrame = event;
        }
      }

      print('Extracted ${frames.length} measured frames.');
      print('Skipped $skipCount non-measured frames.');

      if (frames.isEmpty) {
        throw noMeasuredFramesFound();
      }

      // Compute averages and summarize.
      return BlinkTraceSummary._(
        averageBeginFrameTime: _computeAverageDuration(
          frames.map((BlinkFrame frame) => frame.beginFrame).whereType<BlinkTraceEvent>().toList(),
        ),
        averageUpdateLifecyclePhasesTime: _computeAverageDuration(
          frames
              .map((BlinkFrame frame) => frame.updateAllLifecyclePhases)
              .whereType<BlinkTraceEvent>()
              .toList(),
        ),
      );
    } catch (_) {
      final traceFile = io.File('./chrome-trace.json');
      io.stderr.writeln(
        'Failed to interpret the Chrome trace contents. The trace was saved in ${traceFile.path}',
      );
      traceFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(traceJson));
      rethrow;
    }
  }

  /// The average duration of "WebViewImpl::beginFrame" events.
  ///
  /// This event contains all of scripting time of an animation frame, plus an
  /// unknown small amount of work browser does before and after scripting.
  final Duration averageBeginFrameTime;

  /// The average duration of "WebViewImpl::updateAllLifecyclePhases" events.
  ///
  /// This event contains style, layout, painting, and compositor computations,
  /// which are not included in the scripting time. This event does not
  /// include GPU time, which happens on a separate thread.
  final Duration averageUpdateLifecyclePhasesTime;

  /// The average sum of [averageBeginFrameTime] and
  /// [averageUpdateLifecyclePhasesTime].
  ///
  /// This value contains the vast majority of work the UI thread performs in
  /// any given animation frame.
  final Duration averageTotalUIFrameTime;

  @override
  String toString() =>
      '$BlinkTraceSummary('
      'averageBeginFrameTime: ${averageBeginFrameTime.inMicroseconds / 1000}ms, '
      'averageUpdateLifecyclePhasesTime: ${averageUpdateLifecyclePhasesTime.inMicroseconds / 1000}ms)';
}

/// Contains events pertaining to a single frame in the Blink trace data.
class BlinkFrame {
  /// Corresponds to 'WebViewImpl::beginFrame' event.
  BlinkTraceEvent? beginFrame;

  /// Corresponds to 'WebViewImpl::updateAllLifecyclePhases' event.
  BlinkTraceEvent? updateAllLifecyclePhases;

  /// Corresponds to 'measured_frame' begin event.
  BlinkTraceEvent? beginMeasuredFrame;

  /// Corresponds to 'measured_frame' end event.
  BlinkTraceEvent? endMeasuredFrame;
}

/// Takes a list of events that have non-null [BlinkTraceEvent.tdur] computes
/// their average as a [Duration] value.
Duration _computeAverageDuration(List<BlinkTraceEvent> events) {
  // Compute the sum of "tdur" fields of the last _kMeasuredSampleCount events.
  final double sum = events.skip(math.max(events.length - _kMeasuredSampleCount, 0)).fold(0.0, (
    double previousValue,
    BlinkTraceEvent event,
  ) {
    final int? duration = event.tdur ?? event.dur;
    if (duration == null) {
      throw FormatException('Trace event lacks "tdur" and "dur" fields: $event');
    }
    return previousValue + duration;
  });
  final int sampleCount = math.min(events.length, _kMeasuredSampleCount);
  return Duration(microseconds: sum ~/ sampleCount);
}

/// An event collected by the Blink tracer (in Chrome accessible using chrome://tracing).
///
/// See also:
///  * https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU/preview
class BlinkTraceEvent {
  /// Parses an event from its JSON representation.
  ///
  /// Sample event encoded as JSON (the data is bogus, this just shows the format):
  ///
  /// ```json
  /// {
  ///   "name": "myName",
  ///   "cat": "category,list",
  ///   "ph": "B",
  ///   "ts": 12345,
  ///   "pid": 123,
  ///   "tid": 456,
  ///   "args": {
  ///     "someArg": 1,
  ///     "anotherArg": {
  ///       "value": "my value"
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// For detailed documentation of the format see:
  ///
  /// https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU/preview
  BlinkTraceEvent.fromJson(Map<String, dynamic> json)
    : args = json['args'] as Map<String, dynamic>,
      cat = json['cat'] as String,
      name = json['name'] as String,
      ph = json['ph'] as String,
      pid = _readInt(json, 'pid'),
      tid = _readInt(json, 'tid'),
      ts = _readInt(json, 'ts'),
      tts = _readInt(json, 'tts'),
      tdur = _readInt(json, 'tdur'),
      dur = _readInt(json, 'dur');

  /// Event-specific data.
  final Map<String, dynamic> args;

  /// Event category.
  final String cat;

  /// Event name.
  final String name;

  /// Event "phase".
  final String ph;

  /// Process ID of the process that emitted the event.
  final int? pid;

  /// Thread ID of the thread that emitted the event.
  final int? tid;

  /// Timestamp in microseconds using tracer clock.
  final int? ts;

  /// Timestamp in microseconds using thread clock.
  final int? tts;

  /// Event duration in microseconds.
  final int? tdur;

  /// Wall-clock event duration in microseconds.
  final int? dur;

  /// A "begin frame" event contains all of the scripting time of an animation
  /// frame (JavaScript, WebAssembly), plus a negligible amount of internal
  /// browser overhead.
  ///
  /// This event does not include non-UI thread scripting, such as web workers,
  /// service workers, and CSS Paint paintlets.
  ///
  /// WebViewImpl::beginFrame was used in earlier versions of Chrome, kept
  /// for compatibility.
  ///
  /// This event is a duration event that has its `tdur` populated.
  bool get isBeginFrame {
    return ph == 'X' &&
        (name == 'WebViewImpl::beginFrame' ||
            name == 'WebFrameWidgetBase::BeginMainFrame' ||
            name == 'WebFrameWidgetImpl::BeginMainFrame');
  }

  /// An "update all lifecycle phases" event contains UI thread computations
  /// related to an animation frame that's outside the scripting phase.
  ///
  /// This event includes style recalculation, layer tree update, layout,
  /// painting, and parts of compositing work.
  ///
  /// WebViewImpl::updateAllLifecyclePhases was used in earlier versions of
  /// Chrome, kept for compatibility.
  ///
  /// This event is a duration event that has its `tdur` populated.
  bool get isUpdateAllLifecyclePhases {
    return ph == 'X' &&
        (name == 'WebViewImpl::updateAllLifecyclePhases' ||
            name == 'WebFrameWidgetImpl::UpdateLifecycle');
  }

  /// Whether this is the beginning of a "measured_frame" event.
  ///
  /// This event is a custom event emitted by our benchmark test harness.
  ///
  /// See also:
  ///  * `recorder.dart`, which emits this event.
  bool get isBeginMeasuredFrame => ph == 'b' && name == 'measured_frame';

  /// Whether this is the end of a "measured_frame" event.
  ///
  /// This event is a custom event emitted by our benchmark test harness.
  ///
  /// See also:
  ///  * `recorder.dart`, which emits this event.
  bool get isEndMeasuredFrame => ph == 'e' && name == 'measured_frame';

  @override
  String toString() =>
      '$BlinkTraceEvent('
      'args: ${json.encode(args)}, '
      'cat: $cat, '
      'name: $name, '
      'ph: $ph, '
      'pid: $pid, '
      'tid: $tid, '
      'ts: $ts, '
      'tts: $tts, '
      'tdur: $tdur)';
}

/// Read an integer out of [json] stored under [key].
///
/// Since JSON does not distinguish between `int` and `double`, extra
/// validation and conversion is needed.
///
/// Returns null if the value is null.
int? _readInt(Map<String, dynamic> json, String key) {
  final jsonValue = json[key] as num?;
  return jsonValue?.toInt();
}

/// Used by [Chrome.launch] to detect a glibc bug and retry launching the
/// browser.
///
/// Once every few thousands of launches we hit this glibc bug:
///
/// https://sourceware.org/bugzilla/show_bug.cgi?id=19329.
///
/// When this happens Chrome spits out something like the following then exits with code 127:
///
///     Inconsistency detected by ld.so: ../elf/dl-tls.c: 493: _dl_allocate_tls_init: Assertion `listp->slotinfo[cnt].gen <= GL(dl_tls_generation)' failed!
const String _kGlibcError = 'Inconsistency detected by ld.so';

/// Filters out non-fatal D-Bus connection error messages emitted by Chromium.
///
/// Headless Linux Chrome attempts to query Linux D-Bus desktop services (such as
/// system theme, desktop notifications, and keyrings) when `DBUS_SESSION_BUS_ADDRESS`
/// is missing or disabled. Chromium logs non-fatal fallback notices to stderr via
/// `LOG(ERROR)` in `dbus/bus.cc` (see
/// https://chromium.googlesource.com/chromium/src/+/refs/heads/main/dbus/bus.cc#405)
/// and `dbus/object_proxy.cc`.
///
/// We filter out these benign D-Bus lines to prevent stderr log noise in CI,
/// following the industry standard pattern used by open source projects to filter
/// E2E test logs (e.g. https://github.com/kitelev/exocortex/blob/4290cdade669034e5f71c892fb3e1908c5a2fe12/packages/obsidian-plugin/docker-entrypoint-e2e.sh#L48-L49).
bool _isDbusError(String line) {
  return line.contains('ERROR:dbus/bus.cc') ||
      line.contains('ERROR:dbus/object_proxy.cc') ||
      line.contains('Failed to connect to the bus') ||
      line.contains('org.freedesktop.DBus');
}

Future<io.Process> _spawnChromiumProcess(
  String executable,
  List<String> args, {
  required bool silent,
  String? workingDirectory,
}) async {
  // Keep attempting to launch the browser until one of:
  // - Chrome launched successfully, in which case we just return from the loop.
  // - The tool detected an unretryable Chrome error, in which case we throw ToolExit.
  while (true) {
    final io.Process process = await io.Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
    );

    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((String line) {
      if (!silent) {
        print('[CHROME STDOUT]: $line');
      }
    });

    // Wait until the DevTools are listening before trying to connect. This is
    // only required for flutter_test --platform=chrome and not flutter run.
    var hitGlibcBug = false;
    await process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((String line) => !_isDbusError(line))
        .map((String line) {
          if (!silent) {
            print('[CHROME STDERR]:$line');
          }
          if (line.contains(_kGlibcError)) {
            hitGlibcBug = true;
          }
          return line;
        })
        .firstWhere(
          (String line) => line.startsWith('DevTools listening'),
          orElse: () {
            if (hitGlibcBug) {
              print(
                'Encountered glibc bug https://sourceware.org/bugzilla/show_bug.cgi?id=19329. '
                'Will try launching browser again.',
              );
              return '';
            }
            print('Failed to launch browser. Command used to launch it: ${args.join(' ')}');
            throw Exception(
              'Failed to launch browser. Make sure you are using an up-to-date '
              'Chrome or Edge. Otherwise, consider using -d web-server instead '
              'and filing an issue at https://github.com/flutter/flutter/issues.',
            );
          },
        );

    if (!hitGlibcBug) {
      return process;
    }

    // A precaution that avoids accumulating browser processes, in case the
    // glibc bug doesn't cause the browser to quit and we keep looping and
    // launching more processes.
    unawaited(
      process.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          process.kill();
          return 0;
        },
      ),
    );
  }
}
