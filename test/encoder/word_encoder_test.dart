// Words into the bytes a dictionary's patterns are written in.
//
// The encoder exists to avoid allocating a list per word, so most of what
// matters is that it still agrees with `dart:convert` exactly — including
// where `dart:convert` does something surprising.

import 'dart:convert';

import 'package:flutter_hyphen/src/encoder/word_encoder.dart';
import 'package:flutter_hyphen/src/exception/dictionary_format_exception.dart';
import 'package:flutter_hyphen/src/model/dictionary_charset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DictionaryCharset', () {
    test('only the exact name UTF-8 means UTF-8', () {
      expect(DictionaryCharset.fromHeader('UTF-8'), DictionaryCharset.utf8);
      expect(
        DictionaryCharset.fromHeader('ISO8859-1'),
        DictionaryCharset.latin1,
      );
      expect(DictionaryCharset.fromHeader('utf-8'), DictionaryCharset.latin1);
      expect(DictionaryCharset.fromHeader(''), DictionaryCharset.latin1);
    });
  });

  group('WordEncoder', () {
    late WordEncoder encoder;

    setUp(() => encoder = WordEncoder());

    List<int> encoded(String text, DictionaryCharset charset) {
      encoder.encode(text, charset);
      return encoder.bytes.sublist(0, encoder.byteLength);
    }

    test('agrees with dart:convert on ASCII', () {
      expect(
        encoded('hyphenation', DictionaryCharset.utf8),
        utf8.encode('hyphenation'),
      );
      expect(
        encoded('hyphenation', DictionaryCharset.latin1),
        latin1.encode('hyphenation'),
      );
    });

    test('agrees with dart:convert on two- and three-byte characters', () {
      for (final word in <String>['±§¶', '→↑↓↔', '—…•']) {
        expect(
          encoded(word, DictionaryCharset.utf8),
          utf8.encode(word),
          reason: word,
        );
      }
    });

    test('agrees with dart:convert on characters outside the BMP', () {
      const word = 'a\u{1F600}b';
      expect(encoded(word, DictionaryCharset.utf8), utf8.encode(word));
    });

    test('replaces an unpaired surrogate exactly as dart:convert does', () {
      // Matching this matters: a word carrying one has to hyphenate the same
      // way here as it did through utf8.encode.
      for (final word in <String>['e\uD800f', 'g\uDC00h', '\uD800']) {
        expect(
          encoded(word, DictionaryCharset.utf8),
          utf8.encode(word),
          reason: word.codeUnits.toString(),
        );
      }
    });

    test('counts characters, not code units and not bytes', () {
      encoder.encode('±§¶', DictionaryCharset.utf8);
      expect(encoder.byteLength, 6);
      expect(encoder.characterCount, 3);

      encoder.encode('a\u{1F600}b', DictionaryCharset.utf8);
      expect(encoder.byteLength, 6);
      expect(encoder.characterCount, 3, reason: 'the emoji is one character');
    });

    test('rejects what cannot be written in one byte per character', () {
      expect(
        () => encoder.encode('→↑↓', DictionaryCharset.latin1),
        throwsArgumentError,
      );
    });

    test('the buffer survives a word longer than it is', () {
      final long = '±' * 500;
      expect(encoded(long, DictionaryCharset.utf8), utf8.encode(long));
      expect(
        encoded('ab', DictionaryCharset.utf8),
        utf8.encode('ab'),
        reason: 'and a short word after it reports its own length',
      );
    });

    test('an empty word encodes to nothing', () {
      expect(encoded('', DictionaryCharset.utf8), isEmpty);
      expect(encoder.characterCount, 0);
    });
  });

  test('DictionaryFormatException names its cause', () {
    expect(
      DictionaryFormatException('bad file').toString(),
      contains('bad file'),
    );
  });
}
