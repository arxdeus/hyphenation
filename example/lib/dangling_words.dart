/// Typographic post-processing that keeps short words from hanging at the end
/// of a line.
///
/// This is deliberately *not* part of `flutter_hyphen`: a hyphenation
/// dictionary only describes break points inside a word and never sees the
/// spaces between words, so the "no hanging prepositions" rule belongs to the
/// text, not to the breaker.
library;

import 'dart:typed_data';

/// Words that must not be left dangling at the end of a line.
///
/// A hyphenation dictionary cannot express this: `hyph_*.dic` patterns only
/// describe break points *inside* a word and never see the spaces between
/// words. The typographic rule "no hanging prepositions or conjunctions" is
/// therefore applied to the text itself, by gluing such a word to the next one
/// with a no-break space (U+00A0). `HyphenLineBreaker` never breaks there, so
/// the short word is carried down to the next line together with its noun.
const Set<String> kRussianDanglingWords = <String>{
  // Предлоги
  'в', 'во', 'без', 'до', 'для', 'за', 'из', 'из-за', 'из-под', 'к', 'ко',
  'на', 'над', 'о', 'об', 'обо', 'от', 'ото', 'по', 'под', 'подо', 'перед',
  'при', 'про', 'ради', 'с', 'со', 'у', 'через', 'сквозь', 'между', 'кроме',
  'около', 'после', 'среди', 'вместо', 'вопреки', 'благодаря', 'несмотря',
  // Союзы и частицы
  'а', 'и', 'но', 'да', 'или', 'либо', 'ни', 'что', 'чтобы', 'как', 'если',
  'хотя', 'чем', 'то', 'же', 'ли', 'не', 'бы',
};

const int _kSpace = 0x20;
const int _kTab = 0x09;
const int _kNewline = 0x0A;
const int _kNoBreakSpace = 0x00A0;

/// Replaces the space after every word from [words] with a no-break space.
///
/// Also glues single-character words (initials, "я", digits) that are not in
/// the list, since those look just as bad hanging at a line end.
///
/// The implementation is allocation-free until it actually has to glue
/// something: it scans code units, never materialises a token, and returns
/// [text] itself when nothing changes. Gluing only ever swaps one space for
/// one no-break space, so the result is exactly as long as [text] and is
/// produced by patching a single copy of it rather than by concatenation.
/// See `benchmark/dangling_words_benchmark.dart` for the numbers and for the
/// naive version this replaced.
String preventDanglingWords(
  String text, {
  Set<String> words = kRussianDanglingWords,
}) {
  final matcher = _matcherFor(words);
  final length = text.length;

  // Output is built lazily: while `out` is null the answer is still `text`
  // itself. The first glue copies the whole input once, after which every
  // further glue is a single store.
  Uint16List? out;

  var index = 0;
  var atWordStart = true;
  while (index < length) {
    final unit = text.codeUnitAt(index);
    if (unit == _kSpace || unit == _kTab || unit == _kNewline) {
      atWordStart = true;
      index++;
      continue;
    }

    // A token is a run of anything that is not a plain space. Tabs and
    // newlines only separate tokens when they are reached at the top of the
    // loop, which matches the original behaviour.
    final start = index;
    do {
      index++;
    } while (index < length && text.codeUnitAt(index) != _kSpace);
    final tokenEnd = index;

    // The run of plain spaces right after the token is the candidate to
    // freeze; only a single space qualifies.
    final spaceStart = index;
    while (index < length && text.codeUnitAt(index) == _kSpace) {
      index++;
    }
    final spaceCount = index - spaceStart;

    if (atWordStart &&
        spaceCount == 1 &&
        matcher.matches(text, start, tokenEnd)) {
      (out ??= _copyOf(text))[spaceStart] = _kNoBreakSpace;
    }
    atWordStart = spaceCount != 0;
  }

  if (out == null) {
    return text;
  }
  return String.fromCharCodes(out);
}

/// Copies [text] into a mutable buffer.
///
/// `Uint16List.fromList(text.codeUnits)` reads through `CodeUnits`, a
/// `List<int>` view whose `[]` is a virtual call per character; the explicit
/// loop over `codeUnitAt` measured faster.
Uint16List _copyOf(String text) {
  final length = text.length;
  final units = Uint16List(length);
  for (var i = 0; i < length; i++) {
    units[i] = text.codeUnitAt(i);
  }
  return units;
}

/// Lowercases a single UTF-16 unit, or returns -1 when the general
/// [String.toLowerCase] has to be consulted instead.
///
/// Covers ASCII and the Cyrillic block that actually appears in the word list.
/// Every mapping here is one unit to one unit, which is what lets the caller
/// compare a folded token against a candidate without allocating.
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
    // А-Я.
    return unit + 0x20;
  }
  if (unit <= 0x45F) {
    // а-я, ё and friends: already lowercase.
    return unit;
  }
  return -1;
}

/// Letters, digits and the hyphen, so `«в` and `из-за` are still recognised.
bool _isWordUnit(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    (unit >= 0x0410 && unit <= 0x044F) ||
    unit == 0x0401 ||
    unit == 0x0451 ||
    unit == 0x2D;

/// A word list compiled into a form that can be probed without allocating.
///
/// The words are held in an open-addressed table rather than a [Map], so a
/// probe is an index into a [Int32List] instead of a hash-map lookup with its
/// boxed keys and bucket objects. A hit is confirmed by comparing code units,
/// so the result is exact rather than probabilistic.
class _DanglingMatcher {
  factory _DanglingMatcher(Set<String> words) {
    // Words that are not already lowercase can never be reached, because the
    // lookup key is a lowercased token. Words holding a unit this file cannot
    // fold are reachable, but only through the slow path, which consults the
    // original set.
    final entries = <String>[];
    var maxLength = 0;
    for (final word in words) {
      final length = word.length;
      if (length == 0) {
        continue;
      }
      if (length > maxLength) {
        maxLength = length;
      }
      var foldable = true;
      for (var i = 0; i < length; i++) {
        final unit = word.codeUnitAt(i);
        if (_fold(unit) != unit) {
          foldable = false;
          break;
        }
      }
      if (foldable) {
        entries.add(word);
      }
    }

    // A load factor of at most 1/4 keeps the probe chains at one or two slots,
    // and the table is tiny: 64 entries of 4 bytes for the bundled list.
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

    return _DanglingMatcher._(
      words,
      maxLength,
      entries,
      slots,
      mask,
      Uint16List(maxLength),
    );
  }

  _DanglingMatcher._(
    this.words,
    this.maxLength,
    this._entries,
    this._slots,
    this._mask,
    this._folded,
  );

  /// The original list, used when a token contains a unit [_fold] cannot map.
  final Set<String> words;

  /// Longest entry, used to reject ordinary long words with one comparison.
  final int maxLength;

  /// The reachable words, indexed by the value stored in [_slots] minus one.
  final List<String> _entries;

  /// Open-addressed table: slot -> index into [_entries] plus one, 0 = empty.
  final Int32List _slots;

  /// `_slots.length - 1`, for wrapping a hash into a slot.
  final int _mask;

  /// Scratch space holding the folded token, so verification does not fold a
  /// second time. Reused across calls; this code is synchronous throughout.
  final Uint16List _folded;

  static int _hashOf(String word) {
    var hash = 0;
    for (var i = 0; i < word.length; i++) {
      hash = (hash * 31 + word.codeUnitAt(i)) & 0x3FFFFFFF;
    }
    return hash;
  }

  /// Whether `text[start..end)` should be glued to what follows.
  ///
  /// True when the token is made of word units end to end and is either a
  /// single character or a listed word.
  bool matches(String text, int start, int end) {
    final length = end - start;
    // The overwhelmingly common case: an ordinary word, longer than anything
    // in the list and not a lone character. Rejected before touching the text.
    if (length > maxLength && length != 1) {
      return false;
    }
    if (!_isWordUnit(text.codeUnitAt(start))) {
      return false;
    }
    if (length == 1) {
      return true;
    }
    if (!_isWordUnit(text.codeUnitAt(end - 1))) {
      return false;
    }

    // Fold once, into the scratch buffer, hashing as we go.
    final folded = _folded;
    var hash = 0;
    for (var i = 0; i < length; i++) {
      final unit = _fold(text.codeUnitAt(start + i));
      if (unit < 0) {
        return words.contains(text.substring(start, end).toLowerCase());
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
}
// Callers pass the same const set on every call, so a one-entry cache keyed by
// identity removes the compilation from the hot path entirely.
Set<String>? _cachedWords;
_DanglingMatcher? _cachedMatcher;

_DanglingMatcher _matcherFor(Set<String> words) {
  final cached = _cachedMatcher;
  if (cached != null && identical(words, _cachedWords)) {
    return cached;
  }
  final matcher = _DanglingMatcher(words);
  _cachedWords = words;
  _cachedMatcher = matcher;
  return matcher;
}
