import 'package:example/page/demo_page.dart';
import 'package:flutter/material.dart';

class HyphenDemoApp extends StatelessWidget {
  const HyphenDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_hyphenation',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const DemoPage(),
    );
  }
}
