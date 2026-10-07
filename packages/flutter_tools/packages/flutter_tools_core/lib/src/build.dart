// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// Representation of a build target contributed by a tool extension.
@immutable
class ExtensionBuildTarget {
  /// Creates an [ExtensionBuildTarget] definition.
  const ExtensionBuildTarget({
    required this.name,
    required this.description,
    required this.targetPlatform,
  });

  /// Deserializes an [ExtensionBuildTarget] from a JSON-serializable map.
  factory ExtensionBuildTarget.fromJson(Map<String, Object?> json) {
    return ExtensionBuildTarget(
      name: json[nameKey] as String? ?? '',
      description: json[descriptionKey] as String? ?? '',
      targetPlatform: json[targetPlatformKey] as String? ?? '',
    );
  }

  /// Map key for [name].
  static const String nameKey = 'name';

  /// Map key for [description].
  static const String descriptionKey = 'description';

  /// Map key for [targetPlatform].
  static const String targetPlatformKey = 'targetPlatform';

  /// Deserializes a list of [ExtensionBuildTarget] objects from RPC response data.
  static List<ExtensionBuildTarget> listFromJson(Object? rpcResult) {
    if (rpcResult case final List<Object?> list) {
      return <ExtensionBuildTarget>[
        for (final item in list)
          if (item case final Map<String, Object?> map) ExtensionBuildTarget.fromJson(map),
      ];
    }
    return const <ExtensionBuildTarget>[];
  }

  /// CLI subcommand name of the build target (e.g. `'web'`).
  final String name;

  /// Human-readable description of the build target.
  final String description;

  /// Target platform identifier string (e.g. `'web-javascript'`).
  final String targetPlatform;

  /// Serializes the build target to a JSON-serializable map.
  Map<String, Object?> toMap() => <String, Object?>{
    nameKey: name,
    descriptionKey: description,
    targetPlatformKey: targetPlatform,
  };

  @override
  String toString() =>
      'ExtensionBuildTarget(name: $name, description: $description, '
      'targetPlatform: $targetPlatform)';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ExtensionBuildTarget &&
            other.name == name &&
            other.description == description &&
            other.targetPlatform == targetPlatform);
  }

  @override
  int get hashCode => Object.hash(name, description, targetPlatform);
}

/// Result of executing a build target via a tool extension.
@immutable
class ExtensionBuildResult {
  /// Creates an [ExtensionBuildResult].
  const ExtensionBuildResult({required this.success, this.outputDirectory, this.errorMessage});

  /// Deserializes an [ExtensionBuildResult] from a JSON-serializable map.
  factory ExtensionBuildResult.fromJson(Map<String, Object?> json) {
    return ExtensionBuildResult(
      success: json[successKey] as bool? ?? false,
      outputDirectory: json[outputDirectoryKey] as String?,
      errorMessage: json[errorMessageKey] as String?,
    );
  }

  /// Map key for [success].
  static const String successKey = 'success';

  /// Map key for [outputDirectory].
  static const String outputDirectoryKey = 'outputDirectory';

  /// Map key for [errorMessage].
  static const String errorMessageKey = 'errorMessage';

  /// Whether the build succeeded.
  final bool success;

  /// Path to the build output directory, if applicable.
  final String? outputDirectory;

  /// Error message if the build failed.
  final String? errorMessage;

  /// Serializes the build result to a JSON-serializable map.
  Map<String, Object?> toMap() => <String, Object?>{
    successKey: success,
    outputDirectoryKey: ?outputDirectory,
    errorMessageKey: ?errorMessage,
  };

  @override
  String toString() =>
      'ExtensionBuildResult(success: $success, outputDirectory: $outputDirectory, '
      'errorMessage: $errorMessage)';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ExtensionBuildResult &&
            other.success == success &&
            other.outputDirectory == outputDirectory &&
            other.errorMessage == errorMessage);
  }

  @override
  int get hashCode => Object.hash(success, outputDirectory, errorMessage);
}
