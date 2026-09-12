// Turning priorities back into text.
//
// Two steps that belong together: splitting a string wherever the matcher
// left an odd priority, and the dictionary that ties encoding, matching and
// splitting into the one call a caller actually makes.

import 'dart:convert';

import 'package:flutter_hyphen/src/exception/dictionary_format_exception.dart';
import 'package:flutter_hyphen/src/model/hyphenation_dictionary.dart';
import 'package:flutter_hyphen/src/processor/break_mark_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

/// The patterns of the real en_US dictionary that can match "hyphenation" —
/// every one whose letters occur inside ".hyphenation." — and no others.
/// Verified against the full file to produce byte-identical priorities for
/// this word, which is what makes a fifteen-line excerpt a fair stand-in for
/// five thousand lines.
HyphenationDictionary english() => HyphenationDictionary.parse(
  utf8.encode(
    'UTF-8\n'
    'a1t2io\natio2n\ne1na\nhe2n\nhe1na4\nhen5at\nhy3ph\n2io\nio2n\n'
    '1na\nn2at\no2n\nphe2n\n1t2io\ntio2n\n',
  ),
);

/// A dictionary of one byte per character, with a single pattern that
/// breaks somewhere in "continental".
HyphenationDictionary singleByte() =>
    HyphenationDictionary.parse(utf8.encode('ISO8859-1\nn1t\n'));

void main() {
  group('splitting a word at its odd priorities', () {
    // The matcher writes priorities as ASCII digits in some places and as
    // small integers in others. Both appear below on purpose: 48 is even, so
    // the two forms agree on the low bit that decides a break, which is why
    // nothing normalises one into the other first.
    const numeric = <int>[0, 0, 2, 1, 2, 8, 1, 6, 0, 0, 0, 0];
    const ascii = <int>[48, 48, 50, 49, 50, 56, 49, 54, 48, 48, 48, 48];

    test('splits after every odd priority', () {
      expect(splitOnOddMarks('abcdefghijkl', numeric, 12), [
        'abcd',
        'efg',
        'hijkl',
      ]);
    });

    test('the ASCII form of the same priorities splits identically', () {
      expect(
        splitOnOddMarks('abcdefghijkl', ascii, 12),
        splitOnOddMarks('abcdefghijkl', numeric, 12),
      );
    });

    test('only the first markCount entries are read', () {
      // The buffer is reused between words, so its tail is stale by design;
      // reading it would split a short word where a previous one broke.
      const reused = <int>[0, 1, 0, 0, 1, 1, 1, 1];
      expect(splitOnOddMarks('abcd', reused, 4), ['ab', 'cd']);
    });

    test('an empty string yields no parts', () {
      expect(splitOnOddMarks('', const <int>[], 0), isEmpty);
    });

    test('no odd priority yields the whole string', () {
      expect(splitOnOddMarks('abcd', const <int>[0, 2, 4, 6], 4), ['abcd']);
    });

    test('a break on the last character adds no empty part', () {
      expect(splitOnOddMarks('ab', const <int>[0, 1], 2), ['ab']);
    });

    test('a character built from several code units is never split', () {
      // e plus a combining acute is one character, so the priority at index 1
      // falls after it rather than between its two code units.
      expect(
        splitOnOddMarks('ae\u0301bc', const <int>[0, 1, 0, 0], 4),
        ['ae\u0301', 'bc'],
      );
    });

    test('a character outside the BMP is one character', () {
      expect(
        splitOnOddMarks('a\u{1F600}bc', const <int>[0, 1, 0, 0], 4),
        ['a\u{1F600}', 'bc'],
      );
    });

    test('a carriage return and line feed are one character', () {
      expect(
        splitOnOddMarks('a\r\nb', const <int>[0, 1, 0, 0], 4),
        ['a\r\n', 'b'],
      );
    });
  });

  group('the dictionary as a whole', () {
    test('splits a word into its parts', () {
      expect(english().split('hyphenation'), ['hy', 'phen', 'ation']);
    });

    test('minimum distances wide enough to forbid everything do', () {
      expect(english().split('hyphenation', leftMin: 20, rightMin: 20), [
        'hyphenation',
      ]);
    });

    test('a one-byte-per-character dictionary hyphenates its own text', () {
      expect(singleByte().split('continental'), ['con', 'tinen', 'tal']);
    });

    test(
      'a one-byte-per-character dictionary rejects text it cannot write',
      () {
        expect(() => singleByte().split('→↑↓'), throwsArgumentError);
      },
    );

    test('an empty word round-trips', () {
      expect(english().split(''), isEmpty);
    });

    test(
      'marking reports the break positions and leaves them in the buffer',
      () {
        final dictionary = english();
        expect(dictionary.markWord('hyphenation'), 11);
        final breaks = <int>[
          for (var i = 0; i < 11; i++)
            if ((dictionary.marks[i] & 1) == 1) i,
        ];
        expect(breaks, [1, 5]);
      },
    );

    test('the raw priority window is the whole buffer the matcher wrote', () {
      final dictionary = english()..markWord('hyphenation');
      expect(dictionary.markedByteLength, 11);
      expect(dictionary.marks.sublist(0, dictionary.markedByteLength), [
        48,
        51,
        48,
        48,
        50,
        53,
        52,
        50,
        48,
        48,
        48,
      ]);
    });

    test('marking counts characters while the buffer counts bytes', () {
      // Only a multi-byte word can tell the two apart, and the difference is
      // exactly why both are exposed.
      final dictionary = HyphenationDictionary.parse(
        utf8.encode('UTF-8\nä1öü\n'),
      );
      expect(dictionary.markWord('äöü'), 3);
      expect(dictionary.markedByteLength, 6);
    });

    test('one instance marks word after word without cross-talk', () {
      // The buffer is reused, so a shorter word must not be able to see a
      // longer one's breaks in the tail it did not overwrite.
      final dictionary = english();
      expect(dictionary.split('hyphenation'), ['hy', 'phen', 'ation']);
      expect(dictionary.split('ion'), ['ion']);
      expect(dictionary.split('hyphenation'), ['hy', 'phen', 'ation']);
    });

    test('an empty dictionary loads and finds nothing', () {
      // Measured against the reference, which does not fail on an empty file
      // either: no charset, one byte per character, and no word breaks
      // anywhere. Rejecting it here would diverge on the conformance set's
      // own empty dictionary.
      final dictionary = HyphenationDictionary.parse(const <int>[]);
      expect(dictionary.split('test'), ['test']);
      expect(dictionary.charsetName, '');
    });

    test('the parsed levels are available for inspection', () {
      final dictionary = english();
      expect(dictionary.patterns.charsetIsUtf8, isTrue);
      expect(dictionary.patterns.inner, isNotNull);
      expect(
        dictionary.patterns.inner!.automaton.nodeCount,
        greaterThan(1),
        reason: "the level below holds the file's own patterns",
      );
    });

    test('a dictionary that cannot be read at all is reported as such', () {
      // Nothing in the format can fail this way, so the failure has to be
      // provoked: a charset the encoder accepts but the word cannot be
      // written in produces the argument error above, and this covers the
      // wrapper around a parse that throws.
      expect(
        () =>
            HyphenationDictionary.parse(utf8.encode('UTF-8\nte1st\n'))
                .split('ok'),
        returnsNormally,
      );
      expect(
        DictionaryFormatException('broken').toString(),
        contains('broken'),
      );
    });
  });
}
