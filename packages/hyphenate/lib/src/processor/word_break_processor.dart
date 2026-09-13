import 'package:characters/characters.dart';
import 'package:hyphenate/src/tex/tex_hyphenation_patterns.dart';
import 'package:hyphenate/src/util/code_units.dart';
import 'package:hyphenate/src/util/errors.dart';

/// Finds the break opportunities inside a single word.
///
/// This is the part of [Hyphenator] that talks to the pattern set: it splits
/// a word into letter runs, folds their case, asks the patterns to mark the
/// runs and walks the marks back into code unit offsets. [Hyphenator] keeps
/// the caches and the public API around it.
class WordBreakProcessor {
  /// Creates a processor that looks runs up in [patterns].
  const WordBreakProcessor({
    required this.patterns,
    required this.leftMin,
    required this.rightMin,
    required this.minWordLength,
  });

  /// The pattern set consulted per letter run.
  final TexHyphenationPatterns patterns;

  /// Characters that must stay before a break.
  final int leftMin;

  /// Characters that must move after a break.
  final int rightMin;

  /// The shortest run worth looking up at all.
  final int minWordLength;

  /// The break opportunities inside [word], in ascending order.
  List<int> computeOffsets(String word) {
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
    // Patterns are written lower case, so an all-caps or capitalised word
    // finds nothing unless it is folded first. The fold is
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

    // The engine writes one mark per character into a buffer it owns and
    // reuses, so a word costs no allocation at all here: no list of parts,
    // no substrings, and no second pass to work out where the parts began.
    // The marks are read before the next call on the same [Hyphen], which
    // is the only thing that invalidates them.
    final int markCount;
    try {
      markCount = patterns.markWord(
        lookup,
        leftMin: leftMin,
        rightMin: rightMin,
      );
    } catch (error, stackTrace) {
      // A pattern set that cannot hyphenate one word must never take down
      // the whole widget tree; the word simply stays unbroken.
      reportHyphenationError(error, stackTrace, 'while hyphenating "$run"');
      return;
    }
    final marks = patterns.marks;

    if (simple) {
      // One code unit is one character is one mark, so the mark index is
      // the offset of the break that follows it.
      final limit = markCount < run.length ? markCount : run.length;
      for (var i = 0; i < limit; i++) {
        if ((marks[i] & 1) != 1) {
          continue;
        }
        final offset = i + 1;
        if (offset < leftMin ||
            characterCount - offset < rightMin ||
            offset >= run.length) {
          continue;
        }
        _addOffset(offsets, base + offset);
      }
      return;
    }

    var characterOffset = 0;
    var codeUnitOffset = 0;
    for (final character in lookup.characters) {
      codeUnitOffset += character.length;
      final isBreak =
          characterOffset < markCount && (marks[characterOffset] & 1) == 1;
      characterOffset++;
      if (!isBreak) {
        continue;
      }
      if (characterOffset < leftMin ||
          characterCount - characterOffset < rightMin) {
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
}
