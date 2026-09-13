// Loading hyphenators through Flutter's asset bundle.
//
// Kept out of `package:hyphenation` so that the engine stays pure Dart: it is
// then usable from a plain `dart run`, from a build script that precompiles
// patterns, and from the benchmarks, none of which have a `dart:ui` to link
// against.

import 'package:flutter/services.dart';
import 'package:hyphenation/hyphenation.dart';

/// Loads [Hyphenator]s from the asset bundle.
///
/// Dart does not allow an extension to add a constructor, so this is a static
/// method on the extension rather than `Hyphenator.fromAsset`:
///
/// ```dart
/// final hyphenator = await HyphenatorAsset.fromAsset(
///   'assets/patterns/ushyph1.tex',
/// );
/// ```
extension HyphenatorAsset on Hyphenator {
  /// Loads a pattern set from the asset bundle and compiles a hyphenator.
  ///
  /// [path] is the asset key of a TeX pattern file, for example
  /// `assets/patterns/ushyph1.tex`, declared in `pubspec.yaml`.
  static Future<Hyphenator> fromAsset(
    String path, {
    AssetBundle? bundle,
    int leftMin = 2,
    int rightMin = 2,
    int minWordLength = 5,
    int maxCacheSize = 5000,
    int? maxParagraphCacheSize,
    int maxParagraphCacheBytes = Hyphenator.kDefaultParagraphCacheBytes,
    int maxCachedWordLength = Hyphenator.kDefaultMaxCachedWordLength,
    Iterable<String> danglingWords = const <String>[],
  }) async => Hyphenator.fromSource(
    await (bundle ?? rootBundle).loadString(path),
    leftMin: leftMin,
    rightMin: rightMin,
    minWordLength: minWordLength,
    maxCacheSize: maxCacheSize,
    maxParagraphCacheSize: maxParagraphCacheSize,
    maxParagraphCacheBytes: maxParagraphCacheBytes,
    maxCachedWordLength: maxCachedWordLength,
    danglingWords: danglingWords,
  );
}
