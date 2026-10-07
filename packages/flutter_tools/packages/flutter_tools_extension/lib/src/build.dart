// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart';

import 'protocol_base/service.dart';

/// Extension service interface for contributing and executing build targets.
abstract base class BuildService extends ToolExtensionService {
  /// Service namespace identifier for build services.
  static const String serviceNamespace = 'build';

  /// RPC method identifier to query contributed build targets.
  static const String getTargetsMethod = 'build.getTargets';

  /// RPC method identifier to execute a contributed build target.
  static const String buildMethod = 'build.build';

  /// RPC parameter key for the build target name.
  static const String targetNameParam = 'targetName';

  /// RPC parameter key for the project root directory path.
  static const String projectRootParam = 'projectRoot';

  /// RPC parameter key for the entrypoint Dart file path.
  static const String mainPathParam = 'mainPath';

  /// RPC parameter key for the build mode (`'debug'`, `'profile'`, `'release'`).
  static const String buildModeParam = 'buildMode';

  /// RPC parameter key for optional target-specific build options.
  static const String optionsParam = 'options';

  @override
  String get namespace => serviceNamespace;

  /// Returns the build targets contributed by this extension.
  Future<List<ExtensionBuildTarget>> getBuildTargets();

  /// Builds the specified [targetName] for the project at [projectRoot].
  Future<ExtensionBuildResult> build({
    required String targetName,
    required String projectRoot,
    required String mainPath,
    required String buildMode,
    Map<String, Object?> options = const <String, Object?>{},
  });

  @override
  Future<Map<String, ExtensionRpcHandler>> initialize() async {
    return <String, ExtensionRpcHandler>{'getTargets': _getTargetsRpc, 'build': _buildRpc};
  }

  @override
  Future<void> shutdown() async {}

  Future<List<Map<String, Object?>>> _getTargetsRpc(Map<String, Object?> _) async {
    final List<ExtensionBuildTarget> targets = await getBuildTargets();
    return targets.map((ExtensionBuildTarget target) => target.toMap()).toList();
  }

  Future<Map<String, Object?>> _buildRpc(Map<String, Object?> params) async {
    final String targetName = params[targetNameParam] as String? ?? '';
    final String projectRoot = params[projectRootParam] as String? ?? '';
    final String mainPath = params[mainPathParam] as String? ?? 'lib/main.dart';
    final String buildMode = params[buildModeParam] as String? ?? 'release';
    final Map<String, Object?> options = switch (params[optionsParam]) {
      final Map<String, Object?> map => map,
      final Map<Object?, Object?> map => map.cast<String, Object?>(),
      _ => const <String, Object?>{},
    };
    final ExtensionBuildResult result = await build(
      targetName: targetName,
      projectRoot: projectRoot,
      mainPath: mainPath,
      buildMode: buildMode,
      options: options,
    );
    return result.toMap();
  }
}
