import 'package:flutter/widgets.dart';
import 'package:flutter_hyphenation/src/service/error_reporting.dart';
import 'package:flutter_hyphenation/src/service/hyphenator_asset.dart';
import 'package:hyphenate/hyphenate.dart';

/// Holds the [Hyphenator] instances an application has loaded, keyed by
/// [Locale].
///
/// [HyphenText] resolves its hyphenator from the nearest [HyphenScope], and
/// falls back to this registry when there is none. Registering pattern sets
/// here during startup is the least intrusive way to make every `HyphenText`
/// in an app hyphenate:
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
/// ```
class HyphenationRegistry extends ChangeNotifier {
  HyphenationRegistry._() {
    ensureFlutterHyphenationErrorReporting();
  }

  /// The registry consulted by [HyphenText] when no [HyphenScope] is present.
  static final HyphenationRegistry instance = HyphenationRegistry._();

  final Map<String, Hyphenator> _byLanguageTag = <String, Hyphenator>{};
  Hyphenator? _fallback;
  String? _fallbackOwner;

  /// The hyphenator used when no pattern set matches the requested locale.
  Hyphenator? get fallback => _fallback;

  /// All registered locales.
  Iterable<Locale> get locales =>
      _byLanguageTag.keys.map(_localeFromKey).toList(growable: false);

  /// Registers [hyphenator] for [locale].
  ///
  /// Passing a `null` locale sets the [fallback] used for unmatched locales.
  /// The first pattern set registered also becomes the fallback, so a
  /// single-language app needs no locale plumbing at all. Replacing that locale
  /// also updates its automatic fallback. An explicitly registered fallback
  /// is independent of locale registrations and removals.
  void register(Locale? locale, Hyphenator hyphenator) {
    if (locale == null) {
      _fallback = hyphenator;
      _fallbackOwner = null;
    } else {
      final key = _keyFor(locale);
      _byLanguageTag[key] = hyphenator;
      if (_fallback == null || _fallbackOwner == key) {
        _fallback = hyphenator;
        _fallbackOwner = key;
      }
    }
    notifyListeners();
  }

  /// Loads a pattern asset and registers it for [locale].
  ///
  /// Returns the loaded [Hyphenator]. Calling this twice for the same locale
  /// replaces the previous pattern set.
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
    int maxCacheSize = 5000,
    int? maxParagraphCacheSize,
    int maxParagraphCacheBytes = Hyphenator.kDefaultParagraphCacheBytes,
    int maxCachedWordLength = Hyphenator.kDefaultMaxCachedWordLength,
    Iterable<String> danglingWords = const <String>[],
  }) async {
    final hyphenator = await HyphenatorAsset.fromAsset(
      assetPath,
      bundle: bundle,
      leftMin: leftMin,
      rightMin: rightMin,
      minWordLength: minWordLength,
      maxCacheSize: maxCacheSize,
      maxParagraphCacheSize: maxParagraphCacheSize,
      maxParagraphCacheBytes: maxParagraphCacheBytes,
      maxCachedWordLength: maxCachedWordLength,
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

  /// Removes the pattern set registered for [locale].
  void unregister(Locale? locale) {
    if (locale == null) {
      _fallback = null;
      _fallbackOwner = null;
    } else {
      final key = _keyFor(locale);
      _byLanguageTag.remove(key);
      if (_fallbackOwner == key) {
        _fallback = null;
        _fallbackOwner = null;
      }
    }
    notifyListeners();
  }

  /// Removes every registered pattern set.
  void clear() {
    _byLanguageTag.clear();
    _fallback = null;
    _fallbackOwner = null;
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
