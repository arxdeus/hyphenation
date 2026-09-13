// A minimal `package:flutter_hyphenation` app: register a pattern asset once,
// then use `HyphenText` anywhere in place of `Text`.
//
// Run it with `flutter run` from this directory.
import 'package:flutter/material.dart';
import 'package:flutter_hyphenation/flutter_hyphenation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // One registration per locale is enough; every HyphenText below picks it up.
  await HyphenationRegistry.instance.registerAsset(
    const Locale('en', 'US'),
    'assets/patterns/ushyph1.tex',
  );
  runApp(const ExampleApp());
}

/// Shows the same paragraph hyphenated and unhyphenated in a narrow column.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  static const String _text =
      'Internationalization and localization are counterintuitively '
      'inconsequential without hyphenation in narrow columns.';

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'flutter_hyphenation example',
    home: Scaffold(
      appBar: AppBar(title: const Text('flutter_hyphenation')),
      body: const Center(
        child: SizedBox(
          width: 220,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('HyphenText', style: TextStyle(fontWeight: FontWeight.bold)),
              HyphenText(_text, textAlign: TextAlign.justify),
              SizedBox(height: 24),
              Text('Text', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_text, textAlign: TextAlign.justify),
            ],
          ),
        ),
      ),
    ),
  );
}
