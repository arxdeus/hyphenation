import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hyphen/src/code_units.dart';
import 'package:flutter_hyphen/src/dangling_words.dart';
import 'package:flutter_hyphen/src/lru_cache.dart';
import 'package:hyphen/hyphen.dart';

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
  /// Creates a hyphenator around an already loaded [Hyphen] engine.
  Hyphenator(
    this.hyphen, {
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
    Hyphen.fromDictionaryBytes(bytes),
    leftMin: leftMin,
    rightMin: rightMin,
    minWordLength: minWordLength,
    maxCacheSize: maxCacheSize,
    maxParagraphCacheSize: maxParagraphCacheSize,
    danglingWords: danglingWords,
  );

  /// The underlying hyphenation engine.
  final Hyphen hyphen;

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
  String? cachedBreak(Object key) => _brokenCache[key];

  /// Records [value] as the broken form for [key].
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
    final computed = _computeBreakOffsets(word);
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

  List<int> _computeBreakOffsets(String word) {
    final offsets = <int>[];
    var runStart = -1;

    void flushRun(int end) {
      if (runStart < 0) {
        return;
      }
      _appendRunBreaks(word.substring(runStart, end), runStart, offsets);
      runStart = -1;
    }

    for (var i = 0; i < word.length; i++) {
      final unit = word.codeUnitAt(i);
      if (unit == 0x00AD) {
        // Soft hyphen: an author-provided break opportunity. The character
        // itself is invisible, so the break goes before it and the renderer
        // drops it.
        flushRun(i);
        _addOffset(offsets, i);
        continue;
      }
      if (_isHardHyphen(unit)) {
        flushRun(i);
        // Breaking after an existing hyphen must not add a second one.
        _addOffset(offsets, i + 1);
        continue;
      }
      if (_isWordCharacter(unit)) {
        if (runStart < 0) {
          runStart = i;
        }
        continue;
      }
      flushRun(i);
    }
    flushRun(word.length);

    // No sort: the scan walks the word left to right and every producer below
    // appends in ascending order, which `_addOffset` asserts.
    return offsets;
  }

  void _appendRunBreaks(String run, int base, List<int> offsets) {
    // Grapheme clusters only differ from code units when the word contains a
    // surrogate pair or a combining mark, which is rare and cheap to rule out.
    // Building a `Characters` view for every word otherwise dominates the cost
    // of hyphenating a paragraph.
    final simple = _isSimple(run);
    final characterCount = simple ? run.length : run.characters.length;
    if (characterCount < minWordLength) {
      return;
    }
    // Dictionaries only carry lowercase patterns, so an all-caps or
    // capitalised word finds nothing unless it is folded first. The fold is
    // only usable when it preserves the character count, otherwise the offsets
    // would not map back (for example 'İ'.toLowerCase() is two characters).
    //
    // Running text is overwhelmingly lowercase already, and `toLowerCase`
    // allocates a new string every time, so the cheap scan below pays for
    // itself: only words that actually contain an upper-case unit are folded.
    final String lookup;
    if (!_mayHaveUpperCase(run)) {
      lookup = run;
    } else {
      final lower = run.toLowerCase();
      lookup =
          lower.length == run.length &&
              (simple || lower.characters.length == characterCount)
          ? lower
          : run;
    }

    final List<String> parts;
    try {
      parts = hyphen.hyphenate(lookup, lhmin: leftMin, rhmin: rightMin);
    } catch (error, stackTrace) {
      // A dictionary that cannot hyphenate one word must never take down the
      // whole widget tree; the word simply stays unbroken.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'flutter_hyphen',
          context: ErrorDescription('while hyphenating "$run"'),
        ),
      );
      return;
    }
    if (parts.length < 2) {
      return;
    }

    final totalCharacters = characterCount;
    var characterOffset = 0;
    var codeUnitOffset = 0;
    for (var i = 0; i < parts.length - 1; i++) {
      final partCharacters = simple
          ? parts[i].length
          : parts[i].characters.length;
      characterOffset += partCharacters;
      codeUnitOffset += parts[i].length;
      if (characterOffset < leftMin ||
          totalCharacters - characterOffset < rightMin) {
        continue;
      }
      if (codeUnitOffset <= 0 || codeUnitOffset >= run.length) {
        continue;
      }
      _addOffset(offsets, base + codeUnitOffset);
    }
  }

  /// Whether [text] might contain an upper-case character.
  ///
  /// This only returns false when every code unit is known to be caseless or
  /// already lower-case. Anything unrecognised returns true, so an unhandled
  /// script still takes the folding path and behaves exactly as before; the
  /// fast path is just an optimisation for the common case of lower-case
  /// running text.
  static bool _mayHaveUpperCase(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0x61 && unit <= 0x7A) {
        continue; // a-z
      }
      if (unit < 0x80) {
        if (unit >= 0x41 && unit <= 0x5A) {
          return true; // A-Z
        }
        continue; // digits and ASCII punctuation are caseless
      }
      if (unit >= 0x430 && unit <= 0x45F) {
        continue; // Cyrillic lower case, including e and friends
      }
      return true; // unknown script: fold, as before
    }
    return false;
  }

  /// Whether [text] is free of surrogate pairs and combining marks, so one
  /// code unit is one grapheme cluster.
  static bool _isSimple(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      // Surrogates, combining marks, and variation selectors are the cases
      // where a grapheme cluster spans more than one code unit.
      if (unit >= 0xD800 && unit <= 0xDFFF) {
        return false;
      }
      if (unit >= 0x0300 && unit <= 0x036F) {
        return false;
      }
      if (unit >= 0xFE00 && unit <= 0xFE0F) {
        return false;
      }
      if (unit == 0x200D) {
        return false;
      }
    }
    return true;
  }

  /// Appends [offset], skipping duplicates.
  ///
  /// Offsets arrive in ascending order, so a duplicate can only be the last
  /// one appended. The old `contains` check made this quadratic in the number
  /// of break points, which a very long word actually reaches.
  static void _addOffset(List<int> offsets, int offset) {
    if (offset <= 0) {
      return;
    }
    if (offsets.isNotEmpty) {
      final last = offsets.last;
      assert(offset >= last, 'offsets must be produced in ascending order');
      if (last == offset) {
        return;
      }
    }
    offsets.add(offset);
  }

  static bool _isHardHyphen(int unit) => isHardHyphen(unit);

  static bool _isWordCharacter(int unit) => isWordCharacter(unit);

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
