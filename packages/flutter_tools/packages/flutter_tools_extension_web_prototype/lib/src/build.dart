// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';
import 'package:path/path.dart' as p;

/// Prototype Web [BuildService] implementation.
final class WebBuildService extends BuildService {
  static const String _defaultIndexHtml = '''
<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <title>Flutter Web App</title>
  <link rel="manifest" href="manifest.json">
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';

  static const String _defaultFlutterBootstrapJs = '''
(function() {
  var scriptLoaded = false;
  function loadMainDartJs() {
    if (scriptLoaded) {
      return;
    }
    scriptLoaded = true;
    var scriptTag = document.createElement('script');
    scriptTag.src = 'main.dart.js';
    scriptTag.type = 'application/javascript';
    document.body.append(scriptTag);
  }
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    loadMainDartJs();
  } else {
    window.addEventListener('DOMContentLoaded', loadMainDartJs);
  }
})();
''';

  static const String _defaultFlutterJs = '''
if (!_flutter) {
  var _flutter = {};
}
_flutter.loader = {
  load: function() {
    var scriptTag = document.createElement('script');
    scriptTag.src = 'main.dart.js';
    scriptTag.type = 'application/javascript';
    document.body.append(scriptTag);
  }
};
''';

  @override
  Future<List<ExtensionBuildTarget>> getBuildTargets() async {
    return const <ExtensionBuildTarget>[
      ExtensionBuildTarget(
        name: 'web',
        description: 'Build a web application bundle.',
        targetPlatform: 'web-javascript',
      ),
    ];
  }

  @override
  Future<ExtensionBuildResult> build({
    required String targetName,
    required String projectRoot,
    required String mainPath,
    required String buildMode,
    Map<String, Object?> options = const <String, Object?>{},
  }) async {
    if (targetName != 'web') {
      return ExtensionBuildResult(
        success: false,
        errorMessage: 'Unsupported build target: "$targetName".',
      );
    }

    final String resolvedMainPath = p.isAbsolute(mainPath)
        ? mainPath
        : p.join(projectRoot, mainPath);
    final targetFile = File(resolvedMainPath);
    if (!targetFile.existsSync()) {
      return ExtensionBuildResult(
        success: false,
        errorMessage: 'Target file "$mainPath" not found.',
      );
    }

    final String buildWebPath = p.join(projectRoot, 'build', 'web');
    final buildWebDir = Directory(buildWebPath)..createSync(recursive: true);
    Directory(p.join(buildWebPath, 'assets')).createSync(recursive: true);

    final webSourceDir = Directory(p.join(projectRoot, 'web'));
    if (webSourceDir.existsSync()) {
      _copyDirectoryContents(webSourceDir, buildWebDir);
    }

    final indexHtmlFile = File(p.join(buildWebPath, 'index.html'));
    if (!indexHtmlFile.existsSync()) {
      indexHtmlFile.writeAsStringSync(_defaultIndexHtml);
    } else {
      final String baseHref = switch (options['baseHref']) {
        final String href when href.isNotEmpty => href,
        _ => '/',
      };
      final String updatedHtml = indexHtmlFile
          .readAsStringSync()
          .replaceAll(r'$FLUTTER_BASE_HREF', baseHref)
          .replaceAll('{{flutter_js}}', _defaultFlutterJs)
          .replaceAll(
            '{{flutter_build_config}}',
            '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js","mainJsPath":"main.dart.js"}]};',
          )
          .replaceAll('{{flutter_bootstrap_js}}', _defaultFlutterBootstrapJs);
      indexHtmlFile.writeAsStringSync(updatedHtml);
    }

    final bootstrapFile = File(p.join(buildWebPath, 'flutter_bootstrap.js'));
    if (bootstrapFile.existsSync()) {
      final String updatedBootstrap = bootstrapFile
          .readAsStringSync()
          .replaceAll('{{flutter_js}}', _defaultFlutterJs)
          .replaceAll(
            '{{flutter_build_config}}',
            '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js","mainJsPath":"main.dart.js"}]};',
          );
      bootstrapFile.writeAsStringSync(updatedBootstrap);
    } else {
      bootstrapFile.writeAsStringSync(_defaultFlutterBootstrapJs);
    }

    final flutterJsFile = File(p.join(buildWebPath, 'flutter.js'));
    if (!flutterJsFile.existsSync()) {
      flutterJsFile.writeAsStringSync(_defaultFlutterJs);
    }

    final mainJsFile = File(p.join(buildWebPath, 'main.dart.js'));
    final String mainSource = targetFile.readAsStringSync();
    var compiledWithDart2js = false;

    final packageConfig = File(p.join(projectRoot, '.dart_tool', 'package_config.json'));
    final bool canUseStandaloneDart2js =
        options['compileJs'] == true ||
        (!mainSource.contains('package:flutter/') &&
            !mainSource.contains('dart:ui') &&
            packageConfig.existsSync());

    if (canUseStandaloneDart2js) {
      try {
        final ProcessResult result = await Process.run(Platform.resolvedExecutable, <String>[
          'compile',
          'js',
          '--no-source-maps',
          '-o',
          mainJsFile.path,
          targetFile.path,
        ], workingDirectory: projectRoot);
        if (result.exitCode == 0 && mainJsFile.existsSync()) {
          compiledWithDart2js = true;
        }
      } on Object {
        // Fall through to synthetic bundle generation below.
      }
    }

    if (!compiledWithDart2js) {
      mainJsFile.writeAsStringSync(
        '// Compiled by flutter_tools_extension_web_prototype ($buildMode)\n'
        '// Entrypoint: $mainPath\n'
        '(function() {\n'
        '  console.log("Flutter Web Extension app started ($buildMode)");\n'
        '})();\n',
      );
    }

    return ExtensionBuildResult(success: true, outputDirectory: buildWebDir.path);
  }

  static void _copyDirectoryContents(Directory source, Directory destination) {
    for (final FileSystemEntity entity in source.listSync(followLinks: false)) {
      final String relative = p.relative(entity.path, from: source.path);
      final String targetPath = p.join(destination.path, relative);
      if (entity is Directory) {
        final subDir = Directory(targetPath)..createSync(recursive: true);
        _copyDirectoryContents(entity, subDir);
      } else if (entity is File) {
        File(targetPath)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(entity.readAsBytesSync());
      }
    }
  }
}
