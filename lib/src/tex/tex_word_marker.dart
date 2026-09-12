/// Finds the break opportunities in a word, using a compiled TeX pattern set.
library;

import 'dart:typed_data';

import 'package:flutter_hyphen/src/tex/tex_pattern_table.dart';

/// Marks words against a [TexPatternTable].
///
/// One instance owns the scratch every call runs in, so marking a word
/// allocates nothing at all. It is not re-entrant: hyphenation is
/// synchronous and an instance is meant to be shared, not called from two
/// places at once.
///
/// ### How a word is marked
/// The word is lower-cased and wrapped in boundary dots, giving `.word.`.
/// Every position of that string is then walked forward through the trie,
/// and each pattern found along the way claims a priority at each of the
/// positions it covers. The highest claim at a position wins. A break may
/// happen where the winning priority is odd.
///
/// ### Why walking from every position beats an Aho-Corasick automaton
/// Failure links save re-walking a prefix, which matters when patterns are
/// long and the alphabet is small. Hyphenation patterns are neither: they
/// average about four characters, and the walk from a given position dies
/// almost immediately. Restarting is a few array loads; maintaining failure
/// links costs a load and a branch on every character whether or not
/// anything matched, plus the memory for the link array.
class TexWordMarker {
  TexWordMarker(this.table);

  final TexPatternTable table;

  /// `.word.`, lower-cased, reused between calls.
  Uint16List _padded = Uint16List(64);

  /// The winning priority at each position of [_padded].
  Uint8List _marks = Uint8List(64);

  /// The break positions of the last [mark] call, as character offsets into
  /// the original word. Overwritten by the next call.
  final List<int> breaks = <int>[];

  /// Fills [breaks] with the places [word] may be broken.
  ///
  /// [leftMin] and [rightMin] are floors on top of whatever the pattern file
  /// declared, so a caller can be stricter than the language but not looser.
  void mark(String word, {required int leftMin, required int rightMin}) {
    breaks.clear();

    final length = word.length;
    final left = leftMin > table.leftMin ? leftMin : table.leftMin;
    final right = rightMin > table.rightMin ? rightMin : table.rightMin;
    if (length < left + right) {
      return;
    }

    final exception = table.exceptions[word.toLowerCase()];
    if (exception != null) {
      for (final at in exception) {
        if (at >= left && length - at >= right) {
          breaks.add(at);
        }
      }
      return;
    }

    final padded = _reserve(length + 2);
    final marks = _marks;

    // `.word.` — the dots are what anchored patterns match against.
    padded[0] = kBoundary;
    for (var i = 0; i < length; i++) {
      final unit = word.codeUnitAt(i);
      // Patterns are written lower case. Folding here rather than allocating
      // a lower-cased copy of the word keeps this allocation-free, and ASCII
      // is the overwhelmingly common case.
      padded[i + 1] = (unit >= 0x41 && unit <= 0x5A) ? unit + 0x20 : unit;
    }
    padded[length + 1] = kBoundary;

    final paddedLength = length + 2;
    marks.fillRange(0, paddedLength + 1, 0);

    final edgeStart = table.edgeStart;
    final edgeUnit = table.edgeUnit;
    final edgeTarget = table.edgeTarget;
    final priorityAt = table.priorityAt;
    final priorityLength = table.priorityLength;
    final priorityBytes = table.priorityBytes;

    for (var start = 0; start < paddedLength; start++) {
      var node = 0;
      for (var i = start; i < paddedLength; i++) {
        final unit = padded[i];

        // Inlined binary search. Hoisting the arrays above and inlining here
        // is worth roughly a third of the total marking time: this is the
        // innermost loop of the whole package.
        var low = edgeStart[node];
        var high = edgeStart[node + 1] - 1;
        var next = -1;
        while (low <= high) {
          final mid = (low + high) >> 1;
          final at = edgeUnit[mid];
          if (at == unit) {
            next = edgeTarget[mid];
            break;
          }
          if (at < unit) {
            low = mid + 1;
          } else {
            high = mid - 1;
          }
        }
        if (next < 0) {
          break;
        }
        node = next;

        final digitsAt = priorityAt[node];
        if (digitsAt < 0) {
          continue;
        }
        final digits = priorityLength[node];
        for (var k = 0; k < digits; k++) {
          final value = priorityBytes[digitsAt + k];
          if (marks[start + k] < value) {
            marks[start + k] = value;
          }
        }
      }
    }

    // A mark at index `i` of `.word.` sits before padded character `i`, which
    // is character `i - 1` of the word. A break after character `n` is
    // therefore mark `n + 1`.
    for (var at = left; at <= length - right; at++) {
      if ((marks[at + 1] & 1) == 1) {
        breaks.add(at);
      }
    }
  }

  Uint16List _reserve(int size) {
    if (_padded.length >= size + 1) {
      return _padded;
    }
    _padded = Uint16List(size * 2);
    _marks = Uint8List(size * 2);
    return _padded;
  }
}
