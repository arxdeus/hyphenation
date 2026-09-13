/// Correct, pattern-based hyphenation for Dart.
///
/// The entry point is [Hyphenator], which compiles a TeX pattern file and
/// splits words at their hyphenation points. [HyphenLineBreaker] turns that
/// into lines for a given width, given a way to measure text.
///
/// This package has no Flutter dependency. For widgets, an asset loader and a
/// locale registry, use `package:flutter_hyphenation`.
///
/// ```dart
/// final hyphenator = Hyphenator.fromSource(
///   await File('ushyph1.tex').readAsString(),
/// );
/// hyphenator.split('hyphenation'); // [hy, phen, ation]
/// ```
library;

export 'package:hyphenation/src/model/break_candidate.dart';
export 'package:hyphenation/src/processor/dangling_words.dart';
export 'package:hyphenation/src/processor/hyphen_line_breaker.dart';
export 'package:hyphenation/src/service/hyphenator.dart';
export 'package:hyphenation/src/tex/tex_hyphenation_patterns.dart';
export 'package:hyphenation/src/tex/tex_pattern_minifier.dart';
export 'package:hyphenation/src/util/errors.dart';
