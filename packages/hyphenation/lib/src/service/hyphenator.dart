import 'package:hyphenation/src/cache/lru_cache.dart';
import 'package:hyphenation/src/processor/dangling_words.dart';
import 'package:hyphenation/src/processor/word_break_processor.dart';
import 'package:hyphenation/src/tex/tex_hyphenation_patterns.dart';
import 'package:meta/meta.dart';

/// The Unicode soft hyphen (`U+00AD`).
///
/// A soft hyphen is an invisible character that marks a place where a word may
/// be broken. Flutter's text engine treats it as a break opportunity but never
/// paints a hyphen glyph there, which is why this package performs its own
/// line breaking.
const String kSoftHyphen = '\u00AD';

/// Splits words into their hyphenation parts using a TeX pattern set.
///
/// A [Hyphenator] is cheap to keep around and caches recently seen words, so
/// the same instance should be shared by the whole application. Use
/// [Hyphenator.fromSource] to build one from the text of a `hyph-*.tex` file.
///
/// ### Example
/// ```dart
/// final hyphenator = Hyphenator.fromSource(
///   await File('ushyph1.tex').readAsString(),
/// );
/// hyphenator.split('hyphenation'); // [hy, phen, ation]
/// ```
class Hyphenator {
  /// Creates a hyphenator around an already compiled pattern set.
  Hyphenator(
    this.patterns, {
    this.leftMin = 2,
    this.rightMin = 2,
    this.minWordLength = 5,
    this.maxCacheSize = 5000,
    int? maxParagraphCacheSize,
    this.maxParagraphCacheBytes = kDefaultParagraphCacheBytes,
    this.maxCachedWordLength = kDefaultMaxCachedWordLength,
    Iterable<String> danglingWords = const <String>[],
  }) : danglingWords = DanglingWords.compile(danglingWords),
       maxParagraphCacheSize =
           maxParagraphCacheSize ??
           (maxCacheSize == 0 ? 0 : kDefaultParagraphCacheSize),
       assert(maxParagraphCacheBytes >= 0),
       assert(maxCachedWordLength >= 0),
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
  /// for. [maxParagraphCacheBytes] separately bounds retained payload size.
  static const int kDefaultParagraphCacheSize = 200;

  /// Estimated retained bytes allowed in each shared paragraph cache.
  static const int kDefaultParagraphCacheBytes = 1024 * 1024;

  /// Long tokens are processed normally but not retained in the word cache.
  static const int kDefaultMaxCachedWordLength = 256;

  /// Compiles a hyphenator from the text of a TeX pattern file.
  factory Hyphenator.fromSource(
    String source, {
    int leftMin = 2,
    int rightMin = 2,
    int minWordLength = 5,
    int maxCacheSize = 5000,
    int? maxParagraphCacheSize,
    int maxParagraphCacheBytes = kDefaultParagraphCacheBytes,
    int maxCachedWordLength = kDefaultMaxCachedWordLength,
    Iterable<String> danglingWords = const <String>[],
  }) => Hyphenator(
    TexHyphenationPatterns.parse(source),
    leftMin: leftMin,
    rightMin: rightMin,
    minWordLength: minWordLength,
    maxCacheSize: maxCacheSize,
    maxParagraphCacheSize: maxParagraphCacheSize,
    maxParagraphCacheBytes: maxParagraphCacheBytes,
    maxCachedWordLength: maxCachedWordLength,
    danglingWords: danglingWords,
  );

  /// The pattern set this hyphenator looks words up in.
  ///
  /// Shareable: several [Hyphenator]s with different settings may sit on one
  /// pattern set, which is what keeps a second configuration from costing a
  /// second compile.
  final TexHyphenationPatterns patterns;

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

  /// Estimated retained-byte limit for each paragraph cache. Zero disables
  /// both. Estimates include UTF-16 source/output payloads and fixed entry
  /// overhead, not exact VM heap size or externally owned style objects.
  final int maxParagraphCacheBytes;

  /// Maximum UTF-16 length admitted to the FIFO word cache. Zero disables it.
  /// Longer tokens still produce the same offsets, without retaining them.
  final int maxCachedWordLength;

  int _wordEstimatedBytes = 0;

  static int _wordWeight(String word, List<int> offsets) =>
      64 + 2 * word.length + 8 * offsets.length;

  static int _paragraphWeight(int sourceLength, String value) =>
      128 + 2 * (sourceLength + value.length);

  /// Where word offsets come from before the caches see them.
  late final WordBreakProcessor _breaks = WordBreakProcessor(
    patterns: patterns,
    leftMin: leftMin,
    rightMin: rightMin,
    minWordLength: minWordLength,
  );

  /// Word offsets, kept in a plain map with oldest-first eviction rather than
  /// in an [LruCache].
  ///
  /// This is the hottest and cheapest lookup in the package: a hit costs
  /// around 16 ns, and moving the entry to the end of an LRU on every hit
  /// measured over three times that. It is not worth it here. Recency matters
  /// much less for words than for paragraphs, because the bound is large
  /// enough to hold a realistic vocabulary and a miss only costs a few
  /// microseconds, against the hundreds a paragraph miss costs.
  final Map<String, List<int>> _cache = <String, List<int>>{};

  /// Memoised results of [hyphenate], keyed by the input text.
  ///
  /// Every paragraph marks its whole text before it can be laid out, and a
  /// screen often shows the same string more than once (a rebuilt list, a
  /// repeated label). Keeping the marked form here means the work is done once
  /// per distinct string per app, not once per widget.
  late final LruCache<String, String> _markedCache = LruCache<String, String>(
    maxParagraphCacheSize,
    maxWeight: maxParagraphCacheBytes,
  );

  /// Memoised broken paragraphs, shared by every widget using this
  /// pattern set.
  ///
  /// A screen frequently lays the same string out at the same width more than
  /// once: a rebuilt list, a repeated label, two widgets in equal columns.
  /// Each of those otherwise repeats the whole break from scratch, because the
  /// per-render-object cache cannot see across widgets. The key has to cover
  /// everything that changes the answer, which the caller supplies; it is
  /// compared with `==`, so a record of the inputs is a good key.
  late final LruCache<Object, String> _brokenCache = LruCache<Object, String>(
    maxParagraphCacheSize,
    maxWeight: maxParagraphCacheBytes,
  );

  /// Returns the cached broken form for [key], or null.
  ///
  /// Public so a renderer (`RenderHyphenParagraph` in
  /// `package:flutter_hyphenation`) can reach the cache that has to live on the
  /// shared hyphenator rather than on a render object; two identical
  /// paragraphs must be able to see each other's work. Not part of the
  /// hyphenation API: the key is opaque and entirely the caller's business.
  String? cachedBreak(Object key) => _brokenCache[key];

  /// Records [value] as the broken form for [key].
  ///
  /// See [cachedBreak] for why this is not private.
  void cacheBreak(Object key, String value, {int? sourceLength}) {
    assert(sourceLength == null || sourceLength >= 0);
    _brokenCache.put(
      key,
      value,
      weight: _paragraphWeight(sourceLength ?? value.length, value),
    );
  }

  /// Estimated retained bytes, not exact VM heap measurements. Broken-cache
  /// callers should supply sourceLength to [cacheBreak] for accurate estimates.
  ({int words, int marked, int broken}) get cacheEstimatedBytes => (
    words: _wordEstimatedBytes,
    marked: _markedCache.estimatedWeight,
    broken: _brokenCache.estimatedWeight,
  );

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
  /// pattern set. Existing hard hyphens and [kSoftHyphen] characters always
  /// yield a break opportunity.
  List<int> breakOffsets(String word) {
    if (word.isEmpty) {
      return const <int>[];
    }
    final cacheable = maxCacheSize > 0 && word.length <= maxCachedWordLength;
    final cached = cacheable ? _cache[word] : null;
    if (cached != null) {
      return cached;
    }
    final computed = _breaks.computeOffsets(word);
    // Most words in running text have no break at all (too short, or the
    // pattern set finds nothing). Handing back the shared empty list saves two
    // allocations per word: the growable list and the unmodifiable copy.
    final result = computed.isEmpty
        ? const <int>[]
        : List<int>.unmodifiable(computed);
    if (cacheable) {
      if (_cache.length >= maxCacheSize) {
        final oldest = _cache.keys.first;
        _wordEstimatedBytes -= _wordWeight(oldest, _cache.remove(oldest)!);
      }
      _cache[word] = result;
      _wordEstimatedBytes += _wordWeight(word, result);
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
    final count = offsets.length;
    if (count == 0) {
      // Fixed-length: a split result is a value, and a growable list carries a
      // second backing array plus spare capacity for no benefit here.
      return List<String>.filled(1, word);
    }
    // The part count is known from the offsets, so the list is allocated once
    // at its final size instead of growing while the parts are cut.
    final parts = List<String>.filled(count + 1, word);
    var previous = 0;
    for (var i = 0; i < count; i++) {
      final offset = offsets[i];
      parts[i] = word.substring(previous, offset);
      previous = offset;
    }
    parts[count] = word.substring(previous);
    return parts;
  }

  /// Returns [text] with [separator] inserted at every hyphenation point.
  ///
  /// The default separator is [kSoftHyphen], which makes the result render
  /// identically to the input while giving the text engine extra break
  /// opportunities.
  String hyphenate(String text, {String separator = kSoftHyphen}) {
    if (separator.isEmpty) return text;
    final isDefaultSeparator =
        identical(separator, kSoftHyphen) || separator == kSoftHyphen;
    if (isDefaultSeparator) {
      final cached = _markedCache[text];
      if (cached != null) {
        return cached;
      }
    }

    // Delay allocation until the first insertion. Preserve the source object
    // itself when there are no breaks and never allocate whitespace tokens.
    StringBuffer? buffer;
    var copiedThrough = 0;
    var start = 0;
    while (start < text.length) {
      if (_isWhitespace(text.codeUnitAt(start))) {
        start++;
        continue;
      }
      var end = start + 1;
      while (end < text.length && !_isWhitespace(text.codeUnitAt(end))) {
        end++;
      }
      final offsets = breakOffsets(text.substring(start, end));
      for (final offset in offsets) {
        final insertion = start + offset;
        (buffer ??= StringBuffer())
          ..write(text.substring(copiedThrough, insertion))
          ..write(separator);
        copiedThrough = insertion;
      }
      start = end;
    }
    if (buffer != null) buffer.write(text.substring(copiedThrough));
    final result = buffer?.toString() ?? text;
    if (isDefaultSeparator) {
      _markedCache.put(
        text,
        result,
        weight: _paragraphWeight(text.length, result),
      );
    }
    return result;
  }

  /// Whether this hyphenator would change how [text] is broken into lines.
  ///
  /// True when the pattern set can break at least one word, or when [text]
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

  /// A description naming the pattern set and the cache state.
  ///
  /// `Instance of 'Hyphenator'` says nothing about which pattern set is in
  /// play or whether the caches are doing anything, and this object shows up
  /// in `HyphenText`'s diagnostics.
  @override
  String toString() {
    final (words, marked, broken) = cacheCounts;
    final dangling = danglingWords;
    return 'Hyphenator('
        'patterns: $patterns, '
        'leftMin: $leftMin, '
        'rightMin: $rightMin, '
        'minWordLength: $minWordLength'
        '${dangling == null ? '' : ', danglingWords: $dangling'}, '
        'maxParagraphCacheBytes: $maxParagraphCacheBytes, '
        'maxCachedWordLength: $maxCachedWordLength, '
        'cacheEstimatedBytes: $cacheEstimatedBytes, '
        'cached: $words words, $marked paragraphs, $broken broken)';
  }

  /// Clears the memoisation caches.
  void clearCache() {
    _cache.clear();
    _wordEstimatedBytes = 0;
    _markedCache.clear();
    _brokenCache.clear();
  }

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
}
