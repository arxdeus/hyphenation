// Finding the breaks in a word, one behaviour at a time.
//
// Every expected value here was measured against the reference
// implementation rather than reasoned out, and several were confirmed by
// mutation — the comment says which, because a test that still passes when
// the code it covers is deleted is worse than no test at all.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_hyphen/src/buffer/rewrite_track.dart';
import 'package:flutter_hyphen/src/builder/pattern_level_builder.dart';
import 'package:flutter_hyphen/src/model/edge_limits.dart';
import 'package:flutter_hyphen/src/model/pattern_set.dart';
import 'package:flutter_hyphen/src/parser/dictionary_parser.dart';
import 'package:flutter_hyphen/src/processor/break_mark_processor.dart';
import 'package:flutter_hyphen/src/processor/break_marker.dart';
import 'package:flutter_hyphen/src/util/byte_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// A single level built from pattern lines, with nothing below it.
PatternSet level(List<String> lines, {bool isUtf8 = true}) {
  final draft = LevelDraft(isUtf8: isUtf8);
  for (final line in lines) {
    draft.readLine(Uint8List.fromList(utf8.encode('$line\n')));
  }
  return draft.build(isUtf8 ? 'UTF-8' : 'ISO8859-1', inner: null);
}

/// The level a whole dictionary parses into, and the level below it.
PatternSet parse(String body) => DictionaryParser(utf8.encode(body)).parse();

Uint8List buffer(int length, [int fill = 0]) =>
    Uint8List(length)..fillRange(0, length, fill);

/// The priorities [word] gets from [lines] alone, with no minimum distances
/// and no level below.
List<int> priorities(List<String> lines, String word, {bool isUtf8 = true}) {
  final bytes = utf8.encode(word);
  final marks = buffer(bytes.length + 8);
  BreakMarker().markPatterns(
    level(lines, isUtf8: isUtf8),
    bytes,
    0,
    bytes.length,
    marks,
  );
  return marks.sublist(0, bytes.length);
}

void main() {
  group('applying patterns', () {
    test('a pattern marks the position its digit sits at', () {
      // te1st: a break after "te" in "test".
      expect(priorities(['te1st'], 'test'), [0x30, 0x31, 0x30, 0x30]);
    });

    test('a word no pattern touches comes back blank', () {
      expect(priorities(['te1st'], 'xyz'), [0x30, 0x30, 0x30]);
    });

    test('an empty word is not an error', () {
      expect(priorities(['te1st'], ''), isEmpty);
    });

    test('the highest priority at a position wins', () {
      expect(priorities(['a1b', 'a3b'], 'ab')[0], 0x33);
    });

    test('a higher priority written first is not overwritten by a lower '
        'one from a pattern that matches later', () {
      // "abc" reaches its node one letter before "bcd" reaches its own, so
      // the 3 lands first and the 1 must not downgrade it. Confirmed by
      // mutation: dropping the keep-the-maximum test leaves every other
      // case in this group green and flips index 2 from 0x33 to 0x31.
      expect(priorities(['abc3', 'bc1d'], 'abcd'), [
        0x30,
        0x30,
        0x33,
        0x30,
      ]);
    });

    test('overlapping patterns all contribute', () {
      final marks = priorities(['a1b', 'b1c'], 'abc');
      expect(marks[0], 0x31);
      expect(marks[1], 0x31);
    });

    test('a leading dot anchors a pattern to the start of the word', () {
      expect(priorities(['.a1b'], 'ab')[0], 0x31);
      expect(priorities(['.a1b'], 'xab')[1], 0x30);
    });

    test('a digit inside the word reads as a word boundary', () {
      // Digits become dots before matching, so a dot-anchored pattern fires
      // after one.
      expect(priorities(['.a1b'], '5ab')[1], 0x31);
    });

    test('a pattern that ends on the last letter is dropped, not folded '
        'onto it', () {
      // "ab1" with no closing dot writes its mark against the padded copy's
      // trailing position, which is not a position in the word. Confirmed
      // by mutation: widening the shift by one leaves every other case here
      // green and flips the last mark from 0x30 to 0x31.
      expect(priorities(['ab1'], 'xab'), [0x30, 0x30, 0x30]);
    });

    test('a pattern installed on the root itself is never applied', () {
      // A line of nothing but a digit installs its priority on the root,
      // which stands for the empty prefix. The matcher only ever reaches
      // the root by falling off the trie, and it must not treat that as a
      // match. Confirmed by mutation: dropping the restart guard leaves
      // every other case green and plants a stray 5 at index 0.
      expect(priorities(['5', 'te1st'], 'xtestx'), [
        0x30,
        0x30,
        0x31,
        0x30,
        0x30,
        0x30,
      ]);
    });
  });

  group('ligatures', () {
    test('two-letter ligatures are worth one character, three-letter ones '
        'two', () {
      // The reference build does not enable the long-ligature variant, so
      // ff/fi/fl add nothing and ffi/ffl add one.
      expect(ligatureExtraCharacters(0x80), 0); // ff
      expect(ligatureExtraCharacters(0x81), 0); // fi
      expect(ligatureExtraCharacters(0x82), 0); // fl
      expect(ligatureExtraCharacters(0x83), 1); // ffi
      expect(ligatureExtraCharacters(0x84), 1); // ffl
      expect(ligatureExtraCharacters(0x85), 0); // long st
      expect(ligatureExtraCharacters(0x86), 0); // st
      expect(ligatureExtraCharacters(0x00), 0);
      expect(ligatureExtraCharacters(0xFF), 0);
    });
  });

  group('counting characters', () {
    Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

    test('one byte is one character without UTF-8', () {
      expect(countCharacters(bytes('abc'), 0, 3, 3, utf8: false), 3);
    });

    test('continuation bytes do not count', () {
      final word = bytes('äöü'); // 6 bytes, 3 characters
      expect(countCharacters(word, 0, 6, 6, utf8: true), 3);
    });

    test('a two-letter ligature counts as one', () {
      final word = bytes('ﬀ'); // 3 bytes
      expect(countCharacters(word, 0, 3, 3, utf8: true), 1);
    });

    test('a three-letter ligature counts as two', () {
      final word = bytes('ﬃ'); // 3 bytes
      expect(countCharacters(word, 0, 3, 3, utf8: true), 2);
    });

    test('counting stops at a NUL', () {
      final word = Uint8List.fromList(<int>[0x61, 0x00, 0x62]);
      expect(countCharacters(word, 0, 3, 3, utf8: false), 1);
    });
  });

  group('the left minimum', () {
    test('blanks every mark within the minimum of the start', () {
      final word = utf8.encode('abcdef');
      final marks = buffer(word.length + 8, 0x31); // everything a break
      BreakMarkProcessor.trimLeftEdge(
        level(const <String>[], isUtf8: false),
        word,
        0,
        word.length,
        marks,
        null,
        3,
      );
      // The whole array, not just the boundary, so a pass that blanks one
      // position too many or too few is caught.
      expect(marks.sublist(0, word.length), [
        0x30,
        0x30,
        0x31,
        0x31,
        0x31,
        0x31,
      ]);
    });

    test('leading digits push the boundary outward', () {
      final word = utf8.encode('12abcdef');
      final marks = buffer(word.length + 8, 0x31);
      BreakMarkProcessor.trimLeftEdge(
        level(const <String>[], isUtf8: false),
        word,
        0,
        word.length,
        marks,
        null,
        3,
      );
      // Four positions blanked, not three: each leading digit costs the
      // count one before the walk starts.
      expect(marks.sublist(0, word.length), [
        0x30,
        0x30,
        0x30,
        0x30,
        0x31,
        0x31,
        0x31,
        0x31,
      ]);
    });

    test('does not run off the end of a short word', () {
      final word = utf8.encode('ab');
      final marks = buffer(word.length + 8, 0x31);
      BreakMarkProcessor.trimLeftEdge(
        level(const <String>[], isUtf8: false),
        word,
        0,
        word.length,
        marks,
        null,
        10,
      );
      expect(marks.sublist(0, word.length), [0x30, 0x30]);
    });

    test('a long enough rewrite keeps its break', () {
      // Differentially verified: word "abcdef", minimum 3, a rewrite at
      // index 1 introducing "xxx=y" from one character back. The break at
      // index 1 — blanked in the case above — survives, because the text
      // the rewrite introduces is itself long enough.
      final patterns = level(['a1b/xxx=y,1,1'], isUtf8: false);
      final node = patterns.automaton.nodeForPrefix('ab'.codeUnits);
      final word = utf8.encode('abcdef');
      final marks = buffer(word.length + 8, 0x31);
      final track = RewriteTrack(word.length);
      track.reference[1] = patterns.automaton.replacementRef[node];
      track.shift[1] = 1;

      BreakMarkProcessor.trimLeftEdge(
        patterns,
        word,
        0,
        word.length,
        marks,
        track,
        3,
      );

      expect(marks.sublist(0, word.length), [
        0x30,
        0x31,
        0x31,
        0x31,
        0x31,
        0x31,
      ]);
      expect(
        track.reference[1],
        greaterThanOrEqualTo(0),
        reason: 'the rewrite is long enough to survive the minimum',
      );
    });
  });

  group('the right minimum', () {
    test('blanks every mark within the minimum of the end', () {
      final word = utf8.encode('abcdef');
      final marks = buffer(word.length + 8, 0x31);
      BreakMarkProcessor.trimRightEdge(
        level(const <String>[], isUtf8: false),
        word,
        0,
        word.length,
        word.length,
        marks,
        null,
        3,
      );
      expect(marks.sublist(0, word.length), [
        0x31,
        0x31,
        0x31,
        0x30,
        0x30,
        0x30,
      ]);
    });

    test('does not run off the start of a short word', () {
      final word = utf8.encode('ab');
      final marks = buffer(word.length + 8, 0x31);
      BreakMarkProcessor.trimRightEdge(
        level(const <String>[], isUtf8: false),
        word,
        0,
        word.length,
        word.length,
        marks,
        null,
        10,
      );
      // Index 0 is never reached — the walk stops above it — so it keeps
      // the mark it came in with.
      expect(marks.sublist(0, word.length), [0x31, 0x30]);
    });

    test('counts characters, not bytes', () {
      final word = utf8.encode('aäöüb'); // 1 + 2 + 2 + 2 + 1 bytes
      final marks = buffer(word.length + 8, 0x31);
      BreakMarkProcessor.trimRightEdge(
        level(const <String>[]),
        word,
        0,
        word.length,
        word.length,
        marks,
        null,
        2,
      );
      // The last two characters are blanked, which is the last three bytes.
      expect(marks.sublist(0, word.length), [
        0x31,
        0x31,
        0x31,
        0x31,
        0x31,
        0x30,
        0x30,
        0x30,
      ]);
    });

    test('a long enough rewrite keeps its break', () {
      // Differentially verified: word "abcdef", minimum 3, a rewrite at
      // index 4 introducing "y=xxx". Index 4's blank — present without the
      // rewrite — is suppressed.
      final patterns = level(['e1f/y=xxx,1,1'], isUtf8: false);
      final node = patterns.automaton.nodeForPrefix('ef'.codeUnits);
      final word = utf8.encode('abcdef');
      final marks = buffer(word.length + 8, 0x31);
      final track = RewriteTrack(word.length);
      track.reference[4] = patterns.automaton.replacementRef[node];

      BreakMarkProcessor.trimRightEdge(
        patterns,
        word,
        0,
        word.length,
        word.length,
        marks,
        track,
        3,
      );

      expect(marks.sublist(0, word.length), [
        0x31,
        0x31,
        0x31,
        0x30,
        0x31,
        0x30,
      ]);
      expect(track.reference[4], greaterThanOrEqualTo(0));
    });
  });

  group('squeezing bytes down to characters', () {
    test('a word that starts inside a character is rejected', () {
      final marks = buffer(8, 0x30);
      expect(
        BreakMarkProcessor.compactToCharacters(
          Uint8List.fromList(<int>[0x80, 0x61]),
          0,
          2,
          2,
          marks,
          null,
        ),
        isFalse,
      );
    });

    test('marks move from byte positions to character positions', () {
      final word = utf8.encode('äb'); // 3 bytes, 2 characters
      final marks = Uint8List.fromList(<int>[
        0x30,
        0x31,
        0x32,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(
        BreakMarkProcessor.compactToCharacters(word, 0, 3, 3, marks, null),
        isTrue,
      );
      // The mark of ä's second byte collapses onto ä itself.
      expect(marks[0], 0x31);
      expect(marks[1], 0x32);
    });
  });

  group('compound levels', () {
    test('a break found by the outer level splits the word for the inner '
        'one', () {
      // The outer level's b1c splits "abcd" into "abc" and "d"; each piece
      // goes back through the outer level and, having no boundary of its
      // own, falls through to the inner level's a1b and c1d. Differentially
      // verified: breaks after a, b and c, and none after the last
      // character.
      final patterns = parse('UTF-8\nb1c\nNEXTLEVEL\na1b\nc1d\n');
      final word = utf8.encode('abcd');
      final marks = buffer(word.length + 8);
      BreakMarker().markPatterns(
        patterns,
        word,
        0,
        word.length,
        marks,
        track: RewriteTrack(word.length),
        compoundLeft: 1,
        compoundRight: 1,
      );
      expect(marks.sublist(0, word.length), [0x31, 0x31, 0x31, 0x30]);
    });

    test('a rewrite at a compound boundary changes what the level below '
        'sees', () {
      // The gap this closes: splicing the rewrite into the piece handed
      // down is byte-identical to not doing it on most dictionaries,
      // because the piece rarely feeds a pattern that cares. This one is
      // built so it does — "1dz" only matches the *rewritten* spelling.
      //
      // Differentially verified on "xxaddze": [48, 48, 49, 51, 49, 48, 48].
      // Confirmed by mutation: with the splice turned into a no-op, index 2
      // flips from 49 to 48, because the piece handed down reads "xxad"
      // instead of "xxadz" and "1dz" never fires.
      final patterns = parse('UTF-8\nd3d1ze/dz=,1,1\n1dz\nNEXTLEVEL\na1b\n');
      final word = utf8.encode('xxaddze');
      final marks = buffer(word.length + 8);
      BreakMarker().markPatterns(
        patterns,
        word,
        0,
        word.length,
        marks,
        track: RewriteTrack(word.length),
        compoundLeft: 1,
        compoundRight: 1,
      );
      expect(marks.sublist(0, word.length), [
        0x30,
        0x30,
        0x31,
        0x33,
        0x31,
        0x30,
        0x30,
      ]);
    });

    test('the recursion terminates on a one-character word', () {
      final patterns = parse('UTF-8\nte1st\n');
      final word = utf8.encode('a');
      final marks = buffer(word.length + 8);
      expect(
        () => BreakMarker().markPatterns(
          patterns,
          word,
          0,
          word.length,
          marks,
          track: RewriteTrack(1),
          compoundLeft: 2,
          compoundRight: 2,
        ),
        returnsNormally,
      );
    });

    test('the recursion terminates on an empty word', () {
      final patterns = parse('UTF-8\nte1st\n');
      final marks = buffer(8);
      expect(
        () => BreakMarker().markPatterns(
          patterns,
          Uint8List(0),
          0,
          0,
          marks,
          track: RewriteTrack(1),
          compoundLeft: 2,
          compoundRight: 2,
        ),
        returnsNormally,
      );
    });
  });

  group('rewrites', () {
    test('a rewrite pattern fills the track', () {
      // d3d1ze/dz=,1,1 is a real non-standard pattern, splitting a doubled
      // digraph. Differentially verified on "addze": the track holds "dz="
      // at index 1 with a shift and cut of one, and nothing anywhere else.
      final patterns = level(['d3d1ze/dz=,1,1']);
      final word = utf8.encode('addze');
      final marks = buffer(word.length + 8);
      final track = RewriteTrack(word.length);

      BreakMarker().markPatterns(
        patterns,
        word,
        0,
        word.length,
        marks,
        track: track,
      );

      expect(marks.sublist(0, word.length), [
        0x30,
        0x33,
        0x31,
        0x30,
        0x30,
      ]);
      final node = patterns.automaton.nodeForPrefix('ddze'.codeUnits);
      expect(track.reference.toList(), [
        -1,
        patterns.automaton.replacementRef[node],
        -1,
        -1,
        -1,
      ]);
      expect(track.shift.toList(), [0, 1, 0, 0, 0]);
      expect(track.cut.toList(), [0, 1, 0, 0, 0]);
    });

    test('a rewrite that would be recorded before the start of the word is '
        'dropped', () {
      // ".1xy/z=,1,1" on "xy" produces a recording position of -1. In C
      // that is a write off the front of the heap block — undefined
      // behaviour rather than behaviour to reproduce — and it lands where
      // nothing reads, so skipping it is the only option that neither
      // throws nor diverges. Differentially verified: marks [48, 48] and an
      // untouched track.
      final patterns = level(['.1xy/z=,1,1']);
      final word = utf8.encode('xy');
      final marks = buffer(word.length + 8);
      final track = RewriteTrack(word.length);

      BreakMarker().markPatterns(
        patterns,
        word,
        0,
        word.length,
        marks,
        track: track,
      );

      expect(marks.sublist(0, word.length), [0x30, 0x30]);
      expect(track.reference.toList(), [-1, -1]);
      expect(track.shift.toList(), [0, 0]);
      expect(track.cut.toList(), [0, 0]);
    });
  });

  group('a buffer longer than the word', () {
    test('a suppression cannot match across the end of the word', () {
      // The matcher works in a buffer it reuses, so the bytes after a word
      // are the previous word's. Suppressions are scanned within the word's
      // length for exactly that reason. Measured: the break at index 1
      // survives here and is wrongly lost if the scan is left unbounded.
      final patterns = parse(
        'UTF-8\nNOHYPHEN cde\na1b\nb1c\nc1d\nd1e\ne1f\nNEXTLEVEL\na1b\n',
      );
      final padded = Uint8List(16)..setAll(0, utf8.encode('abcde'));
      final marks = Uint8List(24);
      final marker = BreakMarker();

      expect(marker.markWord(patterns, padded, 0, 4, marks), isTrue);
      expect(marks.sublist(0, 4), [48, 49, 48, 48]);
    });
  });

  group('the two ways of blanking a suppressed position', () {
    // The dictionary's own minimums blank with an ASCII zero and raised
    // ones blank with a NUL. Both read as "no break", so nothing downstream
    // can tell them apart, but the raw priorities are observable and the
    // reference really does differ here.
    const body =
        'UTF-8\nNOHYPHEN bc\na1b\nb1c\nc1d\nNEXTLEVEL\na1b\nb1c\nc1d\n';

    test("the dictionary's own minimums blank with an ASCII zero", () {
      final patterns = parse(body);
      final word = utf8.encode('abcd');
      final marks = buffer(word.length + 8);
      expect(
        BreakMarker().markWord(patterns, word, 0, word.length, marks),
        isTrue,
      );
      expect(marks.sublist(0, word.length), [48, 49, 48, 48]);
      expect(
        marks.sublist(0, word.length),
        isNot(contains(0)),
        reason: 'never a NUL on this path',
      );
    });

    test('raised minimums blank with a NUL', () {
      final patterns = parse(body);
      final word = utf8.encode('abcd');
      final marks = buffer(word.length + 8);
      expect(
        BreakMarker().markWord(
          patterns,
          word,
          0,
          word.length,
          marks,
          raise: EdgeLimits.none,
        ),
        isTrue,
      );
      expect(marks.sublist(0, word.length), [0, 49, 0, 48]);
    });
  });

  test("a raised minimum can never lower the dictionary's own", () {
    final patterns = parse(
      'UTF-8\nLEFTHYPHENMIN 5\na1b\nb1c\nc1d\nd1e\ne1f\n',
    );
    final word = utf8.encode('abcdef');
    final marks = buffer(word.length + 8);
    BreakMarker().markWord(
      patterns,
      word,
      0,
      word.length,
      marks,
      raise: const EdgeLimits(
        left: 1,
        right: 1,
        compoundLeft: 1,
        compoundRight: 1,
      ),
    );
    expect(marks[0] & 1, 0, reason: "the dictionary's 5 wins over 1");
    expect(marks[1] & 1, 0);
  });
}
