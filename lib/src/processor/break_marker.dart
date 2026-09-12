// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'dart:typed_data';

import 'package:flutter_hyphen/src/buffer/match_scratch.dart';
import 'package:flutter_hyphen/src/buffer/rewrite_track.dart';
import 'package:flutter_hyphen/src/constant/dictionary_syntax.dart';
import 'package:flutter_hyphen/src/model/edge_limits.dart';
import 'package:flutter_hyphen/src/model/pattern_automaton.dart';
import 'package:flutter_hyphen/src/model/pattern_set.dart';
import 'package:flutter_hyphen/src/processor/break_mark_processor.dart';
import 'package:flutter_hyphen/src/util/byte_reader.dart';

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
  final List<MatchScratch> _scratch = <MatchScratch>[];

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
    BreakMarkProcessor.trimLeftEdge(
      level,
      word,
      offset,
      length,
      marks,
      track,
      limits.left > 0 ? limits.left : 2,
    );
    BreakMarkProcessor.trimRightEdge(
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
    BreakMarkProcessor.suppress(
      level,
      word,
      offset,
      length,
      marks,
      raise == null ? kDigitZero : 0,
    );

    if (level.charsetIsUtf8) {
      return BreakMarkProcessor.compactToCharacters(
        word,
        offset,
        length,
        length,
        marks,
        track,
      );
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
    padded[end++] = kDot;
    for (var i = 0; i < length; i++) {
      final byte = word[offset + i];
      padded[end++] = (byte <= kDigitNine && byte >= kDigitZero) ? kDot : byte;
    }
    padded[end++] = kDot;

    marks.fillRange(0, end, kDigitZero);

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
      marks.fillRange(shifted, length, kDigitZero);
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
          final split = indexOfByteIn(pool, kEquals, start, start + textLength);
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

        padded[i + 2] = byteAt(word, offset, limit, i + 1);
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
        BreakMarkProcessor.trimLeft(
          level,
          word,
          offset,
          limit,
          marks,
          track,
          compoundLeft,
        );
      }
      if (!atWordEnd) {
        BreakMarkProcessor.trimRight(
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

  MatchScratch _scratchFor(int depth, int length, {required bool rewrites}) {
    while (_scratch.length <= depth) {
      _scratch.add(MatchScratch());
    }
    return _scratch[depth]..prepare(length, rewrites: rewrites);
  }
}
