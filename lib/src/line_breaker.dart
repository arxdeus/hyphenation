import 'package:flutter/widgets.dart';
import 'package:flutter_hyphen/src/hyphenator.dart';

/// One break opportunity inside a hard line.
@immutable
class _Candidate {
  const _Candidate({
    required this.end,
    required this.next,
    required this.hyphen,
  });

  /// Offset just past the last character that stays on the line.
  final int end;

  /// Offset at which the following line starts.
  final int next;

  /// Whether a hyphen has to be painted at the end of the line.
  final bool hyphen;
}

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
  });

  /// Measures the painted width of a string.
  final double Function(String) measure;

  /// The dictionary-backed hyphenator, or `null` to only break at existing
  /// whitespace and hard hyphens.
  final Hyphenator? hyphenator;

  /// The character painted at the end of a hyphenated line.
  final String hyphenCharacter;

  final Map<String, double> _widths = <String, double>{};

  double _width(String text) => _widths[text] ??= measure(text);

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
    final chunks = <String>[];
    for (final line in text.split('\n')) {
      var start = 0;
      for (final candidate in _candidatesFor(line, 0, line.length)) {
        chunks.add(
          _clean(
            line.substring(start, candidate.end) +
                (candidate.hyphen ? hyphenCharacter : ''),
          ),
        );
        start = candidate.next;
      }
    }
    if (chunks.isEmpty) {
      return 0;
    }

    // Measuring every chunk is wasteful: most are obviously too short to win.
    // Sorting by length and stopping once no unmeasured chunk can beat the
    // widest one found keeps this to a handful of measurements, which matters
    // because parents like Center query intrinsics on every layout pass.
    chunks.sort((String a, String b) => b.length.compareTo(a.length));
    var widest = 0.0;
    var widestPerUnit = 0.0;
    for (final chunk in chunks) {
      // No chunk shorter than this can exceed `widest`, given the widest
      // per-code-unit width seen so far.
      if (widestPerUnit > 0 && chunk.length * widestPerUnit <= widest) {
        break;
      }
      final width = _width(chunk);
      if (width > widest) {
        widest = width;
      }
      if (chunk.isNotEmpty) {
        final perUnit = width / chunk.length;
        if (perUnit > widestPerUnit) {
          widestPerUnit = perUnit;
        }
      }
    }
    return widest;
  }

  /// Clears cached measurements. Call this whenever the text style changes.
  void clearCache() => _widths.clear();

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
    final candidates = _candidatesFor(content, 0, content.length);
    if (candidates.isEmpty) {
      out.add(content.trimRight());
      return;
    }

    var start = 0;
    var first = 0;
    while (first < candidates.length) {
      // Binary search for the last candidate that still fits. Widths grow
      // monotonically with the end offset, so the fitting candidates form a
      // prefix of the remaining list.
      var low = first;
      var high = candidates.length - 1;
      var best = -1;
      while (low <= high) {
        final mid = (low + high) >> 1;
        if (_fits(content, start, candidates[mid], maxWidth)) {
          best = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
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

  bool _fits(String content, int start, _Candidate candidate, double width) =>
      _width(_lineText(content, start, candidate)) <= width;

  String _lineText(String content, int start, _Candidate candidate) {
    final raw = content.substring(start, candidate.end).trimRight();
    return _clean(candidate.hyphen ? raw + hyphenCharacter : raw);
  }

  /// Drops soft hyphens, which are invisible but would otherwise survive into
  /// the painted text and confuse width caching.
  static String _clean(String text) =>
      text.contains(kSoftHyphen) ? text.replaceAll(kSoftHyphen, '') : text;

  List<_Candidate> _candidatesFor(String content, int from, int to) {
    final candidates = <_Candidate>[];
    final words = <List<int>>[];
    var index = from;
    while (index < to) {
      while (index < to && _isBreakingSpace(content.codeUnitAt(index))) {
        index++;
      }
      if (index >= to) {
        break;
      }
      final wordStart = index;
      while (index < to && !_isBreakingSpace(content.codeUnitAt(index))) {
        index++;
      }
      words.add(<int>[wordStart, index]);
    }

    for (var i = 0; i < words.length; i++) {
      final wordStart = words[i][0];
      final wordEnd = words[i][1];
      final word = content.substring(wordStart, wordEnd);
      final offsets = hyphenator?.breakOffsets(word) ?? const <int>[];
      for (final offset in offsets) {
        final absolute = wordStart + offset;
        if (absolute <= wordStart || absolute >= wordEnd) {
          continue;
        }
        if (content.codeUnitAt(absolute) == 0x00AD) {
          // The soft hyphen itself is dropped; a real hyphen is painted.
          candidates.add(
            _Candidate(end: absolute, next: absolute + 1, hyphen: true),
          );
        } else if (_isHardHyphen(content.codeUnitAt(absolute - 1))) {
          // Breaking right after an existing hyphen must not double it.
          candidates.add(
            _Candidate(end: absolute, next: absolute, hyphen: false),
          );
        } else {
          candidates.add(
            _Candidate(end: absolute, next: absolute, hyphen: true),
          );
        }
      }
      candidates.add(
        _Candidate(
          end: wordEnd,
          next: i + 1 < words.length ? words[i + 1][0] : to,
          hyphen: false,
        ),
      );
    }
    return candidates;
  }

  static bool _isHardHyphen(int unit) =>
      unit == 0x2D || unit == 0x2010 || unit == 0x2011;

  static bool _isBreakingSpace(int unit) =>
      unit == 0x20 ||
      unit == 0x09 ||
      unit == 0x0B ||
      unit == 0x0C ||
      unit == 0x0D ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x3000;
}
