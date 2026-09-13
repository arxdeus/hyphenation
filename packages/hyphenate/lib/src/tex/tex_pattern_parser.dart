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
  // Materialised, not `source.codeUnits`: that is a lazy view, and
  // `String.fromCharCodes` over one cannot take its fast path. Building a
  // token from a view measured three orders of magnitude worse than from a
  // real list.
  final units = Uint16List.fromList(source.codeUnits);
  final afterName = <int>[0];

  var at = 0;
  while (at < units.length) {
    final kind = nextTexGroup(units, at, afterName);
    at = afterName[0];
    if (kind == TexGroupKind.none) {
      break;
    }
    final isPatterns = kind == TexGroupKind.patterns;
    final scanner = openTexGroup(units, at);
    if (scanner == null) {
      break;
    }
    while (scanner.next()) {
      if (isPatterns) {
        // The token is already exactly the pattern as written, so take it
        // verbatim. Splitting it here and reassembling it would cost five
        // times the whole scan, for a form this entry point does not want.
        patterns.add(String.fromCharCodes(units, scanner.from, scanner.to));
      } else {
        final entry = readTexException(
          String.fromCharCodes(units, scanner.from, scanner.to),
        );
        if (entry != null) {
          exceptions[entry.key] = entry.value;
        }
      }
    }
    at = scanner.end;
  }

  return TexPatternSource(patterns: patterns, exceptions: exceptions);
}

/// Called with each exception: the word with its hyphens removed and folded
/// to lower case, and the offsets a hyphen sat after.
typedef TexExceptionHandler = void Function(String word, List<int> breaks);

/// Splits the token `units[from..to)` into letters and priorities.
///
/// Writes the letters into [letters] and the priority claimed at each of the
/// `length + 1` positions into [priorities], and returns the letter count.
/// Both buffers must have room for `to - from` letters and one more
/// priority; [reserveForPattern] sizes them.
int splitTexPattern(
  List<int> units,
  int from,
  int to,
  Uint16List letters,
  Uint8List priorities,
) {
  var length = 0;
  priorities[0] = 0;
  for (var i = from; i < to; i++) {
    final unit = units[i];
    if (unit >= 0x30 && unit <= 0x39) {
      priorities[length] = unit - 0x30;
    } else {
      letters[length++] = unit;
      priorities[length] = 0;
    }
  }
  return length;
}

int _skipToLineEnd(List<int> units, int from) {
  var i = from;
  while (i < units.length && units[i] != 0x0A) {
    i++;
  }
  return i < units.length ? i + 1 : i;
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

/// Walks the whitespace-separated tokens of a `{...}` group.
///
/// A class rather than a callback because the callback version cost two
/// indirect calls per token — one for the token handler, one for the handler
/// it wrapped — and AOT could not inline either. A pattern file has tens of
/// thousands of tokens, and that doubled the compile time.
///
/// Tokens are reported as `[from, to)` spans of the source's code units, so
/// a caller that only wants to look at the bytes never allocates a string.
class TexGroupScanner {
  TexGroupScanner(this.units, this._cursor);

  final List<int> units;
  int _cursor;

  /// Start of the token [next] found.
  int from = -1;

  /// Offset just past it.
  int to = -1;

  /// Offset just past the group's closing brace, valid once [next] has
  /// returned false.
  int end = -1;

  /// Advances to the next token, or returns false at the end of the group.
  bool next() {
    var i = _cursor;
    var start = -1;
    while (i < units.length) {
      final unit = units[i];
      if (unit == _kCloseBrace) {
        if (start >= 0) {
          from = start;
          to = i;
          _cursor = i;
          return true;
        }
        end = i + 1;
        _cursor = end;
        return false;
      }
      if (unit == _kPercent) {
        if (start >= 0) {
          from = start;
          to = i;
          _cursor = i;
          return true;
        }
        i = _skipToLineEnd(units, i);
        continue;
      }
      if (unit <= _kSpace) {
        if (start >= 0) {
          from = start;
          to = i;
          _cursor = i;
          return true;
        }
        i++;
        continue;
      }
      if (start < 0) {
        start = i;
      }
      i++;
    }
    if (start >= 0) {
      from = start;
      to = i;
      _cursor = i;
      return true;
    }
    end = i;
    _cursor = i;
    return false;
  }
}

/// Opens the group that [name] introduces, or returns null when what follows
/// is not a group after all.
TexGroupScanner? openTexGroup(List<int> units, int afterName) {
  final open = _skipToBrace(units, afterName);
  return open < 0 ? null : TexGroupScanner(units, open + 1);
}

/// What [nextTexGroup] found.
enum TexGroupKind {
  /// A `\patterns{...}` group.
  patterns,

  /// A `\hyphenation{...}` group.
  hyphenation,

  /// Nothing left to read.
  none,
}

/// Finds the next `\patterns` or `\hyphenation` group at or after [at].
///
/// Everything else is skipped: comments, `\message{...}`, `\endinput` and
/// the rest of the TeX plumbing a pattern file carries. On a hit,
/// `outAfterName[0]` holds the offset just past the control sequence's name,
/// ready for [openTexGroup].
///
/// The name is compared unit by unit rather than read into a `String`.
/// Building a string for every control sequence in the file, almost all of
/// which are neither of the two that matter, measured five times the cost of
/// the whole scan.
TexGroupKind nextTexGroup(List<int> units, int at, List<int> outAfterName) {
  var i = at;
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

    final nameStart = i + 1;
    var nameEnd = nameStart;
    while (nameEnd < units.length && _isLetter(units[nameEnd])) {
      nameEnd++;
    }

    if (_matchesName(units, nameStart, nameEnd, _kPatternsName)) {
      outAfterName[0] = nameEnd;
      return TexGroupKind.patterns;
    }
    if (_matchesName(units, nameStart, nameEnd, _kHyphenationName)) {
      outAfterName[0] = nameEnd;
      return TexGroupKind.hyphenation;
    }

    // Step over the whole name, so a `\p` inside it cannot be mistaken for
    // the start of `\patterns`.
    i = nameEnd > nameStart ? nameEnd : nameStart + 1;
  }
  outAfterName[0] = i;
  return TexGroupKind.none;
}

/// `patterns`, as code units.
const List<int> _kPatternsName = <int>[
  0x70,
  0x61,
  0x74,
  0x74,
  0x65,
  0x72,
  0x6E,
  0x73,
];

/// `hyphenation`, as code units.
const List<int> _kHyphenationName = <int>[
  0x68,
  0x79,
  0x70,
  0x68,
  0x65,
  0x6E,
  0x61,
  0x74,
  0x69,
  0x6F,
  0x6E,
];

bool _matchesName(List<int> units, int from, int to, List<int> name) {
  if (to - from != name.length) {
    return false;
  }
  for (var i = 0; i < name.length; i++) {
    if (units[from + i] != name[i]) {
      return false;
    }
  }
  return true;
}

/// `as-so-ciate` becomes `associate` and the offsets `[2, 4]`.
MapEntry<String, List<int>>? readTexException(String token) {
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
