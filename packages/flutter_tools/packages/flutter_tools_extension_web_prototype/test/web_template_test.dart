// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension_web_prototype/src/template.dart';
import 'package:test/test.dart';

void main() {
  group('WebTemplateService', () {
    test('projectTemplates returns web-app template with expected sources', () async {
      final service = WebTemplateService();
      final Set<ProjectTemplate> templates = service.projectTemplates;

      expect(templates, hasLength(1));
      final ProjectTemplate template = templates.first;
      expect(template.name, 'web-app');
      expect(template.hidden, isFalse);
      expect(template.templateDependencies, <String>{'app'});
      expect(
        template.templateSources,
        unorderedEquals(<String>[
          'web/index.html.tmpl',
          'web/manifest.json.tmpl',
          'lib/main.dart.tmpl',
          'pubspec.yaml.tmpl',
        ]),
      );
      expect(
        template.templatePath,
        'package:flutter_tools_extension_web_prototype/templates/web-app',
      );

      final webTemplate = template as WebProjectTemplate;
      final Uri? resolvedUri = await webTemplate.resolveTemplateDirectoryUri();
      expect(resolvedUri, isNotNull);
      for (final String source in template.templateSources) {
        expect(File.fromUri(resolvedUri!.resolve(source)).existsSync(), isTrue);
      }
    });

    test('generateTemplateParameters returns toolParameters unchanged', () async {
      final template = WebProjectTemplate();
      final inputParams = <String, Object?>{'projectName': 'my_web_app', 'org': 'com.example'};

      final Map<String, Object?> result = await template.generateTemplateParameters(inputParams);
      expect(result, equals(inputParams));
    });
  });
}
