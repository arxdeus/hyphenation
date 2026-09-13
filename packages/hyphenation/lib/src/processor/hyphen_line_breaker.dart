import 'package:hyphenation/src/cache/lru_cache.dart';
import 'package:hyphenation/src/model/break_candidate.dart';
import 'package:hyphenation/src/processor/break_candidate_generator.dart';
import 'package:hyphenation/src/service/hyphenator.dart';
import 'package:meta/meta.dart';

/// Breaks text into lines, inserting hyphens at dictionary break points.
///
/// The breaker is greedy: every line takes the longest prefix that fits,
/// preferring a whole word and falling back to a hyphenated part of one. This
/// is the same strategy browsers use for `hyphens: auto`.
///
/// Instances are cheap but cache their measurements, so reusing one across
/// layouts of the same text is much faster than creating a new one.
class HyphenLineBreaker {
  /// Creates a breaker that measures text with [measure].
  ///
  /// [measure] must return the width a string occupies when painted with the
  /// widget's effective text style.
  HyphenLineBreaker({
    required this.measure,
    required this.hyphenator,
    this.hyphenCharacter = '-',
    int maxMeasurementCacheSize = kDefaultMeasurementCacheSize,
    int maxMeasurementCacheBytes = 256 * 1024,
  }) : _widths = LruCache<String, double>(
         maxMeasurementCacheSize,
         maxWeight: maxMeasurementCacheBytes,
       );

  /// Default bound for the measurement cache.
  ///
  /// Breaking a 400-character paragraph once measures about fifty distinct
  /// strings, and a paragraph whose width is animating reuses most of them
  /// from one width to the next, which is why the cache survives a width
  /// change at all. It must still be bounded: a breaker lives as long as the
  /// text and style are unchanged, so a window being dragged would otherwise
  /// grow it without limit.
  static const int kDefaultMeasurementCacheSize = 1024;

  /// Measures the painted width of a string.
  final double Function(String) measure;

  /// The dictionary-backed hyphenator, or `null` to only break at existing
  /// whitespace and hard hyphens.
  final Hyphenator? hyphenator;

  /// The character painted at the end of a hyphenated line.
  final String hyphenCharacter;

  /// Where the breaks this breaker chooses between come from.
  late final BreakCandidateGenerator _candidates = BreakCandidateGenerator(
    hyphenator,
  );

  final LruCache<String, double> _widths;

  /// Running total of every measured width and the code units it covered.
  ///
  /// Their ratio is a cheap guess at how many code units fill a line, which
  /// is used to aim the search for the last fitting candidate: the guess is
  /// usually right or off by one, so a line costs two or three measurements
  /// instead of the log2(candidates) a blind binary search needs.
  double _measuredWidth = 0;
  int _measuredUnits = 0;

  /// How many measurements are currently cached, for tests and diagnostics.
  @visibleForTesting
  int get measurementCacheSize => _widths.length;

  /// Conservative retained-key estimate, not a VM heap measurement.
  @visibleForTesting
  int get estimatedMeasurementCacheBytes => _widths.estimatedWeight;

  double _width(String text) {
    final cached = _widths[text];
    if (cached != null) {
      return cached;
    }
    final width = measure(text);
    _widths.put(text, width, weight: text.length * 2 + 64);
    if (text.isNotEmpty) {
      _measuredWidth += width;
      _measuredUnits += text.length;
    }
    return width;
  }

  /// Breaks [text] into the lines that fit into [maxWidth].
  ///
  /// Existing newlines are preserved as hard breaks. The returned lines never
  /// contain a newline, carry no trailing whitespace, and end with
  /// [hyphenCharacter] where a word was split.
  List<String> breakText(String text, double maxWidth) {
    if (text.isEmpty) {
      return <String>[''];
    }
    final lines = <String>[];
    var start = 0;
    while (true) {
      final newline = text.indexOf('\n', start);
      final end = newline < 0 ? text.length : newline;
      _breakHardLine(text, start, end, maxWidth, lines);
      if (newline < 0) {
        break;
      }
      start = newline + 1;
      if (start > text.length) {
        break;
      }
      if (start == text.length) {
        lines.add('');
        break;
      }
    }
    return lines;
  }

  /// Breaks [text] into lines and joins them with newlines.
  ///
  /// The result is what [HyphenText] hands to the underlying paragraph.
  String breakIntoString(String text, double maxWidth) =>
      breakText(text, maxWidth).join('\n');

  /// The width of the widest chunk that can never be broken.
  ///
  /// This is the smallest width at which the text can be laid out without a
  /// word sticking out, and backs `computeMinIntrinsicWidth`.
  double minIntrinsicWidth(String text) {
    // Only the chunks between two consecutive breaks matter: a line can always
    // be broken at every candidate, so the widest unbreakable chunk decides
    // the minimum width.
    var widest = 0.0;
    for (final line in text.split('\n')) {
      var start = 0;
      for (final candidate in _candidatesForLine(line)) {
        final chunk = _clean(
          line.substring(start, candidate.end) +
              (candidate.hyphen ? hyphenCharacter : ''),
        );
        // Character count cannot bound shaped width in proportional fonts.
        // Stream exact measurements instead of allocating and sorting chunks.
        final width = _width(chunk);
        if (width > widest) widest = width;
        start = candidate.next;
      }
    }
    return widest;
  }

  /// Clears cached measurements. Call this whenever the text style changes.
  void clearCache() {
    _widths.clear();
    _measuredWidth = 0;
    _measuredUnits = 0;
  }

  // Deliberately not memoised. Rebuilding the candidates costs a tokenise and
  // one cached dictionary lookup per word, a few tens of nanoseconds each,
  // against the hundreds of microseconds a break spends measuring in the
  // engine. Keeping them alive measured slower than recomputing them.
  List<BreakCandidate> _candidatesForLine(String content) =>
      _candidates.generate(content, 0, content.length);

  void _breakHardLine(
    String text,
    int lineStart,
    int lineEnd,
    double maxWidth,
    List<String> out,
  ) {
    final content = text.substring(lineStart, lineEnd);
    if (content.trim().isEmpty) {
      out.add(content.trimRight());
      return;
    }
    final candidates = _candidatesForLine(content);
    if (candidates.isEmpty) {
      out.add(content.trimRight());
      return;
    }

    var start = 0;
    var first = 0;
    while (first < candidates.length) {
      final best = _lastFitting(content, start, candidates, first, maxWidth);
      // Nothing fits: emit the smallest chunk anyway so that layout always
      // makes progress, and let the paragraph overflow as a plain Text would.
      final chosen = best < 0 ? first : best;
      final candidate = candidates[chosen];
      out.add(_lineText(content, start, candidate));
      start = candidate.next;
      first = chosen + 1;
      if (start >= content.length) {
        break;
      }
    }
  }

  /// Index of the last candidate in `candidates[first..]` whose line fits
  /// into [maxWidth], or `-1` when even the first one does not.
  ///
  /// Widths grow monotonically with the end offset, so the fitting candidates
  /// form a prefix of the remaining list. Rather than bisecting that list
  /// blindly, the search starts at the candidate the average glyph width
  /// predicts, then gallops outwards until the boundary is bracketed and
  /// bisects the (usually empty) gap. Every measurement is a paragraph layout
  /// of a string the engine has not seen, so probes are what this costs.
  int _lastFitting(
    String content,
    int start,
    List<BreakCandidate> candidates,
    int first,
    double maxWidth,
  ) {
    final last = candidates.length - 1;
    if (_measuredUnits == 0) {
      // A blind first bisection shapes half of the entire hard line, which
      // can be a document rather than a display line. Seed the predictor
      // with its smallest candidate instead. All decisions still use exact
      // measurements, and subsequent lines reuse the same running estimate.
      _width(_lineText(content, start, candidates[first]));
    }
    final fit = _gallop(content, start, candidates, first, last, maxWidth);
    return fit < first ? -1 : fit;
  }

  int _gallop(
    String content,
    int start,
    List<BreakCandidate> candidates,
    int first,
    int last,
    double maxWidth,
  ) {
    // Aim at the last candidate whose length the running average says fits.
    final targetUnits = maxWidth * _measuredUnits / _measuredWidth;
    var low = first;
    var high = last;
    var guess = first;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final candidate = candidates[mid];
      final units = candidate.end - start + (candidate.hyphen ? 1 : 0);
      if (units <= targetUnits) {
        guess = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    // `fit` always fits (or is `first - 1`), `fail` never does (or is
    // `last + 1`); gallop until the pair brackets the boundary.
    int fit;
    int fail;
    if (_fits(content, start, candidates[guess], maxWidth)) {
      fit = guess;
      fail = last + 1;
      var step = 1;
      while (true) {
        final probe = fit + step;
        if (probe > last) {
          break;
        }
        if (_fits(content, start, candidates[probe], maxWidth)) {
          fit = probe;
          step <<= 1;
        } else {
          fail = probe;
          break;
        }
      }
    } else {
      fail = guess;
      fit = first - 1;
      var step = 1;
      while (true) {
        final probe = fail - step;
        if (probe < first) {
          break;
        }
        if (_fits(content, start, candidates[probe], maxWidth)) {
          fit = probe;
          break;
        } else {
          fail = probe;
          step <<= 1;
        }
      }
    }
    return _bisect(content, start, candidates, fit, fail, maxWidth);
  }

  /// Bisects the open interval `(fit, fail)`, where [fit] is known to fit (or
  /// is one before the first index) and [fail] is known not to (or is one past
  /// the last). Returns the last fitting index, or [fit] when none does.
  int _bisect(
    String content,
    int start,
    List<BreakCandidate> candidates,
    int fit,
    int fail,
    double maxWidth,
  ) {
    var best = fit;
    var low = fit + 1;
    var high = fail - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_fits(content, start, candidates[mid], maxWidth)) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return best;
  }

  bool _fits(
    String content,
    int start,
    BreakCandidate candidate,
    double width,
  ) => _width(_lineText(content, start, candidate)) <= width;

  String _lineText(String content, int start, BreakCandidate candidate) {
    final raw = content.substring(start, candidate.end).trimRight();
    return _clean(candidate.hyphen ? raw + hyphenCharacter : raw);
  }

  /// Drops soft hyphens, which are invisible but would otherwise survive into
  /// the painted text and confuse width caching.
  static String _clean(String text) =>
      text.contains(kSoftHyphen) ? text.replaceAll(kSoftHyphen, '') : text;
}
