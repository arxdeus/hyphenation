// Strips a TeX pattern file down to what the engine actually reads.
//
// A `hyph-*.tex` file from CTAN carries a licence header, a changelog,
// `\message{...}`, `\endinput` and, in several languages, a long commented
// appendix. None of it survives compilation, but all of it ships in the app
// bundle. Rewriting the file to the bare tokens of its two groups removes
// every comment, and the result is still a valid pattern file that
// [parseTexPatterns] reads back identically.
//
// What that is worth varies enormously: measured against hyph-utf8,
// `hyph-fr.tex` loses 70% of its bytes and `hyph-de-1996.tex` only 1%,
// because the German file is already one pattern per line. Parse time is
// not measurably affected, so this is a bundle-size tool and nothing more.

import 'package:flutter_hyphen/src/tex/tex_pattern_parser.dart';

/// How the minified file is laid out.
enum TexMinifyLayout {
  /// One token per line. Compresses best, and stays readable in a diff.
  lines,

  /// Tokens separated by single spaces, wrapped at [TexMinifyOptions.width].
  wrapped,
}

/// Knobs for [minifyTexPatterns].
class TexMinifyOptions {
  const TexMinifyOptions({
    this.layout = TexMinifyLayout.lines,
    this.width = 80,
    this.keepExceptions = true,
  });

  /// Token layout inside each group.
  final TexMinifyLayout layout;

  /// Line width used by [TexMinifyLayout.wrapped].
  final int width;

  /// Whether `\hyphenation{...}` exceptions are kept. Dropping them makes
  /// the file smaller at the cost of the words the language explicitly
  /// spells out.
  final bool keepExceptions;
}

/// What [minifyTexPatterns] produced.
class TexMinifyResult {
  const TexMinifyResult({
    required this.source,
    required this.patternCount,
    required this.exceptionCount,
  });

  /// The rewritten pattern file.
  final String source;

  /// Patterns written into `\patterns{...}`.
  final int patternCount;

  /// Exceptions written into `\hyphenation{...}`.
  final int exceptionCount;
}

/// Rewrites [source] as the smallest pattern file with the same meaning.
///
/// The output holds a `\patterns{...}` group with every pattern of the
/// input, in the order it was written, and, unless
/// [TexMinifyOptions.keepExceptions] is false, a `\hyphenation{...}` group
/// with every exception. Comments, control sequences the engine ignores and
/// all other whitespace are gone.
TexMinifyResult minifyTexPatterns(
  String source, {
  TexMinifyOptions options = const TexMinifyOptions(),
}) {
  final parsed = parseTexPatterns(source);
  final exceptions = options.keepExceptions
      ? _exceptionTokens(parsed.exceptions)
      : const <String>[];

  final out = StringBuffer();
  if (parsed.patterns.isNotEmpty) {
    _writeGroup(out, r'\patterns', parsed.patterns, options);
  }
  if (exceptions.isNotEmpty) {
    _writeGroup(out, r'\hyphenation', exceptions, options);
  }

  return TexMinifyResult(
    source: out.toString(),
    patternCount: parsed.patterns.length,
    exceptionCount: exceptions.length,
  );
}

/// Spells an exception back out with its hyphens, so the rewritten file is
/// still a pattern file rather than a private format.
List<String> _exceptionTokens(Map<String, List<int>> exceptions) {
  final tokens = <String>[];
  for (final entry in exceptions.entries) {
    final word = entry.key;
    final breaks = entry.value;
    if (breaks.isEmpty) {
      tokens.add(word);
      continue;
    }
    final buffer = StringBuffer();
    var at = 0;
    for (final offset in breaks) {
      // Defensive: an offset outside the word would silently drop letters.
      final safe = offset < at
          ? at
          : offset > word.length
          ? word.length
          : offset;
      buffer
        ..write(word.substring(at, safe))
        ..write('-');
      at = safe;
    }
    buffer.write(word.substring(at));
    tokens.add(buffer.toString());
  }
  return tokens;
}

void _writeGroup(
  StringBuffer out,
  String name,
  List<String> tokens,
  TexMinifyOptions options,
) {
  out
    ..write(name)
    ..write('{\n');
  switch (options.layout) {
    case TexMinifyLayout.lines:
      for (final token in tokens) {
        out
          ..write(token)
          ..write('\n');
      }
    case TexMinifyLayout.wrapped:
      var column = 0;
      for (final token in tokens) {
        if (column > 0 && column + 1 + token.length > options.width) {
          out.write('\n');
          column = 0;
        } else if (column > 0) {
          out.write(' ');
          column += 1;
        }
        out.write(token);
        column += token.length;
      }
      if (column > 0) {
        out.write('\n');
      }
  }
  out.write('}\n');
}
