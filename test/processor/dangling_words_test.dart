// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dangling_word_lists.dart';

void main() {
  group('DanglingWords.compile', () {
    test('an empty list turns the feature off', () {
      expect(DanglingWords.compile(const <String>[]), isNull);
      expect(DanglingWords.compile(const <String>{}), isNull);
    });

    test('a list of empty strings also turns the feature off', () {
      expect(DanglingWords.compile(const <String>['', '']), isNull);
    });

    test('a non-empty list compiles', () {
      final words = DanglingWords.compile(const <String>['the', 'in']);
      expect(words, isNotNull);
      expect(words!.length, 2);
    });
  });

  group('DanglingWords.contains', () {
    final english = DanglingWords(kEnglishDanglingWords);

    test('matches a listed word', () {
      expect(english.contains('the'), isTrue);
      expect(english.contains('under'), isTrue);
      expect(english.contains('without'), isTrue);
    });

    test('does not match an ordinary word', () {
      expect(english.contains('word'), isFalse);
      expect(english.contains('interface'), isFalse);
    });

    test('is case insensitive', () {
      expect(english.contains('The'), isTrue);
      expect(english.contains('Under'), isTrue);
      expect(english.contains('UNDER'), isTrue);
    });

    test('matches an entry containing a hyphen', () {
      final words = DanglingWords(const <String>['out-of', 'up-to']);
      expect(words.contains('out-of'), isTrue);
      expect(words.contains('OUT-OF'), isTrue);
      expect(words.contains('up-to'), isTrue);
    });

    test('ignores leading punctuation', () {
      // An opening quote or bracket belongs with the word that follows it.
      expect(english.contains('"the'), isTrue);
      expect(english.contains('(the'), isTrue);
      expect(english.contains('„under'), isTrue);
      expect(english.contains('—the'), isTrue);
    });

    test('rejects trailing punctuation', () {
      // The comma ends the clause, so the word is no longer dangling.
      expect(english.contains('the,'), isFalse);
      expect(english.contains('under.'), isFalse);
      expect(english.contains('the"'), isFalse);
      expect(english.contains('the…'), isFalse);
    });

    test('does not glue an unlisted single character', () {
      // The implicit "any one-character word" rule is deliberately absent:
      // only what the caller listed is glued.
      expect(english.contains('i'), isFalse);
      expect(english.contains('1'), isFalse);
      expect(english.contains('x'), isFalse);
      // The article 'a' is in the list, so it still matches.
      expect(english.contains('a'), isTrue);
    });

    test('rejects the empty token and pure punctuation', () {
      expect(english.contains(''), isFalse);
      expect(english.contains('—'), isFalse);
      expect(english.contains('""'), isFalse);
    });

    test('an uppercase entry is unreachable', () {
      // Lookup keys are lowercased, so an uppercase entry can never be hit.
      // It is dropped at compile time rather than silently kept.
      final words = DanglingWords(const <String>['THE', 'of']);
      expect(words.contains('THE'), isFalse);
      expect(words.contains('the'), isFalse);
      expect(words.contains('of'), isTrue);
      expect(words.contains('OF'), isTrue);
    });

    test('falls back to toLowerCase for scripts it cannot fold inline', () {
      // Fullwidth letters are outside the inline fold's fast path, so these
      // go through the general String.toLowerCase.
      final words = DanglingWords(const <String>['ｔｈｅ']);
      expect(words.contains('ｔｈｅ'), isTrue);
      expect(words.contains('ＴＨＥ'), isTrue);
      expect(words.contains('ｔｈｅ,'), isFalse);
      expect(words.contains('(ｔｈｅ'), isTrue);
      expect(words.contains('ｏｆ'), isFalse);
    });

    test('a foldable token is not confused with an unfoldable list', () {
      final words = DanglingWords(const <String>['ｔｈｅ']);
      expect(words.contains('the'), isFalse);
      expect(words.contains('of'), isFalse);
    });
  });

  group('DanglingWords.matches', () {
    final words = DanglingWords(const <String>['the', 'in']);

    test('probes a range of a larger string without substrings', () {
      const text = 'word in text';
      expect(words.matches(text, 5, 7), isTrue); // 'in'
      expect(words.matches(text, 0, 4), isFalse); // 'word'
      expect(words.matches(text, 8, 12), isFalse); // 'text'
    });

    test('an empty range never matches', () {
      expect(words.matches('in', 0, 0), isFalse);
      expect(words.matches('in', 2, 2), isFalse);
    });

    test('handles a table collision without a false positive', () {
      // Many entries in one small table exercise the probe chain; every hit
      // is confirmed by comparing code units, so none of these may leak.
      final many = DanglingWords(
        List<String>.generate(64, (int i) => 'w$i'),
      );
      for (var i = 0; i < 64; i++) {
        expect(many.contains('w$i'), isTrue, reason: 'w$i');
      }
      expect(many.contains('w64'), isFalse);
      expect(many.contains('w'), isFalse);
      expect(many.contains('x1'), isFalse);
    });
  });
}
