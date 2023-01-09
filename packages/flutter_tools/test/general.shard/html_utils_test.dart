// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/html_utils.dart';

import '../src/common.dart';

const String htmlSample1 = '''
<!DOCTYPE html>
<html>
<head>
  <title></title>
  <base href="/foo/222/">
  <meta charset="utf-8">
  <link rel="icon" type="image/png" href="favicon.png"/>
</head>
<body>
  <div></div>
  <script src="main.dart.js"></script>
</body>
</html>
''';

const String htmlSample2 = '''
<!DOCTYPE html>
<html>
<head>
  <title></title>
  <base href="$kBaseHrefPlaceholder">
  <meta charset="utf-8">
  <link rel="icon" type="image/png" href="favicon.png"/>
  <script>$kFlutterJsScriptPlaceholder</script>
</head>
<body>
  <div></div>
  <script src="main.dart.js"></script>
  <script>
    var serviceWorkerVersion = null;
  </script>
  <script>
    navigator.serviceWorker.register('flutter_service_worker.js');
  </script>
</body>
</html>
''';

String htmlSample2Replaced({
  required String baseHref,
  required String serviceWorkerVersion,
  required String flutterJsScript,
}) =>
    '''
<!DOCTYPE html>
<html>
<head>
  <title></title>
  <base href="$baseHref">
  <meta charset="utf-8">
  <link rel="icon" type="image/png" href="favicon.png"/>
  <script>$flutterJsScript</script>
</head>
<body>
  <div></div>
  <script src="main.dart.js"></script>
  <script>
    var serviceWorkerVersion = '$serviceWorkerVersion';
  </script>
  <script>
    navigator.serviceWorker.register('flutter_service_worker.js?v=$serviceWorkerVersion');
  </script>
</body>
</html>
''';

const String htmlSample3 = '''
<!DOCTYPE html>
<html>
<head>
  <title></title>
  <meta charset="utf-8">
  <link rel="icon" type="image/png" href="favicon.png"/>
</head>
<body>
  <div></div>
  <script src="main.dart.js"></script>
</body>
</html>
''';

void main() {
  test('can parse baseHref', () {
    expect(IndexHtml('<base href="/foo/111/">').baseHref, 'foo/111');
    expect(IndexHtml(htmlSample1).baseHref, 'foo/222');
    expect(IndexHtml(htmlSample2).baseHref, ''); // Placeholder base href.
  });

  test('handles missing baseHref', () {
    expect(IndexHtml('').baseHref, '');
    expect(IndexHtml('<base>').baseHref, '');
    expect(IndexHtml(htmlSample3).baseHref, '');
  });

  test('throws on invalid baseHref', () {
    expect(() => IndexHtml('<base href>').baseHref, throwsToolExit());
    expect(() => IndexHtml('<base href="">').baseHref, throwsToolExit());
    expect(() => IndexHtml('<base href="foo/111">').baseHref, throwsToolExit());
    expect(
      () => IndexHtml('<base href="foo/111/">').baseHref,
      throwsToolExit(),
    );
    expect(
      () => IndexHtml('<base href="/foo/111">').baseHref,
      throwsToolExit(),
    );
  });

  test('applies substitutions', () {
    final IndexHtml indexHtml = IndexHtml(htmlSample2);
    indexHtml.applySubstitutions(
      baseHref: '/foo/333/',
      serviceWorkerVersion: 'v123xyz',
      flutterJsScript: 'console.log("flutter.js");',
    );
    expect(
      indexHtml.content,
      htmlSample2Replaced(
        baseHref: '/foo/333/',
        serviceWorkerVersion: 'v123xyz',
        flutterJsScript: 'console.log("flutter.js");',
      ),
    );
  });

  test('re-parses after substitutions', () {
    final IndexHtml indexHtml = IndexHtml(htmlSample2);
    expect(indexHtml.baseHref, ''); // Placeholder base href.

    indexHtml.applySubstitutions(
      baseHref: '/foo/333/',
      serviceWorkerVersion: 'v123xyz',
      flutterJsScript: '',
    );
    // The parsed base href should be updated after substitutions.
    expect(indexHtml.baseHref, 'foo/333');
  });

  group('$substituteInText', () {
    test('simple substitutions', () {
      expect(
        substituteInText(r'foo $_$BAR baz', <String, String>{r'$_$BAR': 'barbar'}),
        'foo barbar baz',
      );
      expect(
        substituteInText(
          r'$_$FOO bar $_$BAZ',
          <String, String>{r'$_$BAZ': 'bazbaz', r'$_$FOO': 'foofoo'},
        ),
        'foofoo bar bazbaz',
      );
    });

    test('various lengths', () {
      expect(
        substituteInText(
          'foo bar baz',
          <String, String>{'foo': 'MyFoo', 'bar': 'MyBar', 'baz': 'MyBaz'},
        ),
        'MyFoo MyBar MyBaz',
      );
    });

    test('recursive substitutions', () {
      expect(
        substituteInText(
          'foo bar baz',
          <String, String>{'foo': 'MyFoo', 'MyFoo': 'MyFoo2'},
        ),
        'MyFoo2 bar baz',
      );
      expect(
        substituteInText(
          'foo bar baz',
          <String, String>{'foo': 'MyFoo', 'MyFoo': 'MyFoo2', 'MyFoo2': 'MyFoo3'},
        ),
        'MyFoo3 bar baz',
      );
      expect(
        substituteInText(
          'foo bar baz',
          <String, String>{'foo': 'bar', 'bar': 'MyBar2'},
        ),
        'MyBar2 MyBar2 baz',
      );
    });
  });
}
