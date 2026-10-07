// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Prototype Web platform extension package for Flutter tools extensibility.
library flutter_tools_extension_web_prototype;

import 'dart:isolate';

import 'package:flutter_tools_extension/flutter_tools_extension.dart';

import 'src/build.dart';
import 'src/config.dart';
import 'src/device.dart';
import 'src/diagnostics.dart';
import 'src/template.dart';

export 'src/build.dart';
export 'src/config.dart';
export 'src/device.dart';
export 'src/diagnostics.dart';
export 'src/template.dart';

/// Isolate entrypoint for the prototype Web Flutter Tool Extension.
void webExtensionEntryPoint(SendPort sendPort) {
  final buildService = WebBuildService();
  ToolExtensionEntryPoint.run(
    sendPort,
    <ToolExtensionService>[
      WebExtensionDiagnostics(),
      WebConfigurationExtension(),
      WebTemplateService(),
      buildService,
      WebDeviceService(buildService: buildService),
    ],
    supportedPlatforms: const <String>{'linux', 'macos', 'windows'},
    logger: (String message) {},
  );
}
