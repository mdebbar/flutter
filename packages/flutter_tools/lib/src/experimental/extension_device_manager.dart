// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

import '../application_package.dart';
import '../base/logger.dart';
import '../build_info.dart';
import '../device.dart' hide Category;
import '../device_port_forwarder.dart';
import '../globals.dart' as globals;
import '../project.dart';
import 'extension_discovery.dart';
import 'extension_manager.dart';

/// A host-side [DeviceService] client adapter delegating RPC queries to an [ExtensionConnection].
final class ExtensionDeviceClient extends DeviceService {
  /// Creates an [ExtensionDeviceClient] wrapping the host [connection].
  ExtensionDeviceClient(this.connection, {required this._logger});

  /// The active extension isolate connection.
  final ExtensionConnection connection;
  final Logger _logger;

  @override
  Future<List<TargetDevice>> getDevices() async {
    _logger.printTrace(
      'ExtensionDeviceClient fetching devices via RPC ("${DeviceService.getDevicesMethod}")...',
    );
    try {
      final Object? rawResult = await connection
          .sendRequest(DeviceService.getDevicesMethod)
          .timeout(const Duration(seconds: 5));
      final List<TargetDevice> devices = TargetDevice.listFromJson(rawResult);
      _logger.printTrace('ExtensionDeviceClient received ${devices.length} device(s) via RPC.');
      return devices;
    } on Object catch (err, stack) {
      _logger.printTrace('ExtensionDeviceClient failed to get devices: $err\n$stack');
    }
    return const <TargetDevice>[];
  }

  @override
  Future<bool> isSupportedForProject({required String deviceId, required Uri projectRoot}) async {
    _logger.printTrace(
      'ExtensionDeviceClient checking project support for "$deviceId" via RPC '
      '("${DeviceService.isSupportedForProjectMethod}")...',
    );
    try {
      final Object? rawResult = await connection
          .sendRequest(DeviceService.isSupportedForProjectMethod, <String, Object?>{
            DeviceService.deviceIdParam: deviceId,
            DeviceService.projectRootParam: projectRoot.toString(),
          })
          .timeout(const Duration(seconds: 5));
      if (rawResult case final bool supported) {
        return supported;
      }
    } on Object catch (err, stack) {
      _logger.printTrace(
        'ExtensionDeviceClient failed to check project support for "$deviceId": $err\n$stack',
      );
    }
    return false;
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
    _logger.printTrace(
      'ExtensionDeviceClient starting app on "$deviceId" via RPC '
      '("${DeviceService.startAppMethod}")...',
    );
    try {
      final Object? rawResult = await connection
          .sendRequest(DeviceService.startAppMethod, <String, Object?>{
            DeviceService.deviceIdParam: deviceId,
            DeviceService.projectRootParam: projectRoot,
            DeviceService.mainPathParam: mainPath,
            DeviceService.buildModeParam: buildMode,
            DeviceService.routeParam: ?route,
            DeviceService.optionsParam: options,
          })
          .timeout(const Duration(minutes: 5));
      if (rawResult case final Map<String, Object?> map) {
        return ExtensionLaunchResult.fromJson(map);
      }
      if (rawResult case final Map<Object?, Object?> map) {
        return ExtensionLaunchResult.fromJson(map.cast<String, Object?>());
      }
    } on Object catch (err, stack) {
      _logger.printTrace('ExtensionDeviceClient failed to start app on "$deviceId": $err\n$stack');
      return ExtensionLaunchResult(
        succeeded: false,
        errorMessage: 'Extension startApp RPC failed: $err',
      );
    }
    return const ExtensionLaunchResult(
      succeeded: false,
      errorMessage: 'Invalid response from extension startApp service.',
    );
  }

  @override
  Future<ExtensionReloadResult> reloadApp({
    required String deviceId,
    bool fullRestart = false,
  }) async {
    _logger.printTrace(
      'ExtensionDeviceClient reloading app on "$deviceId" via RPC '
      '("${DeviceService.reloadAppMethod}")...',
    );
    try {
      final Object? rawResult = await connection
          .sendRequest(DeviceService.reloadAppMethod, <String, Object?>{
            DeviceService.deviceIdParam: deviceId,
            DeviceService.fullRestartParam: fullRestart,
          })
          .timeout(const Duration(minutes: 5));
      if (rawResult case final Map<String, Object?> map) {
        return ExtensionReloadResult.fromJson(map);
      }
      if (rawResult case final Map<Object?, Object?> map) {
        return ExtensionReloadResult.fromJson(map.cast<String, Object?>());
      }
    } on Object catch (err, stack) {
      _logger.printTrace('ExtensionDeviceClient failed to reload app on "$deviceId": $err\n$stack');
      return ExtensionReloadResult(
        succeeded: false,
        message: 'Extension reloadApp RPC failed: $err',
      );
    }
    return const ExtensionReloadResult(
      succeeded: false,
      message: 'Invalid response from extension reloadApp service.',
    );
  }

  @override
  Future<bool> stopApp({required String deviceId}) async {
    _logger.printTrace(
      'ExtensionDeviceClient stopping app on "$deviceId" via RPC '
      '("${DeviceService.stopAppMethod}")...',
    );
    try {
      final Object? rawResult = await connection
          .sendRequest(DeviceService.stopAppMethod, <String, Object?>{
            DeviceService.deviceIdParam: deviceId,
          })
          .timeout(const Duration(seconds: 5));
      if (rawResult case final bool stopped) {
        return stopped;
      }
    } on Object catch (err, stack) {
      _logger.printTrace('ExtensionDeviceClient failed to stop app on "$deviceId": $err\n$stack');
    }
    return false;
  }
}

/// A host-side [DeviceDiscovery] mechanism that discovers devices registered by active extensions.
class ExtensionDevices extends PollingDeviceDiscovery {
  /// Creates an [ExtensionDevices] instance.
  ExtensionDevices({required this._extensionManager, required this._logger})
    : super('tool_extension');

  final ExtensionManager _extensionManager;
  final Logger _logger;

  @override
  bool get supportsPlatform => true;

  @override
  bool get canListAnything => true;

  @override
  List<String> get wellKnownIds => const <String>[];

  @override
  Future<List<Device>> pollingGetDevices({
    Duration? timeout,
    bool forWirelessDiscovery = false,
  }) async {
    _logger.printTrace('ExtensionDevices polling active tool extension devices...');
    await _extensionManager.ensureInitialized();
    final List<DeviceService> deviceServices = _extensionManager.deviceExtensions;
    if (deviceServices.isEmpty) {
      _logger.printTrace('ExtensionDevices found 0 active device extensions.');
      return <Device>[];
    }

    final List<List<Device>> devicesPerService = await Future.wait(
      deviceServices.whereType<ExtensionDeviceClient>().map((ExtensionDeviceClient service) async {
        try {
          final List<TargetDevice> devices = await service.getDevices();
          return devices
              .map(
                (TargetDevice targetDevice) => ExtensionBackedDevice(
                  connection: service.connection,
                  deviceService: service,
                  logger: _logger,
                  targetDevice: targetDevice,
                ),
              )
              .toList();
        } on Object catch (e, st) {
          _logger.printTrace('Error querying device extension service: $e\n$st');
          return <Device>[];
        }
      }),
    );

    final targetDevices = <Device>[for (final deviceList in devicesPerService) ...deviceList];

    _logger.printTrace('ExtensionDevices retrieved ${targetDevices.length} target device(s).');
    return targetDevices;
  }

  @override
  Future<List<String>> getDiagnostics() async => <String>[];
}

/// A host-side [Device] wrapper representing a target device backed by a tool extension.
class ExtensionBackedDevice extends Device {
  /// Creates an [ExtensionBackedDevice] wrapping a [TargetDevice].
  ExtensionBackedDevice({
    required this.connection,
    required this._deviceService,
    required this._logger,
    required TargetDevice targetDevice,
  }) : _targetDevice = targetDevice,
       super(
         targetDevice.id,
         category: targetDevice.category,
         platformType: targetDevice.category == Category.web
             ? PlatformType.web
             : PlatformType.custom,
         ephemeral: targetDevice.ephemeral,
         logger: _logger,
       );

  final DeviceService _deviceService;
  final Logger _logger;
  final TargetDevice _targetDevice;
  final ExtensionConnection connection;

  /// The application URL returned by the last [startApp] invocation, if any.
  String? lastAppUrl;

  @override
  String get name => _targetDevice.name;

  @override
  Future<bool> isSupported() async => _targetDevice.isSupported;

  @override
  FutureOr<bool> supportsRuntimeMode(BuildMode buildMode) => true;

  @override
  bool get supportsHotReload => true;

  @override
  bool get supportsHotRestart => true;

  @override
  Future<bool> isSupportedForProject(FlutterProject flutterProject) =>
      _deviceService.isSupportedForProject(deviceId: id, projectRoot: flutterProject.directory.uri);

  @override
  Future<CpuArch> get cpuArch async => CpuArch.unknown;

  @override
  Future<String> get sdkNameAndVersion async =>
      _targetDevice.sdkNameAndVersion ?? 'Tool Extension Device';

  @override
  Future<String> get targetPlatformDisplayName async => _targetDevice.targetPlatform ?? 'custom';

  @override
  Future<TargetPlatform> get targetPlatform async {
    final String? platformName = _targetDevice.targetPlatform;
    if (platformName != null) {
      try {
        return TargetPlatform.fromName(platformName);
      } on Object {
        // Fall through if unrecognized target platform name supplied.
      }
    }
    return TargetPlatform.unsupported;
  }

  @override
  Future<bool> get isLocalEmulator async => false;

  @override
  Future<String?> get emulatorId async => null;

  @override
  DevicePortForwarder? get portForwarder => null;

  @override
  DeviceLogReader getLogReader({ApplicationPackage? app, bool includePastLogs = false}) =>
      NoOpDeviceLogReader(name);

  @override
  void clearLogs() {}

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> isLatestBuildInstalled(ApplicationPackage app) async => false;

  @override
  Future<bool> installApp(ApplicationPackage app, {String? userIdentifier}) async => true;

  @override
  Future<LaunchResult> startApp(
    ApplicationPackage? package, {
    String? mainPath,
    String? route,
    DebuggingOptions? debuggingOptions,
    Map<String, Object?>? platformArgs,
    bool prebuiltApplication = false,
    bool ipv6 = false,
    String? userIdentifier,
  }) async {
    final ExtensionLaunchResult result = await _deviceService.startApp(
      deviceId: id,
      projectRoot: globals.fs.currentDirectory.path,
      mainPath: mainPath ?? 'lib/main.dart',
      buildMode: debuggingOptions?.buildInfo.mode.name ?? 'debug',
      route: route,
      options: platformArgs ?? const <String, Object?>{},
    );
    lastAppUrl = result.appUrl;
    if (result.appUrl != null) {
      _logger.printStatus('${mainPath ?? 'lib/main.dart'} is being served at ${result.appUrl}');
    }
    if (!result.succeeded) {
      if (result.errorMessage != null) {
        _logger.printError(result.errorMessage!);
      }
      return LaunchResult.failed();
    }
    final Uri? vmServiceUri = result.vmServiceUri != null
        ? Uri.tryParse(result.vmServiceUri!)
        : null;
    return LaunchResult.succeeded(vmServiceUri: vmServiceUri);
  }

  /// Reloads or restarts the running application via the underlying [DeviceService].
  Future<ExtensionReloadResult> reloadExtensionApp({bool fullRestart = false}) =>
      _deviceService.reloadApp(deviceId: id, fullRestart: fullRestart);

  @override
  Future<bool> stopApp(ApplicationPackage? app, {String? userIdentifier}) async =>
      _deviceService.stopApp(deviceId: id);

  @override
  Future<bool> uninstallApp(ApplicationPackage app, {String? userIdentifier}) async => true;

  @override
  Future<bool> isAppInstalled(ApplicationPackage app, {String? userIdentifier}) async => false;
}
