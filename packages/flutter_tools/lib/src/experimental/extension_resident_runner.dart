// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';

import '../device.dart';
import '../resident_runner.dart';
import 'extension_device_manager.dart';

/// A [ResidentRunner] that delegates application launch, hot reload, hot restart,
/// and teardown to an out-of-process tool extension via [ExtensionBackedDevice].
class ExtensionResidentRunner extends ResidentRunner {
  /// Creates an [ExtensionResidentRunner].
  ExtensionResidentRunner(
    super.flutterDevices, {
    required super.target,
    required super.debuggingOptions,
    super.stayResident = true,
    this.ipv6 = false,
    super.projectRootPath,
    super.machine = false,
  });

  /// Whether IPv6 networking is enabled.
  final bool ipv6;

  ExtensionBackedDevice get _extensionDevice =>
      flutterDevices.first.device! as ExtensionBackedDevice;

  @override
  bool get supportsDetach => false;

  @override
  Future<int> run({
    Completer<DebugConnectionInfo>? connectionInfoCompleter,
    Completer<void>? appStartedCompleter,
    String? route,
  }) async {
    final LaunchResult result = await _extensionDevice.startApp(
      null,
      mainPath: target,
      route: route,
      debuggingOptions: debuggingOptions,
      ipv6: ipv6,
    );
    if (!result.started) {
      appFailedToStart();
      return 1;
    }

    if (connectionInfoCompleter != null && !connectionInfoCompleter.isCompleted) {
      connectionInfoCompleter.complete(
        DebugConnectionInfo(wsUri: result.vmServiceUri, baseUri: _extensionDevice.lastAppUrl),
      );
    }
    if (appStartedCompleter != null && !appStartedCompleter.isCompleted) {
      appStartedCompleter.complete();
    }

    if (stayResident) {
      printHelp(details: false);
      return waitForAppToFinish();
    }
    await exitApp();
    return 0;
  }

  @override
  Future<int> attach({
    Completer<DebugConnectionInfo>? connectionInfoCompleter,
    Completer<void>? appStartedCompleter,
    bool needsFullRestart = true,
  }) async {
    if (appStartedCompleter != null && !appStartedCompleter.isCompleted) {
      appStartedCompleter.complete();
    }
    if (stayResident) {
      return waitForAppToFinish();
    }
    await cleanupAtFinish();
    return 0;
  }

  @override
  Future<OperationResult> restart({
    bool fullRestart = false,
    String? reason,
    bool silent = false,
    bool pause = false,
  }) async {
    final ExtensionReloadResult res = await _extensionDevice.reloadExtensionApp(
      fullRestart: fullRestart,
    );
    if (res.succeeded) {
      final String message =
          res.message ?? (fullRestart ? 'Restarted application.' : 'Reloaded application.');
      if (!silent) {
        logger.printStatus(message);
      }
      return OperationResult(0, message);
    }
    final String errorMessage = res.message ?? 'Reload failed.';
    logger.printError(errorMessage);
    return OperationResult(1, errorMessage);
  }

  @override
  Future<void> cleanupAfterSignal() async {
    await _extensionDevice.stopApp(null);
  }

  @override
  Future<void> cleanupAtFinish() async {
    await _extensionDevice.stopApp(null);
  }
}
