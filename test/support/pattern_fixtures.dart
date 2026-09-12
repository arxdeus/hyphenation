// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_hyphen/src/builder/pattern_level_builder.dart';
import 'package:flutter_hyphen/src/model/pattern_set.dart';
import 'package:flutter_hyphen/src/parser/dictionary_parser.dart';
import 'package:flutter_hyphen/src/processor/break_marker.dart';

// Finding the breaks in a word, one behaviour at a time.
//
// Every expected value here was measured against the reference
// implementation rather than reasoned out, and several were confirmed by
// mutation — the comment says which, because a test that still passes when
// the code it covers is deleted is worse than no test at all.

/// A single level built from pattern lines, with nothing below it.
PatternSet level(List<String> lines, {bool isUtf8 = true}) {
  final draft = LevelDraft(isUtf8: isUtf8);
  for (final line in lines) {
    draft.readLine(Uint8List.fromList(utf8.encode('$line\n')));
  }
  return draft.build(isUtf8 ? 'UTF-8' : 'ISO8859-1', inner: null);
}

/// The level a whole dictionary parses into, and the level below it.
PatternSet parse(String body) => DictionaryParser(utf8.encode(body)).parse();

Uint8List buffer(int length, [int fill = 0]) =>
    Uint8List(length)..fillRange(0, length, fill);

/// The priorities [word] gets from [lines] alone, with no minimum distances
/// and no level below.
List<int> priorities(List<String> lines, String word, {bool isUtf8 = true}) {
  final bytes = utf8.encode(word);
  final marks = buffer(bytes.length + 8);
  BreakMarker().markPatterns(
    level(lines, isUtf8: isUtf8),
    bytes,
    0,
    bytes.length,
    marks,
  );
  return marks.sublist(0, bytes.length);
}
