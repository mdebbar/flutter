// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:meta/meta.dart';

import 'base/common.dart';

/// Placeholder for base href.
const String kBaseHrefPlaceholder = r'$FLUTTER_BASE_HREF';
/// Placeholder for flutter.js script.
const String kFlutterJsScriptPlaceholder = r'$_$FLUTTER_JS_SCRIPT';

final RegExp _substitutionPlaceholderRegExp = RegExp(r'\$_\$[A-Z_]+');

class IndexHtml {
  IndexHtml(this._content);

  String get content => _content;
  String _content;

  Document _getDocument({bool generateSpans = false}) =>
      parse(_content, generateSpans: generateSpans);

  /// Parses the base href from the index.html file.
  String get baseHref {
    final Element? baseElement = _getDocument().querySelector('base');
    final String? baseHref = baseElement?.attributes == null
        ? null
        : baseElement!.attributes['href'];

    if (baseHref == null || baseHref == kBaseHrefPlaceholder) {
      return '';
    }

    if (!baseHref.startsWith('/')) {
      throw ToolExit(
        'Error: The base href in "web/index.html" must be absolute (i.e. start '
        'with a "/"), but found: `${baseElement!.outerHtml}`.\n'
        '$_basePathExample',
      );
    }

    if (!baseHref.endsWith('/')) {
      throw ToolExit(
        'Error: The base href in "web/index.html" must end with a "/", but found: `${baseElement!.outerHtml}`.\n'
        '$_basePathExample',
      );
    }

    return stripLeadingSlash(stripTrailingSlash(baseHref));
  }

  /// Applies substitutions to the content of the index.html file.
  void applySubstitutions({
    required String baseHref,
    required String? serviceWorkerVersion,
    required String flutterJsScript,
  }) {
    _applyLegacySubstitutions(
      baseHref: baseHref,
      serviceWorkerVersion: serviceWorkerVersion,
    );

    final Map<String, String> substitutions = <String, String>{
      kFlutterJsScriptPlaceholder: flutterJsScript,
      // r'FOO': () => 'bar',
    };

    final StringBuffer buffer = StringBuffer();
    final Document document = _getDocument(generateSpans: true);
    int lastEnd = 0;
    for (final Element script in document.querySelectorAll('script')) {
      if (!script.attributes.containsKey('src')) {
        buffer.write(_content.substring(lastEnd, script.innerHtmlStart));
        buffer.write(substituteInText(script.innerHtml, substitutions));
        lastEnd = script.innerHtmlEnd;
      }
    }
    buffer.write(_content.substring(lastEnd));
    _content = buffer.toString();
  }

  void _applyLegacySubstitutions({
    required String baseHref,
    required String? serviceWorkerVersion,
  }) {
    // These substitutions are kept for backwards compatibility. All new
    // substitutions should be added to the new map-based system above.

    if (_content.contains(kBaseHrefPlaceholder)) {
      _content = _content.replaceAll(kBaseHrefPlaceholder, baseHref);
    }

    if (serviceWorkerVersion != null) {
      _content = _content
          .replaceFirst(
            'var serviceWorkerVersion = null',
            "var serviceWorkerVersion = '$serviceWorkerVersion'",
          )
          // This is for legacy index.html that still uses the old service
          // worker loading mechanism.
          .replaceFirst(
            "navigator.serviceWorker.register('flutter_service_worker.js')",
            "navigator.serviceWorker.register('flutter_service_worker.js?v=$serviceWorkerVersion')",
          );
    }
  }
}

@visibleForTesting
String substituteInText(String text, Map<String, String> substitutions) {
  // Make sure all keys in the `substitutions` map start with "$_$".
  assert(() {
    for (final String placeholder in substitutions.keys) {
      if (!_substitutionPlaceholderRegExp.hasMatch(placeholder)) {
        throw Exception('Invalid placeholder: $placeholder');
      }
    }
    return true;
  }());

  _substitutionPlaceholderRegExp.allMatches(text).forEach((Match match) {
    final String placeholder = match.group(0)!;
    final String? substitution = substitutions[placeholder];
    if (substitution == null) {
      throw Exception(
          'Unknown placeholder found in web/index.html: $placeholder');
    }
    text = text.replaceRange(match.start, match.end, substitution);
  });
  return text;
}

extension on Element {
  int get innerHtmlStart {
    return sourceSpan!.end.offset;
  }
  int get innerHtmlEnd {
    return innerHtmlStart + innerHtml.length;
  }
}

/// Strips the leading slash from a path.
String stripLeadingSlash(String path) {
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  return path;
}

/// Strips the trailing slash from a path.
String stripTrailingSlash(String path) {
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

const String _basePathExample = '''
For example, to serve from the root use:

    <base href="/">

To serve from a subpath "foo" (i.e. http://localhost:8080/foo/ instead of http://localhost:8080/) use:

    <base href="/foo/">

For more information, see: https://developer.mozilla.org/en-US/docs/Web/HTML/Element/base
''';
