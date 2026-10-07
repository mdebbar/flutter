// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:test/test.dart';

void main() {
  group('ExtensionBuildTarget', () {
    test('serializes and deserializes correctly', () {
      const target = ExtensionBuildTarget(
        name: 'web',
        description: 'Build a web application bundle.',
        targetPlatform: 'web-javascript',
      );

      final Map<String, Object?> map = target.toMap();
      expect(map['name'], 'web');
      expect(map['description'], 'Build a web application bundle.');
      expect(map['targetPlatform'], 'web-javascript');

      final parsed = ExtensionBuildTarget.fromJson(map);
      expect(parsed, equals(target));
      expect(parsed.hashCode, equals(target.hashCode));
      expect(parsed.toString(), contains('web-javascript'));
    });

    test('listFromJson handles valid and invalid lists', () {
      final validJson = <String, Object?>{
        'name': 'web',
        'description': 'Build a web application bundle.',
        'targetPlatform': 'web-javascript',
      };

      final List<ExtensionBuildTarget> targets = ExtensionBuildTarget.listFromJson(<Object?>[
        validJson,
      ]);
      expect(targets, hasLength(1));
      expect(targets.first.name, 'web');
      expect(targets.first.targetPlatform, 'web-javascript');

      expect(ExtensionBuildTarget.listFromJson(null), isEmpty);
      expect(ExtensionBuildTarget.listFromJson('invalid'), isEmpty);
    });
  });

  group('ExtensionBuildResult', () {
    test('serializes and deserializes success result', () {
      const result = ExtensionBuildResult(success: true, outputDirectory: '/tmp/project/build/web');

      final Map<String, Object?> map = result.toMap();
      expect(map['success'], isTrue);
      expect(map['outputDirectory'], '/tmp/project/build/web');
      expect(map.containsKey('errorMessage'), isFalse);

      final parsed = ExtensionBuildResult.fromJson(map);
      expect(parsed, equals(result));
      expect(parsed.hashCode, equals(result.hashCode));
      expect(parsed.toString(), contains('/tmp/project/build/web'));
    });

    test('serializes and deserializes failure result', () {
      const result = ExtensionBuildResult(success: false, errorMessage: 'Build failed.');

      final Map<String, Object?> map = result.toMap();
      expect(map['success'], isFalse);
      expect(map['errorMessage'], 'Build failed.');
      expect(map.containsKey('outputDirectory'), isFalse);

      final parsed = ExtensionBuildResult.fromJson(map);
      expect(parsed, equals(result));
      expect(parsed.hashCode, equals(result.hashCode));
    });
  });
}
