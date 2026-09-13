// The minimums are written out at every call site on purpose: what a test
// asks for is half of what it asserts, and reading it should not require
// knowing the default.
// ignore_for_file: avoid_redundant_argument_values

// The marker: does it find the breaks Liang's algorithm says it should?
import 'dart:io';

import 'package:hyphenation/src/tex/tex_hyphenation_patterns.dart';
import 'package:test/test.dart';

/// The pattern file the package ships as its English default.
TexHyphenationPatterns _english() => TexHyphenationPatterns.parse(
  File('../../example/assets/patterns/ushyph1.tex').readAsStringSync(),
);

void main() {
  group('marking', () {
    test('the worked example from the literature', () {
      // `hyphenation` is the word Liang's thesis uses to demonstrate the
      // algorithm, and it is the one every implementation is checked against.
      expect(
        _english().split('hyphenation', leftMin: 2, rightMin: 3),
        <String>['hy', 'phen', 'ation'],
      );
    });

    test('words a reader would recognise as correctly broken', () {
      final patterns = _english();
      expect(
        patterns.split('mathematics', leftMin: 2, rightMin: 3).join('-'),
        'math-e-mat-ics',
      );
      expect(
        patterns.split('algorithm', leftMin: 2, rightMin: 3).join('-'),
        'al-go-rithm',
      );
      expect(
        patterns.split('computer', leftMin: 2, rightMin: 3).join('-'),
        'com-puter',
      );
    });

    test('a word with no break stays whole', () {
      expect(_english().split('strength', leftMin: 2, rightMin: 3), <String>[
        'strength',
      ]);
    });

    test('a word shorter than the minimums is never broken', () {
      final patterns = _english();
      expect(patterns.split('at', leftMin: 2, rightMin: 3), <String>['at']);
      expect(patterns.split('the', leftMin: 2, rightMin: 3), <String>['the']);
    });

    test('the empty string is handled rather than thrown at', () {
      expect(_english().split('', leftMin: 2, rightMin: 3), <String>['']);
    });
  });

  group('minimum distances', () {
    test('a caller may be stricter than the language', () {
      final patterns = _english();
      final loose = patterns
          .breakOffsets('hyphenation', leftMin: 2, rightMin: 2)
          .toList();
      final strict = patterns
          .breakOffsets('hyphenation', leftMin: 5, rightMin: 5)
          .toList();
      expect(strict.length, lessThan(loose.length));
      for (final at in strict) {
        expect(at, greaterThanOrEqualTo(5));
        expect('hyphenation'.length - at, greaterThanOrEqualTo(5));
      }
    });

    test('a caller may not be looser than the language', () {
      // The file declares 2/3, so asking for 1/1 still gets 2/3.
      final patterns = _english();
      for (final at in patterns.breakOffsets(
        'hyphenation',
        leftMin: 1,
        rightMin: 1,
      )) {
        expect(at, greaterThanOrEqualTo(2));
        expect('hyphenation'.length - at, greaterThanOrEqualTo(3));
      }
    });
  });

  group('case', () {
    test('a capitalised word breaks where its lower-case form does', () {
      final patterns = _english();
      expect(
        patterns.breakOffsets('Hyphenation', leftMin: 2, rightMin: 3),
        patterns.breakOffsets('hyphenation', leftMin: 2, rightMin: 3).toList(),
      );
    });

    test('the parts keep the spelling they were given', () {
      expect(
        _english().split('Hyphenation', leftMin: 2, rightMin: 3),
        <String>['Hy', 'phen', 'ation'],
      );
    });
  });

  group('exceptions', () {
    test('an exception overrides the patterns', () {
      final patterns = TexHyphenationPatterns.parse(
        r'''
\patterns{ a1b1c1d1e1f1g1h1i1j }
\hyphenation{ ab-cdefghij }
''',
        leftMin: 1,
        rightMin: 1,
      );
      expect(
        patterns.split('abcdefghij', leftMin: 1, rightMin: 1),
        <String>['ab', 'cdefghij'],
      );
    });

    test('an exception with no hyphens forbids every break', () {
      final patterns = TexHyphenationPatterns.parse(
        r'''
\patterns{ a1b1c1d1e1f1g }
\hyphenation{ abcdefg }
''',
        leftMin: 1,
        rightMin: 1,
      );
      expect(patterns.split('abcdefg', leftMin: 1, rightMin: 1), <String>[
        'abcdefg',
      ]);
    });

    test('an exception is matched regardless of case', () {
      final patterns = TexHyphenationPatterns.parse(
        r'''
\patterns{ a1b1c1d1e1f1g1h1i1j }
\hyphenation{ ab-cdefghij }
''',
        leftMin: 1,
        rightMin: 1,
      );
      expect(
        patterns.split('Abcdefghij', leftMin: 1, rightMin: 1),
        <String>['Ab', 'cdefghij'],
      );
    });
  });

  group('the algorithm itself', () {
    // These pattern sets are synthetic, so they declare the loosest possible
    // minimums: the point is what the patterns do, not what English
    // typography asks for on top of them.
    TexHyphenationPatterns compile(String source) =>
        TexHyphenationPatterns.parse(source, leftMin: 1, rightMin: 1);

    test('an odd priority permits a break and an even one forbids it', () {
      final odd = compile(r'\patterns{ ab1cd }');
      expect(odd.split('abcd', leftMin: 1, rightMin: 1), <String>['ab', 'cd']);

      final even = compile(r'\patterns{ ab2cd }');
      expect(even.split('abcd', leftMin: 1, rightMin: 1), <String>['abcd']);
    });

    test('the highest priority at a position wins', () {
      // Both patterns claim at the same position, between `b` and `c`. The
      // even 2 is larger than the odd 1, so it wins and the break is
      // forbidden.
      final patterns = compile(r'\patterns{ b1c ab2cd }');
      expect(patterns.split('abcd', leftMin: 1, rightMin: 1), <String>['abcd']);

      // The other way round, the odd one is larger and the break stands.
      final reversed = compile(r'\patterns{ b2c ab3cd }');
      expect(reversed.split('abcd', leftMin: 1, rightMin: 1), <String>[
        'ab',
        'cd',
      ]);
    });

    test('a leading dot anchors to the start of the word', () {
      final patterns = compile(r'\patterns{ .ab1cd }');
      expect(patterns.split('abcd', leftMin: 1, rightMin: 1), <String>[
        'ab',
        'cd',
      ]);
      // The same letters inside a longer word do not match the anchor.
      expect(patterns.split('xabcd', leftMin: 1, rightMin: 1), <String>[
        'xabcd',
      ]);
    });

    test('a trailing dot anchors to the end of the word', () {
      final patterns = compile(r'\patterns{ ab1cd. }');
      expect(patterns.split('abcd', leftMin: 1, rightMin: 1), <String>[
        'ab',
        'cd',
      ]);
      expect(patterns.split('abcdx', leftMin: 1, rightMin: 1), <String>[
        'abcdx',
      ]);
    });

    test('a pattern set with nothing in it breaks nothing', () {
      final patterns = compile(r'\patterns{ }');
      expect(patterns.split('hyphenation', leftMin: 1, rightMin: 1), <String>[
        'hyphenation',
      ]);
    });
  });

  group('reuse', () {
    test('the marker may be called repeatedly without carrying state', () {
      final patterns = _english();
      final first = patterns.split('hyphenation', leftMin: 2, rightMin: 3);
      patterns.split('mathematics', leftMin: 2, rightMin: 3);
      patterns.split('a', leftMin: 2, rightMin: 3);
      final again = patterns.split('hyphenation', leftMin: 2, rightMin: 3);
      expect(again, first);
    });

    test('a word longer than the scratch grows it rather than failing', () {
      final patterns = _english();
      final long = 'hyphenation' * 40;
      expect(patterns.split(long, leftMin: 2, rightMin: 3).join(), long);
    });
  });

  group('the marks buffer', () {
    test('agrees with the offsets for the same word', () {
      final patterns = _english();
      for (final word in <String>[
        'hyphenation',
        'mathematics',
        'strength',
        'computer',
      ]) {
        final count = patterns.markWord(word, leftMin: 2, rightMin: 3);
        final marks = patterns.marks;
        final fromMarks = <int>[
          for (var i = 0; i < count; i++)
            if ((marks[i] & 1) == 1) i + 1,
        ];
        expect(
          fromMarks,
          patterns.breakOffsets(word, leftMin: 2, rightMin: 3),
          reason: word,
        );
      }
    });

    test('writes one entry per character', () {
      final patterns = _english();
      expect(patterns.markWord('hyphenation', leftMin: 2, rightMin: 3), 11);
    });

    test('a word too short to break writes nothing', () {
      final patterns = _english();
      expect(patterns.markWord('at', leftMin: 2, rightMin: 3), 0);
    });

    test('is stable when read twice for the same word', () {
      final patterns = _english();
      final count = patterns.markWord('hyphenation', leftMin: 2, rightMin: 3);
      final first = List<int>.from(patterns.marks.take(count));
      final second = List<int>.from(patterns.marks.take(count));
      expect(second, first);
    });

    test('is rebuilt for the next word, not carried over', () {
      final patterns = _english();
      patterns.markWord('hyphenation', leftMin: 2, rightMin: 3);
      final long = List<int>.from(patterns.marks.take(11));
      expect(long.where((mark) => mark == 1), isNotEmpty);

      // A word with no break at all must not inherit the previous marks.
      final count = patterns.markWord('strength', leftMin: 2, rightMin: 3);
      final marks = patterns.marks;
      for (var i = 0; i < count; i++) {
        expect(marks[i], 0, reason: 'index $i');
      }
    });

    test('reading offsets without marks leaves the offsets intact', () {
      // The per-character form is derived from the offsets on demand, so
      // asking for it must not disturb them.
      final patterns = _english();
      final before = patterns
          .breakOffsets('hyphenation', leftMin: 2, rightMin: 3)
          .toList();
      patterns.markWord('hyphenation', leftMin: 2, rightMin: 3);
      final marks = patterns.marks;
      expect(marks, isNotEmpty);
      final after = patterns
          .breakOffsets('hyphenation', leftMin: 2, rightMin: 3)
          .toList();
      expect(after, before);
    });

    test('an exception fills the buffer too', () {
      final patterns = TexHyphenationPatterns.parse(
        r'''
\patterns{ a1b1c1d1e1f1g1h1i1j }
\hyphenation{ ab-cdefghij }
''',
        leftMin: 1,
        rightMin: 1,
      );
      final count = patterns.markWord('abcdefghij', leftMin: 1, rightMin: 1);
      expect(count, 10);
      final marks = patterns.marks;
      final fromMarks = <int>[
        for (var i = 0; i < count; i++)
          if ((marks[i] & 1) == 1) i + 1,
      ];
      expect(fromMarks, <int>[2]);
    });
  });
}
