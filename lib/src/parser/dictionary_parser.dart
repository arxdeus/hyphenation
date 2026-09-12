import 'dart:typed_data';

import 'package:flutter_hyphen/src/buffer/replacement_pool.dart';
import 'package:flutter_hyphen/src/builder/pattern_level_builder.dart';
import 'package:flutter_hyphen/src/constant/dictionary_syntax.dart';
import 'package:flutter_hyphen/src/model/dictionary_charset.dart';
import 'package:flutter_hyphen/src/model/edge_limits.dart';
import 'package:flutter_hyphen/src/model/pattern_set.dart';
import 'package:flutter_hyphen/src/parser/dictionary_line_scanner.dart';

/// Turns the bytes of a `hyph_*.dic` file into the levels the matcher runs.
///
/// ### The format
/// A charset name on the first line, then one pattern per line. A pattern is
/// letters with priority digits wedged between them (`hy3ph`: breaking after
/// `hy` is worth 3), optionally anchored to a word edge with `.`, optionally
/// followed by `/text,at,cut` to rewrite the word where it matches. Lines
/// starting with `%` are comments; four keywords set the minimum distances
/// and one lists substrings that forbid a break beside them. `NEXTLEVEL`
/// splits the file into an outer level that finds compound boundaries and an
/// inner one that hyphenates what lies between them.
///
/// ### Why it reads like a file rather than a string
/// The reference implementation reads lines into a fixed 100-byte buffer,
/// and several of the format's quirks fall out of that: a line that does not
/// fit is thrown away whole, the charset line is read into a 20-byte buffer
/// whose overflow is *not* thrown away but reparsed as a pattern, and the
/// last byte of the suppression line is dropped whether or not it is a
/// newline. Dictionaries were written against that behaviour, so
/// [DictionaryLineScanner] reproduces it instead of splitting on `\n` and hoping.
class DictionaryParser {
  DictionaryParser(List<int> source)
    : _bytes = source is Uint8List ? source : Uint8List.fromList(source);

  final Uint8List _bytes;

  /// Reads the whole file and returns its outermost level.
  ///
  /// Never rejects a file. An empty one yields a dictionary that hyphenates
  /// nothing, which is what the reference implementation does; anything
  /// stricter would turn a harmless asset mistake into a crash at startup.
  PatternSet parse() {
    final scanner = DictionaryLineScanner(_bytes);
    final pool = ReplacementPool();
    final charsetName = _readCharsetName(scanner);
    final isUtf8 =
        DictionaryCharset.fromHeader(charsetName) == DictionaryCharset.utf8;

    // The first section of the file is always the one carrying the real
    // patterns. It only becomes the *inner* level if a NEXTLEVEL keyword
    // turns up to give it an outer one.
    final patterns = LevelDraft(isUtf8: isUtf8, replacements: pool);
    final compounds = LevelDraft(isUtf8: isUtf8, replacements: pool);

    if (_readSection(scanner, patterns)) {
      _readSection(scanner, compounds);
      pool.seal();
      return patterns.build(
        charsetName,
        inner: compounds.build(charsetName, inner: null),
      );
    }

    // No NEXTLEVEL: the outer level is invented from the punctuation rules
    // alone. It still answers for the word-level minimums, so it inherits
    // them, and it makes compound minimums up when the file states none.
    _addPunctuationRules(compounds, isUtf8: isUtf8);
    pool.seal();
    return PatternSet(
      automaton: compounds.trie.finish(),
      limits: EdgeLimits(
        left: patterns.left,
        right: patterns.right,
        compoundLeft: patterns.compoundLeft != 0
            ? patterns.compoundLeft
            : (patterns.left != 0 ? patterns.left : 3),
        compoundRight: patterns.compoundRight != 0
            ? patterns.compoundRight
            : (patterns.right != 0 ? patterns.right : 3),
      ),
      suppressions: compounds.suppressions,
      charsetIsUtf8: isUtf8,
      charsetName: charsetName,
      inner: patterns.build(charsetName, inner: null),
    );
  }

  String _readCharsetName(DictionaryLineScanner scanner) {
    final line = scanner.next(budget: kCharsetBudget, discardOverflow: false);
    if (line == null) {
      return '';
    }
    final end = trimLineEnd(line, 0, line.length);
    var nul = 0;
    while (nul < end && line[nul] != 0) {
      nul++;
    }
    return String.fromCharCodes(line, 0, nul);
  }

  /// Reads lines into [draft]. Returns whether it stopped at a `NEXTLEVEL`
  /// keyword rather than at the end of the file.
  bool _readSection(DictionaryLineScanner scanner, LevelDraft draft) {
    while (true) {
      final line = scanner.next();
      if (line == null) {
        return false;
      }
      if (scanner.overflowed) {
        continue;
      }
      if (startsWithKeyword(line, 'NEXTLEVEL')) {
        return true;
      }
      if (line.isNotEmpty && line[0] != kPercent) {
        draft.readLine(line);
      }
    }
  }

  /// The outer level a dictionary without `NEXTLEVEL` gets: break at an
  /// existing hyphen or apostrophe, and never leave one stranded.
  void _addPunctuationRules(LevelDraft draft, {required bool isUtf8}) {
    if (!isUtf8) {
      draft.readLine(_ascii("NOHYPHEN ',-\n"));
    } else {
      draft.readLine(
        Uint8List.fromList(<int>[
          ..."NOHYPHEN ',".codeUnits,
          0xE2, 0x80, 0x93, // en dash
          kComma,
          0xE2, 0x80, 0x99, // right single quotation mark
          kComma, 0x2D, kNewline,
        ]),
      );
    }
    draft.readLine(_ascii('1-1\n'));
    draft.readLine(_ascii("1'1\n"));
    if (isUtf8) {
      draft.readLine(
        Uint8List.fromList(const <int>[0x31, 0xE2, 0x80, 0x93, 0x31, 0x0A]),
      );
      draft.readLine(
        Uint8List.fromList(const <int>[0x31, 0xE2, 0x80, 0x99, 0x31, 0x0A]),
      );
    }
  }

  static Uint8List _ascii(String text) => Uint8List.fromList(text.codeUnits);
}
