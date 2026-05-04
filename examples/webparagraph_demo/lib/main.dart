import 'package:flutter/material.dart';
import 'home.dart';

void main() {
  runApp(const WebParagraphDemoApp());
}

class WebParagraphDemoApp extends StatelessWidget {
  const WebParagraphDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebParagraph Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.cyan,
        fontFamily: 'Roboto', // Default font
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -1),
          bodyLarge: TextStyle(fontSize: 16, color: Color(0xFFCCCCCC)),
        ),
      ),
      home: const HomePage(),
    );
  }
}
