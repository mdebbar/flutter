// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

/// Prototype Web platform extension configuration and feature flag provider.
class WebConfigurationExtension extends ConfigurationExtension {
  static const String kEnableWeb = 'enable-web';
  static const String kWebBrowserFlag = 'web-browser-flag';

  @override
  String get title => 'Flutter Web Extension Prototype';

  @override
  Future<List<FeatureFlag>> getFeatureFlags() async {
    return const <FeatureFlag>[
      FeatureFlag(name: kEnableWeb, help: 'Enable Flutter for web.', enabledByDefault: true),
    ];
  }

  @override
  Future<List<ConfigOption>> getConfigurations() async {
    return const <ConfigOption>[
      ConfigOption(
        name: kWebBrowserFlag,
        help: 'Additional flags to pass to Chrome when launching a web app.',
        value: '',
      ),
    ];
  }
}
