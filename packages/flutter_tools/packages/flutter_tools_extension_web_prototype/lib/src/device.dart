// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'build.dart';
import 'diagnostics.dart';

class _WebAppSession {
  _WebAppSession({
    required this.server,
    required this.projectRoot,
    required this.mainPath,
    required this.buildMode,
    required this.options,
    this.chromeProcess,
    this.userDataDir,
    this.debugPort,
  });

  final HttpServer server;
  final String projectRoot;
  final String mainPath;
  final String buildMode;
  final Map<String, Object?> options;
  final Process? chromeProcess;
  final Directory? userDataDir;
  final int? debugPort;
}

/// Prototype Web [DeviceService] implementation providing `chrome` and `web-server` devices.
final class WebDeviceService extends DeviceService {
  /// Creates a [WebDeviceService] backed by [WebBuildService].
  WebDeviceService({required this._buildService})
    : _findChromeExecutable = WebExtensionDiagnostics.findChromeExecutable,
      _getChromeVersion = WebExtensionDiagnostics.getChromeVersion;

  /// Creates a [WebDeviceService] with custom Chrome discovery callbacks for testing.
  WebDeviceService.withOverrides({
    required this._buildService,
    required this._findChromeExecutable,
    required this._getChromeVersion,
  });

  final WebBuildService _buildService;
  final Future<String?> Function() _findChromeExecutable;
  final Future<String> Function(String executable) _getChromeVersion;
  final Map<String, _WebAppSession> _sessions = <String, _WebAppSession>{};

  /// Returns whether an active web session exists for [deviceId].
  bool hasActiveSession(String deviceId) => _sessions.containsKey(deviceId);

  @override
  Future<List<TargetDevice>> getDevices() async {
    final String? chromeExecutable = await _findChromeExecutable();
    final String chromeVersion = chromeExecutable != null
        ? await _getChromeVersion(chromeExecutable)
        : 'Google Chrome';

    return <TargetDevice>[
      TargetDevice(
        category: Category.web,
        id: 'chrome',
        name: 'Chrome (web)',
        ephemeral: false,
        sdkNameAndVersion: chromeVersion,
        targetPlatform: 'web-javascript',
      ),
      const TargetDevice(
        category: Category.web,
        id: 'web-server',
        name: 'Web Server (web)',
        ephemeral: false,
        sdkNameAndVersion: 'Flutter Tools',
        targetPlatform: 'web-javascript',
      ),
    ];
  }

  @override
  Future<bool> isSupportedForProject({required String deviceId, required Uri projectRoot}) async {
    if (deviceId != 'chrome' && deviceId != 'web-server') {
      return false;
    }
    return Directory.fromUri(projectRoot.resolve('web')).existsSync() ||
        File.fromUri(projectRoot.resolve('pubspec.yaml')).existsSync();
  }

  @override
  Future<ExtensionLaunchResult> startApp({
    required String deviceId,
    required String projectRoot,
    required String mainPath,
    required String buildMode,
    String? route,
    Map<String, Object?> options = const <String, Object?>{},
  }) async {
    if (deviceId != 'chrome' && deviceId != 'web-server') {
      return ExtensionLaunchResult(
        succeeded: false,
        errorMessage: 'Unsupported web device: "$deviceId".',
      );
    }

    if (_sessions.containsKey(deviceId)) {
      await stopApp(deviceId: deviceId);
    }

    final ExtensionBuildResult buildResult = await _buildService.build(
      targetName: 'web',
      projectRoot: projectRoot,
      mainPath: mainPath,
      buildMode: buildMode,
      options: options,
    );
    if (!buildResult.success) {
      return ExtensionLaunchResult(succeeded: false, errorMessage: buildResult.errorMessage);
    }

    final String buildWebDir = buildResult.outputDirectory ?? p.join(projectRoot, 'build', 'web');
    final Handler handler = createStaticHandler(buildWebDir, defaultDocument: 'index.html');
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    shelf_io.serveRequests(server, handler);

    final String normalizedRoute = switch (route) {
      final String r when r.startsWith('/') => r.substring(1),
      final String r => r,
      null => '',
    };
    final appUrl = 'http://localhost:${server.port}/$normalizedRoute';

    Process? chromeProcess;
    Directory? userDataDir;
    int? debugPort;

    if (deviceId == 'chrome' && options['launchChrome'] != false) {
      final String? chromeExecutable = await _findChromeExecutable();
      if (chromeExecutable != null) {
        try {
          debugPort = await _findFreePort();
          userDataDir = Directory.systemTemp.createTempSync('flutter_web_ext_chrome.');
          final bool useHeadless =
              options['headless'] == true ||
              (Platform.isLinux && Platform.environment['DISPLAY'] == null);
          final args = <String>[
            '--user-data-dir=${userDataDir.path}',
            '--remote-debugging-port=$debugPort',
            '--no-first-run',
            '--no-default-browser-check',
            '--disable-extensions',
            '--disable-popup-blocking',
            if (useHeadless) ...<String>['--headless', '--disable-gpu', '--no-sandbox'],
            appUrl,
          ];
          chromeProcess = await Process.start(chromeExecutable, args);
        } on Object {
          // Allow serving to continue even if spawning the browser fails in a restricted environment.
        }
      }
    }

    _sessions[deviceId] = _WebAppSession(
      server: server,
      projectRoot: projectRoot,
      mainPath: mainPath,
      buildMode: buildMode,
      options: options,
      chromeProcess: chromeProcess,
      userDataDir: userDataDir,
      debugPort: debugPort,
    );

    return ExtensionLaunchResult(succeeded: true, appUrl: 'http://localhost:${server.port}/');
  }

  @override
  Future<ExtensionReloadResult> reloadApp({
    required String deviceId,
    bool fullRestart = false,
  }) async {
    final _WebAppSession? session = _sessions[deviceId];
    if (session == null) {
      return const ExtensionReloadResult(
        succeeded: false,
        message: 'No active web session for device.',
      );
    }

    final ExtensionBuildResult buildResult = await _buildService.build(
      targetName: 'web',
      projectRoot: session.projectRoot,
      mainPath: session.mainPath,
      buildMode: session.buildMode,
      options: session.options,
    );
    if (!buildResult.success) {
      return ExtensionReloadResult(
        succeeded: false,
        message: buildResult.errorMessage ?? 'Failed to rebuild web application.',
      );
    }

    final int? debugPort = session.debugPort;
    if (debugPort != null) {
      final chromeConnection = ChromeConnection('localhost', debugPort);
      try {
        final List<ChromeTab> tabs = await chromeConnection.getTabs().timeout(
          const Duration(seconds: 1),
        );
        if (tabs.isNotEmpty) {
          final WipConnection wipConnection = await tabs.first.connect().timeout(
            const Duration(seconds: 1),
          );
          await wipConnection.page.reload().timeout(const Duration(seconds: 1));
          await wipConnection.close();
        }
      } on Object {
        // Ignore DevTools connection errors when running in headless or web-server mode.
      } finally {
        chromeConnection.close();
      }
    }

    return ExtensionReloadResult(
      succeeded: true,
      message: fullRestart ? 'Restarted web application.' : 'Reloaded web application.',
    );
  }

  @override
  Future<bool> stopApp({required String deviceId}) async {
    final _WebAppSession? session = _sessions.remove(deviceId);
    if (session == null) {
      return true;
    }

    await _cleanupSession(session);
    return true;
  }

  @override
  Future<void> shutdown() async {
    final List<_WebAppSession> activeSessions = _sessions.values.toList();
    _sessions.clear();
    for (final session in activeSessions) {
      await _cleanupSession(session);
    }
  }

  Future<void> _cleanupSession(_WebAppSession session) async {
    try {
      await session.server.close(force: true);
    } on Object {
      // Ignore server close errors.
    }
    try {
      session.chromeProcess?.kill();
    } on Object {
      // Ignore process kill errors.
    }
    final Directory? userDataDir = session.userDataDir;
    if (userDataDir != null && userDataDir.existsSync()) {
      try {
        userDataDir.deleteSync(recursive: true);
      } on Object {
        // Ignore temporary directory cleanup errors.
      }
    }
  }

  static Future<int> _findFreePort() async {
    final ServerSocket socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final int port = socket.port;
    await socket.close();
    return port;
  }
}
