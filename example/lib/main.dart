import 'package:example/app.dart';
import 'package:example/constant/dangling_words.dart';
import 'package:example/constant/demo_patterns.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

Future<void> main() async {
  // Marionette lets an agent drive this demo (tap, screenshot, hot reload)
  // over the VM service. It is debug-only and changes nothing about how the
  // widgets below behave.
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  // Registering here makes every HyphenText in the app hyphenate without any
  // further plumbing.
  // `danglingWords` is the whole of the "no hanging prepositions" feature:
  // HyphenLineBreaker stops offering a break after any of these words, so it
  // is carried down to the next line with the word it belongs to. Nothing is
  // inserted into the text. Leave it out to turn the feature off.
  final hyphenator = await HyphenationRegistry.instance.registerAsset(
    const Locale('en', 'US'),
    kEnglishPatterns,
    danglingWords: kEnglishDanglingWords,
  );
  kPlainHyphenator = Hyphenator(hyphenator.patterns);
  runApp(const HyphenDemoApp());
}
