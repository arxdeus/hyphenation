// Output agreement characterization, not linguistic correctness.
// Run: cd benchmark/comparison && flutter test benchmark/quality_comparison.dart
// No implementation or unsourced dictionary transcription is an oracle here.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyphen/hyphen.dart' as hyphen_pkg;
import 'package:hyphenation/hyphenation.dart' as ours;
import 'package:hyphenator_impure/hyphenator.dart' as impure;

import 'support/corpora.dart';
import 'support/flutter_adapters.dart';

/// Validate the structural contract before comparing UTF-16 break offsets.
/// Interior Unicode scalar boundaries are necessary, not proof of linguistically
/// appropriate hyphenation. The measured corpus is lowercase ASCII.
Set<int> checkedOffsets(String name, String word, List<String> parts) {
  final context = '$name splitting "$word": $parts';
  expect(parts, isNotEmpty, reason: context);
  expect(parts.join(), word, reason: 'Input preservation: $context');
  expect(parts.every((part) => part.isNotEmpty), isTrue, reason: context);
  final offsets = <int>{};
  var position = 0;
  for (var i = 0; i < parts.length - 1; i++) {
    position += parts[i].length;
    expect(position, inExclusiveRange(0, word.length), reason: context);
    final previous = word.codeUnitAt(position - 1);
    final next = word.codeUnitAt(position);
    expect(
      previous >= 0xd800 &&
          previous <= 0xdbff &&
          next >= 0xdc00 &&
          next <= 0xdfff,
      isFalse,
      reason: 'Split must not bisect a surrogate pair: $context',
    );
    expect(offsets.add(position), isTrue, reason: context);
  }
  return offsets;
}

void main() {
  test('structural checks reject invalid splitter output', () {
    expect(checkedOffsets('test', 'abcd', ['ab', 'cd']), {2});
    expect(
      () => checkedOffsets('test', 'abcd', ['ab', 'ce']),
      throwsA(isA<TestFailure>()),
    );
    expect(
      () => checkedOffsets('test', 'abcd', ['', 'abcd']),
      throwsA(isA<TestFailure>()),
    );
    expect(
      () => checkedOffsets('test', '😀x', ['\ud83d', '\ude00x']),
      throwsA(isA<TestFailure>()),
    );
  });

  test('pairwise output agreement and structural integrity', () {
    // Common source rules, with required format-specific preprocessing.
    // Exceptions are omitted for every implementation.
    // Symmetric 3/3 minima also respect hyphenation's en_US right-minimum floor.
    final ourHyphenator = ours.Hyphenator.fromSource(
      controlledPatternSource(),
      leftMin: 3,
      rightMin: 3,
    );
    final xHyphenator = buildHyphenatorx(controlledHyphenatorxSource());
    final impureHyphenator = impure.Hyphenator(
      resource: ImpureFileLoader(controlledPatternSource()),
      // Explicit benchmark configuration, rather than a bundled-default claim.
      // ignore: avoid_redundant_argument_values
      minLetterCount: 3,
    );
    final hunspell = hyphen_pkg.Hyphen.fromDictionaryBytes(
      controlledHunspellBytes(),
    );
    final corpus = <String>[
      ...kProse.map((word) => word.toLowerCase()),
      ...kLongWords,
      ...uniqueWords(1000),
    ];
    expect(corpus, isNotEmpty);
    expect(corpus.every((word) => RegExp(r'^[a-z]+$').hasMatch(word)), isTrue);
    final splitters = <String, List<String> Function(String)>{
      'hyphenation': ourHyphenator.split,
      'hyphenatorx': xHyphenator.syllablesWord,
      'hyphenator_impure': impureHyphenator.hyphenateWordToList,
      'hyphen': (word) => hunspell.hyphenate(word, lhmin: 3, rhmin: 3),
    };
    final offsets = <String, List<Set<int>>>{
      for (final entry in splitters.entries)
        entry.key: [
          for (final word in corpus)
            checkedOffsets(entry.key, word, entry.value(word)),
        ],
    };
    for (final entry in offsets.entries) {
      for (var i = 0; i < corpus.length; i++) {
        for (final offset in entry.value[i]) {
          expect(
            offset,
            greaterThanOrEqualTo(3),
            reason: '${entry.key} left minimum on ${corpus[i]}',
          );
          expect(
            corpus[i].length - offset,
            greaterThanOrEqualTo(3),
            reason: '${entry.key} right minimum on ${corpus[i]}',
          );
        }
      }
    }
    final packages = <String, Object?>{};
    for (final name in splitters.keys) {
      final own = offsets[name]!;
      final breaks = own.fold<int>(0, (sum, value) => sum + value.length);
      final wordsWithBreak = own.where((value) => value.isNotEmpty).length;
      packages[name] = {
        'break_points': breaks,
        'break_points_per_word': breaks / corpus.length,
        'words_with_at_least_one_break': wordsWithBreak,
        'words_with_at_least_one_break_pct':
            100 * wordsWithBreak / corpus.length,
        'input_preservation_and_valid_boundaries_checked': own.length,
      };
    }
    final pairwise = <Map<String, Object?>>[];
    final names = splitters.keys.toList();
    for (var a = 0; a < names.length; a++) {
      for (var b = a + 1; b < names.length; b++) {
        var identical = 0;
        var shared = 0;
        var onlyA = 0;
        var onlyB = 0;
        var eitherBreaks = 0;
        var identicalWithBreaks = 0;
        final examples = <Map<String, Object?>>[];
        for (var i = 0; i < corpus.length; i++) {
          final left = offsets[names[a]]![i];
          final right = offsets[names[b]]![i];
          final same = left.length == right.length && left.containsAll(right);
          if (same) identical++;
          if (left.isNotEmpty || right.isNotEmpty) {
            eitherBreaks++;
            if (same) identicalWithBreaks++;
          }
          shared += left.intersection(right).length;
          onlyA += left.difference(right).length;
          onlyB += right.difference(left).length;
          if (!same && examples.length < 8) {
            examples.add({
              'word': corpus[i],
              'a_offsets': left.toList()..sort(),
              'b_offsets': right.toList()..sort(),
            });
          }
        }
        final union = shared + onlyA + onlyB;
        pairwise.add({
          'a': names[a],
          'b': names[b],
          'words_identical': identical,
          'words_identical_pct': 100 * identical / corpus.length,
          'words_with_break_in_either': eitherBreaks,
          'words_identical_with_breaks': identicalWithBreaks,
          'words_identical_pct_among_either_with_breaks': eitherBreaks == 0
              ? null
              : 100 * identicalWithBreaks / eitherBreaks,
          'shared_break_points': shared,
          'a_only_break_points': onlyA,
          'b_only_break_points': onlyB,
          'break_point_jaccard': union == 0 ? null : shared / union,
          'first_disagreement_examples': examples,
        });
      }
    }
    final report = <String, Object?>{
      'suite': 'output_agreement',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'interpretation':
          'Agreement is not correctness. More or fewer break '
          'opportunities is not a quality ranking. No linguistic oracle is used.',
      'scope':
          'Lowercase ASCII prose/long words and synthetic suffixed tokens. '
          'Structural checks do not establish linguistic correctness or general '
          'Unicode support. Synthetic tokens are not representative English.',
      'offset_unit': 'UTF-16 code units',
      'configuration': {
        'patterns':
            'Common source rules from hyph-en-us.tex with required '
            'format-specific preprocessing (including Hunspell closure)',
        'exceptions': 'Excluded for every implementation',
        'left_min': 3,
        'right_min': 3,
        'hyphenatorx_and_impure_minLetterCount': 3,
        'notes':
            'Both minLetterCount APIs are configurable. The controlled '
            '3/3 configuration is not a comparison of bundled defaults.',
      },
      'corpus_sampling':
          'Lowercase prose + long words + 1000 frozen synthetic suffixed '
          'tokens from shared uniqueWords(1000). Repeated words retain their '
          'occurrence weight.',
      'corpus_size': corpus.length,
      'corpus_unique_words': corpus.toSet().length,
      'corpus_words': corpus,
      'packages': packages,
      'pairwise_agreement': pairwise,
    };
    // ignore: avoid_print
    print('Output agreement, not correctness, over ${corpus.length} words.');
    for (final pair in pairwise) {
      // ignore: avoid_print
      print(
        '${pair['a']} / ${pair['b']}: '
        '${pair['words_identical']}/${corpus.length} identical words, '
        '${pair['shared_break_points']} shared, '
        '${pair['a_only_break_points']} A-only, '
        '${pair['b_only_break_points']} B-only break points.',
      );
    }
    final target = File(resultPath('quality.json'));
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  }, timeout: const Timeout(Duration(minutes: 30)));
}
