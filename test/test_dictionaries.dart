import 'dart:io';

import 'package:flutter_hyphen/flutter_hyphen.dart';

/// The English dictionary shipped with the example app.
const String kEnglishDictionaryPath =
    'example/assets/dictionary/hyph_en_US.dic';

/// Loads the example English dictionary from disk.
///
/// Widget tests cannot read real assets through `rootBundle`, so the bytes are
/// read from the repository instead.
Hyphenator loadEnglishHyphenator({
  int leftMin = 2,
  int rightMin = 2,
  int minWordLength = 5,
  Iterable<String> danglingWords = const <String>[],
}) => Hyphenator.fromBytes(
  File(kEnglishDictionaryPath).readAsBytesSync(),
  leftMin: leftMin,
  rightMin: rightMin,
  minWordLength: minWordLength,
  danglingWords: danglingWords,
);

/// A dictionary that breaks a handful of Latin words, built inline so the
/// tests do not depend on a bundled English dictionary.
///
/// The patterns use the standard TeX/the legacy engine syntax: odd digits mark a
/// hyphenation point after the preceding character.
Hyphenator loadTestLatinHyphenator({
  int minWordLength = 5,
  int leftMin = 2,
  int rightMin = 2,
  Iterable<String> danglingWords = const <String>[],
}) => Hyphenator.fromBytes(
  const <String>[
    'UTF-8',
    'hy3phen',
    'hyphen5ation',
    'in3ter',
    'na3tion',
    'al3ways',
    'won3der',
    'der3ful',
    'ex3tra',
    'tra3or',
    'or3di',
    'di3nary',
    'com3pu',
    'pu3ter',
  ].join('\n').codeUnits,
  minWordLength: minWordLength,
  leftMin: leftMin,
  rightMin: rightMin,
  danglingWords: danglingWords,
);
