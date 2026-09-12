import 'dart:typed_data';

import 'package:flutter_hyphen/src/constant/dangling_word_defaults.dart';
import 'package:flutter_hyphen/src/util/code_units.dart';

/// A word list compiled into a form that can be probed without allocating.
///
/// [HyphenLineBreaker] asks this, once per word of every line it breaks,
/// whether a word must be carried down to the next line together with the word
/// that follows it. That is a hot path, so the list is not consulted as a
/// [Set] of strings: probing one would mean building a substring per word and
/// lowercasing it, which is two allocations per word thrown away immediately.
///
/// Instead the words are held in an open-addressed table indexed by a hash
/// computed over the input in place, and a hit is confirmed by comparing code
/// units. The probe is therefore exact rather than probabilistic, and costs no
/// allocation at all. See `benchmark/dangling_words_benchmark.dart`.
class DanglingWords {
  /// Compiles [words] into a probe table.
  ///
  /// Matching is case-insensitive, so entries should be lowercase; an entry
  /// that is not is unreachable and is dropped.
  factory DanglingWords(Iterable<String> words) {
    // Only lowercase entries are reachable, because the lookup key is a
    // lowercased token. Entries holding a unit this library cannot fold are
    // reachable, but only through the slow path, which consults [source].
    final source = <String>{
      for (final word in words)
        if (word.isNotEmpty) word,
    };
    final entries = <String>[];
    var maxLength = 0;
    var hasUnfoldable = false;
    for (final word in source) {
      final length = word.length;
      if (length > maxLength) {
        maxLength = length;
      }
      var foldable = true;
      for (var i = 0; i < length; i++) {
        final unit = word.codeUnitAt(i);
        final folded = _fold(unit);
        if (folded < 0) {
          hasUnfoldable = true;
          foldable = false;
          break;
        }
        if (folded != unit) {
          // Not lowercase, therefore unreachable.
          foldable = false;
          break;
        }
      }
      if (foldable) {
        entries.add(word);
      }
    }

    // A load factor of at most 1/4 keeps the probe chains at one or two slots,
    // and the table is tiny: 256 slots of four bytes for the bundled list.
    var capacity = 8;
    while (capacity < entries.length * 4) {
      capacity *= 2;
    }
    final slots = Int32List(capacity);
    final mask = capacity - 1;
    for (var i = 0; i < entries.length; i++) {
      var slot = _hashOf(entries[i]) & mask;
      while (slots[slot] != 0) {
        slot = (slot + 1) & mask;
      }
      // Zero means empty, so entries are stored one-based.
      slots[slot] = i + 1;
    }

    return DanglingWords._(
      source,
      maxLength,
      hasUnfoldable,
      entries,
      slots,
      mask,
      Uint16List(maxLength),
    );
  }

  DanglingWords._(
    this.source,
    this.maxLength,
    this._hasUnfoldable,
    this._entries,
    this._slots,
    this._mask,
    this._folded,
  );

  /// Compiles [words], or returns `null` when there is nothing to compile.
  ///
  /// `null` is how the rest of the package spells "the feature is off", so an
  /// empty or absent list costs a single null check per line.
  static DanglingWords? compile(Iterable<String> words) {
    if (words.isEmpty) {
      return null;
    }
    final compiled = DanglingWords(words);
    return compiled.source.isEmpty ? null : compiled;
  }

  /// The bundled English list, compiled once.
  static final DanglingWords english = DanglingWords(kEnglishDanglingWords);

  /// The words as given, used when a token contains a unit [_fold] cannot map.
  final Set<String> source;

  /// Longest entry, used to reject ordinary words with one comparison.
  final int maxLength;

  /// Whether any entry needs the general [String.toLowerCase] to be matched.
  final bool _hasUnfoldable;

  /// The reachable words, indexed by the value stored in [_slots] minus one.
  final List<String> _entries;

  /// Open-addressed table: slot to index into [_entries] plus one, 0 is empty.
  final Int32List _slots;

  /// `_slots.length - 1`, for wrapping a hash into a slot.
  final int _mask;

  /// Scratch space holding the folded token, so a confirmed hit does not fold
  /// it a second time. Reused across calls; this code is synchronous
  /// throughout and never escapes the buffer.
  final Uint16List _folded;

  /// How many words the list holds.
  int get length => source.length;

  /// Whether [word] would be glued to the word that follows it.
  bool contains(String word) => matches(word, 0, word.length);

  /// Whether the token `content[start..end)` must be glued to the next word.
  ///
  /// [start] and [end] delimit a whitespace-separated token, which may carry
  /// punctuation. Leading punctuation is ignored, so `"the` still matches: an
  /// opening quote belongs with the word that follows it. Trailing punctuation
  /// is not, so `the,` does not match: the comma ends the clause, and the word
  /// is no longer dangling.
  bool matches(String content, int start, int end) {
    if (end <= start) {
      return false;
    }
    // Trailing punctuation means the phrase ended here.
    if (!isDanglingWordUnit(content.codeUnitAt(end - 1))) {
      return false;
    }
    // Leading punctuation («, „, (, —) belongs with the word.
    var from = start;
    while (from < end && !isDanglingWordUnit(content.codeUnitAt(from))) {
      from++;
    }
    final length = end - from;
    // The common case: an ordinary word, longer than anything in the list.
    // Rejected before reading a single character of it.
    if (length == 0 || length > maxLength) {
      return false;
    }

    // Fold once, into the scratch buffer, hashing as we go.
    final folded = _folded;
    var hash = 0;
    for (var i = 0; i < length; i++) {
      final unit = _fold(content.codeUnitAt(from + i));
      if (unit < 0) {
        // A script this library does not fold. Rare, and only reachable when
        // the list itself contains such a word.
        return _hasUnfoldable &&
            source.contains(content.substring(from, end).toLowerCase());
      }
      folded[i] = unit;
      hash = (hash * 31 + unit) & 0x3FFFFFFF;
    }

    var slot = hash & _mask;
    while (true) {
      final entry = _slots[slot];
      if (entry == 0) {
        return false;
      }
      final candidate = _entries[entry - 1];
      if (candidate.length == length) {
        var same = true;
        for (var i = 0; i < length; i++) {
          if (candidate.codeUnitAt(i) != folded[i]) {
            same = false;
            break;
          }
        }
        if (same) {
          return true;
        }
      }
      slot = (slot + 1) & _mask;
    }
  }

  static int _hashOf(String word) {
    var hash = 0;
    for (var i = 0; i < word.length; i++) {
      hash = (hash * 31 + word.codeUnitAt(i)) & 0x3FFFFFFF;
    }
    return hash;
  }

  @override
  String toString() => 'DanglingWords($length words)';
}

/// Lowercases a single UTF-16 unit, or returns -1 when the general
/// [String.toLowerCase] has to be consulted instead.
///
/// Covers ASCII and the Cyrillic block. Every mapping here is one unit to one
/// unit, which is what lets a caller compare a folded token against a
/// candidate without allocating; the general `toLowerCase` is not, so anything
/// it would handle differently is rejected here and sent down the slow path.
int _fold(int unit) {
  if (unit < 0x80) {
    return (unit >= 0x41 && unit <= 0x5A) ? unit + 0x20 : unit;
  }
  if (unit < 0x400) {
    return -1;
  }
  if (unit <= 0x40F) {
    // Ѐ-Џ, including Ё.
    return unit + 0x50;
  }
  if (unit <= 0x42F) {
    // U+0410-U+042F: the uppercase Cyrillic block.
    return unit + 0x20;
  }
  if (unit <= 0x45F) {
    // U+0430-U+045F: already lowercase.
    return unit;
  }
  return -1;
}
