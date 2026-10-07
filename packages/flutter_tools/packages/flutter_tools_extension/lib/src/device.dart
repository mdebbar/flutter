// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart';

import 'protocol_base/service.dart';

/// Extension service interface for retrieving target devices.
abstract base class DeviceService extends ToolExtensionService {
  /// Service namespace identifier for device services.
  static const String serviceNamespace = 'device';

  /// RPC method identifier to query contributed target devices.
  static const String getDevicesMethod = 'device.getDevices';

  /// RPC method identifier to query whether a target device is supported for a project.
  static const String isSupportedForProjectMethod = 'device.isSupportedForProject';

  /// RPC method identifier to launch an application on a target device.
  static const String startAppMethod = 'device.startApp';

  /// RPC method identifier to reload or restart a running application on a target device.
  static const String reloadAppMethod = 'device.reloadApp';

  /// RPC method identifier to stop a running application on a target device.
  static const String stopAppMethod = 'device.stopApp';

  /// RPC parameter key for the target device ID.
  static const String deviceIdParam = 'deviceId';

  /// RPC parameter key for the project root URI or path.
  static const String projectRootParam = 'projectRoot';

  /// RPC parameter key for the entrypoint Dart file path.
  static const String mainPathParam = 'mainPath';

  /// RPC parameter key for the build mode (`'debug'`, `'profile'`, `'release'`).
  static const String buildModeParam = 'buildMode';

  /// RPC parameter key for the initial route.
  static const String routeParam = 'route';

  /// RPC parameter key for optional launch options.
  static const String optionsParam = 'options';

  /// RPC parameter key for whether a reload should be a full restart.
  static const String fullRestartParam = 'fullRestart';

  @override
  String get namespace => serviceNamespace;

  /// Returns the target devices contributed by this extension.
  Future<List<TargetDevice>> getDevices();

  /// Returns whether the target device with [deviceId] is supported for the
  /// Flutter project at [projectRoot].
  Future<bool> isSupportedForProject({required String deviceId, required Uri projectRoot});

  /// Launches the application at [projectRoot] on the target device with [deviceId].
  Future<ExtensionLaunchResult> startApp({
    required String deviceId,
    required String projectRoot,
    required String mainPath,
    required String buildMode,
    String? route,
    Map<String, Object?> options = const <String, Object?>{},
  }) async => const ExtensionLaunchResult(
    succeeded: false,
    errorMessage: 'startApp is not implemented by this extension.',
  );

  /// Reloads or restarts the running application on the target device with [deviceId].
  Future<ExtensionReloadResult> reloadApp({
    required String deviceId,
    bool fullRestart = false,
  }) async => const ExtensionReloadResult(
    succeeded: false,
    message: 'reloadApp is not implemented by this extension.',
  );

  /// Stops the running application on the target device with [deviceId].
  Future<bool> stopApp({required String deviceId}) async => true;

  @override
  Future<Map<String, ExtensionRpcHandler>> initialize() async {
    return <String, ExtensionRpcHandler>{
      'getDevices': _getDevicesRpc,
      'isSupportedForProject': _isSupportedForProjectRpc,
      'startApp': _startAppRpc,
      'reloadApp': _reloadAppRpc,
      'stopApp': _stopAppRpc,
    };
  }

  @override
  Future<void> shutdown() async {}

  Future<List<Map<String, Object?>>> _getDevicesRpc(Map<String, Object?> _) async {
    final List<TargetDevice> devices = await getDevices();
    return devices.map((TargetDevice device) => device.toMap()).toList();
  }

  Future<bool> _isSupportedForProjectRpc(Map<String, Object?> params) async {
    final String deviceId = params[deviceIdParam] as String? ?? '';
    final String projectRootStr = params[projectRootParam] as String? ?? '';
    return isSupportedForProject(deviceId: deviceId, projectRoot: Uri.parse(projectRootStr));
  }

  Future<Map<String, Object?>> _startAppRpc(Map<String, Object?> params) async {
    final String deviceId = params[deviceIdParam] as String? ?? '';
    final String projectRoot = params[projectRootParam] as String? ?? '';
    final String mainPath = params[mainPathParam] as String? ?? 'lib/main.dart';
    final String buildMode = params[buildModeParam] as String? ?? 'debug';
    final route = params[routeParam] as String?;
    final Map<String, Object?> options = switch (params[optionsParam]) {
      final Map<String, Object?> map => map,
      final Map<Object?, Object?> map => map.cast<String, Object?>(),
      _ => const <String, Object?>{},
    };
    final ExtensionLaunchResult result = await startApp(
      deviceId: deviceId,
      projectRoot: projectRoot,
      mainPath: mainPath,
      buildMode: buildMode,
      route: route,
      options: options,
    );
    return result.toMap();
  }

  Future<Map<String, Object?>> _reloadAppRpc(Map<String, Object?> params) async {
    final String deviceId = params[deviceIdParam] as String? ?? '';
    final bool fullRestart = params[fullRestartParam] as bool? ?? false;
    final ExtensionReloadResult result = await reloadApp(
      deviceId: deviceId,
      fullRestart: fullRestart,
    );
    return result.toMap();
  }

  Future<bool> _stopAppRpc(Map<String, Object?> params) async {
    final String deviceId = params[deviceIdParam] as String? ?? '';
    return stopApp(deviceId: deviceId);
  }
}
