// Reads TeX hyphenation pattern files: `\patterns{...}` and
// `\hyphenation{...}`.
//
// The format is Liang's, as described in his 1983 thesis and used by every
// `hyph-*.tex` file on CTAN. A pattern is a run of letters with priority
// digits wedged between them, so `hy3ph` says that breaking between `hy`
// and `ph` is worth 3. A `.` anchors the pattern to a word edge. Odd
// priorities permit a break, even ones forbid it, and the highest priority
// claimed at a position wins.
//
// `\hyphenation{...}` lists exceptions spelled with explicit hyphens
// (`as-so-ciate`), which override the patterns outright.
//
// Everything outside those two groups is commentary: TeX comments start at
// `%` and run to the end of the line, and files carry a header of them.

import 'dart:typed_data';

/// What a pattern file contained, before it is compiled for matching.
class TexPatternSource {
  TexPatternSource({required this.patterns, required this.exceptions});

  /// Pattern strings as written, digits included.
  final List<String> patterns;

  /// Exceptions, keyed by the word with its hyphens removed and folded to
  /// lower case. The value holds the character offsets a hyphen sits after.
  final Map<String, List<int>> exceptions;
}

const int _kPercent = 0x25; // %
const int _kBackslash = 0x5C; // \
const int _kOpenBrace = 0x7B; // {
const int _kCloseBrace = 0x7D; // }
const int _kHyphen = 0x2D; // -
const int _kSpace = 0x20;

/// Parses the text of a `hyph-*.tex` file.
///
/// Unknown control sequences and stray text are skipped rather than
/// rejected: pattern files carry `\message{...}`, `\endinput` and assorted
/// TeX plumbing that has nothing to do with hyphenation, and a reader that
/// insisted on understanding all of it would reject most real files.
TexPatternSource parseTexPatterns(String source) {
  final patterns = <String>[];
  final exceptions = <String, List<int>>{};

  final units = source.codeUnits;
  var i = 0;
  while (i < units.length) {
    final unit = units[i];

    if (unit == _kPercent) {
      i = _skipToLineEnd(units, i);
      continue;
    }
    if (unit != _kBackslash) {
      i++;
      continue;
    }

    final name = _readControlName(units, i + 1);
    if (name == 'patterns') {
      final open = _skipToBrace(units, i + 1 + name.length);
      if (open < 0) {
        break;
      }
      i = _readGroup(units, open + 1, patterns.add);
      continue;
    }
    if (name == 'hyphenation') {
      final open = _skipToBrace(units, i + 1 + name.length);
      if (open < 0) {
        break;
      }
      i = _readGroup(units, open + 1, (token) {
        final entry = _readException(token);
        if (entry != null) {
          exceptions[entry.key] = entry.value;
        }
      });
      continue;
    }

    // Some other control sequence. Step over its name so that a `\p` inside
    // it cannot be mistaken for the start of `\patterns`.
    i += 1 + (name.isEmpty ? 1 : name.length);
  }

  return TexPatternSource(patterns: patterns, exceptions: exceptions);
}

int _skipToLineEnd(List<int> units, int from) {
  var i = from;
  while (i < units.length && units[i] != 0x0A) {
    i++;
  }
  return i < units.length ? i + 1 : i;
}

String _readControlName(List<int> units, int from) {
  var i = from;
  while (i < units.length && _isLetter(units[i])) {
    i++;
  }
  return String.fromCharCodes(units, from, i);
}

bool _isLetter(int unit) =>
    (unit >= 0x61 && unit <= 0x7A) || (unit >= 0x41 && unit <= 0x5A);

int _skipToBrace(List<int> units, int from) {
  var i = from;
  while (i < units.length) {
    final unit = units[i];
    if (unit == _kOpenBrace) {
      return i;
    }
    if (unit == _kPercent) {
      i = _skipToLineEnd(units, i);
      continue;
    }
    if (unit > _kSpace) {
      // Something other than whitespace or a comment sits between the
      // control sequence and its group, so this was not the group we
      // expected.
      return -1;
    }
    i++;
  }
  return -1;
}

/// Reads whitespace-separated tokens until the group closes, and returns the
/// offset just past the closing brace.
int _readGroup(List<int> units, int from, void Function(String) onToken) {
  final buffer = StringBuffer();
  var i = from;
  while (i < units.length) {
    final unit = units[i];
    if (unit == _kCloseBrace) {
      if (buffer.isNotEmpty) {
        onToken(buffer.toString());
      }
      return i + 1;
    }
    if (unit == _kPercent) {
      if (buffer.isNotEmpty) {
        onToken(buffer.toString());
        buffer.clear();
      }
      i = _skipToLineEnd(units, i);
      continue;
    }
    if (unit <= _kSpace) {
      if (buffer.isNotEmpty) {
        onToken(buffer.toString());
        buffer.clear();
      }
      i++;
      continue;
    }
    buffer.writeCharCode(unit);
    i++;
  }
  if (buffer.isNotEmpty) {
    onToken(buffer.toString());
  }
  return i;
}

/// `as-so-ciate` becomes `associate` and the offsets `[2, 4]`.
MapEntry<String, List<int>>? _readException(String token) {
  final letters = StringBuffer();
  final breaks = <int>[];
  for (final unit in token.codeUnits) {
    if (unit == _kHyphen) {
      breaks.add(letters.length);
    } else {
      letters.writeCharCode(unit);
    }
  }
  if (letters.isEmpty) {
    return null;
  }
  return MapEntry(letters.toString().toLowerCase(), breaks);
}

/// Splits a pattern into its letters and the priority it claims at each
/// position.
///
/// `hy3ph` yields the letters `hyph` and priorities `[0, 0, 3, 0, 0]`: one
/// more than there are letters, because a priority may be claimed before the
/// first letter and after the last.
class ParsedPattern {
  ParsedPattern(this.letters, this.priorities);

  final Uint16List letters;
  final Uint8List priorities;
}

ParsedPattern parsePattern(String pattern) {
  final units = pattern.codeUnits;
  final letters = Uint16List(units.length);
  final priorities = Uint8List(units.length + 1);
  var length = 0;
  for (final unit in units) {
    if (unit >= 0x30 && unit <= 0x39) {
      priorities[length] = unit - 0x30;
    } else {
      letters[length++] = unit;
    }
  }
  return ParsedPattern(
    Uint16List.sublistView(letters, 0, length),
    Uint8List.sublistView(priorities, 0, length + 1),
  );
}
