/// The compiled form of a TeX pattern set, and the matcher that runs it.
///
/// Patterns are stored as a trie flattened into typed arrays, the same shape
/// the rest of this package uses for its hot data: a node is an index, not an
/// object, so walking the trie costs an array load rather than a pointer
/// chase through the heap.
///
/// ### Why a trie rather than a hash of every substring
/// Matching a word means asking, for every position, which patterns start
/// there. A trie answers that by walking forward from each position and
/// stopping the moment no pattern continues, which on real text is after two
/// or three characters. Hashing every substring instead would compute a hash
/// per candidate whether or not any pattern could match it.
///
/// ### Characters, not bytes
/// Patterns are matched over UTF-16 code units taken straight from the Dart
/// string. There is no encode step and no byte/character conversion pass,
/// because the priorities are claimed at character positions and that is
/// where the caller wants them.
library;

import 'dart:typed_data';

import 'package:flutter_hyphen/src/tex/tex_pattern_parser.dart';

/// A word boundary, in patterns and in the word being matched.
const int kBoundary = 0x2E; // '.'

/// Patterns compiled into a trie, ready to mark words.
class TexPatternTable {
  TexPatternTable._({
    required this.edgeStart,
    required this.edgeUnit,
    required this.edgeTarget,
    required this.tableBase,
    required this.tableEntries,
    required this.priorityAt,
    required this.priorityLength,
    required this.priorityBytes,
    required this.exceptions,
    required this.leftMin,
    required this.rightMin,
  });

  /// Where node `n`'s edges live in [edgeUnit] / [edgeTarget]:
  /// `[edgeStart[n], edgeStart[n + 1])`. Sorted by code unit, so a lookup is
  /// a binary search on a node with many children.
  final Int32List edgeStart;
  final Uint16List edgeUnit;
  final Int32List edgeTarget;

  /// Offset of a node's direct table in [tableEntries], or -1 when the node
  /// has few enough edges to be worth searching instead.
  ///
  /// A direct table turns the lookup into a single indexed load. It costs
  /// [kTableSpan] entries, so only nodes wide enough to pay for it get one:
  /// in a real pattern set that is the root and its busiest children, which
  /// between them absorb most of the lookups.
  final Int32List tableBase;
  final Int32List tableEntries;

  /// Where this node's priority vector starts in [priorityBytes], or -1 when
  /// no pattern ends here.
  final Int32List priorityAt;
  final Uint8List priorityLength;

  /// Priorities as small integers, not ASCII digits: they are compared and
  /// maximised, never printed.
  final Uint8List priorityBytes;

  /// Words the pattern file gives explicit breaks for, keyed lower case.
  final Map<String, List<int>> exceptions;

  /// The mins the pattern file declares, or the TeX defaults when it is
  /// silent. Kept here because they belong to the language, not the caller.
  final int leftMin;
  final int rightMin;

  /// Compiles [source] into a matcher.
  factory TexPatternTable.compile(
    TexPatternSource source, {
    int leftMin = 2,
    int rightMin = 3,
  }) {
    final builder = _TrieBuilder();
    for (final pattern in source.patterns) {
      final parsed = parsePattern(pattern);
      builder.insert(parsed.letters, parsed.priorities);
    }
    return builder.finish(
      exceptions: source.exceptions,
      leftMin: leftMin,
      rightMin: rightMin,
    );
  }

  /// The node [unit] leads to from [node], or -1.
  ///
  /// A direct table where the node has one, a binary search where it does
  /// not. This is the single hottest lookup in the package: it runs once per
  /// character of every pattern prefix tried, which is several times per
  /// character of every word.
  int edgeFrom(int node, int unit) {
    final base = tableBase[node];
    if (base >= 0) {
      if (unit >= kTableSpan) {
        return -1;
      }
      return tableEntries[base + unit];
    }
    var low = edgeStart[node];
    var high = edgeStart[node + 1] - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final at = edgeUnit[mid];
      if (at == unit) {
        return edgeTarget[mid];
      }
      if (at < unit) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return -1;
  }
}

/// How many code units a direct table covers.
///
/// Patterns are letters and the boundary dot, which in every Latin-script
/// pattern file live below 128. A wider table would cover the occasional
/// accented letter too, but those sit in nodes far too narrow to be given a
/// table at all.
const int kTableSpan = 128;

/// How many edges a node needs before a direct table is worth its memory.
///
/// Below this a binary search is two or three steps, which is cheaper than
/// the cache miss a sparse table would cost.
const int kTableThreshold = 12;

/// Grows a trie one pattern at a time, then freezes it into typed arrays.
///
/// Nodes are held in growable lists while building because the final size is
/// not known until the last pattern is read. None of this survives
/// [finish]; the matcher never sees an object.
class _TrieBuilder {
  final List<Map<int, int>> _edges = <Map<int, int>>[<int, int>{}];
  final List<Uint8List?> _priorities = <Uint8List?>[null];

  void insert(Uint16List letters, Uint8List priorities) {
    var node = 0;
    for (final unit in letters) {
      final edges = _edges[node];
      var next = edges[unit];
      if (next == null) {
        next = _edges.length;
        _edges.add(<int, int>{});
        _priorities.add(null);
        edges[unit] = next;
      }
      node = next;
    }

    // Trailing zeroes carry no information and every pattern has some, so
    // dropping them shrinks the priority blob substantially.
    var length = priorities.length;
    while (length > 0 && priorities[length - 1] == 0) {
      length--;
    }
    _priorities[node] = Uint8List.sublistView(priorities, 0, length);
  }

  TexPatternTable finish({
    required Map<String, List<int>> exceptions,
    required int leftMin,
    required int rightMin,
  }) {
    final nodeCount = _edges.length;
    final edgeStart = Int32List(nodeCount + 1);
    var edgeCount = 0;
    for (var node = 0; node < nodeCount; node++) {
      edgeStart[node] = edgeCount;
      edgeCount += _edges[node].length;
    }
    edgeStart[nodeCount] = edgeCount;

    final edgeUnit = Uint16List(edgeCount);
    final edgeTarget = Int32List(edgeCount);
    final priorityAt = Int32List(nodeCount)..fillRange(0, nodeCount, -1);
    final priorityLength = Uint8List(nodeCount);
    final priorityBlob = <int>[];
    final tableBase = Int32List(nodeCount)..fillRange(0, nodeCount, -1);

    // Lay the direct tables out before filling anything, so their storage is
    // one allocation rather than one per node.
    var tableCount = 0;
    for (var node = 0; node < nodeCount; node++) {
      if (_edges[node].length >= kTableThreshold) {
        tableBase[node] = tableCount * kTableSpan;
        tableCount++;
      }
    }
    final tableEntries = Int32List(tableCount * kTableSpan)
      ..fillRange(0, tableCount * kTableSpan, -1);

    for (var node = 0; node < nodeCount; node++) {
      // Sorted so the matcher can binary search.
      final units = _edges[node].keys.toList(growable: false)..sort();
      var at = edgeStart[node];
      final base = tableBase[node];
      for (final unit in units) {
        final target = _edges[node][unit]!;
        edgeUnit[at] = unit;
        edgeTarget[at] = target;
        if (base >= 0 && unit < kTableSpan) {
          tableEntries[base + unit] = target;
        }
        at++;
      }

      final priorities = _priorities[node];
      if (priorities != null && priorities.isNotEmpty) {
        priorityAt[node] = priorityBlob.length;
        priorityLength[node] = priorities.length;
        priorityBlob.addAll(priorities);
      }
    }

    return TexPatternTable._(
      edgeStart: edgeStart,
      edgeUnit: edgeUnit,
      edgeTarget: edgeTarget,
      tableBase: tableBase,
      tableEntries: tableEntries,
      priorityAt: priorityAt,
      priorityLength: priorityLength,
      priorityBytes: Uint8List.fromList(priorityBlob),
      exceptions: exceptions,
      leftMin: leftMin,
      rightMin: rightMin,
    );
  }
}
