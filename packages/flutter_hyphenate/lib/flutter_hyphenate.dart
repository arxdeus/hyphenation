/// Correct, pattern-based hyphenation for Flutter text.
///
/// The entry point is [HyphenText], a drop-in replacement for [Text] that
/// breaks long words across lines and paints a hyphen at the break. The
/// hyphenation engine itself lives in `package:hyphenate`, which this library
/// re-exports, so importing this one is enough.
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

export 'package:flutter_hyphenate/src/service/error_reporting.dart';
export 'package:flutter_hyphenate/src/service/hyphenation_registry.dart';
export 'package:flutter_hyphenate/src/service/hyphenator_asset.dart';
export 'package:flutter_hyphenate/src/tex/tex_asset_loading.dart';
export 'package:flutter_hyphenate/src/widget/hyphen_paragraph.dart';
export 'package:flutter_hyphenate/src/widget/hyphen_scope.dart';
export 'package:flutter_hyphenate/src/widget/hyphen_text.dart';
export 'package:hyphenate/hyphenate.dart';
