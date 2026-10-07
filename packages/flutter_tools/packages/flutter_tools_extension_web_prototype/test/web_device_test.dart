// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension_web_prototype/src/build.dart';
import 'package:flutter_tools_extension_web_prototype/src/device.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('WebDeviceService', () {
    late Directory tempDir;
    late WebBuildService buildService;
    late WebDeviceService deviceService;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('web_device_test.');
      buildService = WebBuildService();
      deviceService = WebDeviceService.withOverrides(
        buildService: buildService,
        findChromeExecutable: () async => '/usr/bin/google-chrome',
        getChromeVersion: (String executable) async => 'Google Chrome 130.0.0.0',
      );
    });

    tearDown(() async {
      await deviceService.shutdown();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('getDevices returns chrome and web-server devices', () async {
      final List<TargetDevice> devices = await deviceService.getDevices();

      expect(devices, hasLength(2));
      expect(devices[0].id, 'chrome');
      expect(devices[0].name, 'Chrome (web)');
      expect(devices[0].category, Category.web);
      expect(devices[0].ephemeral, isFalse);
      expect(devices[0].isSupported, isTrue);
      expect(devices[0].sdkNameAndVersion, 'Google Chrome 130.0.0.0');
      expect(devices[0].targetPlatform, 'web-javascript');

      expect(devices[1].id, 'web-server');
      expect(devices[1].name, 'Web Server (web)');
      expect(devices[1].category, Category.web);
      expect(devices[1].ephemeral, isFalse);
      expect(devices[1].isSupported, isTrue);
      expect(devices[1].sdkNameAndVersion, 'Flutter Tools');
      expect(devices[1].targetPlatform, 'web-javascript');
    });

    test('isSupportedForProject checks deviceId and project files', () async {
      expect(
        await deviceService.isSupportedForProject(deviceId: 'chrome', projectRoot: tempDir.uri),
        isFalse,
      );

      Directory.fromUri(tempDir.uri.resolve('web')).createSync();
      expect(
        await deviceService.isSupportedForProject(deviceId: 'chrome', projectRoot: tempDir.uri),
        isTrue,
      );
      expect(
        await deviceService.isSupportedForProject(deviceId: 'web-server', projectRoot: tempDir.uri),
        isTrue,
      );
      expect(
        await deviceService.isSupportedForProject(deviceId: 'unknown', projectRoot: tempDir.uri),
        isFalse,
      );
    });

    test('startApp serves built web app over HTTP and supports reloadApp and stopApp', () async {
      File(p.join(tempDir.path, 'lib', 'main.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('void main() {}\n');

      final ExtensionLaunchResult launchResult = await deviceService.startApp(
        deviceId: 'web-server',
        projectRoot: tempDir.path,
        mainPath: 'lib/main.dart',
        buildMode: 'debug',
      );

      expect(launchResult.succeeded, isTrue);
      expect(launchResult.appUrl, isNotNull);
      expect(deviceService.hasActiveSession('web-server'), isTrue);

      final client = HttpClient();
      try {
        final HttpClientRequest request = await client.getUrl(Uri.parse(launchResult.appUrl!));
        final HttpClientResponse response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        final String body = await response.transform(utf8.decoder).join();
        expect(body, contains('flutter_bootstrap.js'));
      } finally {
        client.close(force: true);
      }

      final ExtensionReloadResult reloadResult = await deviceService.reloadApp(
        deviceId: 'web-server',
      );
      expect(reloadResult.succeeded, isTrue);
      expect(reloadResult.message, 'Reloaded web application.');

      final ExtensionReloadResult restartResult = await deviceService.reloadApp(
        deviceId: 'web-server',
        fullRestart: true,
      );
      expect(restartResult.succeeded, isTrue);
      expect(restartResult.message, 'Restarted web application.');

      final bool stopped = await deviceService.stopApp(deviceId: 'web-server');
      expect(stopped, isTrue);
      expect(deviceService.hasActiveSession('web-server'), isFalse);
    });

    test('reloadApp returns failure when no session is active', () async {
      final ExtensionReloadResult result = await deviceService.reloadApp(deviceId: 'web-server');
      expect(result.succeeded, isFalse);
      expect(result.message, 'No active web session for device.');
    });
  });
}
