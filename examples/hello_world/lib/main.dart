// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 20.0,
        children: [
          Text(
            'Hello, world!',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.normal,
              fontStyle: FontStyle.normal,
            ),
          ),
          Text(
            'Hello, world!',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, fontStyle: FontStyle.normal),
          ),
          Text(
            'Hello, world!',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.normal,
              fontStyle: FontStyle.italic,
            ),
          ),
          Text(
            'Hello, world!',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}
