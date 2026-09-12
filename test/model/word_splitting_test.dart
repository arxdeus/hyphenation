// Turning priorities back into text.
//
// Two steps that belong together: splitting a string wherever the matcher
// left an odd priority, and the dictionary that ties encoding, matching and
// splitting into the one call a caller actually makes.

import 'dart:convert';

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
}
