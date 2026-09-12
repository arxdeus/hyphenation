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

export 'package:flutter_hyphen/src/constant/dangling_word_defaults.dart'
    show kEnglishDanglingWords;
export 'package:flutter_hyphen/src/model/hyphenation_dictionary.dart'
    show HyphenationDictionary;
export 'package:flutter_hyphen/src/processor/dangling_words.dart'
    show DanglingWords;
export 'package:flutter_hyphen/src/processor/hyphen_line_breaker.dart'
    show HyphenLineBreaker;
export 'package:flutter_hyphen/src/service/hyphenation_registry.dart'
    show HyphenationRegistry;
export 'package:flutter_hyphen/src/service/hyphenator.dart'
    show Hyphenator, kSoftHyphen;
export 'package:flutter_hyphen/src/widget/hyphen_paragraph.dart'
    show HyphenParagraph, RenderHyphenParagraph;
export 'package:flutter_hyphen/src/widget/hyphen_scope.dart' show HyphenScope;
export 'package:flutter_hyphen/src/widget/hyphen_text.dart' show HyphenText;
