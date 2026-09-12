// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'dart:typed_data';

import 'package:flutter_hyphen/src/buffer/replacement_pool.dart';
import 'package:flutter_hyphen/src/builder/pattern_trie.dart';
import 'package:flutter_hyphen/src/model/dictionary_charset.dart';
import 'package:flutter_hyphen/src/model/edge_limits.dart';
import 'package:flutter_hyphen/src/model/pattern_set.dart';

const int _digitZero = 0x30;
const int _digitNine = 0x39;
const int _space = 0x20;
const int _tab = 0x09;
const int _slash = 0x2F;
const int _comma = 0x2C;
const int _dot = 0x2E;
const int _newline = 0x0A;
const int _carriageReturn = 0x0D;
const int _percent = 0x25;

/// The longest line the format allows. Anything past it is discarded, and
/// dictionaries in the wild rely on that to carry documentation in over-long
/// lines.
const int kLineBudget = 100;

/// The smaller budget the charset line is read with, which also behaves
/// differently when it overflows.
const int _charsetBudget = 20;

/// Turns the bytes of a `hyph_*.dic` file into the levels the matcher runs.
///
/// ### The format
/// A charset name on the first line, then one pattern per line. A pattern is
/// letters with priority digits wedged between them (`hy3ph`: breaking after
/// `hy` is worth 3), optionally anchored to a word edge with `.`, optionally
/// followed by `/text,at,cut` to rewrite the word where it matches. Lines
/// starting with `%` are comments; four keywords set the minimum distances
/// and one lists substrings that forbid a break beside them. `NEXTLEVEL`
/// splits the file into an outer level that finds compound boundaries and an
/// inner one that hyphenates what lies between them.
///
/// ### Why it reads like a file rather than a string
/// The reference implementation reads lines into a fixed 100-byte buffer,
/// and several of the format's quirks fall out of that: a line that does not
/// fit is thrown away whole, the charset line is read into a 20-byte buffer
/// whose overflow is *not* thrown away but reparsed as a pattern, and the
/// last byte of the suppression line is dropped whether or not it is a
/// newline. Dictionaries were written against that behaviour, so
/// [_LineScanner] reproduces it instead of splitting on `\n` and hoping.
class DictionaryParser {
  DictionaryParser(List<int> source)
    : _bytes = source is Uint8List ? source : Uint8List.fromList(source);

  final Uint8List _bytes;

  /// Reads the whole file and returns its outermost level.
  ///
  /// Never rejects a file. An empty one yields a dictionary that hyphenates
  /// nothing, which is what the reference implementation does; anything
  /// stricter would turn a harmless asset mistake into a crash at startup.
  PatternSet parse() {
    final scanner = _LineScanner(_bytes);
    final pool = ReplacementPool();
    final charsetName = _readCharsetName(scanner);
    final isUtf8 =
        DictionaryCharset.fromHeader(charsetName) == DictionaryCharset.utf8;

    // The first section of the file is always the one carrying the real
    // patterns. It only becomes the *inner* level if a NEXTLEVEL keyword
    // turns up to give it an outer one.
    final patterns = LevelDraft(isUtf8: isUtf8, replacements: pool);
    final compounds = LevelDraft(isUtf8: isUtf8, replacements: pool);

    if (_readSection(scanner, patterns)) {
      _readSection(scanner, compounds);
      pool.seal();
      return patterns.build(
        charsetName,
        inner: compounds.build(charsetName, inner: null),
      );
    }

    // No NEXTLEVEL: the outer level is invented from the punctuation rules
    // alone. It still answers for the word-level minimums, so it inherits
    // them, and it makes compound minimums up when the file states none.
    _addPunctuationRules(compounds, isUtf8: isUtf8);
    pool.seal();
    return PatternSet(
      automaton: compounds.trie.finish(),
      limits: EdgeLimits(
        left: patterns.left,
        right: patterns.right,
        compoundLeft: patterns.compoundLeft != 0
            ? patterns.compoundLeft
            : (patterns.left != 0 ? patterns.left : 3),
        compoundRight: patterns.compoundRight != 0
            ? patterns.compoundRight
            : (patterns.right != 0 ? patterns.right : 3),
      ),
      suppressions: compounds.suppressions,
      charsetIsUtf8: isUtf8,
      charsetName: charsetName,
      inner: patterns.build(charsetName, inner: null),
    );
  }

  String _readCharsetName(_LineScanner scanner) {
    final line = scanner.next(budget: _charsetBudget, discardOverflow: false);
    if (line == null) {
      return '';
    }
    final end = trimLineEnd(line, 0, line.length);
    var nul = 0;
    while (nul < end && line[nul] != 0) {
      nul++;
    }
    return String.fromCharCodes(line, 0, nul);
  }

  /// Reads lines into [draft]. Returns whether it stopped at a `NEXTLEVEL`
  /// keyword rather than at the end of the file.
  bool _readSection(_LineScanner scanner, LevelDraft draft) {
    while (true) {
      final line = scanner.next();
      if (line == null) {
        return false;
      }
      if (scanner.overflowed) {
        continue;
      }
      if (startsWithKeyword(line, 'NEXTLEVEL')) {
        return true;
      }
      if (line.isNotEmpty && line[0] != _percent) {
        draft.readLine(line);
      }
    }
  }

  /// The outer level a dictionary without `NEXTLEVEL` gets: break at an
  /// existing hyphen or apostrophe, and never leave one stranded.
  void _addPunctuationRules(LevelDraft draft, {required bool isUtf8}) {
    if (!isUtf8) {
      draft.readLine(_ascii("NOHYPHEN ',-\n"));
    } else {
      draft.readLine(
        Uint8List.fromList(<int>[
          ..."NOHYPHEN ',".codeUnits,
          0xE2, 0x80, 0x93, // en dash
          _comma,
          0xE2, 0x80, 0x99, // right single quotation mark
          _comma, 0x2D, _newline,
        ]),
      );
    }
    draft.readLine(_ascii('1-1\n'));
    draft.readLine(_ascii("1'1\n"));
    if (isUtf8) {
      draft.readLine(
        Uint8List.fromList(const <int>[0x31, 0xE2, 0x80, 0x93, 0x31, 0x0A]),
      );
      draft.readLine(
        Uint8List.fromList(const <int>[0x31, 0xE2, 0x80, 0x99, 0x31, 0x0A]),
      );
    }
  }

  static Uint8List _ascii(String text) => Uint8List.fromList(text.codeUnits);
}

/// One level under construction: its trie, its minimums, its suppressions,
/// and the scratch a pattern line is taken apart into.
///
/// Separate from [PatternSet] on purpose. A level is mutable exactly while
/// it is being read and immutable forever after, and the two halves have no
/// fields in common worth sharing: this one holds a trie that grows, that
/// one holds an automaton that is only matched against.
class LevelDraft {
  LevelDraft({required this.isUtf8, ReplacementPool? replacements})
    : trie = PatternTrie(replacements ?? ReplacementPool());

  /// Whether patterns are UTF-8. Only the rewrite offsets care, and they
  /// care a lot: they are stated in characters and used as byte offsets.
  final bool isUtf8;

  final PatternTrie trie;

  int left = 0;
  int right = 0;
  int compoundLeft = 0;
  int compoundRight = 0;
  List<Uint8List> suppressions = const <Uint8List>[];

  /// A pattern's letters and its priority digits, split apart. Both are
  /// bounded by the line budget, so one pair of buffers serves every line of
  /// every dictionary; they grow only for a caller handing [readLine] a line
  /// no reader would have produced.
  Uint8List _letters = Uint8List(kLineBudget + 2);
  Uint8List _priorities = Uint8List(kLineBudget + 2);

  /// Parses one line — a keyword or a pattern.
  ///
  /// [line] includes its newline, as the reader delivers it. This is the
  /// unit the format is actually defined in, which is why it is public:
  /// testing a line at a time says far more than assembling a file around
  /// every case.
  void readLine(Uint8List line) {
    if (startsWithKeyword(line, 'LEFTHYPHENMIN')) {
      left = parseInteger(line, 13, line.length);
      return;
    }
    if (startsWithKeyword(line, 'RIGHTHYPHENMIN')) {
      right = parseInteger(line, 14, line.length);
      return;
    }
    if (startsWithKeyword(line, 'COMPOUNDLEFTHYPHENMIN')) {
      compoundLeft = parseInteger(line, 21, line.length);
      return;
    }
    if (startsWithKeyword(line, 'COMPOUNDRIGHTHYPHENMIN')) {
      compoundRight = parseInteger(line, 22, line.length);
      return;
    }
    if (startsWithKeyword(line, 'NOHYPHEN')) {
      suppressions = _parseSuppressions(line);
      return;
    }
    _readPattern(line);
  }

  /// Freezes this level. The draft is finished with afterwards.
  PatternSet build(String charsetName, {required PatternSet? inner}) =>
      PatternSet(
        automaton: trie.finish(),
        limits: EdgeLimits(
          left: left,
          right: right,
          compoundLeft: compoundLeft,
          compoundRight: compoundRight,
        ),
        suppressions: suppressions,
        charsetIsUtf8: isUtf8,
        charsetName: charsetName,
        inner: inner,
      );

  /// `NOHYPHEN a,b,c` — comma separated, with the last byte of the line
  /// dropped unconditionally.
  ///
  /// That drop strips the newline on a normal line and eats a real character
  /// on a file whose last line has none. It is the reference
  /// implementation's behaviour, so dictionaries depend on it.
  static List<Uint8List> _parseSuppressions(Uint8List line) {
    var start = 8;
    while (start < line.length &&
        (line[start] == _space || line[start] == _tab)) {
      start++;
    }
    final end = start < line.length ? line.length - 1 : line.length;
    if (start >= end) {
      return const <Uint8List>[];
    }
    final entries = <Uint8List>[];
    var from = start;
    // Scanning from start + 1 never splits at offset zero, so a list that
    // opens with a comma keeps it inside the first entry.
    for (var i = start + 1; i < end; i++) {
      if (line[i] == _comma) {
        entries.add(Uint8List.sublistView(line, from, i));
        from = i + 1;
      }
    }
    entries.add(Uint8List.sublistView(line, from, end));
    return entries;
  }

  void _readPattern(Uint8List line) {
    var patternEnd = line.length;
    var rewriteFrom = -1;
    var rewriteTo = -1;
    var rewriteAt = 0;
    var rewriteCut = 0;

    final slash = indexOfByte(line, _slash, 0, line.length);
    if (slash >= 0) {
      final tail = slash + 1;
      patternEnd = slash;
      rewriteFrom = tail;

      final comma = indexOfByte(line, _comma, tail, line.length);
      if (comma >= 0) {
        rewriteTo = comma;
        final second = indexOfByte(line, _comma, comma + 1, line.length);
        if (second >= 0) {
          rewriteAt = parseInteger(line, comma + 1, line.length) - 1;
          rewriteCut = parseInteger(line, second + 1, line.length);
        }
        // One comma and no second leaves both at zero, and the cut falls
        // back to the pattern's own length below. The asymmetry is the
        // reference implementation's and it was measured, not reasoned
        // about: the tempting fix of reusing the no-comma branch here
        // disagrees with it.
      } else {
        rewriteTo = trimLineEnd(line, tail, line.length);
        rewriteCut = patternEnd;
      }
    }

    _reserveScratch(patternEnd + 2);
    final letters = _letters;
    final priorities = _priorities;
    priorities[0] = _digitZero;
    var length = 0;
    for (var i = 0; i < patternEnd && line[i] > _space; i++) {
      final byte = line[i];
      if (byte >= _digitZero && byte <= _digitNine) {
        priorities[length] = byte;
      } else {
        letters[length++] = byte;
        priorities[length] = _digitZero;
      }
    }

    // Leading zero priorities are dropped, so a vector starts at the first
    // position that can produce a break. A pattern with a rewrite keeps its
    // vector whole instead, minus an anchoring dot, because the rewrite's
    // offsets are stated against the untrimmed pattern.
    final anchored = length > 0 && letters[0] == _dot;
    var from = 0;
    if (rewriteFrom < 0) {
      while (from < length + 1 && priorities[from] == _digitZero) {
        from++;
      }
    } else {
      if (anchored) {
        from++;
      }
      if (isUtf8) {
        // The rewrite's offsets count characters; the matcher counts bytes.
        // One walk over the pattern converts them.
        var characters = -1;
        var startCharacter = -1;
        var byteIndex = anchored ? 1 : 0;
        for (; byteIndex < length + 1; byteIndex++) {
          if (byteIndex >= length || (letters[byteIndex] >> 6) != 2) {
            characters++;
          }
          if (startCharacter < 0 && rewriteAt == characters) {
            startCharacter = rewriteAt;
            rewriteAt = byteIndex;
          }
          if (startCharacter >= 0 &&
              (characters - startCharacter) == rewriteCut) {
            rewriteCut = byteIndex - rewriteAt;
            break;
          }
        }
        if (anchored) {
          rewriteAt--;
        }
      }
    }

    // Find how much of this pattern's prefix the trie already holds. One
    // walk answers both "does this pattern have a node" and "where do the
    // missing nodes start", and it costs a byte comparison per level where
    // looking each prefix up separately would cost a hash of it.
    var depth = 0;
    var deepest = 0;
    while (depth < length) {
      final next = trie.follow(deepest, letters[depth]);
      if (next < 0) {
        break;
      }
      deepest = next;
      depth++;
    }

    final existed = depth == length;
    final node = existed ? deepest : trie.addNode();
    trie.setPriorities(node, priorities, from, length + 1);
    if (rewriteFrom >= 0) {
      trie.setReplacement(
        node,
        line,
        rewriteFrom,
        rewriteTo,
        at: rewriteAt,
        cut: rewriteCut == 0 ? length : rewriteCut,
      );
    } else {
      // A later plain pattern landing on a node an earlier rewrite created
      // must clear the rewrite, not inherit it.
      trie.clearReplacement(node);
    }

    if (existed) {
      return;
    }
    // Hang the new node back onto the trie, longest missing prefix first,
    // which is the order the edges have to end up in.
    var child = node;
    for (var end = length; end > depth; end--) {
      final parent = end - 1 == depth ? deepest : trie.addNode();
      trie.addEdge(parent, child, letters[end - 1]);
      child = parent;
    }
  }

  void _reserveScratch(int size) {
    if (_letters.length >= size) {
      return;
    }
    _letters = Uint8List(size * 2);
    _priorities = Uint8List(size * 2);
  }
}

/// Whether [buffer] opens with [keyword].
bool startsWithKeyword(Uint8List buffer, String keyword) {
  if (buffer.length < keyword.length) {
    return false;
  }
  for (var i = 0; i < keyword.length; i++) {
    if (buffer[i] != keyword.codeUnitAt(i)) {
      return false;
    }
  }
  return true;
}

/// The first [byte] in `buffer[from..end)`, or -1.
int indexOfByte(Uint8List buffer, int byte, int from, int end) {
  for (var i = from; i < end; i++) {
    if (buffer[i] == byte) {
      return i;
    }
  }
  return -1;
}

/// `buffer[start..end)` without one trailing newline, and without the
/// carriage return in front of it.
int trimLineEnd(Uint8List buffer, int start, int end) {
  var last = end;
  if (last > start &&
      (buffer[last - 1] == _carriageReturn || buffer[last - 1] == _newline)) {
    last--;
  }
  if (last > start + 1 && buffer[last - 1] == _carriageReturn) {
    last--;
  }
  return last;
}

/// `atoi`: leading blanks, an optional sign, then digits; the rest is
/// ignored, and a line with no digits at all reads as zero.
int parseInteger(Uint8List buffer, int from, int end) {
  var i = from;
  while (i < end && (buffer[i] == _space || buffer[i] == _tab)) {
    i++;
  }
  var sign = 1;
  if (i < end && (buffer[i] == 0x2D || buffer[i] == 0x2B)) {
    if (buffer[i] == 0x2D) {
      sign = -1;
    }
    i++;
  }
  var value = 0;
  while (i < end && buffer[i] >= _digitZero && buffer[i] <= _digitNine) {
    value = value * 10 + (buffer[i] - _digitZero);
    i++;
  }
  return sign * value;
}

/// Hands out one line at a time, the way a fixed-size buffered read does.
class _LineScanner {
  _LineScanner(this._bytes);

  final Uint8List _bytes;
  int _position = 0;

  /// Whether the last line was longer than its budget and was therefore
  /// thrown away.
  bool overflowed = false;

  /// The next line, newline included, or null at the end of the file.
  ///
  /// [discardOverflow] picks between the two things a fixed-size read does
  /// when a line does not fit: skip to the end of the line and report the
  /// whole thing lost (what pattern lines do), or stop at the cap and leave
  /// the remainder to be handed out as if it were the next line (what the
  /// charset line does).
  Uint8List? next({
    int budget = kLineBudget,
    bool discardOverflow = true,
  }) {
    if (_position >= _bytes.length) {
      return null;
    }

    overflowed = false;
    final start = _position;
    final cap = start + budget - 1;
    var end = start;
    while (end < _bytes.length && end < cap && _bytes[end] != _newline) {
      end++;
    }

    // Only a newline strictly inside the budget was actually read. One
    // sitting exactly on the cap is the byte the read never reaches, and
    // taking it for found turns an over-long line into a valid one — the
    // difference between a 99-character pattern and a 100-character one the
    // format says to discard.
    if (end < cap && end < _bytes.length && _bytes[end] == _newline) {
      _position = end + 1;
      return Uint8List.sublistView(_bytes, start, _position);
    }

    if (end >= cap) {
      if (!discardOverflow) {
        _position = end;
        return Uint8List.sublistView(_bytes, start, end);
      }
      overflowed = true;
      var skip = end;
      while (skip < _bytes.length && _bytes[skip] != _newline) {
        skip++;
      }
      _position = skip < _bytes.length ? skip + 1 : skip;
      return Uint8List.sublistView(_bytes, start, end);
    }

    // End of file with no trailing newline.
    _position = end;
    return Uint8List.sublistView(_bytes, start, end);
  }
}
