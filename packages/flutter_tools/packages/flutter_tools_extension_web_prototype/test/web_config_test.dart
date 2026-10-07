// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension_web_prototype/src/config.dart';
import 'package:test/test.dart';

void main() {
  group('WebConfigurationExtension', () {
    test('getFeatureFlags returns enable-web feature flag', () async {
      final extension = WebConfigurationExtension();
      expect(extension.title, 'Flutter Web Extension Prototype');

      final List<FeatureFlag> flags = await extension.getFeatureFlags();
      expect(flags, hasLength(1));
      expect(flags.first.name, 'enable-web');
      expect(flags.first.help, 'Enable Flutter for web.');
      expect(flags.first.enabledByDefault, isTrue);
    });

    test('getConfigurations returns web-browser-flag config option', () async {
      final extension = WebConfigurationExtension();
      final List<ConfigOption> configs = await extension.getConfigurations();

      expect(configs, hasLength(1));
      expect(configs.first.name, 'web-browser-flag');
      expect(configs.first.value, '');
    });
  });
}
