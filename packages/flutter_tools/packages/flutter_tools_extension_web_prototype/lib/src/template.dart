// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:isolate';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

/// The template service for the Web extension prototype.
final class WebTemplateService extends TemplateService {
  @override
  Set<String> get appPlatformTemplates => const <String>{};

  @override
  Set<String> get pluginPlatformTemplates => const <String>{};

  @override
  Set<ProjectTemplate> get projectTemplates => <ProjectTemplate>{WebProjectTemplate()};
}

/// The custom project template representing the 'web-app' template.
final class WebProjectTemplate extends ProjectTemplate {
  @override
  String get name => 'web-app';

  @override
  bool get hidden => false;

  @override
  Set<String> get templateDependencies => const <String>{'app'};

  @override
  Set<String> get templateSources => const <String>{
    'web/index.html.tmpl',
    'web/manifest.json.tmpl',
    'lib/main.dart.tmpl',
    'pubspec.yaml.tmpl',
  };

  @override
  String get templatePath => 'package:flutter_tools_extension_web_prototype/templates/web-app';

  /// Resolves [templatePath] to a file system [Uri] using [Isolate.resolvePackageUri].
  Future<Uri?> resolveTemplateDirectoryUri() async {
    final Uri? packageRoot = await Isolate.resolvePackageUri(
      Uri.parse('package:flutter_tools_extension_web_prototype/'),
    );
    return packageRoot?.resolve('templates/web-app/');
  }

  @override
  Future<Map<String, Object?>> generateTemplateParameters(
    Map<String, Object?> toolParameters,
  ) async {
    return toolParameters;
  }
}
