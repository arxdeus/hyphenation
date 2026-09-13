// Patterns above ASCII: the dispatch tables must cover them.
//
// A node with enough edges gets a direct lookup table instead of a binary
// search. The table is keyed on the node's own span of code units, and these
// tests exist because an earlier version keyed it on a fixed 0..127 window
// instead: every accented letter and every Cyrillic letter then missed at the
// root, which silently disabled hyphenation for most languages that are not
// English.
//
// The minimums are written out at every call site on purpose.
// ignore_for_file: avoid_redundant_argument_values

import 'package:hyphenate/src/tex/tex_hyphenation_patterns.dart';
import 'package:hyphenate/src/tex/tex_pattern_parser.dart';
import 'package:hyphenate/src/tex/tex_pattern_table.dart';
import 'package:test/test.dart';

/// Marks a word without ever consulting a dispatch table.
///
/// The tables are an optimisation, so the answer with them must equal the
/// answer without them. This walks the edge list directly, which is the
/// definition the tables have to match.
List<int> _withoutTables(
  TexPatternTable table,
  String word, {
  required int leftMin,
  required int rightMin,
}) {
  final padded = '.${word.toLowerCase()}.';
  final marks = List<int>.filled(padded.length + 1, 0);
  for (var start = 0; start < padded.length; start++) {
    var node = 0;
    for (var i = start; i < padded.length; i++) {
      final unit = padded.codeUnitAt(i);
      var next = -1;
      for (var e = table.edgeStart[node]; e < table.edgeStart[node + 1]; e++) {
        if (table.edgeUnit[e] == unit) {
          next = table.edgeTarget[e];
          break;
        }
      }
      if (next < 0) {
        break;
      }
      node = next;
      final at = table.priorityAt[node];
      if (at < 0) {
        continue;
      }
      for (var k = 0; k < table.priorityLength[node]; k++) {
        final value = table.priorityBytes[at + k];
        if (marks[start + k] < value) {
          marks[start + k] = value;
        }
      }
    }
  }
  final offsets = <int>[];
  for (var at = leftMin; at <= word.length - rightMin; at++) {
    if ((marks[at + 1] & 1) == 1) {
      offsets.add(at);
    }
  }
  return offsets;
}

/// A pattern set wide enough at the root to earn a dispatch table, written in
/// [alphabet] so the table has to span that script's code units.
String _widePatternSet(String alphabet) {
  final patterns = <String>[
    for (final letter in alphabet.split('')) '${letter}1$letter',
  ];
  return '\\patterns{\n${patterns.join('\n')}\n}\n';
}

void main() {
  group('code units above ASCII', () {
    test('a Cyrillic pattern matches at the root', () {
      // The root is always wide enough for a table, and every one of these
      // letters is far above the 127 an ASCII-sized window would stop at.
      final patterns = TexHyphenationPatterns.parse(
        r'''
\patterns{
про1грамма
з1драв
ком1пью
}
''',
        leftMin: 1,
        rightMin: 1,
      );
      expect(
        patterns.split('компьютер', leftMin: 2, rightMin: 2),
        <String>['ком', 'пьютер'],
      );
    });

    test('a German pattern matches through ä, ö, ü and ß', () {
      final patterns = TexHyphenationPatterns.parse(
        r'''
\patterns{
ä1rzte
gr1öß
stra1ße
}
''',
        leftMin: 1,
        rightMin: 1,
      );
      expect(patterns.split('ärzte', leftMin: 1, rightMin: 1), <String>[
        'ä',
        'rzte',
      ]);
      expect(patterns.split('straße', leftMin: 1, rightMin: 1), <String>[
        'stra',
        'ße',
      ]);
    });

    test('a tabled node answers the same as its edge list, Latin', () {
      // 26 accented letters at the root: comfortably over the table
      // threshold, and every one of them above 127.
      const alphabet = 'àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþ';
      final source = parseTexPatterns(_widePatternSet(alphabet));
      final table = TexPatternTable.compile(source, leftMin: 1, rightMin: 1);
      final patterns = TexHyphenationPatterns.parse(
        _widePatternSet(alphabet),
        leftMin: 1,
        rightMin: 1,
      );

      for (final letter in alphabet.split('')) {
        final word = '$letter$letter$letter';
        expect(
          patterns.breakOffsets(word, leftMin: 1, rightMin: 1),
          _withoutTables(table, word, leftMin: 1, rightMin: 1),
          reason: 'U+${letter.codeUnitAt(0).toRadixString(16)}',
        );
      }
    });

    test('a tabled node answers the same as its edge list, Cyrillic', () {
      const alphabet = 'абвгдежзийклмнопрстуфхцчшщыэюя';
      final source = parseTexPatterns(_widePatternSet(alphabet));
      final table = TexPatternTable.compile(source, leftMin: 1, rightMin: 1);
      final patterns = TexHyphenationPatterns.parse(
        _widePatternSet(alphabet),
        leftMin: 1,
        rightMin: 1,
      );

      for (final letter in alphabet.split('')) {
        final word = '$letter$letter$letter';
        expect(
          patterns.breakOffsets(word, leftMin: 1, rightMin: 1),
          _withoutTables(table, word, leftMin: 1, rightMin: 1),
          reason: 'U+${letter.codeUnitAt(0).toRadixString(16)}',
        );
      }
    });

    test('a unit below the table range is rejected, not wrapped', () {
      // A table keyed on a node's range starts at its lowest unit. A lookup
      // below that produces a negative offset, and reading it as unsigned is
      // what keeps it from indexing backwards into another node's table.
      const alphabet = 'абвгдежзийклмнопрстуфхцчшщыэюя';
      final patterns = TexHyphenationPatterns.parse(
        _widePatternSet(alphabet),
        leftMin: 1,
        rightMin: 1,
      );
      // ASCII sits far below every Cyrillic letter in the table.
      expect(patterns.breakOffsets('abc', leftMin: 1, rightMin: 1), isEmpty);
      expect(patterns.split('abc', leftMin: 1, rightMin: 1), <String>['abc']);
    });

    test('a unit above the table range is rejected', () {
      const alphabet = 'abcdefghijklmnopqrstuvwxyz';
      final patterns = TexHyphenationPatterns.parse(
        _widePatternSet(alphabet),
        leftMin: 1,
        rightMin: 1,
      );
      // Cyrillic sits far above every ASCII letter in the table.
      expect(patterns.breakOffsets('ффф', leftMin: 1, rightMin: 1), isEmpty);
    });
  });
}
