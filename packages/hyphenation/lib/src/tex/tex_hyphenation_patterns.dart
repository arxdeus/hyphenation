// A hyphenation dictionary built from TeX pattern files.

import 'dart:typed_data';

import 'package:hyphenation/src/tex/tex_pattern_table.dart';
import 'package:hyphenation/src/tex/tex_word_marker.dart';

/// Hyphenates words using Liang's algorithm over a TeX pattern file.
///
/// Load one from the text of a `hyph-*.tex` file:
///
/// ```dart
/// final patterns = TexHyphenationPatterns.parse(texSource);
/// patterns.split('hyphenation'); // [hy, phen, ation]
/// ```
class TexHyphenationPatterns {
  TexHyphenationPatterns._(this._table) : _marker = TexWordMarker(_table);

  final TexPatternTable _table;
  final TexWordMarker _marker;

  /// Compiles the text of a TeX pattern file.
  ///
  /// [leftMin] and [rightMin] are the language's own minimum distances. TeX
  /// pattern files state them in a comment rather than in syntax, so they
  /// cannot be read out of the file and are supplied here instead; the
  /// defaults are TeX's own.
  factory TexHyphenationPatterns.parse(
    String source, {
    int leftMin = 2,
    int rightMin = 3,
  }) => TexHyphenationPatterns._(
    TexPatternTable.compileSource(
      source,
      leftMin: leftMin,
      rightMin: rightMin,
    ),
  );

  /// How many patterns were compiled.
  int get patternNodeCount => _table.edgeStart.length - 1;

  /// One mark per character of the last marked word: odd where the word may
  /// be broken after that character. Valid until the next call.
  Uint8List get marks => _marker.marks;

  /// Marks [word] and returns how many entries of [marks] were written.
  ///
  /// The allocation-free path: nothing is returned but a count, and the
  /// caller reads the marks straight out of the buffer.
  int markWord(String word, {int leftMin = 1, int rightMin = 1}) {
    _marker.mark(word, leftMin: leftMin, rightMin: rightMin);
    return _marker.markCount;
  }

  /// The character offsets [word] may be broken after.
  ///
  /// The returned list is owned by this instance and is overwritten by the
  /// next call. Copy it if it has to outlive that.
  List<int> breakOffsets(String word, {int leftMin = 1, int rightMin = 1}) {
    _marker.mark(word, leftMin: leftMin, rightMin: rightMin);
    return _marker.breaks;
  }

  /// [word] split into the parts it may be broken into.
  List<String> split(String word, {int leftMin = 1, int rightMin = 1}) {
    _marker.mark(word, leftMin: leftMin, rightMin: rightMin);
    final breaks = _marker.breaks;
    final count = breaks.length;
    if (count == 0) {
      return List<String>.filled(1, word);
    }
    // The number of parts is known up front, so the list is sized once rather
    // than grown while the parts are cut.
    final parts = List<String>.filled(count + 1, word);
    var from = 0;
    for (var i = 0; i < count; i++) {
      final at = breaks[i];
      parts[i] = word.substring(from, at);
      from = at;
    }
    parts[count] = word.substring(from);
    return parts;
  }
}
