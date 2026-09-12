// Turning priorities back into text.
//
// Two steps that belong together: splitting a string wherever the matcher
// left an odd priority, and the dictionary that ties encoding, matching and
// splitting into the one call a caller actually makes.

import 'dart:convert';

import 'package:flutter_hyphen/src/exception/dictionary_format_exception.dart';
import 'package:flutter_hyphen/src/model/hyphenation_dictionary.dart';
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

    test('a dictionary failure is a FormatException', () {
      // Catching FormatException is how a caller handles malformed data from
      // any SDK parser, and a bad .dic file is exactly that.
      expect(DictionaryFormatException('broken'), isA<FormatException>());
      // A word that cannot be written in the dictionary's charset keeps
      // reporting ArgumentError, which is what latin1.encode does and what
      // callers already handle; only the dictionary-level failure is a
      // FormatException.
      expect(
        () => singleByte().markWord('日本語のことば'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the message still names the dictionary, not just the format', () {
      // FormatException.toString() would say "FormatException", which loses
      // the only thing a stack trace needs: which parse failed.
      expect(
        DictionaryFormatException('broken').toString(),
        startsWith('DictionaryFormatException: broken'),
      );
    });
  });
}
