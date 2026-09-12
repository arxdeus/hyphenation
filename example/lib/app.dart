import 'package:flutter/material.dart';

import 'page/demo_page.dart';

class HyphenDemoApp extends StatelessWidget {
  const HyphenDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_hyphen',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const DemoPage(),
    );
  }
}
