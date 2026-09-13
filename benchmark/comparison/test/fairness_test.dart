// Explicit minima document the controlled configuration.
// ignore_for_file: avoid_redundant_argument_values
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyphen/hyphen.dart';
import 'package:hyphenation/hyphenation.dart' as ours;
import 'package:hyphenator_impure/hyphenator.dart' as impure;

import '../benchmark/support/corpora.dart';
import '../benchmark/support/flutter_adapters.dart';
import '../benchmark/support/measure.dart';
import '../benchmark/support/reporting.dart';

void main() {
  test('zero-variance Fieller interval is a valid point', () {
    final result = RatioInterval.compute(
      Measurement('a', [2, 2, 2], 1),
      Measurement('b', [1, 1, 1], 1),
    );
    expect(result.isValid, isTrue);
    expect([result.ratio, result.low, result.high], [2, 2, 2]);
  });
  test('invalid intervals serialize as null and raw trials persist', () {
    final row = ComparisonRow(
      name: 'test',
      units: 'words',
      unitCount: 1,
      results: {
        'base': Measurement('base', [1], 1),
        'other': Measurement('other', [2], 1),
      },
    );
    final json = jsonDecode(jsonEncode(row.toJson())) as Map;
    final other = (json['packages'] as Map)['other'] as Map;
    expect(other['ratio_ci_valid'], isFalse);
    expect(other['ratio_ci_low'], isNull);
    expect(other['ratio_ci_high'], isNull);
    expect(other['trials_ns'], [2]);
  });
  test('calibration never exceeds non-power-of-two cap', () {
    final result = measure(
      'cap',
      () => Blackhole.consume(1),
      trials: 2,
      maxCalibrationIterations: 3,
      targetBatchDuration: const Duration(seconds: 1),
      warmupBudget: Duration.zero,
    );
    expect(result.batchSize, 3);
    expect(result.trialsNs, hasLength(2));
    expect(Blackhole.value, 1);
  });
  test('measurement rejects empty trials and invalid caps', () {
    expect(() => measure('x', () {}, trials: 0), throwsArgumentError);
    expect(
      () => measure('x', () {}, maxCalibrationIterations: 0),
      throwsArgumentError,
    );
    expect(() => measureGroup({}), throwsArgumentError);
  });
  test('group rotates timed trial order and retains each sample', () {
    final calls = <String>[];
    final results = measureGroup(
      {
        for (final name in ['a', 'b', 'c']) name: () => calls.add(name),
      },
      trials: 3,
      warmupBudget: Duration.zero,
      maxCalibrationIterations: 1,
    );
    expect(
      calls,
      hasLength(24),
      reason: '6 calibration calls, 9 fixed prewarm calls, 9 retained calls',
    );
    expect(calls.skip(calls.length - 9), [
      'a',
      'b',
      'c',
      'b',
      'c',
      'a',
      'c',
      'a',
      'b',
    ]);
    expect(results.keys, ['a', 'b', 'c']);
    for (final result in results.values) {
      expect(result.trialsNs, hasLength(3));
      expect(result.batchSize, 1);
    }
  });
  test('corpus is frozen unique alphabetic and bounded', () {
    final words = uniqueWords(2000);
    expect(words, uniqueWords(2000));
    expect(words.toSet(), hasLength(2000));
    expect(words.every((word) => RegExp(r'^[a-z]+$').hasMatch(word)), isTrue);
    expect(() => uniqueWords(30000), throwsRangeError);
  });
  test('paragraph adapter retains punctuation and whitespace', () {
    final seen = <String>[];
    final output = hyphenateParagraph('Abc,  def!\nGhi.', (word) {
      seen.add(word);
      return [word.substring(0, 1), word.substring(1)];
    });
    expect(seen, ['Abc', 'def', 'Ghi']);
    expect(output, 'A\u00adbc,  d\u00adef!\nG\u00adhi.');
    expect(output.replaceAll('\u00ad', ''), 'Abc,  def!\nGhi.');
  });
  test('TeX and JSON preserve tokens, Hunspell expands equivalent states', () {
    final tokens = controlledPatternTokens();
    final loader = ImpureFileLoader(controlledPatternSource());
    expect(tokens.length, greaterThan(4000));
    expect(loader.patternsStrings.toList(), tokens);
    expect(loader.exceptionsStrings, isEmpty);
    final config = jsonDecode(controlledHyphenatorxSource()) as Map;
    final recovered = <String>[];
    for (final raw in config['pattern'] as List) {
      final pattern = raw as Map;
      final letters = pattern['result'] as String;
      final levels = pattern['levels'] as List;
      final token = StringBuffer();
      for (var i = 0; i <= letters.length; i++) {
        if (levels[i] != 0) token.write(levels[i]);
        if (i < letters.length) token.write(letters[i]);
      }
      recovered.add(token.toString());
    }
    expect(recovered, tokens);
    expect(config['exception'], isEmpty);
    final compiled = utf8
        .decode(controlledHunspellBytes())
        .split('\n')
        .skip(3)
        .where((s) => s.isNotEmpty)
        .toList();
    expect(compiled, hasLength(6400));
    expect(compiled, contains('.a2ch4'));
    final official = File('test/fixtures/hunspell_controlled.dic')
        .readAsLinesSync()
        .skip(3)
        .toList();
    expect(
      compiled..sort(),
      official,
      reason: 'Full normalized official substrings.pl golden',
    );
  });
  test(
    'Hunspell preprocessing closes prefix outputs and merges suffix maxima',
    () {
      final bytes = compileHunspellPatterns(['a1b', 'xab4c', 'b3c']);
      expect(
        utf8.decode(bytes),
        'UTF-8\nLEFTHYPHENMIN 3\nRIGHTHYPHENMIN 3\n'
        'a1b\nb3c\nxa1b\nxab4c\n',
      );
      final dictionary = Hyphen.fromDictionaryBytes(bytes);
      // a1b supplies offset 3, while max(4,3) suppresses offset 4.
      expect(dictionary.hyphenate('xxabcxx', lhmin: 3, rhmin: 3), [
        'xxa',
        'bcxx',
      ]);
      final duplicate = compileHunspellPatterns(['a1b', 'a2b']);
      expect(utf8.decode(duplicate).split('\n'), contains('a2b'));
      expect(
        () => compileHunspellPatterns(['a1b/replacement']),
        throwsArgumentError,
      );
    },
  );
  test(
    'compiled Hunspell preserves shared rule semantics across frozen corpus',
    () {
      final dictionary = Hyphen.fromDictionaryBytes(controlledHunspellBytes());
      final own = ours.Hyphenator.fromSource(
        controlledPatternSource(),
        leftMin: 3,
        rightMin: 3,
      );
      for (final word in [
        ...kProse.map((w) => w.toLowerCase()),
        ...kLongWords,
        ...uniqueWords(2000),
      ]) {
        expect(
          dictionary.hyphenate(word, lhmin: 3, rhmin: 3),
          own.split(word),
          reason: word,
        );
      }
    },
  );
  test('controlled engines preserve words and enforce actual minima 3/3', () {
    final source = controlledPatternSource();
    final own = ours.Hyphenator.fromSource(source, leftMin: 3, rightMin: 3);
    final other = impure.Hyphenator(
      resource: ImpureFileLoader(source),
      minLetterCount: 3,
    );
    final x = buildHyphenatorx(controlledHyphenatorxSource());
    final hyphen = Hyphen.fromDictionaryBytes(controlledHunspellBytes());
    for (final word in {...kProse, ...kLongWords, ...uniqueWords(32)}) {
      for (final parts in [
        own.split(word),
        other.hyphenateWordToList(word),
        x.syllablesWord(word),
        hyphen.hyphenate(word, lhmin: 3, rhmin: 3),
      ]) {
        expect(parts.join(), word);
        var offset = 0;
        for (final part in parts.take(parts.length - 1)) {
          offset += part.length;
          expect(offset, greaterThanOrEqualTo(3), reason: '$word $parts');
          expect(
            word.length - offset,
            greaterThanOrEqualTo(3),
            reason: '$word $parts',
          );
        }
      }
    }
  });
}
