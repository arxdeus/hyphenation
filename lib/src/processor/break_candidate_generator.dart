import 'package:flutter_hyphen/src/model/break_candidate.dart';
import 'package:flutter_hyphen/src/service/hyphenator.dart';
import 'package:flutter_hyphen/src/util/code_units.dart' as units;

/// Turns a stretch of text into the break opportunities a line breaker may
/// choose between.
///
/// Separate from [HyphenLineBreaker] because the two answer different
/// questions: this one knows where a break *may* fall, the breaker decides
/// which of them it takes.
class BreakCandidateGenerator {
  /// Creates a generator that asks [hyphenator] where words may break.
  const BreakCandidateGenerator(this.hyphenator);

  /// The hyphenator consulted per word, or null when hyphenation is off.
  final Hyphenator? hyphenator;

  /// Break opportunities in `content[from..to)`.
  List<BreakCandidate> generate(String content, int from, int to) {
    final candidates = <BreakCandidate>[];
    // Word bounds are kept flat, as start/end pairs in one list, rather than
    // as a list of two-element lists: this runs for every word of every hard
    // line on every break, and the inner lists were pure allocation churn.
    final words = <int>[];
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
      words
        ..add(wordStart)
        ..add(index);
    }

    final wordCount = words.length >> 1;
    // Hoisted: when the feature is off this is the only cost it has.
    final dangling = hyphenator?.danglingWords;
    for (var i = 0; i < wordCount; i++) {
      final wordStart = words[i * 2];
      final wordEnd = words[i * 2 + 1];
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
            BreakCandidate(end: absolute, next: absolute + 1, hyphen: true),
          );
        } else if (_isHardHyphen(content.codeUnitAt(absolute - 1))) {
          // Breaking right after an existing hyphen must not double it.
          candidates.add(
            BreakCandidate(end: absolute, next: absolute, hyphen: false),
          );
        } else {
          candidates.add(
            BreakCandidate(end: absolute, next: absolute, hyphen: true),
          );
        }
      }
      final isLast = i + 1 >= wordCount;
      // A dangling word is glued to the word after it simply by not offering
      // the break that would separate them, so the line runs on and takes
      // both. Nothing is inserted into the text.
      //
      // The last word of a hard line is never glued: there is nothing after
      // it to carry it down to, and dropping its candidate would drop the
      // text with it.
      if (isLast ||
          dangling == null ||
          !dangling.matches(content, wordStart, wordEnd)) {
        candidates.add(
          BreakCandidate(
            end: wordEnd,
            next: isLast ? to : words[(i + 1) * 2],
            hyphen: false,
          ),
        );
      }
    }
    return candidates;
  }

  static bool _isHardHyphen(int unit) => units.isHardHyphen(unit);

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
