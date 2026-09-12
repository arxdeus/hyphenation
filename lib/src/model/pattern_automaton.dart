// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'dart:typed_data';

/// How close to an edge a break may fall.
///
/// A dictionary states its own minimums; a caller may raise them but never
/// lower them. `compound*` apply at the internal edges of a compound word,
/// where a break was already taken, rather than at the ends of the word.
class EdgeLimits {
  const EdgeLimits({
    this.left = 0,
    this.right = 0,
    this.compoundLeft = 0,
    this.compoundRight = 0,
  });

  /// Nothing required — what a dictionary that declares no minimums has.
  static const EdgeLimits none = EdgeLimits();

  /// Characters that must stay before a break.
  final int left;

  /// Characters that must move after a break.
  final int right;

  /// [left], at a compound boundary.
  final int compoundLeft;

  /// [right], at a compound boundary.
  final int compoundRight;

  /// This and [other], each field at whichever is larger.
  EdgeLimits raisedTo(EdgeLimits other) => EdgeLimits(
    left: left > other.left ? left : other.left,
    right: right > other.right ? right : other.right,
    compoundLeft: compoundLeft > other.compoundLeft
        ? compoundLeft
        : other.compoundLeft,
    compoundRight: compoundRight > other.compoundRight
        ? compoundRight
        : other.compoundRight,
  );

  @override
  String toString() =>
      'EdgeLimits($left, $right, compound $compoundLeft, $compoundRight)';
}

/// The pattern trie of one hyphenation level, flattened for matching.
///
/// Patterns are strings of letters carrying a priority digit between each
/// pair; matching a word against all of them at once is a classic
/// Aho-Corasick problem, and this is the automaton for it: a trie of pattern
/// prefixes, a failure link per node, and the priority vector of whichever
/// pattern ends at a node.
///
/// Everything lives in typed arrays indexed by node number. Nothing here is
/// an object, because the matcher touches most of it once per input byte,
/// and a `List` of nodes costs a pointer chase and a bounds-checked object
/// load where an `Int32List` costs a load.
///
/// ### Edges
/// Compressed-row style: the edges leaving node `n` occupy
/// `[edgeStart[n], edgeStart[n + 1])` of [edgeByte] and [edgeTarget], in the
/// order they were added. The order is not incidental — the matcher takes
/// the first edge that matches, as the reference implementation does.
///
/// Nodes with many edges also get a 256-entry direct table. In a real
/// dictionary that is the root and nothing else, and the root is where every
/// failure chain ends, so the one kilobyte removes the longest scan in the
/// matcher.
///
/// ### Replacements
/// A pattern may carry a rewrite ("non-standard hyphenation", where the
/// spelling changes at the break). The rewrite text of every such
/// pattern goes into the dictionary's [ReplacementPool], and a node refers
/// to its own by a packed `(offset << 8) | length` — see [packReplacement] —
/// or by -1 for the overwhelming majority of nodes that have none.
///
/// Packing is what keeps a replacement an `int`. The matcher has to carry
/// one per character through its recursion and back out again, and as an
/// `int` that bookkeeping is three `Int32List`s it can pool; as an object
/// reference it would be a `List<Uint8List?>` it has to allocate and clear.
class PatternAutomaton {
  PatternAutomaton({
    required this.nodeCount,
    required this.edgeStart,
    required this.edgeByte,
    required this.edgeTarget,
    required this.failureLink,
    required this.tableBase,
    required this.tableEntries,
    required this.priorityAt,
    required this.priorityLength,
    required this.priorityBytes,
    required this.replacementRef,
    required this.replacementAt,
    required this.replacementCut,
    required this.replacements,
    required this.rewritesWords,
  });

  /// How many nodes the trie has, root included.
  final int nodeCount;

  /// Index into [edgeByte] / [edgeTarget] where each node's edges begin;
  /// `nodeCount + 1` entries, so the last node's end is available too.
  final Int32List edgeStart;
  final Uint8List edgeByte;
  final Int32List edgeTarget;

  /// Where to continue matching after a node runs out of edges: the node of
  /// the longest proper suffix of this node's prefix. -1 at the root, which
  /// is what makes the matcher restart there.
  final Int32List failureLink;

  /// Offset of a node's direct table in [tableEntries], or -1 when the node
  /// has none and its edges must be scanned.
  final Int32List tableBase;
  final Int32List tableEntries;

  /// Where this node's priority vector starts in [priorityBytes], or -1
  /// when no pattern ends at this node.
  final Int32List priorityAt;

  /// How long it is. A pattern cannot be longer than the line it was read
  /// from, so a byte is enough.
  final Uint8List priorityLength;

  /// Priority digits, as the ASCII bytes the dictionary is written in.
  final Uint8List priorityBytes;

  /// Packed `(offset << 8) | length` into [replacements], or -1.
  final Int32List replacementRef;

  /// Where in the matched pattern the replacement starts, and how many
  /// characters of it the replacement consumes.
  final Int32List replacementAt;
  final Int32List replacementCut;

  /// The text every replacement in the whole dictionary points into.
  ///
  /// Shared by every level on purpose: the matcher carries a replacement
  /// found by one level into the bookkeeping of another, so a reference has
  /// to mean the same thing everywhere.
  final ReplacementPool replacements;

  /// Whether any node here carries a replacement. When nothing does, the
  /// matcher can skip the whole rewrite bookkeeping, which is most of what
  /// it would otherwise do per matched pattern.
  final bool rewritesWords;

  /// The node reached by following [bytes], or -1.
  ///
  /// Plain trie descent, no failure links: this answers "is this exact
  /// string a pattern prefix", which is what a caller inspecting the
  /// automaton wants.
  int nodeForPrefix(List<int> bytes) {
    var node = 0;
    for (var i = 0; i < bytes.length; i++) {
      node = edgeFrom(node, bytes[i]);
      if (node < 0) {
        return -1;
      }
    }
    return node;
  }

  /// The node [byte] leads to from [node], or -1.
  int edgeFrom(int node, int byte) {
    final base = tableBase[node];
    if (base >= 0) {
      return tableEntries[base + byte];
    }
    final end = edgeStart[node + 1];
    for (var i = edgeStart[node]; i < end; i++) {
      if (edgeByte[i] == byte) {
        return edgeTarget[i];
      }
    }
    return -1;
  }

  /// The priority digits of the pattern ending at [node], or null.
  Uint8List? prioritiesOf(int node) {
    final at = priorityAt[node];
    if (at < 0) {
      return null;
    }
    return Uint8List.sublistView(priorityBytes, at, at + priorityLength[node]);
  }

  /// The replacement text of the pattern ending at [node], or null.
  Uint8List? replacementOf(int node) {
    final ref = replacementRef[node];
    if (ref < 0) {
      return null;
    }
    return Uint8List.sublistView(
      replacements.bytes,
      replacementStart(ref),
      replacementStart(ref) + replacementLength(ref),
    );
  }

  /// Packs a slice of [replacementBytes] into the reference the matcher
  /// passes around.
  ///
  /// The 8-bit length field is not a guess: a replacement is part of one
  /// dictionary line, and lines longer than 100 bytes are discarded before
  /// they ever get here.
  static int packReplacement(int start, int length) {
    assert(length >= 0 && length < 256, 'replacement too long to pack');
    assert(start >= 0 && start <= 0x7FFFFF, 'replacement blob too large');
    return (start << 8) | length;
  }

  /// The offset a [packReplacement] result refers to.
  static int replacementStart(int ref) => ref >> 8;

  /// The length a [packReplacement] result refers to.
  static int replacementLength(int ref) => ref & 0xFF;
}

/// One hyphenation level: its patterns, its minimums, its suppressions, and
/// the level it defers to.
///
/// A dictionary is always at least two levels deep. The outer one decides
/// where a word splits into parts — at an existing hyphen or apostrophe, or
/// at a compound boundary the dictionary knows about — and the inner one
/// hyphenates each part. A dictionary without a `NEXTLEVEL` keyword gets an
/// outer level synthesised for it from the punctuation rules alone.
class PatternSet {
  PatternSet({
    required this.automaton,
    required this.limits,
    required this.suppressions,
    required this.charsetIsUtf8,
    required this.charsetName,
    required this.inner,
  }) : rewritesWords =
           automaton.rewritesWords || (inner?.rewritesWords ?? false);

  /// The patterns of this level.
  final PatternAutomaton automaton;

  /// This level's own minimums.
  final EdgeLimits limits;

  /// Substrings that forbid a break on either side of themselves, from the
  /// dictionary's `NOHYPHEN` line.
  final List<Uint8List> suppressions;

  /// Whether patterns and words are UTF-8 rather than one byte per
  /// character.
  final bool charsetIsUtf8;

  /// The charset line as written, kept because a dictionary may name
  /// something other than the two that are supported.
  final String charsetName;

  /// The level that hyphenates the parts this one finds, or null at the
  /// innermost level.
  final PatternSet? inner;

  /// Whether this level or any below it rewrites words.
  ///
  /// Not the same question as [PatternAutomaton.rewritesWords], and the
  /// difference is load-bearing: a level hands its rewrite carrier *down*,
  /// so a level with no rewrites of its own still has to supply one when a
  /// level below it has them. Deciding this per level instead silently drops
  /// every non-standard break in the dictionary.
  final bool rewritesWords;
}

/// The replacement texts of a whole dictionary, in one buffer.
///
/// One pool per dictionary rather than one per level, because the matcher
/// hands a replacement found on one level to the bookkeeping of another: a
/// packed reference is only meaningful if every level resolves it against
/// the same bytes.
class ReplacementPool {
  Uint8List _bytes = Uint8List(64);
  int _fill = 0;

  /// The bytes every packed reference points into.
  Uint8List get bytes => _bytes;

  /// How many of them are in use.
  int get length => _fill;

  /// Copies `source[start..end)` in and returns its packed reference.
  int add(Uint8List source, int start, int end) {
    final size = end - start;
    if (_fill + size > _bytes.length) {
      var grown = _bytes.length * 2;
      while (grown < _fill + size) {
        grown *= 2;
      }
      _bytes = Uint8List(grown)..setRange(0, _fill, _bytes);
    }
    _bytes.setRange(_fill, _fill + size, source, start);
    final ref = PatternAutomaton.packReplacement(_fill, size);
    _fill += size;
    return ref;
  }

  /// Trims the buffer to what is actually in it. Called once, when the
  /// dictionary is fully parsed.
  void seal() {
    if (_bytes.length != _fill) {
      _bytes = _bytes.sublist(0, _fill);
    }
  }
}
