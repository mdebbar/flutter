// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension_web_prototype/src/build.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('WebBuildService', () {
    late Directory tempDir;
    late WebBuildService buildService;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('web_build_test.');
      buildService = WebBuildService();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('getBuildTargets returns web build target', () async {
      final List<ExtensionBuildTarget> targets = await buildService.getBuildTargets();

      expect(targets, hasLength(1));
      expect(targets.first.name, 'web');
      expect(targets.first.description, 'Build a web application bundle.');
      expect(targets.first.targetPlatform, 'web-javascript');
    });

    test('build fails for unsupported targetName', () async {
      final ExtensionBuildResult result = await buildService.build(
        targetName: 'apk',
        projectRoot: tempDir.path,
        mainPath: 'lib/main.dart',
        buildMode: 'release',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Unsupported build target'));
    });

    test('build fails when target main file does not exist', () async {
      final ExtensionBuildResult result = await buildService.build(
        targetName: 'web',
        projectRoot: tempDir.path,
        mainPath: 'lib/main.dart',
        buildMode: 'release',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, 'Target file "lib/main.dart" not found.');
    });

    test('build creates web bundle and copies web directory contents', () async {
      File(p.join(tempDir.path, 'lib', 'main.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('void main() {}\n');
      File(p.join(tempDir.path, 'web', 'index.html'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          r'<!DOCTYPE html><html><head><base href="$FLUTTER_BASE_HREF"></head><body><script src="flutter_bootstrap.js" async></script></body></html>',
        );
      File(p.join(tempDir.path, 'web', 'manifest.json'))
          .writeAsStringSync('{"name":"test_web_app"}');

      final ExtensionBuildResult result = await buildService.build(
        targetName: 'web',
        projectRoot: tempDir.path,
        mainPath: 'lib/main.dart',
        buildMode: 'release',
      );

      expect(result.success, isTrue);
      final String buildWebDir = p.join(tempDir.path, 'build', 'web');
      expect(result.outputDirectory, buildWebDir);
      expect(Directory(p.join(buildWebDir, 'assets')).existsSync(), isTrue);
      expect(File(p.join(buildWebDir, 'index.html')).existsSync(), isTrue);
      expect(
        File(p.join(buildWebDir, 'index.html')).readAsStringSync(),
        contains('<base href="/">'),
      );
      expect(File(p.join(buildWebDir, 'manifest.json')).existsSync(), isTrue);
      expect(File(p.join(buildWebDir, 'flutter_bootstrap.js')).existsSync(), isTrue);
      expect(File(p.join(buildWebDir, 'flutter.js')).existsSync(), isTrue);
      expect(File(p.join(buildWebDir, 'main.dart.js')).existsSync(), isTrue);
    });
  });
}
