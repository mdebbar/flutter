// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

import '../base/logger.dart';
import '../features.dart';
import 'extension_discovery.dart';
import 'extension_manager.dart';

/// A host-side [BuildService] client adapter delegating RPC queries to an [ExtensionConnection].
final class BuildExtensionClient extends BuildService {
  /// Creates a [BuildExtensionClient] wrapping the host [connection].
  BuildExtensionClient(this.connection, {required this._logger});

  /// The active extension isolate connection.
  final ExtensionConnection connection;
  final Logger _logger;

  @override
  Future<List<ExtensionBuildTarget>> getBuildTargets() async {
    _logger.printTrace(
      'BuildExtensionClient fetching build targets via RPC ("${BuildService.getTargetsMethod}")...',
    );
    try {
      final Object? rawResult = await connection
          .sendRequest(BuildService.getTargetsMethod)
          .timeout(const Duration(seconds: 5));
      final List<ExtensionBuildTarget> targets = ExtensionBuildTarget.listFromJson(rawResult);
      _logger.printTrace(
        'BuildExtensionClient received ${targets.length} build target(s) via RPC.',
      );
      return targets;
    } on Object catch (err, stack) {
      _logger.printTrace('BuildExtensionClient failed to get build targets: $err\n$stack');
    }
    return const <ExtensionBuildTarget>[];
  }

  @override
  Future<ExtensionBuildResult> build({
    required String targetName,
    required String projectRoot,
    required String mainPath,
    required String buildMode,
    Map<String, Object?> options = const <String, Object?>{},
  }) async {
    _logger.printTrace(
      'BuildExtensionClient executing build for "$targetName" via RPC '
      '("${BuildService.buildMethod}")...',
    );
    try {
      final Object? rawResult = await connection
          .sendRequest(BuildService.buildMethod, <String, Object?>{
            BuildService.targetNameParam: targetName,
            BuildService.projectRootParam: projectRoot,
            BuildService.mainPathParam: mainPath,
            BuildService.buildModeParam: buildMode,
            BuildService.optionsParam: options,
          })
          .timeout(const Duration(minutes: 5));
      if (rawResult case final Map<String, Object?> map) {
        return ExtensionBuildResult.fromJson(map);
      }
      if (rawResult case final Map<Object?, Object?> map) {
        return ExtensionBuildResult.fromJson(map.cast<String, Object?>());
      }
    } on Object catch (err, stack) {
      _logger.printTrace('BuildExtensionClient failed to build "$targetName": $err\n$stack');
      return ExtensionBuildResult(success: false, errorMessage: 'Extension build RPC failed: $err');
    }
    return const ExtensionBuildResult(
      success: false,
      errorMessage: 'Invalid response from extension build service.',
    );
  }
}

/// Manages discovering and executing build targets contributed by active tool extensions.
class ExtensionBuildManager {
  /// Creates an [ExtensionBuildManager].
  ExtensionBuildManager({
    required this._extensionManager,
    required this._featureFlags,
    required this._logger,
  });

  final ExtensionManager _extensionManager;
  final FeatureFlags _featureFlags;
  final Logger _logger;

  /// Queries all active build extensions for contributed [ExtensionBuildTarget]s.
  Future<List<ExtensionBuildTarget>> getBuildTargets() async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      return const <ExtensionBuildTarget>[];
    }
    await _extensionManager.ensureInitialized();
    final List<BuildService> buildServices = _extensionManager.buildExtensions;
    if (buildServices.isEmpty) {
      return const <ExtensionBuildTarget>[];
    }
    final List<List<ExtensionBuildTarget>> perService = await Future.wait(
      buildServices.map((BuildService service) async {
        try {
          return await service.getBuildTargets();
        } on Object catch (e, st) {
          _logger.printTrace('Error querying build extension service: $e\n$st');
          return const <ExtensionBuildTarget>[];
        }
      }),
    );
    return <ExtensionBuildTarget>[for (final list in perService) ...list];
  }

  /// Executes [targetName] on the extension that contributes it.
  Future<ExtensionBuildResult> build({
    required String targetName,
    required String projectRoot,
    required String mainPath,
    required String buildMode,
    Map<String, Object?> options = const <String, Object?>{},
  }) async {
    if (!_featureFlags.isToolExtensionsEnabled) {
      return const ExtensionBuildResult(
        success: false,
        errorMessage: 'Tool extensions are disabled.',
      );
    }
    await _extensionManager.ensureInitialized();
    for (final BuildService service in _extensionManager.buildExtensions) {
      final List<ExtensionBuildTarget> targets = await service.getBuildTargets();
      if (targets.any((ExtensionBuildTarget t) => t.name == targetName)) {
        return service.build(
          targetName: targetName,
          projectRoot: projectRoot,
          mainPath: mainPath,
          buildMode: buildMode,
          options: options,
        );
      }
    }
    return ExtensionBuildResult(
      success: false,
      errorMessage: 'No active tool extension provides build target "$targetName".',
    );
  }
}
