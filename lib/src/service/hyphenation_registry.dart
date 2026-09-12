// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'package:flutter/widgets.dart';
import 'package:flutter_hyphen/src/service/hyphenator.dart';

/// Holds the [Hyphenator] instances an application has loaded, keyed by
/// [Locale].
///
/// [HyphenText] resolves its hyphenator from the nearest [HyphenScope], and
/// falls back to this registry when there is none. Registering dictionaries
/// here during startup is the least intrusive way to make every `HyphenText`
/// in an app hyphenate:
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
/// ```
class HyphenationRegistry extends ChangeNotifier {
  HyphenationRegistry._();

  /// The registry consulted by [HyphenText] when no [HyphenScope] is present.
  static final HyphenationRegistry instance = HyphenationRegistry._();

  final Map<String, Hyphenator> _byLanguageTag = <String, Hyphenator>{};
  Hyphenator? _fallback;

  /// The hyphenator used when no dictionary matches the requested locale.
  Hyphenator? get fallback => _fallback;

  /// All registered locales.
  Iterable<Locale> get locales =>
      _byLanguageTag.keys.map(_localeFromKey).toList(growable: false);

  /// Registers [hyphenator] for [locale].
  ///
  /// Passing a `null` locale sets the [fallback] used for unmatched locales.
  /// The first dictionary registered also becomes the fallback, so a
  /// single-language app needs no locale plumbing at all.
  void register(Locale? locale, Hyphenator hyphenator) {
    if (locale == null) {
      _fallback = hyphenator;
    } else {
      _byLanguageTag[_keyFor(locale)] = hyphenator;
      _fallback ??= hyphenator;
    }
    notifyListeners();
  }

  /// Loads a dictionary asset and registers it for [locale].
  ///
  /// Returns the loaded [Hyphenator]. Calling this twice for the same locale
  /// replaces the previous dictionary.
  ///
  /// [danglingWords] lists words that must not be left hanging at the end of
  /// a line, such as English prepositions and conjunctions. No list is
  /// bundled; supply one for your language and house style. Leave it empty to
  /// turn the feature off.
  Future<Hyphenator> registerAsset(
    Locale? locale,
    String assetPath, {
    AssetBundle? bundle,
    int leftMin = 2,
    int rightMin = 2,
    int minWordLength = 5,
    Iterable<String> danglingWords = const <String>[],
  }) async {
    final hyphenator = await Hyphenator.fromAsset(
      assetPath,
      bundle: bundle,
      leftMin: leftMin,
      rightMin: rightMin,
      minWordLength: minWordLength,
      danglingWords: danglingWords,
    );
    register(locale, hyphenator);
    return hyphenator;
  }

  /// Returns the hyphenator registered for [locale].
  ///
  /// Resolution walks from the most specific match to the least specific one:
  /// `language_script_country`, then `language_country`, then `language`, and
  /// finally the [fallback].
  Hyphenator? resolve(Locale? locale) {
    if (locale != null) {
      for (final key in _candidateKeys(locale)) {
        final hyphenator = _byLanguageTag[key];
        if (hyphenator != null) {
          return hyphenator;
        }
      }
    }
    return _fallback;
  }

  /// Removes the dictionary registered for [locale].
  void unregister(Locale? locale) {
    if (locale == null) {
      _fallback = null;
    } else {
      final removed = _byLanguageTag.remove(_keyFor(locale));
      if (identical(removed, _fallback)) {
        _fallback = null;
      }
    }
    notifyListeners();
  }

  /// Removes every registered dictionary.
  void clear() {
    _byLanguageTag.clear();
    _fallback = null;
    notifyListeners();
  }

  static String _keyFor(Locale locale) => locale.toString();

  static Iterable<String> _candidateKeys(Locale locale) sync* {
    yield locale.toString();
    if (locale.scriptCode != null && locale.countryCode != null) {
      yield Locale(locale.languageCode, locale.countryCode).toString();
    }
    if (locale.scriptCode != null || locale.countryCode != null) {
      yield locale.languageCode;
    }
  }

  static Locale _localeFromKey(String key) {
    final parts = key.split('_');
    return switch (parts.length) {
      1 => Locale(parts[0]),
      2 => Locale(parts[0], parts[1]),
      _ => Locale.fromSubtags(
        languageCode: parts[0],
        scriptCode: parts[1],
        countryCode: parts[2],
      ),
    };
  }
}
