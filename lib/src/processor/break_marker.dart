// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'dart:typed_data';

import 'package:flutter_hyphen/src/model/edge_limits.dart';
import 'package:flutter_hyphen/src/model/pattern_automaton.dart';
import 'package:flutter_hyphen/src/model/pattern_set.dart';

const int _digitZero = 0x30;
const int _digitNine = 0x39;
const int _dot = 0x2E;
const int _equals = 0x3D;

/// Where a rewritten break begins and ends, one entry per character of the
/// word being marked.
///
/// A `hyph_*.dic` dictionary rarely populates one of these. It exists
/// for the non-standard patterns the format allows, where the spelling
/// changes at the break and the replacement text, how far back it starts and
/// how much it swallows all have to travel with the break itself.
///
/// Three `Int32List`s rather than a list of byte arrays: a replacement is a
/// packed reference into the dictionary's shared pool (see
/// [PatternAutomaton.packReplacement]), which keeps this poolable and free
/// of per-word allocation.
class RewriteTrack {
  RewriteTrack(int length)
    : reference = Int32List(length)..fillRange(0, length, -1),
      shift = Int32List(length),
      cut = Int32List(length);

  /// Packed replacement reference per character, -1 where there is none.
  final Int32List reference;

  /// How far back from the break the replacement text starts.
  final Int32List shift;

  /// How many characters of the original the replacement swallows.
  final Int32List cut;

  /// Returns this to the state a freshly built one is in.
  void clear() {
    reference.fillRange(0, reference.length, -1);
    shift.fillRange(0, shift.length, 0);
    cut.fillRange(0, cut.length, 0);
  }
}

/// Marks the break opportunities in a word.
///
/// One instance owns the scratch every call runs in, so marking a word
/// allocates nothing at all for a dictionary that does not rewrite words —
/// which is every dictionary without a `/` pattern. It is not re-entrant:
/// hyphenation is synchronous and a single instance is meant to be shared,
/// not called from two places at once.
///
/// ### What "marking" means
/// Every character of the word gets a priority digit. The word may be broken
/// after a character whose digit is odd. The digits come from patterns that
/// matched, from whichever matched highest at each position; then the
/// minimum distances blank out everything too near an edge, and the
/// suppression list blanks out everything beside a forbidden substring.
///
/// ### Levels
/// A dictionary is at least two levels deep. The outer one runs first and
/// finds the boundaries of compound parts; each part is then handed back to
/// the outer level as a word of its own, and a part with no boundaries in it
/// falls through to the inner level's patterns. That recursion is why the
/// scratch is indexed by depth.
class BreakMarker {
  final List<_LevelScratch> _scratch = <_LevelScratch>[];

  /// Marks every break opportunity of `word[offset..offset + length)` into
  /// [marks], which must have room for `length + 3` bytes and must arrive
  /// zeroed.
  ///
  /// [raise] lifts the dictionary's own minimum distances; passing null
  /// leaves them as the dictionary states them.
  ///
  /// Returns false when the word is not valid text in the dictionary's
  /// charset, which is the one failure the algorithm can report.
  bool markWord(
    PatternSet level,
    Uint8List word,
    int offset,
    int length,
    Uint8List marks, {
    EdgeLimits? raise,
  }) {
    final limits = raise == null ? level.limits : level.limits.raisedTo(raise);
    final track = level.rewritesWords
        ? RewriteTrack(length == 0 ? 1 : length)
        : null;

    markPatterns(
      level,
      word,
      offset,
      length,
      marks,
      track: track,
      compoundLeft: limits.compoundLeft,
      compoundRight: limits.compoundRight,
    );
    trimLeftEdge(
      level,
      word,
      offset,
      length,
      marks,
      track,
      limits.left > 0 ? limits.left : 2,
    );
    trimRightEdge(
      level,
      word,
      offset,
      length,
      length,
      marks,
      track,
      limits.right > 0 ? limits.right : 2,
    );

    // Raised minimums and stated ones do not blank a suppressed position the
    // same way: one writes a zero digit, the other writes a NUL. Both read as
    // "no break", so nothing downstream can tell them apart — but the raw
    // marks are observable through the dictionary's own API, and the
    // reference implementation really does differ here, so the difference is
    // kept rather than tidied away.
    _suppress(
      level,
      word,
      offset,
      length,
      marks,
      raise == null ? _digitZero : 0,
    );

    if (level.charsetIsUtf8) {
      return compactToCharacters(word, offset, length, length, marks, track);
    }
    return true;
  }

  /// Runs [level]'s patterns over `word[offset..offset + length)` and
  /// everything the level below has to say about the pieces, and nothing
  /// else: no minimum distances at the ends of the word, no suppressions, no
  /// squeezing from bytes down to characters.
  ///
  /// [markWord] is the whole job; this is the part of it that applies
  /// patterns, exposed because that is the part worth probing on its own.
  void markPatterns(
    PatternSet level,
    Uint8List word,
    int offset,
    int length,
    Uint8List marks, {
    RewriteTrack? track,
    int compoundLeft = 0,
    int compoundRight = 0,
    bool atWordStart = true,
    bool atWordEnd = true,
  }) => _markLevel(
    level,
    word,
    offset,
    length,
    length,
    marks,
    track,
    compoundLeft,
    compoundRight,
    atWordStart: atWordStart,
    atWordEnd: atWordEnd,
    depth: 0,
  );

  /// Runs one level's patterns over the word, then splits it at whatever
  /// breaks they found and runs the level below over each piece.
  ///
  /// [limit] is how far the buffer may be read: the slices handed to the
  /// recursion are windows into a longer buffer, and the difference between
  /// "the word ends here" and "the buffer ends here" decides what the
  /// minimum-distance passes see. [atWordStart] and [atWordEnd] say whether
  /// this slice still touches the real ends of the word, which is what tells
  /// the compound minimums to apply.
  void _markLevel(
    PatternSet level,
    Uint8List word,
    int offset,
    int limit,
    int length,
    Uint8List marks,
    RewriteTrack? track,
    int compoundLeft,
    int compoundRight, {
    required bool atWordStart,
    required bool atWordEnd,
    required int depth,
  }) {
    if (length > limit) {
      throw RangeError.range(length, 0, limit, 'length');
    }

    final automaton = level.automaton;
    final rewrites = automaton.rewritesWords;
    final paddedLength = length + 3;
    final scratch = _scratchFor(depth, length, rewrites: rewrites);
    final padded = scratch.padded;
    final spanCut = scratch.spanCut;
    final spanIndex = scratch.spanIndex;
    final spanRef = scratch.spanRef;
    var tracking = 0;

    // Patterns are written against a word with a dot glued to each end, and
    // any digit inside the word counts as one of those dots.
    var end = 0;
    padded[end++] = _dot;
    for (var i = 0; i < length; i++) {
      final byte = word[offset + i];
      padded[end++] = (byte <= _digitNine && byte >= _digitZero) ? _dot : byte;
    }
    padded[end++] = _dot;

    marks.fillRange(0, end, _digitZero);

    final edgeStart = automaton.edgeStart;
    final edgeByte = automaton.edgeByte;
    final edgeTarget = automaton.edgeTarget;
    final failureLink = automaton.failureLink;
    final tableBase = automaton.tableBase;
    final tableEntries = automaton.tableEntries;
    final priorityAt = automaton.priorityAt;
    final priorityLength = automaton.priorityLength;
    final priorityBytes = automaton.priorityBytes;

    var node = 0;
    for (var i = 0; i < end; i++) {
      final byte = padded[i];
      var restarted = false;

      for (;;) {
        if (node < 0) {
          // Fell off the trie. Start again at the root on the *next* byte,
          // without applying whatever pattern the root may carry: the root
          // stands for the empty prefix, which nothing has matched.
          node = 0;
          restarted = true;
          break;
        }
        var next = -1;
        final base = tableBase[node];
        if (base >= 0) {
          next = tableEntries[base + byte];
        } else {
          final edgeEnd = edgeStart[node + 1];
          for (var edge = edgeStart[node]; edge < edgeEnd; edge++) {
            if (edgeByte[edge] == byte) {
              next = edgeTarget[edge];
              break;
            }
          }
        }
        if (next >= 0) {
          node = next;
          break;
        }
        node = failureLink[node];
      }
      if (restarted) {
        continue;
      }

      final digitsAt = priorityAt[node];
      if (digitsAt < 0) {
        continue;
      }
      final digits = priorityLength[node];
      final at = i + 1 - digits;

      if (!rewrites) {
        // Nothing on this level rewrites anything, so the bookkeeping below
        // would store nulls into arrays nothing reads. Same arithmetic,
        // none of the stores.
        for (var k = 0; k < digits; k++) {
          final value = priorityBytes[digitsAt + k];
          if (marks[at + k] < value) {
            marks[at + k] = value;
          }
        }
        continue;
      }

      final reference = automaton.replacementRef[node];
      final replaceAt = automaton.replacementAt[node];
      final replaceCut = automaton.replacementCut[node];

      if (reference >= 0) {
        if (tracking == 0) {
          for (; tracking < length; tracking++) {
            spanRef[tracking] = -1;
            spanIndex[tracking] = -1;
          }
        }
        spanCut[at + replaceAt] = replaceCut;
      }
      for (var k = 0; k < digits; k++) {
        final value = priorityBytes[digitsAt + k];
        if (marks[at + k] < value) {
          marks[at + k] = value;
          if (value & 1 != 0) {
            spanRef[at + k] = reference;
            if (reference >= 0 &&
                k >= replaceAt &&
                k <= replaceAt + replaceCut) {
              spanIndex[at + replaceAt] = at + k;
            }
          }
        }
      }
    }

    // The marks were written against the padded word; shift them back onto
    // the real one and clear whatever the shift left behind. The mark that
    // belonged to the closing dot is dropped rather than folded onto the
    // last character: a pattern cannot ask for a break after the end.
    var shifted = 0;
    for (; shifted < end - 3; shifted++) {
      marks[shifted] = marks[shifted + 1];
    }
    if (shifted < length) {
      marks.fillRange(shifted, length, _digitZero);
    }
    if (length < marks.length) {
      marks[length] = 0;
    }

    if (tracking != 0 && track != null) {
      for (var i = 0; i < length; i++) {
        final index = spanIndex[i];
        if (index >= 0 && spanRef[index] >= 0) {
          // The reference implementation writes these three without
          // checking that the index is in range, and it can be -1: the
          // pattern `.1xy/z=,1,1` on the word `xy` reaches here with one.
          // In C that is a one-element write off the front of the heap
          // block, which is undefined behaviour rather than behaviour to
          // reproduce; the write lands where nothing reads, so skipping it
          // is both safe and the only option that does not throw.
          if (index - 1 >= 0 && index - 1 < track.reference.length) {
            track.reference[index - 1] = spanRef[index];
            track.shift[index - 1] = index - i;
            track.cut[index - 1] = spanCut[i];
          }
          i += spanCut[i] - 1;
        }
      }
    }

    final inner = level.inner;
    if (inner == null) {
      return;
    }

    // A carrier for the recursion, allocated only when something below can
    // write to it. `rewritesWords` on the level, not on the automaton: this
    // carrier is handed down, and the level below may rewrite where this one
    // does not.
    final innerTrack = level.rewritesWords ? scratch.trackFor(length) : null;
    final innerMarks = scratch.innerMarks;
    final pool = automaton.replacements.bytes;
    var segmentStart = 0;

    for (var i = 0; i < length; i++) {
      if ((marks[i] & 1) == 0 && !(segmentStart > 0 && i + 1 == length)) {
        continue;
      }
      if (i - segmentStart > 0) {
        var grown = 0;
        final saved = padded[i + 2];
        padded[i + 2] = 0;

        // A break that rewrites the word changes what the next level sees:
        // splice the replacement into the padded copy first, so the piece
        // handed down is spelled the way the break leaves it.
        if (track != null && track.reference[i] >= 0) {
          final reference = track.reference[i];
          final start = PatternAutomaton.replacementStart(reference);
          final textLength = PatternAutomaton.replacementLength(reference);
          final split = _indexOfByte(pool, _equals, start, start + textLength);
          final into = 2 + i - track.shift[i];
          for (var k = 0; k < textLength && into + k < paddedLength - 1; k++) {
            padded[into + k] = pool[start + k];
          }
          if (split >= 0) {
            grown = (split - start) - track.shift[i];
            if (2 + i + grown < paddedLength) {
              padded[2 + i + grown] = 0;
            }
          }
        }

        _markLevel(
          level,
          padded,
          segmentStart + 1,
          paddedLength - segmentStart - 1,
          i - segmentStart + 1 + grown,
          innerMarks,
          innerTrack,
          compoundLeft,
          compoundRight,
          atWordStart: segmentStart == 0 && atWordStart,
          atWordEnd: (marks[i] & 1) == 0 && atWordEnd,
          depth: depth + 1,
        );

        for (var k = 0; k < i - segmentStart; k++) {
          marks[segmentStart + k] = innerMarks[k];
          if (innerTrack != null &&
              innerTrack.reference[k] >= 0 &&
              track != null) {
            track.reference[segmentStart + k] = innerTrack.reference[k];
            track.shift[segmentStart + k] = innerTrack.shift[k];
            track.cut[segmentStart + k] = innerTrack.cut[k];
          }
        }

        padded[i + 2] = _byteAt(word, offset, limit, i + 1);
        if (track != null && track.reference[i] >= 0) {
          final copy = length < paddedLength - 2 ? length : paddedLength - 2;
          for (var k = 0; k < copy; k++) {
            padded[1 + k] = word[offset + k];
          }
        }
        // Undoing the temporary terminator has no counterpart in the
        // reference implementation and provably cannot matter: the only way
        // it reads back as zero is on the last iteration, after which
        // nothing reads the padded copy again. Kept as a no-op rather than
        // removed, so the shape of the loop still lines up with the original.
        if (saved != 0 && padded[i + 2] == 0) {
          padded[i + 2] = saved;
        }
      }
      segmentStart = i + 1;
      if (innerTrack != null) {
        innerTrack.reference.fillRange(0, innerTrack.reference.length, -1);
      }
    }

    // No compound boundary anywhere: the whole word goes down to the next
    // level, and the compound minimums apply at whichever ends of it are not
    // ends of the real word.
    if (segmentStart == 0) {
      _markLevel(
        inner,
        word,
        offset,
        limit,
        length,
        marks,
        track,
        compoundLeft,
        compoundRight,
        atWordStart: atWordStart,
        atWordEnd: atWordEnd,
        depth: depth + 1,
      );
      if (!atWordStart) {
        _trimLeft(level, word, offset, limit, marks, track, compoundLeft);
      }
      if (!atWordEnd) {
        _trimRight(
          level,
          word,
          offset,
          limit,
          length,
          marks,
          track,
          compoundRight,
        );
      }
    }
  }

  /// Blanks every mark within [minimum] characters of the start of the word.
  void trimLeftEdge(
    PatternSet level,
    Uint8List word,
    int offset,
    int length,
    Uint8List marks,
    RewriteTrack? track,
    int minimum,
  ) => _trimLeft(level, word, offset, length, marks, track, minimum);

  void _trimLeft(
    PatternSet level,
    Uint8List word,
    int offset,
    int limit,
    Uint8List marks,
    RewriteTrack? track,
    int minimum,
  ) {
    final utf8 = level.charsetIsUtf8;
    final pool = level.automaton.replacements.bytes;
    var counted = 1;

    if (utf8 &&
        _byteAt(word, offset, limit, 0) == 0xEF &&
        _byteAt(word, offset, limit, 1) == 0xAC) {
      counted += ligatureExtraCharacters(_byteAt(word, offset, limit, 2));
    }

    // Leading digits are not characters of the word for this purpose.
    for (
      var k = 0;
      _byteAt(word, offset, limit, k) <= _digitNine &&
          _byteAt(word, offset, limit, k) >= _digitZero;
      k++
    ) {
      counted--;
    }

    final reference = track?.reference;
    var i = 0;
    while (counted < minimum && _byteAt(word, offset, limit, i) != 0) {
      do {
        if (reference != null && i < reference.length && reference[i] >= 0) {
          // A rewritten break keeps its mark if the text it introduces is
          // itself long enough to satisfy the minimum.
          final start = PatternAutomaton.replacementStart(reference[i]);
          final textLength = PatternAutomaton.replacementLength(reference[i]);
          final split = _indexOfByte(pool, _equals, start, start + textLength);
          if (split >= 0 &&
              (countCharacters(
                        word,
                        offset,
                        limit,
                        i - track!.shift[i] + 1,
                        utf8: utf8,
                      ) +
                      countCharacters(
                        pool,
                        start,
                        textLength,
                        split - start,
                        utf8: utf8,
                      )) <
                  minimum) {
            reference[i] = -1;
            marks[i] = _digitZero;
          }
        } else {
          marks[i] = _digitZero;
        }
        i++;

        if (utf8 &&
            _byteAt(word, offset, limit, i) == 0xEF &&
            _byteAt(word, offset, limit, i + 1) == 0xAC) {
          counted += ligatureExtraCharacters(
            _byteAt(word, offset, limit, i + 2),
          );
        }
      } while (utf8 && (_byteAt(word, offset, limit, i) & 0xC0) == 0x80);
      counted++;
    }
  }

  /// Blanks every mark within [minimum] characters of the end of the word.
  void trimRightEdge(
    PatternSet level,
    Uint8List word,
    int offset,
    int limit,
    int length,
    Uint8List marks,
    RewriteTrack? track,
    int minimum,
  ) => _trimRight(level, word, offset, limit, length, marks, track, minimum);

  void _trimRight(
    PatternSet level,
    Uint8List word,
    int offset,
    int limit,
    int length,
    Uint8List marks,
    RewriteTrack? track,
    int minimum,
  ) {
    final utf8 = level.charsetIsUtf8;
    final pool = level.automaton.replacements.bytes;
    var counted = 0;

    // Trailing digits are not characters of the word for this purpose.
    for (
      var k = length - 1;
      k > 0 &&
          _byteAt(word, offset, limit, k) <= _digitNine &&
          _byteAt(word, offset, limit, k) >= _digitZero;
      k--
    ) {
      counted--;
    }

    final reference = track?.reference;
    for (var i = length - 1; counted < minimum && i > 0; i--) {
      if (reference != null && i < reference.length && reference[i] >= 0) {
        final start = PatternAutomaton.replacementStart(reference[i]);
        final textLength = PatternAutomaton.replacementLength(reference[i]);
        final split = _indexOfByte(pool, _equals, start, start + textLength);
        if (split >= 0) {
          final from = i - track!.shift[i] + track.cut[i] + 1;
          final clamped = from < 0 ? 0 : (from > limit ? limit : from);
          if ((countCharacters(
                    word,
                    offset + clamped,
                    limit - clamped,
                    100,
                    utf8: utf8,
                  ) +
                  countCharacters(
                    pool,
                    split + 1,
                    start + textLength - split - 1,
                    start + textLength - split - 1,
                    utf8: utf8,
                  )) <
              minimum) {
            reference[i] = -1;
            marks[i] = _digitZero;
          }
        }
      } else {
        marks[i] = _digitZero;
      }
      final byte = _byteAt(word, offset, limit, i);
      if (!utf8 || (byte & 0xC0) == 0xC0 || (byte & 0x80) != 0x80) {
        counted++;
      }
    }
  }

  /// Blanks the marks on both sides of every suppressed substring.
  ///
  /// The scan stops at [length] rather than at the end of the buffer, which
  /// matters whenever the buffer is longer than the word: a suppressed
  /// substring must not be allowed to match across the word and whatever
  /// happens to follow it in a reused buffer.
  void _suppress(
    PatternSet level,
    Uint8List word,
    int offset,
    int length,
    Uint8List marks,
    int blank,
  ) {
    final suppressions = level.suppressions;
    for (var n = 0; n < suppressions.length; n++) {
      final needle = suppressions[n];
      final needleLength = needle.length;
      // An empty entry — which `NOHYPHEN a,,b` produces — would match at
      // every position and walk off the front of the marks. Skipped.
      if (needleLength == 0) {
        continue;
      }
      final first = needle[0];
      final last = length - needleLength;
      for (var at = 0; at <= last; at++) {
        if (word[offset + at] != first) {
          continue;
        }
        var k = 1;
        while (k < needleLength && word[offset + at + k] == needle[k]) {
          k++;
        }
        if (k != needleLength) {
          continue;
        }
        final tail = at + needleLength - 1;
        if (tail < marks.length) {
          marks[tail] = blank;
        }
        if (at > 0) {
          marks[at - 1] = blank;
        }
      }
    }
  }

  /// Squeezes [marks] from one entry per byte down to one entry per
  /// character, in place.
  ///
  /// Returns false when the word starts inside a character, which is the
  /// only malformed input this can detect and the one failure the algorithm
  /// reports.
  bool compactToCharacters(
    Uint8List word,
    int offset,
    int limit,
    int length,
    Uint8List marks,
    RewriteTrack? track,
  ) {
    if (limit > 0 && (word[offset] >> 6) == 2) {
      return false;
    }

    var out = -1;
    if (track == null) {
      // The shape almost every word has.
      for (var i = 0; i < length; i++) {
        if ((word[offset + i] >> 6) != 2) {
          out++;
        }
        marks[out] = marks[i];
      }
    } else {
      final reference = track.reference;
      final shift = track.shift;
      final cut = track.cut;
      for (var i = 0; i < length; i++) {
        if ((word[offset + i] >> 6) != 2) {
          out++;
        }
        marks[out] = marks[i];

        if (i < shift.length) {
          var span = shift[i];
          var characters = 0;
          for (var k = 0; k < span; k++) {
            if ((_byteAt(word, offset, limit, i - k) >> 6) != 2) {
              characters++;
            }
          }
          shift[out] = characters;
          var k = i - span + 1;
          span = k + cut[i];
          characters = 0;
          for (; k < span; k++) {
            if ((_byteAt(word, offset, limit, k) >> 6) != 2) {
              characters++;
            }
          }
          cut[out] = characters;
          reference[out] = reference[i];
          if (out < i) {
            reference[i] = -1;
            shift[i] = 0;
            cut[i] = 0;
          }
        }
      }
    }
    if (out + 1 < marks.length) {
      marks[out + 1] = 0;
    }
    return true;
  }

  _LevelScratch _scratchFor(int depth, int length, {required bool rewrites}) {
    while (_scratch.length <= depth) {
      _scratch.add(_LevelScratch());
    }
    return _scratch[depth]..prepare(length, rewrites: rewrites);
  }
}

/// The buffers one level of the recursion works in.
///
/// The recursion's depth is bounded by the length of the word, so the arena
/// is a list indexed by depth that grows once and is reused forever after.
/// The reference implementation allocates all of this per call.
class _LevelScratch {
  Uint8List padded = Uint8List(0);
  Uint8List innerMarks = Uint8List(0);
  Int32List spanCut = _noInts;
  Int32List spanIndex = _noInts;
  Int32List spanRef = _noInts;
  RewriteTrack? _track;

  static final Int32List _noInts = Int32List(0);

  /// Sizes the buffers for a word of [length] bytes and puts the ones that
  /// are read before they are written into their documented start state.
  void prepare(int length, {required bool rewrites}) {
    final size = length + 3;
    if (padded.length < size) {
      // Word lengths cluster, and a regrow costs a full allocation, so the
      // first one is generous enough to cover every word in running text.
      final grown = size < 64 ? 64 : size * 2;
      padded = Uint8List(grown);
      innerMarks = Uint8List(grown);
    }
    // Every byte of the padded copy is written below except the last, which
    // the compound recursion reads back through its window.
    padded[length + 2] = 0;

    if (!rewrites) {
      return;
    }
    if (spanCut.length < size) {
      final grown = size < 64 ? 64 : size * 2;
      spanCut = Int32List(grown);
      spanIndex = Int32List(grown)..fillRange(0, grown, -1);
      spanRef = Int32List(grown)..fillRange(0, grown, -1);
    } else {
      spanCut.fillRange(0, size, 0);
      spanIndex.fillRange(0, size, -1);
      spanRef.fillRange(0, size, -1);
    }
  }

  /// A cleared carrier for the recursion, big enough for [length]
  /// characters.
  RewriteTrack trackFor(int length) {
    final size = length == 0 ? 1 : length;
    final existing = _track;
    if (existing == null || existing.reference.length < size) {
      return _track = RewriteTrack(size < 64 ? 64 : size * 2);
    }
    return existing..clear();
  }
}

/// How many extra characters the ligature at a `U+FB00`..`U+FB06` sequence
/// is worth, given its third byte.
///
/// Zero for the two-letter ligatures and one for the three-letter ones. The
/// reference build does not enable the long-ligature variant, so `ﬀ` counts
/// as one character and `ﬃ` as two.
int ligatureExtraCharacters(int thirdByte) {
  switch (thirdByte) {
    case 0x83: // ffi
    case 0x84: // ffl
      return 1;
    case 0x80: // ff
    case 0x81: // fi
    case 0x82: // fl
    case 0x85: // long st
    case 0x86: // st
      return 0;
  }
  return 0;
}

/// How many characters the first [count] bytes of `buffer[offset..)` hold,
/// stopping early at a NUL.
int countCharacters(
  Uint8List buffer,
  int offset,
  int limit,
  int count, {
  required bool utf8,
}) {
  var characters = 0;
  var i = 0;
  while (i < count && _byteAt(buffer, offset, limit, i) != 0) {
    characters++;
    if (utf8 &&
        _byteAt(buffer, offset, limit, i) == 0xEF &&
        _byteAt(buffer, offset, limit, i + 1) == 0xAC) {
      characters += ligatureExtraCharacters(
        _byteAt(buffer, offset, limit, i + 2),
      );
    }
    for (
      i++;
      utf8 && (_byteAt(buffer, offset, limit, i) & 0xC0) == 0x80;
      i++
    ) {}
  }
  return characters;
}

/// `buffer[offset + at]`, or 0 when [at] is outside `[0, limit)`.
///
/// The algorithm reads past both ends of the word in several places — the
/// ligature probe in the left-edge pass most obviously. In C those reads
/// land in whatever the allocator left there; here they are defined to be
/// zero, which is what the reference implementation's own behaviour turns
/// out to depend on.
@pragma('vm:prefer-inline')
int _byteAt(Uint8List buffer, int offset, int limit, int at) =>
    (at < 0 || at >= limit) ? 0 : buffer[offset + at];

int _indexOfByte(Uint8List buffer, int byte, int from, int end) {
  for (var i = from; i < end; i++) {
    if (buffer[i] == byte) {
      return i;
    }
  }
  return -1;
}
