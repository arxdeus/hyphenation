/// Correct, pattern-based hyphenation for Flutter text.
///
/// The entry point is [HyphenText], a drop-in replacement for [Text] that
/// breaks long words across lines and paints a hyphen at the break.
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await HyphenationRegistry.instance.registerAsset(
///     const Locale('en', 'US'),
///     'assets/patterns/ushyph1.tex',
///   );
///   runApp(const MyApp());
/// }
///
/// // ... anywhere in the tree:
/// const HyphenText('Internationalization is a long word.');
/// ```
library;

export 'package:flutter_hyphen/src/processor/dangling_words.dart';
export 'package:flutter_hyphen/src/processor/hyphen_line_breaker.dart';
export 'package:flutter_hyphen/src/service/hyphenation_registry.dart';
export 'package:flutter_hyphen/src/service/hyphenator.dart';
export 'package:flutter_hyphen/src/tex/tex_asset_loading.dart';
export 'package:flutter_hyphen/src/tex/tex_hyphenation_patterns.dart';
export 'package:flutter_hyphen/src/tex/tex_pattern_minifier.dart';
export 'package:flutter_hyphen/src/widget/hyphen_paragraph.dart';
export 'package:flutter_hyphen/src/widget/hyphen_scope.dart';
export 'package:flutter_hyphen/src/widget/hyphen_text.dart';
