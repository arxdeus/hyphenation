/// Correct, pattern-based hyphenation for Dart.
///
/// The entry point is [Hyphenator], which compiles a TeX pattern file and
/// splits words at their hyphenation points. [HyphenLineBreaker] turns that
/// into lines for a given width, given a way to measure text.
///
/// This package has no Flutter dependency. For widgets, an asset loader and a
/// locale registry, use `package:flutter_hyphenate`.
///
/// ```dart
/// final hyphenator = Hyphenator.fromSource(
///   await File('ushyph1.tex').readAsString(),
/// );
/// hyphenator.split('hyphenation'); // [hy, phen, ation]
/// ```
library;

export 'package:hyphenate/src/model/break_candidate.dart';
export 'package:hyphenate/src/processor/dangling_words.dart';
export 'package:hyphenate/src/processor/hyphen_line_breaker.dart';
export 'package:hyphenate/src/service/hyphenator.dart';
export 'package:hyphenate/src/tex/tex_hyphenation_patterns.dart';
export 'package:hyphenate/src/tex/tex_pattern_minifier.dart';
export 'package:hyphenate/src/util/errors.dart';
