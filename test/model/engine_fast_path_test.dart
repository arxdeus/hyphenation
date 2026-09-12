import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_hyphen/src/buffer/match_scratch.dart';
import 'package:flutter_hyphen/src/encoder/word_encoder.dart';
import 'package:flutter_hyphen/src/model/dictionary_charset.dart';
import 'package:flutter_hyphen/src/model/edge_limits.dart';
import 'package:flutter_hyphen/src/model/hyphenation_dictionary.dart';
import 'package:flutter_hyphen/src/processor/break_marker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ASCII reserves actual bytes and non-ASCII preserves its copied prefix',
    () {
      final encoder = WordEncoder();
      final initial = encoder.bytes;
      encoder.encode('a' * 60, DictionaryCharset.utf8);
      expect(identical(encoder.bytes, initial), isTrue);
      for (final word in [
        '${'a' * 60}é',
        '${'a' * 150}😀',
        '${'a' * 700}\uD800',
        'short',
        '',
        'é${'b' * 600}',
      ]) {
        encoder.encode(word, DictionaryCharset.utf8);
        expect(encoder.bytes.sublist(0, encoder.byteLength), utf8.encode(word));
        expect(encoder.characterCount, word.runes.length);
      }
    },
  );

  test(
    'scratch does not allocate recursive output until there is a boundary',
    () {
      final scratch = MatchScratch()..prepare(50, rewrites: false);
      expect(scratch.padded.length, 64);
      expect(scratch.innerMarks, isEmpty);
      final inner = scratch.innerMarksFor(50);
      expect(inner.length, 64);
      scratch.prepare(200, rewrites: false);
      expect(identical(scratch.innerMarks, inner), isTrue);
      expect(scratch.innerMarksFor(200).length, greaterThanOrEqualTo(203));
    },
  );

  test('limit merges reuse dominating immutable values', () {
    const a = EdgeLimits(left: 2, right: 3);
    const b = EdgeLimits(left: 4, right: 5, compoundLeft: 2);
    expect(identical(a.raisedTo(b), b), isTrue);
    expect(identical(b.raisedTo(a), b), isTrue);
    final mixed = b.raisedTo(const EdgeLimits(compoundRight: 8));
    expect(
      [mixed.left, mixed.right, mixed.compoundLeft, mixed.compoundRight],
      [4, 5, 2, 8],
    );
  });

  test('cached overrides retain null versus explicit zero suppression', () {
    final dictionary = HyphenationDictionary.parse(
      utf8.encode('UTF-8\nNOHYPHEN b\nNEXTLEVEL\na1b1c1d\n'),
    );
    for (var i = 0; i < 5; i++) {
      dictionary.markWord('abcd', leftMin: 0);
      expect(dictionary.marks[1], 0);
      dictionary.markWord('abcd');
      expect(dictionary.marks[1], 48);
      dictionary.markWord('abcd', rightMin: 0);
      expect(dictionary.marks[1], 0);
    }
  });

  test('ASCII compaction bypass keeps complete raw marks identical', () {
    for (final source in [
      'UTF-8\na1b\nb1c\nc1d\n',
      'UTF-8\nNOHYPHEN b\na1b\nb1c\n',
      'UTF-8\na1b/x=y,1,2\nb1c\n',
      'UTF-8\na1b\nNEXTLEVEL\nb1c\nc1d\n',
    ]) {
      final dictionary = HyphenationDictionary.parse(utf8.encode(source));
      final marker = BreakMarker();
      for (final text in ['', 'a', 'abcd', 'abcd-abcd', '12abcd34', 'abc']) {
        final word = Uint8List.fromList(utf8.encode(text));
        final reference = Uint8List(word.length + 8);
        expect(
          marker.markWord(dictionary.patterns, word, 0, word.length, reference),
          isTrue,
        );
        dictionary.markWord(text);
        expect(
          dictionary.marks.sublist(0, reference.length),
          reference,
          reason: '$source / $text',
        );
      }
    }
  });

  test(
    'pooled rewrite track agrees with fresh instances after word size changes',
    () {
      for (final source in [
        'UTF-8\nd3d1ze/dz=,1,1\na1b/x=y,1,2\n',
        'UTF-8\na1b\nNEXTLEVEL\nd3d1ze/dz=,1,1\n',
        'UTF-8\nd3d1ze/dz=,1,1\nNEXTLEVEL\na1b\n',
      ]) {
        final bytes = utf8.encode(source);
        final reused = HyphenationDictionary.parse(bytes);
        for (final word in [
          'addze' * 30,
          'abcd',
          'addze',
          'ab-addze',
          'äaddzeé',
          'ab',
          '',
          'addze-addze',
          'a',
          'addze',
        ]) {
          final fresh = HyphenationDictionary.parse(bytes);
          for (final minimum in [null, 0, 1, 5, 2]) {
            expect(
              reused.markWord(word, leftMin: minimum),
              fresh.markWord(word, leftMin: minimum),
            );
            expect(
              reused.marks.sublist(0, reused.markedByteLength + 8),
              fresh.marks.sublist(0, fresh.markedByteLength + 8),
              reason: '$source / $word / $minimum',
            );
          }
        }
      }
    },
  );
}
