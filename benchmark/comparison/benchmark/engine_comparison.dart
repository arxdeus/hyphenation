// Explicit minima document the controlled configuration.
// ignore_for_file: avoid_redundant_argument_values
// Controlled pattern-only fixture, not package default dictionaries.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyphen/hyphen.dart' as hyphen_pkg;
import 'package:hyphenation/hyphenation.dart' as ours;
import 'package:hyphenator_impure/hyphenator.dart' as impure;
import 'package:hyphenatorx/hyphenatorx.dart' as hyphenatorx;

import 'support/corpora.dart';
import 'support/flutter_adapters.dart';
import 'support/measure.dart';
import 'support/reporting.dart';

void main() {
  final report = ComparisonReport('engine');

  late String ourSource;
  late String impureSource;
  late String hyphenatorxSource;
  late List<int> hunspellBytes;

  late ours.TexHyphenationPatterns ourPatterns;
  late ours.Hyphenator ourHyphenator;
  late ours.Hyphenator ourPartsCaching;
  late impure.Hyphenator impureHyphenator;
  late hyphenatorx.Hyphenator xHyphenator;
  late hyphen_pkg.Hyphen hunspell;

  setUpAll(() {
    ourSource = ourPatternSource();
    impureSource = controlledPatternSource();
    hyphenatorxSource = controlledHyphenatorxSource();
    hunspellBytes = controlledHunspellBytes();

    ourPatterns = ours.TexHyphenationPatterns.parse(
      ourSource,
      leftMin: 3,
      rightMin: 3,
    );
    ourHyphenator = ours.Hyphenator(ourPatterns, leftMin: 3, rightMin: 3);
    // hyphenatorx caches finished part lists per word by default. This variant
    // opts into the same trade so one row compares like with like; the default
    // above keeps our shipped configuration in the table too.
    ourPartsCaching = ours.Hyphenator(
      ourPatterns,
      leftMin: 3,
      rightMin: 3,
      cacheSplitParts: true,
    );
    impureHyphenator = impure.Hyphenator(
      resource: ImpureFileLoader(impureSource),
      minLetterCount: 3,
    );
    xHyphenator = buildHyphenatorx(hyphenatorxSource);
    hunspell = hyphen_pkg.Hyphen.fromDictionaryBytes(hunspellBytes);

    report.outputs.addAll(<String, String>{
      'hyphenation': ourHyphenator.split('internationalization').join('-'),
      'hyphenatorx': xHyphenator
          .syllablesWord('internationalization')
          .join('-'),
      'hyphenator_impure': impureHyphenator
          .hyphenateWordToList('internationalization')
          .join('-'),
      'hyphen': hunspell
          .hyphenate('internationalization', lhmin: 3, rhmin: 3)
          .join('-'),
    });
  });

  tearDownAll(() {
    print(report.render());
    print('Blackhole retained ${Blackhole.value.runtimeType}');
    final target = File(resultPath('engine.json'));
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
  });

  void compare(
    String name,
    String units,
    int unitCount,
    void Function() baseline,
    Map<String, void Function()> candidates, {
    String? note,
    Duration batch = const Duration(milliseconds: 50),
    int trials = 10,
  }) {
    final results = measureGroup(
      {'hyphenation': baseline, ...candidates},
      trials: trials,
      targetBatchDuration: batch,
    );
    report.add(
      ComparisonRow(
        name: name,
        units: units,
        unitCount: unitCount,
        results: results,
        note: note,
      ),
    );
  }

  group('engine', () {
    test('load the English dictionary', () {
      compare(
        'load en-US dictionary',
        'dictionaries',
        1,
        () => Blackhole.consume(
          ours.Hyphenator(
            ours.TexHyphenationPatterns.parse(
              ourSource,
              leftMin: 3,
              rightMin: 3,
            ),
            leftMin: 3,
            rightMin: 3,
          ),
        ),
        <String, void Function()>{
          'hyphenatorx': () =>
              Blackhole.consume(buildHyphenatorx(hyphenatorxSource)),
          'hyphenator_impure': () => Blackhole.consume(
            impure.Hyphenator(resource: ImpureFileLoader(impureSource)),
          ),
          'hyphen': () => Blackhole.consume(
            hyphen_pkg.Hyphen.fromDictionaryBytes(hunspellBytes),
          ),
        },
        note: 'Same pattern tokens, no exceptions, minima 3/3. Format conversion and file reads excluded.',
        batch: const Duration(milliseconds: 200),
        trials: 5,
      );
    }, timeout: const Timeout(Duration(minutes: 20)));

    test('split prose words, warm cache', () {
      compare(
        'split 32 prose words, warm',
        'words',
        kProse.length,
        () {
          for (final word in kProse) {
            Blackhole.consume(ourHyphenator.split(word));
          }
        },
        <String, void Function()>{
          'hyphenatorx': () {
            for (final word in kProse) {
              Blackhole.consume(xHyphenator.syllablesWord(word));
            }
          },
          'hyphenator_impure': () {
            for (final word in kProse) {
              Blackhole.consume(impureHyphenator.hyphenateWordToList(word));
            }
          },
          'hyphen': () {
            for (final word in kProse) {
              Blackhole.consume(hunspell.hyphenate(word, lhmin: 3, rhmin: 3));
            }
          },
        },
        note: 'hyphenator_impure and hyphen have no word cache',
      );
    }, timeout: const Timeout(Duration(minutes: 20)));

    test('split long words, warm cache', () {
      compare(
        'split 10 long words, warm',
        'words',
        kLongWords.length,
        () {
          for (final word in kLongWords) {
            Blackhole.consume(ourHyphenator.split(word));
          }
        },
        <String, void Function()>{
          'hyphenatorx': () {
            for (final word in kLongWords) {
              Blackhole.consume(xHyphenator.syllablesWord(word));
            }
          },
          'hyphenator_impure': () {
            for (final word in kLongWords) {
              Blackhole.consume(impureHyphenator.hyphenateWordToList(word));
            }
          },
          'hyphen': () {
            for (final word in kLongWords) {
              Blackhole.consume(hunspell.hyphenate(word, lhmin: 3, rhmin: 3));
            }
          },
        },
        note:
            'Hand-selected words of 14 to 28 letters; '
            'not representative prose',
      );
    }, timeout: const Timeout(Duration(minutes: 20)));

    test('split prose words, cold cache', () {
      compare(
        'split 32 prose words, cold',
        'words',
        kProse.length,
        () {
          final fresh = ours.Hyphenator(ourPatterns, leftMin: 3, rightMin: 3);
          for (final word in kProse) {
            Blackhole.consume(fresh.split(word));
          }
        },
        <String, void Function()>{
          'hyphenatorx': () {
            xHyphenator.calc.cacheHyphendWords.clear();
            xHyphenator.calc.cacheNonHyphendWords.clear();
            xHyphenator.calc.cacheHyphenateSyllables.clear();
            xHyphenator.calc.cacheNonHyphenateSyllables.clear();
            for (final word in kProse) {
              Blackhole.consume(xHyphenator.syllablesWord(word));
            }
          },
          'hyphenator_impure': () {
            for (final word in kProse) {
              Blackhole.consume(impureHyphenator.hyphenateWordToList(word));
            }
          },
          'hyphen': () {
            final fresh = hunspell;
            for (final word in kProse) {
              Blackhole.consume(fresh.hyphenate(word, lhmin: 3, rhmin: 3));
            }
          },
        },
        note:
            'Cache reset/allocation included for cached engines; '
            'uncached engines reuse the compiled dictionary.',
        batch: const Duration(milliseconds: 200),
        trials: 5,
      );
    }, timeout: const Timeout(Duration(minutes: 20)));

    test('split 2000 distinct words', () {
      final words = uniqueWords(2000);
      compare(
        'split 2000 distinct words',
        'words',
        words.length,
        () {
          for (final word in words) {
            Blackhole.consume(ourHyphenator.split(word));
          }
        },
        <String, void Function()>{
          'hyphenation (cacheSplitParts)': () {
            for (final word in words) {
              Blackhole.consume(ourPartsCaching.split(word));
            }
          },
          'hyphenatorx': () {
            for (final word in words) {
              Blackhole.consume(xHyphenator.syllablesWord(word));
            }
          },
          'hyphenator_impure': () {
            for (final word in words) {
              Blackhole.consume(impureHyphenator.hyphenateWordToList(word));
            }
          },
          'hyphen': () {
            for (final word in words) {
              Blackhole.consume(hunspell.hyphenate(word, lhmin: 3, rhmin: 3));
            }
          },
        },
        note: 'Frozen synthetic 2000-word corpus; repeated passes, package cache policies differ. Our default rebuilds parts per call; the cacheSplitParts variant retains them as hyphenatorx does, for more memory.',
        batch: const Duration(milliseconds: 300),
        trials: 5,
      );
    }, timeout: const Timeout(Duration(minutes: 30)));

    test('hyphenate a paragraph', () {
      compare(
        'hyphenate a paragraph, common adapter',
        'chars',
        kSampleParagraph.length,
        () => Blackhole.consume(
          hyphenateParagraph(kSampleParagraph, ourHyphenator.split),
        ),
        {
          'hyphenatorx': () => Blackhole.consume(
            hyphenateParagraph(kSampleParagraph, xHyphenator.syllablesWord),
          ),
          'hyphenator_impure': () => Blackhole.consume(
            hyphenateParagraph(
              kSampleParagraph,
              impureHyphenator.hyphenateWordToList,
            ),
          ),
          'hyphen': () => Blackhole.consume(
            hyphenateParagraph(
              kSampleParagraph,
              (word) => hunspell.hyphenate(word, lhmin: 3, rhmin: 3),
            ),
          ),
        },
        note: 'Same tokenization and reassembly; no whole-paragraph cache. Minima 3/3.',
      );
    }, timeout: const Timeout(Duration(minutes: 20)));
  });
}
