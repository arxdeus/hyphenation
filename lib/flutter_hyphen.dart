// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

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

export 'package:flutter_hyphen/src/model/hyphenation_dictionary.dart';
export 'package:flutter_hyphen/src/processor/dangling_words.dart';
export 'package:flutter_hyphen/src/processor/hyphen_line_breaker.dart';
export 'package:flutter_hyphen/src/service/hyphenation_registry.dart';
export 'package:flutter_hyphen/src/service/hyphenator.dart';
export 'package:flutter_hyphen/src/widget/hyphen_paragraph.dart';
export 'package:flutter_hyphen/src/widget/hyphen_scope.dart';
export 'package:flutter_hyphen/src/widget/hyphen_text.dart';
