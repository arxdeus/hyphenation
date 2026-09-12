// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'package:characters/characters.dart';

/// Splits [text] after every character whose mark in [marks] is odd.
///
/// Only the first [markCount] entries are read, so a caller may pass a
/// longer buffer it reuses between words.
///
/// ### Why odd, and why no conversion first
/// A mark is a priority, and the convention is that an odd one is a break.
/// The matcher writes priorities as the ASCII digits the dictionary is
/// written in ('0' is 48) in most places and as small integers in others.
/// Both forms agree on the low bit — 48 is even — so testing it directly is
/// correct for either, and the conversion pass that would normalise them is
/// pure waste.
///
/// ### Grapheme clusters
/// A mark belongs to a character, and a character can be several code units:
/// an `e` followed by a combining acute is one character, and so is an
/// emoji. The fast path below is not an approximation of that, it is a proof
/// that the slow path is unnecessary: nothing below U+0300 combines with
/// anything, so a string made only of such code units has one character per
/// code unit, and the marks can be applied by index. CR followed by LF is
/// the single exception, and it is checked for.
List<String> splitOnOddMarks(String text, List<int> marks, int markCount) {
  if (text.isEmpty) {
    return const <String>[];
  }

  if (_isOneCharacterPerCodeUnit(text)) {
    final limit = markCount < text.length ? markCount : text.length;
    var breaks = 0;
    for (var i = 0; i < limit; i++) {
      if ((marks[i] & 1) == 1) {
        breaks++;
      }
    }
    if (breaks == 0) {
      return <String>[text];
    }

    final parts = List<String>.filled(breaks + 1, '');
    var part = 0;
    var start = 0;
    for (var i = 0; i < limit; i++) {
      if ((marks[i] & 1) == 1) {
        parts[part++] = text.substring(start, i + 1);
        start = i + 1;
      }
    }
    if (start < text.length) {
      parts[part] = text.substring(start);
      return parts;
    }
    // A mark on the last character leaves no tail, and an empty trailing
    // part is not one.
    return parts.sublist(0, part);
  }

  final parts = <String>[];
  final buffer = StringBuffer();
  var index = 0;
  for (final character in text.characters) {
    buffer.write(character);
    if (index < markCount && (marks[index] & 1) == 1) {
      parts.add(buffer.toString());
      buffer.clear();
    }
    index++;
  }
  if (buffer.isNotEmpty) {
    parts.add(buffer.toString());
  }
  return parts;
}

/// Whether every code unit of [text] stands on its own as a character.
///
/// Deliberately blunt rather than clever: U+0300 is the first code point
/// that joins the one before it, so everything below stands alone, and
/// everything at or above takes the slow path whether or not it would
/// actually have joined.
bool _isOneCharacterPerCodeUnit(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0x0300) {
      return false;
    }
    if (unit == 0x0D && i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A) {
      return false;
    }
  }
  return true;
}
