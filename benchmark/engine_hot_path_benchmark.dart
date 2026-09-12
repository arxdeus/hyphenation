// Pure-Dart engine hot paths. Run with `dart run` or `dart compile exe`.
// The optional first argument is the number of measured calls per scenario.
// JSON output reports ns/call and a checksum, not a wall-clock score.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_hyphen/src/model/hyphenation_dictionary.dart';

void main(List<String> args) {
  final runs = args.isEmpty ? 200000 : int.parse(args.first);
  final english = HyphenationDictionary.parse(
    File('example/assets/dictionary/hyph_en_US.dic').readAsBytesSync(),
  );
  final rewrite = HyphenationDictionary.parse(
    utf8.encode(
      'UTF-8\nd3d1ze/dz=,1,1\na1b/x=y,1,2\nä1ö\n',
    ),
  );
  const prose = [
    'Internationalization',
    'localization',
    'complementary',
    'disciplines',
    'determine',
    'whether',
    'application',
    'feels',
    'native',
    'people',
    'Typography',
    'impression',
    'justified',
    'columns',
    'unhyphenated',
    'whitespace',
    'paragraph',
    'unusually',
    'technical',
    'vocabulary',
    'container',
    'Dictionary',
    'hyphenation',
    'computed',
    'incrementally',
    'memoised',
    'implementation',
    'responsibilities',
    'considerations',
    'representations',
    'unquestionably',
    'straightforwardly',
  ];
  final scenarios = <String, (HyphenationDictionary, List<String>, bool)>{
    'english_mark': (english, prose, false),
    'english_split': (english, prose, true),
    'compounds_mark': (
      english,
      [
        'dictionary-based',
        'straightforwardly-unquestionably',
        'well-known',
        'state-of-the-art',
        'mother-in-law',
      ],
      false,
    ),
    'unicode_mark': (
      english,
      [
        'naïveté',
        'café',
        'überraschung',
        'программирование',
        '日本語',
        'a😀hyphenation',
        'ﬃnancial',
      ],
      false,
    ),
    'rewrites_mark': (
      rewrite,
      [
        'addze',
        'aaddze',
        'abaddze',
        'addze-addze',
        'äöaddze',
        'plain',
      ],
      false,
    ),
  };
  final results = <String, Object>{};
  for (final entry in scenarios.entries) {
    final (dictionary, words, split) = entry.value;
    var sink = 0;
    void work(int count) {
      var index = 0;
      for (var i = 0; i < count; i++) {
        final word = words[index];
        if (++index == words.length) index = 0;
        if (split) {
          sink += dictionary.split(word, leftMin: 2, rightMin: 2).length;
        } else {
          sink += dictionary.markWord(word, leftMin: 2, rightMin: 2);
          sink += dictionary.marks[1];
        }
      }
    }

    work(50000);
    final watch = Stopwatch()..start();
    work(runs);
    watch.stop();
    results[entry.key] = {
      'ns_per_call': watch.elapsedMicroseconds * 1000 / runs,
      'checksum': sink,
    };
  }
  print(jsonEncode(results));
}
