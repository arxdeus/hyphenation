// Benchmark for the dangling-word feature: the rule that a short word such as
// a preposition must never be left hanging at the end of a line.
//
// Run it with:
//
// ```bash
// flutter test benchmark/dangling_words_benchmark.dart
// ```
//
// Measurement is done by [bench_press](https://pub.dev/packages/bench_press),
// which calibrates a batch size so timer quantisation is negligible, detects
// steady state instead of guessing a warmup count, runs repeated trials, and
// reports a Fieller 95% confidence interval for the ratio between variants.
//
// The benchmark has three parts, in decreasing order of how much they matter:
//
//  1. `layout` - what the feature costs a real `HyphenText`. This is the only
//     number a user feels, and it is the one that justifies the design.
//  2. `matcher` - the throughput of `DanglingWords.matches` against the naive
//     `Set.contains(token.toLowerCase())` it replaced. This keeps the probe
//     table honest.
//  3. `rewriting` - the approach that was *not* taken, kept as evidence.
//
// What the numbers say, measured on an M-series Mac:
//
//  - End to end the feature is free: laying out a `HyphenText` measures 0.96x
//    with it on, CI [0.88, 1.05], which is indistinguishable from off.
//  - Breaking alone costs about 11% more (1.11x). Almost none of that is the
//    probe, which is 0.66us against the 563us the break spends measuring
//    candidate lines in the engine. It is that suppressing a break changes
//    which lines are chosen: on the prose sample the glued version needs 31
//    lines where the plain one needs 30, and a line is a measurement or two.
//    That extra line is the typographic price of the rule itself, not an
//    implementation cost; a no-break space would pay it too.
//  - The matcher is roughly 12x faster than the `Set<String>` it replaced,
//    and unlike it allocates nothing.
//
// Why the text is not rewritten
//
// The obvious implementation glues the words by editing the string: replace
// the space after a dangling word with U+00A0, which the breaker never breaks
// at. The `rewriting` group measures that approach, both naively and after
// hard optimisation, because it is what this package used to do in its
// example app and it is what most implementations of this rule do.
//
// It loses on every axis:
//
//  - It allocates a whole new string per call, on a path that runs during
//    layout. Suppressing the break allocates nothing.
//  - It puts characters into the text that the caller never wrote, which
//    survive into selection, semantics and the clipboard.
//  - It gets `minIntrinsicWidth` right only by accident. Break suppression
//    shares its candidate list with the intrinsics path, so a glued pair is
//    treated as one unbreakable chunk for free.
//
// The optimised rewrite below is about 7-10x faster than the naive one and it
// is still the wrong answer. That is the point of keeping it: making the
// rewrite fast is what demonstrated it was not worth doing.
//
// How the matcher got fast, in case it needs changing:
//
//  - The length prefilter is the biggest single win. A token can only match
//    if it is no longer than the longest listed word, so an ordinary word is
//    rejected by one integer comparison without reading a character. In prose
//    that is almost every token.
//  - The words live in an open-addressed `Int32List` table rather than a
//    `Set<String>`, so a probe is an array index instead of a hash-map lookup
//    with boxed keys and bucket objects, and it needs no substring.
//  - Case folding is a branch on the code unit for ASCII and Cyrillic, with a
//    fallback to `String.toLowerCase` for anything else, so correctness does
//    not depend on the alphabet. The folded token goes into a reusable
//    scratch buffer, so confirming a hit does not fold it a second time.
//
// Tried and rejected in the matcher:
//
//  - Packing the folded code units into a single int key (6 bits each) to get
//    a `Set<int>` probe. The alphabet needed is Latin, Cyrillic, digits and
//    the hyphen, over 64 symbols, so the packing needs more bits than a
//    9-character word leaves in a 64-bit int.
//  - Trusting the hash and skipping verification. It saves a loop over at
//    most 9 units on the rare tokens that reach it, which does not show up
//    against the prefilter, and it turns a collision into a silently wrong
//    document.

import 'dart:typed_data';

import 'package:bench_press/bench_press.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/test_dictionaries.dart';
import 'text_layout_benchmark.dart' show buildHost, kStyle, pumpSync;

/// Realistic prose: a normal density of short words to glue.
const String kProse =
    'Programming with Flutter is an interesting and entertaining occupation. '
    'Internationalization of an application guarantees the immediate '
    'availability of its content. The direct interaction of a user with the '
    'interface demands extraordinary attention to typography and to '
    'hyphenation. The improvement of computational systems continues '
    'uninterrupted, and performance remains the determining factor. Because '
    'of the way a column is set, the text under a heading, and also before '
    'an illustration, looks better if not one preposition is left hanging at '
    'the end of a line.';

/// Nothing to glue: long words only, so the pass is pure overhead.
const String kNoMatches =
    'Internationalization frameworks generally require careful consideration '
    'whenever typography interacts with localisation, because hyphenation '
    'dictionaries describe intraword opportunities exclusively, never '
    'addressing interword relationships between neighbouring constituents.';

/// Worst case: every token is a listed word, so every gap is a candidate.
final String kAllShort = List<String>.filled(
  120,
  'in and the of from as that',
).join(' ');

/// A long document, the size at which this would actually be noticed.
final String kDocument = List<String>.filled(40, kProse).join(' ');

/// Punctuation-heavy text, which exercises the rejection paths.
const String kPunctuated =
    '"The" — this is, to my mind, not (quite) it; "out-of" and "up-to" too: '
    'see p. 42, sec. 3.1, and also A. B. Author, "The Bronze Rider" [1837].';

/// Layout benchmarks are far slower than the microbenchmarks bench_press is
/// tuned for, so the budgets are widened to keep a run to a few seconds.
const BenchmarkConfig kLayoutConfig = BenchmarkConfig(
  trials: 10,
  minWarmupIterations: 3,
  maxWarmupIterations: 30,
  targetBatchDuration: Duration(milliseconds: 50),
  maxWarmupDurationSeconds: 3,
);

/// Microbenchmarks are cheap, so more trials cost little.
const BenchmarkConfig kMicroConfig = BenchmarkConfig(
  trials: 25,
  targetBatchDuration: Duration(milliseconds: 20),
);

/// One baseline versus candidate comparison, rendered as a table row.
class Comparison {
  Comparison(this.name, this.units, this.baseline, this.candidate);

  /// What was compared.
  final String name;

  /// Characters covered by one operation, for the throughput column.
  final int units;

  /// The slower, or reference, variant.
  final BenchmarkResult baseline;

  /// The variant under test.
  final BenchmarkResult candidate;

  /// Ratio of the means, with a Fieller 95% confidence interval.
  FiellerInterval get interval => FiellerInterval.compute(
    sampleA: candidate.rawTrialLatenciesNs,
    sampleB: baseline.rawTrialLatenciesNs,
  );

  String get row {
    final ratio = interval;
    final baseUs = (baseline.metrics.medianNs / 1000).toStringAsFixed(2);
    final candUs = (candidate.metrics.medianNs / 1000).toStringAsFixed(2);
    final mcps = units / candidate.metrics.medianNs * 1000;
    final ci = ratio.isValid
        ? '[${ratio.lowerBound.toStringAsFixed(2)}, '
              '${ratio.upperBound.toStringAsFixed(2)}]'
        : 'n/a';
    return '${name.padRight(26)}'
        '${units.toString().padLeft(7)}'
        '${baseUs.padLeft(10)}'
        '${candUs.padLeft(10)}'
        '${'${ratio.ratio.toStringAsFixed(2)}x'.padLeft(8)}'
        '${ci.padLeft(16)}'
        '${mcps.toStringAsFixed(0).padLeft(9)}';
  }
}

// ---------------------------------------------------------------------------
// The rejected approach: rewriting the text with no-break spaces.
// ---------------------------------------------------------------------------

/// The naive rewrite, as it was written before any optimisation.
///
/// Three substrings and a `toLowerCase` per token, all discarded immediately,
/// into a `StringBuffer` that is written even when the result is identical to
/// the input.
String naiveRewrite(String text, Set<String> words) {
  final buffer = StringBuffer();
  var index = 0;
  var atWordStart = true;
  while (index < text.length) {
    final unit = text.codeUnitAt(index);
    if (unit == 0x20 || unit == 0x09 || unit == 0x0A) {
      buffer.writeCharCode(unit);
      atWordStart = true;
      index++;
      continue;
    }
    final start = index;
    while (index < text.length && text.codeUnitAt(index) != 0x20) {
      index++;
    }
    final token = text.substring(start, index);
    buffer.write(token);
    final spaceStart = index;
    while (index < text.length && text.codeUnitAt(index) == 0x20) {
      index++;
    }
    final spaces = text.substring(spaceStart, index);
    final core = _naiveCore(token);
    final glue =
        atWordStart &&
        spaces == ' ' &&
        core.isNotEmpty &&
        core.length == token.length &&
        words.contains(core.toLowerCase());
    buffer.write(glue ? '\u00A0' : spaces);
    atWordStart = spaces.isNotEmpty;
  }
  return buffer.toString();
}

String _naiveCore(String token) {
  var start = 0;
  var end = token.length;
  while (start < end && !_naiveIsWordUnit(token.codeUnitAt(start))) {
    start++;
  }
  while (end > start && !_naiveIsWordUnit(token.codeUnitAt(end - 1))) {
    end--;
  }
  return token.substring(start, end);
}

bool _naiveIsWordUnit(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    (unit >= 0x0410 && unit <= 0x044F) ||
    unit == 0x0401 ||
    unit == 0x0451 ||
    unit == 0x2D;

/// The rewrite after hard optimisation, for the fairest possible comparison.
///
/// Scans code units without materialising a token, probes the compiled
/// [DanglingWords] table, and returns the input instance untouched when there
/// is nothing to glue. Gluing swaps one space for one no-break space, so the
/// result is exactly as long as the input and is produced by patching a single
/// copy rather than by concatenation.
///
/// Even so, see the file header: this is the approach the package does not
/// use.
String optimisedRewrite(String text, DanglingWords words) {
  final length = text.length;
  Uint16List? out;
  var index = 0;
  var atWordStart = true;
  while (index < length) {
    final unit = text.codeUnitAt(index);
    if (unit == 0x20 || unit == 0x09 || unit == 0x0A) {
      atWordStart = true;
      index++;
      continue;
    }
    final start = index;
    do {
      index++;
    } while (index < length && text.codeUnitAt(index) != 0x20);
    final tokenEnd = index;
    final spaceStart = index;
    while (index < length && text.codeUnitAt(index) == 0x20) {
      index++;
    }
    final spaceCount = index - spaceStart;
    if (atWordStart &&
        spaceCount == 1 &&
        words.matches(text, start, tokenEnd)) {
      (out ??= _copyOf(text))[spaceStart] = 0x00A0;
    }
    atWordStart = spaceCount != 0;
  }
  if (out == null) {
    return text;
  }
  return String.fromCharCodes(out);
}

/// `Uint16List.fromList(text.codeUnits)` reads through a `List<int>` view
/// whose `[]` is a virtual call per character; this measured faster.
Uint16List _copyOf(String text) {
  final length = text.length;
  final units = Uint16List(length);
  for (var i = 0; i < length; i++) {
    units[i] = text.codeUnitAt(i);
  }
  return units;
}

/// Splits [text] into word ranges, the way the line breaker does.
///
/// Returned as flat start/end pairs so the matcher can be measured on ranges
/// of the original string, which is how it is actually called.
Int32List wordRanges(String text) {
  final bounds = <int>[];
  var index = 0;
  while (index < text.length) {
    while (index < text.length && text.codeUnitAt(index) == 0x20) {
      index++;
    }
    if (index >= text.length) {
      break;
    }
    final start = index;
    while (index < text.length && text.codeUnitAt(index) != 0x20) {
      index++;
    }
    bounds
      ..add(start)
      ..add(index);
  }
  return Int32List.fromList(bounds);
}

void main() {
  final comparisons = <Comparison>[];
  final words = DanglingWords.english;

  Future<void> compare(
    String name,
    int units,
    String baselineName,
    void Function() baseline,
    String candidateName,
    void Function() candidate, {
    BenchmarkConfig config = kMicroConfig,
  }) async {
    final group = BenchmarkGroup.compare(
      name: name,
      baseline: (baselineName, baseline),
      candidates: <String, dynamic Function()>{candidateName: candidate},
      config: config,
    );
    final results = <BenchmarkResult>[];
    for (final variant in group.variants) {
      results.add(await variant.report(config: config));
    }
    comparisons.add(Comparison(name, units, results[0], results[1]));
  }

  tearDownAll(() {
    final buffer = StringBuffer()
      ..writeln()
      ..writeln('=' * 86)
      ..writeln(
        '  Dangling words   (median us/op, Fieller 95% CI on the ratio)',
      )
      ..writeln('=' * 86)
      ..writeln(
        '${'scenario'.padRight(26)}${'chars'.padLeft(7)}'
        '${'baseline'.padLeft(10)}${'candidate'.padLeft(10)}'
        '${'ratio'.padLeft(8)}${'95% CI'.padLeft(16)}${'Mchar/s'.padLeft(9)}',
      )
      ..writeln('-' * 86);
    for (final comparison in comparisons) {
      buffer.writeln(comparison.row);
    }
    buffer
      ..writeln('=' * 86)
      ..writeln(
        'Ratio < 1 means the candidate is faster. The last column is the '
        'candidate only.',
      )
      ..writeln('=' * 86);
    // ignore: avoid_print
    print(buffer);
  });

  group('layout', () {
    // What the feature costs where it runs. Both rows disable the paragraph
    // break cache, because a cached paragraph does no breaking at all and
    // would measure nothing but the engine laying the result out again.
    testWidgets('breaking a paragraph', (WidgetTester tester) async {
      final painter = TextPainter(textDirection: TextDirection.ltr);
      double measure(String text) {
        painter
          ..text = TextSpan(text: text, style: kStyle)
          ..layout();
        return painter.width;
      }

      final plain = loadEnglishHyphenator();
      final glued = loadEnglishHyphenator(
        danglingWords: kEnglishDanglingWords,
      );
      // Warm the word cache, so dictionary lookups are not what is measured.
      plain.hyphenate(kProse);
      glued.hyphenate(kProse);

      // A fresh breaker per iteration, so every call breaks from scratch.
      // This isolates the breaker: no widget, no engine relayout.
      void breakWith(Hyphenator hyphenator) {
        Blackhole.consume(
          HyphenLineBreaker(
            measure: measure,
            hyphenator: hyphenator,
          ).breakText(kProse, 320),
        );
      }

      await compare(
        'break from scratch',
        kProse.length,
        'off',
        () => breakWith(plain),
        'on',
        () => breakWith(glued),
        config: kLayoutConfig,
      );

      // The ratio is only interpretable next to the line counts. Removing
      // break opportunities forces earlier breaks, so the paragraph can end
      // up with an extra line, and a line costs measurements. That is where
      // the difference is, not in the probe.
      final without = HyphenLineBreaker(
        measure: measure,
        hyphenator: plain,
      ).breakText(kProse, 320);
      final glue = HyphenLineBreaker(
        measure: measure,
        hyphenator: glued,
      ).breakText(kProse, 320);
      // ignore: avoid_print
      print(
        '\nLines for the prose sample at 320px:\n'
        '  off: ${without.length}\n'
        '  on:  ${glue.length}',
      );
      painter.dispose();
    });

    testWidgets('laying out a HyphenText', (WidgetTester tester) async {
      // End to end, including the engine. The line counts differ between the
      // two variants, which is a real effect of the rule rather than an
      // artefact: refusing a break forces an earlier one, so a line can end
      // short and the paragraph can gain a line.
      // One shared engine, and no paragraph break cache: otherwise the first
      // iteration breaks the paragraph and every later one is answered from
      // the cache, which would measure the engine rather than the feature.
      final engine = loadEnglishHyphenator().dictionary;
      final plain = Hyphenator(engine, maxParagraphCacheSize: 0);
      final glued = Hyphenator(
        engine,
        maxParagraphCacheSize: 0,
        danglingWords: kEnglishDanglingWords,
      );
      plain.hyphenate(kProse);
      glued.hyphenate(kProse);

      var seed = 0;
      void pump(Hyphenator hyphenator) {
        pumpSync(
          tester,
          buildHost(
            KeyedSubtree(
              key: ValueKey<int>(seed++),
              child: HyphenText(
                kProse,
                style: kStyle,
                hyphenator: hyphenator,
              ),
            ),
            320,
          ),
        );
      }

      await compare(
        'HyphenText layout',
        kProse.length,
        'off',
        () => pump(plain),
        'on',
        () => pump(glued),
        config: kLayoutConfig,
      );
    });
  });

  group('matcher', () {
    // DanglingWords.matches against the Set<String> it replaced, over the word
    // ranges of a paragraph, which is exactly how the breaker calls it.
    Future<void> measure(String name, String text) async {
      final ranges = wordRanges(text);
      final count = ranges.length >> 1;
      final source = words.source;

      expect(
        <bool>[
          for (var i = 0; i < count; i++)
            words.matches(text, ranges[i * 2], ranges[i * 2 + 1]),
        ],
        isNotEmpty,
        reason: 'the corpus must contain words to probe',
      );

      await compare(
        name,
        text.length,
        'Set<String>',
        () {
          for (var i = 0; i < count; i++) {
            final token = text.substring(ranges[i * 2], ranges[i * 2 + 1]);
            Blackhole.consume(source.contains(token.toLowerCase()));
          }
        },
        'DanglingWords',
        () {
          for (var i = 0; i < count; i++) {
            Blackhole.consume(
              words.matches(text, ranges[i * 2], ranges[i * 2 + 1]),
            );
          }
        },
      );
    }

    test('prose', () => measure('probe: prose', kProse));
    test('document', () => measure('probe: document', kDocument));
    test('no matches', () => measure('probe: nothing to glue', kNoMatches));
    test('all short', () => measure('probe: every word listed', kAllShort));
    test('punctuated', () => measure('probe: punctuation heavy', kPunctuated));
  });

  group('rewriting', () {
    // The approach this package does not use, kept as evidence. See the file
    // header for why a 7-10x faster rewrite is still the wrong answer.
    Future<void> measure(String name, String text) async {
      final source = words.source;
      await compare(
        name,
        text.length,
        'naive rewrite',
        () => Blackhole.consume(naiveRewrite(text, source)),
        'optimised rewrite',
        () => Blackhole.consume(optimisedRewrite(text, words)),
      );
    }

    test('prose', () => measure('rewrite: prose', kProse));
    test('document', () => measure('rewrite: document', kDocument));
    test('all short', () => measure('rewrite: every word listed', kAllShort));

    test('the optimised rewrite still allocates a new string', () {
      // Which is the whole objection to it: this runs during layout.
      final rewritten = optimisedRewrite(kProse, words);
      expect(identical(rewritten, kProse), isFalse);
      expect(rewritten.contains('\u00A0'), isTrue);
      expect(rewritten.length, kProse.length);
      // Break suppression produces no such string at all.
      expect(kProse.contains('\u00A0'), isFalse);
    });
  });
}
