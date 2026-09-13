// The compiled form of a TeX pattern set, and the matcher that runs it.
//
// Patterns are stored as a trie flattened into typed arrays, the same shape
// the rest of this package uses for its hot data: a node is an index, not an
// object, so walking the trie costs an array load rather than a pointer
// chase through the heap.
//
// ### Why a trie rather than a hash of every substring
// Matching a word means asking, for every position, which patterns start
// there. A trie answers that by walking forward from each position and
// stopping the moment no pattern continues, which on real text is after two
// or three characters. Hashing every substring instead would compute a hash
// per candidate whether or not any pattern could match it.
//
// ### Characters, not bytes
// Patterns are matched over UTF-16 code units taken straight from the Dart
// string. There is no encode step and no byte/character conversion pass,
// because the priorities are claimed at character positions and that is
// where the caller wants them.

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
    required this.tableFirst,
    required this.tableSpan,
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
  /// A direct table turns the lookup into a single indexed load. Only nodes
  /// wide enough to pay for the storage get one: in a real pattern set that
  /// is the root and its busiest children, which between them absorb most of
  /// the lookups.
  final Int32List tableBase;

  /// The lowest code unit a node's table covers; its entry sits at
  /// `tableBase[node]`. [tableSpan] says how many units follow it.
  ///
  /// Tables are keyed on the node's own range rather than a fixed window
  /// starting at zero. A node's children are letters of one script and sit
  /// close together, so the range is short even when the units themselves
  /// are large — and a fixed window would silently miss every unit above it,
  /// which is every accented letter in Latin scripts and every letter in
  /// Cyrillic and Greek.
  final Int32List tableFirst;

  /// How many code units each node's table covers.
  final Int32List tableSpan;

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
      // Unsigned compare: one branch rejects both a unit below the range and
      // one above it, because a negative offset reinterprets as huge.
      final offset = unit - tableFirst[node];
      final span = tableSpan[node];
      return offset.toUnsigned(32) < span ? tableEntries[base + offset] : -1;
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

/// How many edges a node needs before a direct table is worth its memory.
///
/// Below this a binary search is two or three steps, which is cheaper than
/// the cache miss a sparse table would cost.
const int kTableThreshold = 12;

/// How sparse a node's table may be before it is not worth building.
///
/// A node whose edges are `a`, `z` and one accented letter spans a hundred
/// entries to hold three. Past this ratio the search is cheaper than the
/// cache footprint.
const int kMaxTableSparsity = 4;

/// Grows a trie one pattern at a time, then freezes it into typed arrays.
///
/// Nodes are numbers in growable typed arrays, not objects: a pattern file
/// makes tens of thousands of them on an app's startup path, and a `Map` per
/// node costs an allocation, a hash per lookup and a rehash per growth.
///
/// Each node's edges are a singly linked list threaded through [_edgeNext],
/// newest first. Insertion is a push, and the lists are short — half of all
/// nodes are leaves and the mean degree is barely above one — so the scan
/// that looks an edge up beats hashing it. [finish] sorts them into
/// contiguous rows.
class _TrieBuilder {
  /// The first edge leaving each node, or -1.
  Int32List _nodeFirstEdge = Int32List(1024)..[0] = -1;
  int _nodeCount = 1;

  /// Edge fields, parallel: which unit it consumes, which node it reaches,
  /// and the next edge out of the same node.
  Uint16List _edgeUnit = Uint16List(1024);
  Int32List _edgeTarget = Int32List(1024);
  Int32List _edgeNext = Int32List(1024);
  int _edgeCount = 0;

  /// Where each node's priorities start in [_priorityBlob], or -1, and how
  /// many there are.
  Int32List _priorityAt = Int32List(1024)..[0] = -1;
  Uint8List _priorityLength = Uint8List(1024);
  final BytesBuilder _priorityBlob = BytesBuilder(copy: false);
  int _priorityBlobLength = 0;

  void insert(Uint16List letters, Uint8List priorities) {
    var node = 0;
    for (final unit in letters) {
      var next = -1;
      for (var e = _nodeFirstEdge[node]; e >= 0; e = _edgeNext[e]) {
        if (_edgeUnit[e] == unit) {
          next = _edgeTarget[e];
          break;
        }
      }
      if (next < 0) {
        next = _addNode();
        _addEdge(node, unit, next);
      }
      node = next;
    }

    // Trailing zeroes carry no information and every pattern has some, so
    // dropping them shrinks the priority blob substantially.
    var length = priorities.length;
    while (length > 0 && priorities[length - 1] == 0) {
      length--;
    }
    if (length == 0) {
      _priorityAt[node] = -1;
      _priorityLength[node] = 0;
      return;
    }
    // A later pattern landing on a node an earlier one already reached
    // simply appends again; the older run is left orphaned in the blob,
    // which costs a few bytes and saves tracking every node's extent.
    _priorityAt[node] = _priorityBlobLength;
    _priorityLength[node] = length;
    _priorityBlob.add(Uint8List.sublistView(priorities, 0, length));
    _priorityBlobLength += length;
  }

  int _addNode() {
    if (_nodeCount == _nodeFirstEdge.length) {
      _nodeFirstEdge = _grownInt32(_nodeFirstEdge);
      _priorityAt = _grownInt32(_priorityAt);
      _priorityLength = _grownUint8(_priorityLength);
    }
    _nodeFirstEdge[_nodeCount] = -1;
    _priorityAt[_nodeCount] = -1;
    _priorityLength[_nodeCount] = 0;
    return _nodeCount++;
  }

  void _addEdge(int from, int unit, int to) {
    if (_edgeCount == _edgeUnit.length) {
      _edgeUnit = _grownUint16(_edgeUnit);
      _edgeTarget = _grownInt32(_edgeTarget);
      _edgeNext = _grownInt32(_edgeNext);
    }
    _edgeUnit[_edgeCount] = unit;
    _edgeTarget[_edgeCount] = to;
    _edgeNext[_edgeCount] = _nodeFirstEdge[from];
    _nodeFirstEdge[from] = _edgeCount;
    _edgeCount++;
  }

  /// Sorts `[from, to)` of a row by code unit, carrying the targets along.
  ///
  /// Insertion sort because rows are tiny: the mean degree of a real pattern
  /// trie is barely above one, and the widest node in English has 27 edges.
  /// A comparison sort with a closure would allocate per row.
  static void _sortRow(Uint16List units, Int32List targets, int from, int to) {
    for (var i = from + 1; i < to; i++) {
      final unit = units[i];
      final target = targets[i];
      var j = i - 1;
      while (j >= from && units[j] > unit) {
        units[j + 1] = units[j];
        targets[j + 1] = targets[j];
        j--;
      }
      units[j + 1] = unit;
      targets[j + 1] = target;
    }
  }

  static Int32List _grownInt32(Int32List from) =>
      Int32List(from.length * 2)..setRange(0, from.length, from);

  static Uint16List _grownUint16(Uint16List from) =>
      Uint16List(from.length * 2)..setRange(0, from.length, from);

  static Uint8List _grownUint8(Uint8List from) =>
      Uint8List(from.length * 2)..setRange(0, from.length, from);

  TexPatternTable finish({
    required Map<String, List<int>> exceptions,
    required int leftMin,
    required int rightMin,
  }) {
    final nodeCount = _nodeCount;
    final edgeCount = _edgeCount;

    // Row starts, by counting each node's edges off its linked list.
    final edgeStart = Int32List(nodeCount + 1);
    for (var node = 0; node < nodeCount; node++) {
      var degree = 0;
      for (var e = _nodeFirstEdge[node]; e >= 0; e = _edgeNext[e]) {
        degree++;
      }
      edgeStart[node + 1] = degree;
    }
    for (var node = 0; node < nodeCount; node++) {
      edgeStart[node + 1] += edgeStart[node];
    }

    final edgeUnit = Uint16List(edgeCount);
    final edgeTarget = Int32List(edgeCount);
    final tableBase = Int32List(nodeCount)..fillRange(0, nodeCount, -1);
    final tableFirst = Int32List(nodeCount);
    final tableSpan = Int32List(nodeCount);

    // Lay each node's edges into its row, then sort the row by code unit so
    // the matcher can binary search it. The lists are threaded newest first,
    // so this also undoes the reversal.
    for (var node = 0; node < nodeCount; node++) {
      var at = edgeStart[node];
      for (var e = _nodeFirstEdge[node]; e >= 0; e = _edgeNext[e]) {
        edgeUnit[at] = _edgeUnit[e];
        edgeTarget[at] = _edgeTarget[e];
        at++;
      }
      _sortRow(edgeUnit, edgeTarget, edgeStart[node], at);
    }

    // Decide which nodes get a table, and how wide each one has to be, before
    // filling anything: the storage is then one allocation rather than one
    // per node.
    //
    // A table covers exactly the node's own span of code units. That is what
    // makes it correct for scripts above ASCII, and it is usually *smaller*
    // than a fixed window would be, because a node's children are letters of
    // one alphabet and sit close together.
    var tableLength = 0;
    for (var node = 0; node < nodeCount; node++) {
      final from = edgeStart[node];
      final degree = edgeStart[node + 1] - from;
      if (degree < kTableThreshold) {
        continue;
      }
      // The row is sorted, so its range is its two ends.
      final lowest = edgeUnit[from];
      final span = edgeUnit[from + degree - 1] - lowest + 1;
      // A node spread thinly across a wide range would spend more on holes
      // than the search costs.
      if (span > degree * kMaxTableSparsity) {
        continue;
      }
      tableBase[node] = tableLength;
      tableFirst[node] = lowest;
      tableSpan[node] = span;
      tableLength += span;
    }

    final tableEntries = Int32List(tableLength)..fillRange(0, tableLength, -1);
    for (var node = 0; node < nodeCount; node++) {
      final base = tableBase[node];
      if (base < 0) {
        continue;
      }
      final first = tableFirst[node];
      final end = edgeStart[node + 1];
      for (var e = edgeStart[node]; e < end; e++) {
        tableEntries[base + edgeUnit[e] - first] = edgeTarget[e];
      }
    }

    return TexPatternTable._(
      edgeStart: edgeStart,
      edgeUnit: edgeUnit,
      edgeTarget: edgeTarget,
      tableBase: tableBase,
      tableFirst: tableFirst,
      tableSpan: tableSpan,
      tableEntries: tableEntries,
      // Copied rather than viewed: a sublist view carries an offset the JIT
      // has to add on every load, and these two are read once per matched
      // node. The copy happens once per pattern file.
      priorityAt: Int32List(nodeCount)..setRange(0, nodeCount, _priorityAt),
      priorityLength: Uint8List(nodeCount)
        ..setRange(0, nodeCount, _priorityLength),
      priorityBytes: _priorityBlob.takeBytes(),
      exceptions: exceptions,
      leftMin: leftMin,
      rightMin: rightMin,
    );
  }
}
