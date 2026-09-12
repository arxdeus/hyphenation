// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'dart:typed_data';

import 'package:flutter_hyphen/src/encoder/word_encoder.dart';
import 'package:flutter_hyphen/src/exception/dictionary_format_exception.dart';
import 'package:flutter_hyphen/src/model/dictionary_charset.dart';
import 'package:flutter_hyphen/src/model/edge_limits.dart';
import 'package:flutter_hyphen/src/model/pattern_set.dart';
import 'package:flutter_hyphen/src/parser/dictionary_parser.dart';
import 'package:flutter_hyphen/src/processor/break_mark_splitter.dart';
import 'package:flutter_hyphen/src/processor/break_marker.dart';

/// A parsed hyphenation dictionary: the thing that knows where a word may be
/// broken.
///
/// Reads the `hyph_*.dic` files the the legacy engine project and its
/// derivatives distribute, which is the same format `hyphen.tex` patterns are
/// compiled into. Pure Dart, no plugin, no platform channel.
///
/// ```dart
/// final dictionary = HyphenationDictionary.parse(bytes);
/// dictionary.split('hyphenation'); // [hy, phen, ation]
/// ```
///
/// ### Cost
/// Parsing is the expensive part and happens once. Marking a word after that
/// allocates nothing at all, for any dictionary that does not rewrite words
/// as it breaks them — any `hyph_*.dic` without a `/` pattern, `hyph_en_US.dic`
/// included. That is what makes it reasonable to call [markWord]
/// for every word of every paragraph.
///
/// ### Sharing
/// One instance is meant to be shared. It owns the buffers every call runs
/// in, which is exactly why it must not be used from two places at once:
/// hyphenation is synchronous, so that means one instance per isolate,
/// never one shared across them.
class HyphenationDictionary {
  HyphenationDictionary._(this._patterns, this._charset);

  /// Parses the bytes of a `hyph_*.dic` file.
  ///
  /// Throws [DictionaryFormatException] if the bytes cannot be read at all.
  /// An empty or contentless file is not an error: it parses into a
  /// dictionary that finds no breaks, which keeps a missing asset from
  /// bringing down a widget tree at startup.
  factory HyphenationDictionary.parse(List<int> bytes) {
    final PatternSet patterns;
    try {
      patterns = DictionaryParser(bytes).parse();
    } catch (error) {
      throw DictionaryFormatException('could not read the dictionary: $error');
    }
    return HyphenationDictionary._(
      patterns,
      patterns.charsetIsUtf8
          ? DictionaryCharset.utf8
          : DictionaryCharset.latin1,
    );
  }

  final PatternSet _patterns;
  final DictionaryCharset _charset;

  final WordEncoder _encoder = WordEncoder();
  final BreakMarker _marker = BreakMarker();

  /// One priority per character of the word, plus the slack the matcher
  /// works in.
  Uint8List _marks = Uint8List(72);

  int _markedBytes = 0;

  /// The levels this dictionary was parsed into. Interesting for inspecting
  /// a dictionary — how many patterns it holds, what minimums it states —
  /// and for nothing else.
  PatternSet get patterns => _patterns;

  /// The charset name the dictionary's first line declared.
  String get charsetName => _patterns.charsetName;

  /// The priorities the last [markWord] produced.
  ///
  /// Entry `i` belongs to character `i` of that word, and an odd entry means
  /// the word may be broken after it. Valid for [markWord]'s return value
  /// entries, and only until the next call on this instance.
  Uint8List get marks => _marks;

  /// How many bytes of [marks] the matcher wrote for the last word.
  ///
  /// The same as [markWord]'s return value except for a UTF-8 dictionary
  /// and a word with multi-byte characters, where the matcher works in bytes
  /// and squeezes its result down to characters afterwards, leaving the tail
  /// of the buffer holding whatever it held before the squeeze. Exposed
  /// because that whole window, stale tail included, is what the reference
  /// implementation hands back, and the golden corpus pins it.
  int get markedByteLength => _markedBytes;

  /// Marks every break opportunity in [word] and returns how many characters
  /// it has.
  ///
  /// The answer is left in [marks] rather than returned, which is what makes
  /// this allocation-free. [leftMin], [rightMin], [compoundLeftMin] and
  /// [compoundRightMin] raise the minimum distances the dictionary states;
  /// they can never lower them.
  ///
  /// Throws [ArgumentError] if [word] cannot be written in the dictionary's
  /// charset.
  int markWord(
    String word, {
    int? leftMin,
    int? rightMin,
    int? compoundLeftMin,
    int? compoundRightMin,
  }) {
    _encoder.encode(word, _charset);
    final length = _encoder.byteLength;
    if (_marks.length < length + 8) {
      _marks = Uint8List((length + 8) * 2);
    }
    final marks = _marks..fillRange(0, length + 8, 0);

    final raise =
        (leftMin == null &&
            rightMin == null &&
            compoundLeftMin == null &&
            compoundRightMin == null)
        ? null
        : EdgeLimits(
            left: leftMin ?? 0,
            right: rightMin ?? 0,
            compoundLeft: compoundLeftMin ?? 0,
            compoundRight: compoundRightMin ?? 0,
          );

    final ok = _marker.markWord(
      _patterns,
      _encoder.bytes,
      0,
      length,
      marks,
      raise: raise,
    );
    if (!ok) {
      throw DictionaryFormatException(
        "the word could not be read in the dictionary's charset",
      );
    }

    _markedBytes = length;
    return _encoder.characterCount;
  }

  /// Splits [word] at every break opportunity.
  ///
  /// ```dart
  /// dictionary.split('hyphenation'); // [hy, phen, ation]
  /// ```
  ///
  /// Allocates, unlike [markWord], and is here for callers that want the
  /// pieces rather than the positions.
  List<String> split(
    String word, {
    int? leftMin,
    int? rightMin,
    int? compoundLeftMin,
    int? compoundRightMin,
  }) {
    if (word.isEmpty) {
      return const <String>[];
    }
    final characters = markWord(
      word,
      leftMin: leftMin,
      rightMin: rightMin,
      compoundLeftMin: compoundLeftMin,
      compoundRightMin: compoundRightMin,
    );
    return splitOnOddMarks(word, _marks, characters);
  }
}
