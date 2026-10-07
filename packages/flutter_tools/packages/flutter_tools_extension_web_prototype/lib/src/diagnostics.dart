// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools_core/flutter_tools_core.dart';
import 'package:flutter_tools_extension/flutter_tools_extension.dart';

/// Prototype Web platform extension diagnostic validator check for `flutter doctor`.
class WebExtensionDiagnostics extends DiagnosticsExtension {
  /// Creates a [WebExtensionDiagnostics] using system Chrome discovery.
  WebExtensionDiagnostics()
    : _findExecutable = findChromeExecutable,
      _getVersion = getChromeVersion;

  /// Creates a [WebExtensionDiagnostics] with custom discovery callbacks for testing.
  WebExtensionDiagnostics.withOverrides({required this._findExecutable, required this._getVersion});

  final Future<String?> Function() _findExecutable;
  final Future<String> Function(String executable) _getVersion;

  @override
  String get title => 'Chrome - develop for the web';

  @override
  Future<List<ValidationResult>> runDiagnostics() async {
    final String? executable = await _findExecutable();
    if (executable == null) {
      return <ValidationResult>[
        ValidationResult(ValidationType.missing, <ValidationMessage>[
          const ValidationMessage.error('Cannot find Chrome executable.'),
        ], statusInfo: 'Cannot find Chrome'),
      ];
    }

    final String version = await _getVersion(executable);
    return <ValidationResult>[
      ValidationResult(ValidationType.success, <ValidationMessage>[
        ValidationMessage('Chrome at $executable'),
        ValidationMessage(version),
      ], statusInfo: version),
    ];
  }

  /// Locates the Chrome executable on the host platform.
  static Future<String?> findChromeExecutable() async {
    final String? envChrome = Platform.environment['CHROME_EXECUTABLE'];
    if (envChrome != null && envChrome.isNotEmpty && File(envChrome).existsSync()) {
      return envChrome;
    }

    const commonPaths = <String>[
      '/usr/bin/google-chrome',
      '/usr/bin/google-chrome-stable',
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    ];
    for (final candidate in commonPaths) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    final lookupCmd = Platform.isWindows ? 'where' : 'which';
    const commandNames = <String>[
      'google-chrome',
      'google-chrome-stable',
      'chromium',
      'chromium-browser',
      'chrome',
    ];
    for (final name in commandNames) {
      try {
        final ProcessResult result = await Process.run(lookupCmd, <String>[name]);
        if (result.exitCode == 0) {
          final String path = (result.stdout as String).trim().split('\n').first.trim();
          if (path.isNotEmpty && File(path).existsSync()) {
            return path;
          }
        }
      } on Object {
        // Ignore lookup failures and continue checking candidates.
      }
    }

    return null;
  }

  /// Queries `<executable> --version` for the human-readable Chrome version string.
  static Future<String> getChromeVersion(String executable) async {
    try {
      final ProcessResult result = await Process.run(executable, const <String>['--version']);
      if (result.exitCode == 0) {
        final String output = (result.stdout as String).trim();
        if (output.isNotEmpty) {
          return output.split('\n').first.trim();
        }
      }
    } on Object {
      // Fallback to default version string if invoking `--version` fails.
    }
    return 'Google Chrome';
  }
}
