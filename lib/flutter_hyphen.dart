/// Correct, dictionary-based hyphenation for Flutter text.
///
/// The entry point is [HyphenText], a drop-in replacement for [Text] that
/// breaks long words across lines and paints a hyphen at the break.
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await HyphenationRegistry.instance.registerAsset(
///     const Locale('en', 'US'),
///     'assets/dictionary/hyph_en_US.dic',
///   );
///   runApp(const MyApp());
/// }
///
/// // ... anywhere in the tree:
/// const HyphenText('Internationalization is a long word.');
/// ```
library;

export 'package:flutter_hyphen/src/dangling_words.dart'
    show DanglingWords, kEnglishDanglingWords;
export 'package:flutter_hyphen/src/hyphen_paragraph.dart'
    show HyphenParagraph, RenderHyphenParagraph;
export 'package:flutter_hyphen/src/hyphen_scope.dart'
    show HyphenScope, HyphenationRegistry;
export 'package:flutter_hyphen/src/hyphen_text.dart' show HyphenText;
export 'package:flutter_hyphen/src/hyphenator.dart'
    show Hyphenator, kSoftHyphen;
export 'package:flutter_hyphen/src/line_breaker.dart' show HyphenLineBreaker;
