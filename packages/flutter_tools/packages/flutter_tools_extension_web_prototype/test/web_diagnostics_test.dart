// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension_web_prototype/src/diagnostics.dart';
import 'package:test/test.dart';

void main() {
  group('WebExtensionDiagnostics', () {
    test('returns success validation result when Chrome executable is found', () async {
      final diagnostics = WebExtensionDiagnostics.withOverrides(
        findExecutable: () async => '/usr/bin/google-chrome',
        getVersion: (String executable) async => 'Google Chrome 130.0.0.0',
      );

      expect(diagnostics.title, 'Chrome - develop for the web');
      final List<ValidationResult> results = await diagnostics.runDiagnostics();

      expect(results, hasLength(1));
      expect(results.first.type, ValidationType.success);
      expect(results.first.statusInfo, 'Google Chrome 130.0.0.0');
      expect(
        results.first.messages,
        equals(const <ValidationMessage>[
          ValidationMessage('Chrome at /usr/bin/google-chrome'),
          ValidationMessage('Google Chrome 130.0.0.0'),
        ]),
      );
    });

    test('returns missing validation result when Chrome executable is not found', () async {
      final diagnostics = WebExtensionDiagnostics.withOverrides(
        findExecutable: () async => null,
        getVersion: (String executable) async => 'Google Chrome',
      );

      final List<ValidationResult> results = await diagnostics.runDiagnostics();

      expect(results, hasLength(1));
      expect(results.first.type, ValidationType.missing);
      expect(results.first.statusInfo, 'Cannot find Chrome');
      expect(
        results.first.messages,
        equals(const <ValidationMessage>[
          ValidationMessage.error('Cannot find Chrome executable.'),
        ]),
      );
    });
  });
}
