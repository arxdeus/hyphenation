// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hyphen/src/cache/lru_cache.dart';
import 'package:flutter_hyphen/src/model/hyphenation_dictionary.dart';
import 'package:flutter_hyphen/src/processor/dangling_words.dart';
import 'package:flutter_hyphen/src/processor/word_break_processor.dart';
import 'package:meta/meta.dart';

/// The Unicode soft hyphen (`U+00AD`).
///
/// A soft hyphen is an invisible character that marks a place where a word may
/// be broken. Flutter's text engine treats it as a break opportunity but never
/// paints a hyphen glyph there, which is why this package performs its own
/// line breaking.
const String kSoftHyphen = '\u00AD';

/// Splits words into their hyphenation parts using a the legacy engine
/// dictionary.
///
/// A [Hyphenator] is cheap to keep around and caches every word it has already
/// seen, so the same instance should be shared by the whole application. Use
/// [Hyphenator.fromAsset] to build one from a bundled `hyph_*.dic` file.
///
/// ### Example
/// ```dart
/// final hyphenator = await Hyphenator.fromAsset(
///   'assets/dictionary/hyph_en_US.dic',
/// );
/// hyphenator.split('hyphenation'); // [hy, phen, ation]
/// ```
class Hyphenator {
  /// Creates a hyphenator around an already parsed dictionary.
  Hyphenator(
    this.dictionary, {
    this.leftMin = 2,
    this.rightMin = 2,
    this.minWordLength = 5,
    this.maxCacheSize = 5000,
    int? maxParagraphCacheSize,
    Iterable<String> danglingWords = const <String>[],
  }) : danglingWords = DanglingWords.compile(danglingWords),
       maxParagraphCacheSize =
           maxParagraphCacheSize ??
           (maxCacheSize == 0 ? 0 : kDefaultParagraphCacheSize),
       assert(leftMin >= 1, 'leftMin must be at least 1'),
       assert(rightMin >= 1, 'rightMin must be at least 1'),
       assert(minWordLength >= 1, 'minWordLength must be at least 1'),
       assert(maxCacheSize >= 0, 'maxCacheSize must not be negative'),
       assert(
         maxParagraphCacheSize == null || maxParagraphCacheSize >= 0,
         'maxParagraphCacheSize must not be negative',
       );

  /// Default for [maxParagraphCacheSize].
  ///
  /// Paragraph-sized entries are three orders of magnitude larger than word
  /// entries, so they get their own, much smaller bound: a few hundred covers
  /// a screenful of paragraphs at several widths, which is what the cache is
  /// for, while keeping the whole thing well under a megabyte.
  static const int kDefaultParagraphCacheSize = 200;

  /// Loads a dictionary from the asset bundle.
  ///
  /// [path] is the asset key of a the legacy engine `.dic` file, for example
  /// `assets/dictionary/hyph_en_US.dic`.
  static Future<Hyphenator> fromAsset(
    String path, {
    AssetBundle? bundle,
    int leftMin = 2,
    int rightMin = 2,
    int minWordLength = 5,
    int maxCacheSize = 5000,
    int? maxParagraphCacheSize,
    Iterable<String> danglingWords = const <String>[],
  }) async {
    final data = await (bundle ?? rootBundle).load(path);
    return Hyphenator.fromBytes(
      data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ),
      leftMin: leftMin,
      rightMin: rightMin,
      minWordLength: minWordLength,
      maxCacheSize: maxCacheSize,
      maxParagraphCacheSize: maxParagraphCacheSize,
      danglingWords: danglingWords,
    );
  }

  /// Loads a dictionary from the raw bytes of a `.dic` file.
  factory Hyphenator.fromBytes(
    List<int> bytes, {
    int leftMin = 2,
    int rightMin = 2,
    int minWordLength = 5,
    int maxCacheSize = 5000,
    int? maxParagraphCacheSize,
    Iterable<String> danglingWords = const <String>[],
  }) => Hyphenator(
    HyphenationDictionary.parse(bytes),
    leftMin: leftMin,
    rightMin: rightMin,
    minWordLength: minWordLength,
    maxCacheSize: maxCacheSize,
    maxParagraphCacheSize: maxParagraphCacheSize,
    danglingWords: danglingWords,
  );

  /// The dictionary this hyphenator looks words up in.
  ///
  /// Shareable: several [Hyphenator]s with different settings may sit on one
  /// dictionary, which is what keeps a second configuration from costing a
  /// second parse.
  final HyphenationDictionary dictionary;

  /// Words that must never be left hanging at the end of a line, or `null`
  /// when the feature is off.
  ///
  /// [HyphenLineBreaker] drops the break opportunity after such a word, so it
  /// is carried down to the next line together with the word it belongs to.
  /// Nothing is inserted into the text: the string that gets painted is the
  /// one that was passed in.
  final DanglingWords? danglingWords;

  /// The minimum number of characters that must stay on the line before a
  /// break. Dictionaries carry their own values; this is an extra floor.
  final int leftMin;

  /// The minimum number of characters that must move to the next line.
  final int rightMin;

  /// Words shorter than this are never hyphenated.
  final int minWordLength;

  /// How many words to keep in the memoisation cache. Set to `0` to disable
  /// caching.
  ///
  /// Word entries are small (a short string and a handful of ints), so this
  /// can be generous. Paragraph-sized results are bounded separately by
  /// [maxParagraphCacheSize].
  final int maxCacheSize;

  /// How many paragraph-sized results to keep, for both [hyphenate] and the
  /// broken-line cache behind [cachedBreak].
  ///
  /// Each entry holds a whole paragraph, and its key holds the source text and
  /// the style, so these are roughly a thousand times larger than a word
  /// entry. Defaults to [kDefaultParagraphCacheSize], or to `0` when
  /// [maxCacheSize] is `0`.
  final int maxParagraphCacheSize;

  /// Word offsets, kept in a plain map with oldest-first eviction rather than
  /// in an [LruCache].
  ///
  /// This is the hottest and cheapest lookup in the package: a hit costs
  /// around 16 ns, and moving the entry to the end of an LRU on every hit
  /// measured over three times that. It is not worth it here. Recency matters
  /// much less for words than for paragraphs, because the bound is large
  /// enough to hold a realistic vocabulary and a miss only costs a few
  /// microseconds, against the hundreds a paragraph miss costs.
  /// Where the offsets come from before the caches see them.
  late final WordBreakProcessor _breaks = WordBreakProcessor(
    dictionary: dictionary,
    leftMin: leftMin,
    rightMin: rightMin,
    minWordLength: minWordLength,
  );

  final Map<String, List<int>> _cache = <String, List<int>>{};

  /// Memoised results of [hyphenate], keyed by the input text.
  ///
  /// Every paragraph marks its whole text before it can be laid out, and a
  /// screen often shows the same string more than once (a rebuilt list, a
  /// repeated label). Keeping the marked form here means the work is done once
  /// per distinct string per app, not once per widget.
  late final LruCache<String, String> _markedCache = LruCache<String, String>(
    maxParagraphCacheSize,
  );

  /// Memoised broken paragraphs, shared by every widget using this
  /// dictionary.
  ///
  /// A screen frequently lays the same string out at the same width more than
  /// once: a rebuilt list, a repeated label, two widgets in equal columns.
  /// Each of those otherwise repeats the whole break from scratch, because the
  /// per-render-object cache cannot see across widgets. The key has to cover
  /// everything that changes the answer, which the caller supplies; it is
  /// compared with `==`, so a record of the inputs is a good key.
  late final LruCache<Object, String> _brokenCache = LruCache<Object, String>(
    maxParagraphCacheSize,
  );

  /// Returns the cached broken form for [key], or null.
  ///
  /// Public only so [RenderHyphenParagraph] can reach the cache that has to
  /// live on the shared hyphenator rather than on a render object; two
  /// identical paragraphs must be able to see each other's work.
  @internal
  String? cachedBreak(Object key) => _brokenCache[key];

  /// Records [value] as the broken form for [key].
  ///
  /// See [cachedBreak] for why this is not private.
  @internal
  void cacheBreak(Object key, String value) => _brokenCache[key] = value;

  /// How many entries each cache currently holds, for tests and diagnostics.
  @visibleForTesting
  (int words, int marked, int broken) get cacheCounts =>
      (_cache.length, _markedCache.length, _brokenCache.length);

  /// Returns the offsets inside [word] at which a hyphen may be inserted.
  ///
  /// Offsets are UTF-16 code unit indices, strictly between `0` and
  /// `word.length`, in ascending order. A break at offset `i` means the text
  /// may be rendered as `word.substring(0, i)` + a hyphen, then
  /// `word.substring(i)`.
  ///
  /// [word] may contain punctuation; only its letter runs are looked up in the
  /// dictionary. Existing hard hyphens and [kSoftHyphen] characters always
  /// yield a break opportunity.
  List<int> breakOffsets(String word) {
    if (word.isEmpty) {
      return const <int>[];
    }
    final cached = _cache[word];
    if (cached != null) {
      return cached;
    }
    final computed = _breaks.computeOffsets(word);
    // Most words in running text have no break at all (too short, or the
    // dictionary finds nothing). Handing back the shared empty list saves two
    // allocations per word: the growable list and the unmodifiable copy.
    final result = computed.isEmpty
        ? const <int>[]
        : List<int>.unmodifiable(computed);
    if (maxCacheSize > 0) {
      if (_cache.length >= maxCacheSize) {
        _cache.remove(_cache.keys.first);
      }
      _cache[word] = result;
    }
    return result;
  }

  /// Splits [word] into the chunks between its hyphenation points.
  ///
  /// ```dart
  /// hyphenator.split('hyphenation'); // [hy, phen, ation]
  /// ```
  List<String> split(String word) {
    final offsets = breakOffsets(word);
    if (offsets.isEmpty) {
      return <String>[word];
    }
    final parts = <String>[];
    var previous = 0;
    for (final offset in offsets) {
      parts.add(word.substring(previous, offset));
      previous = offset;
    }
    parts.add(word.substring(previous));
    return parts;
  }

  /// Returns [text] with [separator] inserted at every hyphenation point.
  ///
  /// The default separator is [kSoftHyphen], which makes the result render
  /// identically to the input while giving the text engine extra break
  /// opportunities.
  String hyphenate(String text, {String separator = kSoftHyphen}) {
    final isDefaultSeparator =
        identical(separator, kSoftHyphen) || separator == kSoftHyphen;
    if (isDefaultSeparator) {
      final cached = _markedCache[text];
      if (cached != null) {
        return cached;
      }
    }

    final buffer = StringBuffer();
    _forEachToken(text, (token) {
      if (_isSeparatorRun(token)) {
        buffer.write(token);
        return;
      }
      // Written straight from the offsets rather than via `split`, which would
      // allocate a list of substrings for every word. This runs on every
      // paragraph, so the allocations are worth avoiding.
      final offsets = breakOffsets(token);
      if (offsets.isEmpty) {
        buffer.write(token);
        return;
      }
      var previous = 0;
      for (final offset in offsets) {
        buffer
          ..write(token.substring(previous, offset))
          ..write(separator);
        previous = offset;
      }
      buffer.write(token.substring(previous));
    });
    final result = buffer.toString();
    if (isDefaultSeparator) {
      _markedCache[text] = result;
    }
    return result;
  }

  /// Whether this hyphenator would change how [text] is broken into lines.
  ///
  /// True when the dictionary can break at least one word, or when [text]
  /// contains a word from [danglingWords] that would be glued to its
  /// neighbour.
  ///
  /// This is what a paragraph needs to know before it commits to breaking
  /// lines itself, and it is far cheaper than [hyphenate]: it stops at the
  /// first hit and allocates nothing beyond the word it has to look up.
  ///
  /// The dangling-word half matters more than it looks: a paragraph of short
  /// words may well have no hyphenation point at all, and without it such a
  /// paragraph would be handed straight to the engine and silently ignore the
  /// word list.
  bool hasBreakOpportunity(String text) {
    final dangling = danglingWords;
    var start = 0;
    while (start < text.length) {
      final whitespace = _isWhitespace(text.codeUnitAt(start));
      var end = start + 1;
      while (end < text.length &&
          _isWhitespace(text.codeUnitAt(end)) == whitespace) {
        end++;
      }
      if (!whitespace) {
        // A dangling word only changes anything when something follows it on
        // the same line, so the last token of the text does not count.
        if (dangling != null &&
            end < text.length &&
            dangling.matches(text, start, end)) {
          return true;
        }
        if (breakOffsets(text.substring(start, end)).isNotEmpty) {
          return true;
        }
      }
      start = end;
    }
    return false;
  }

  /// Clears the memoisation caches.
  void clearCache() {
    _cache.clear();
    _markedCache.clear();
    _brokenCache.clear();
  }

  static bool _isSeparatorRun(String token) =>
      token.isNotEmpty && _isWhitespace(token.codeUnitAt(0));

  static bool _isWhitespace(int unit) =>
      unit == 0x20 ||
      unit == 0x09 ||
      unit == 0x0A ||
      unit == 0x0B ||
      unit == 0x0C ||
      unit == 0x0D ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x3000;

  static void _forEachToken(String text, void Function(String) visit) {
    var start = 0;
    while (start < text.length) {
      final whitespace = _isWhitespace(text.codeUnitAt(start));
      var end = start + 1;
      while (end < text.length &&
          _isWhitespace(text.codeUnitAt(end)) == whitespace) {
        end++;
      }
      visit(text.substring(start, end));
      start = end;
    }
  }
}
