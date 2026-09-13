// Loading pattern files through Flutter's asset bundle.
//
// Kept apart from [TexHyphenationPatterns] itself so that the engine stays
// pure Dart: it is then usable from a plain `dart run`, from a build script
// that precompiles patterns, and from the benchmarks, none of which have a
// `dart:ui` to link against.

import 'package:flutter/services.dart';
import 'package:flutter_hyphen/src/tex/tex_hyphenation_patterns.dart';

/// Loads [TexHyphenationPatterns] from the asset bundle.
extension TexHyphenationPatternsAsset on TexHyphenationPatterns {
  /// Loads and compiles a pattern file from the asset bundle.
  ///
  /// [path] is the asset key of a TeX pattern file, for example
  /// `assets/patterns/ushyph1.tex`, declared in `pubspec.yaml`:
  ///
  /// ```yaml
  /// flutter:
  ///   assets:
  ///     - assets/patterns/ushyph1.tex
  /// ```
  static Future<TexHyphenationPatterns> fromAsset(
    String path, {
    AssetBundle? bundle,
    int leftMin = 2,
    int rightMin = 3,
  }) async => TexHyphenationPatterns.parse(
    await (bundle ?? rootBundle).loadString(path),
    leftMin: leftMin,
    rightMin: rightMin,
  );
}
