// Benchmark comparing the layout cost of `Text` and `HyphenText`.
//
// Run it with:
//
// ```bash
// flutter test benchmark/text_layout_benchmark.dart
// ```
//
// Measurement is done by [bench_press](https://pub.dev/packages/bench_press),
// which handles the parts that are easy to get wrong by hand: it calibrates a
// batch size so timer quantisation is negligible, detects steady state instead
// of guessing a warmup count, runs repeated trials, and reports a Fieller 95%
// confidence interval for the ratio between the two widgets.
//
// bench_press normally runs benchmarks through its own CLI (`dart run
// bench_press run`). That is not usable here: laying out text needs `dart:ui`,
// which only exists under the Flutter test binding, so the benchmarks are
// driven through its library API from inside `flutter test` instead.
//
// What the numbers say, measured on an M-series Mac:
//
//  - In steady state `HyphenText` costs about what a plain `Text` costs, and
//    on a list of paragraphs it is faster: break results are memoised on the
//    shared `Hyphenator`, so a paragraph whose text, style and width have been
//    seen before is answered from cache, while a plain `Text` re-breaks every
//    time.
//  - The expensive rows are the ones that actually decide line breaks, and
//    measurement is 88% of that; everything else the breaker does is 12%. So
//    the breaker aims its search (predict from the average glyph width, gallop
//    outwards, then bisect the remaining gap) instead of bisecting blindly:
//    5.7 measurements per line down to 2.2, and about 2.3x faster breaking.
//    Greedy breaking needs at least 2.0 per line, one to show a candidate fits
//    and one to show the next does not, so the search is within 9% of its
//    floor. Further wins have to come from measuring differently, not from
//    searching better, and the prefix-width note below covers that attempt.
//  - A cold dictionary adds lookups on top, roughly 3 us per uncached word
//    against 16 ns cached. That part is the hyphenation engine itself, so it
//    is a floor set by the dictionary rather than something the breaker can
//    remove.
//
// Earlier findings worth recording, so they are not retried:
//
//  - Estimating line widths from cached per-segment measurements and only
//    confirming near the answer measured about twice as slow as the plain
//    binary search, because the extra per-segment measurements cost more than
//    the handful of probes they saved.
//  - Breaking every paragraph through the engine, by marking it with soft
//    hyphens and reading the chosen line starts back out, needs one layout
//    instead of O(lines x log candidates) measurements. It was faster on a
//    cold cache but lost on every other axis once results were memoised on the
//    Hyphenator, and it produced worse line breaking: reserving a hyphen's
//    width on every line cost two extra lines on the sample paragraph, while
//    reserving it only where needed leaves stranded short lines. Removed.
//  - Summing a line's width from the cached widths of the segments between
//    break candidates is exact (widths are additive except across a space when
//    `wordSpacing` is set), and a repeat measurement costs about 1 us against
//    17 us for a string the engine has not seen. It still lost badly, because
//    on a cold cache it measures many more distinct short strings than the
//    binary search measures long ones: the cold row went from 13.9x to 40.8x.
//  - Prefix widths from a single layout: lay the line out once at infinite
//    width and take any candidate's width as the difference of two
//    `getOffsetForCaret` values, so the search needs no measurement at all.
//    Rejected on measurement, twice over. Accuracy: the default test font is
//    fixed-advance (i, m and W all 16.0), which makes the idea look exact, but
//    with a real kerned font (Times New Roman via FontLoader) the error is up
//    to 0.74px and nonzero in 45% of Latin ranges, because a run shaped alone
//    kerns differently at its edges than in context. Cost: layout is about
//    7us + 0.22us per character, so one pass over a 398-character paragraph is
//    95.8us plus ~100 caret lookups at 0.76us, against the ~264us of
//    measurement it would save. Roughly break-even, for a loss of exactness.
//  - Memoising the break candidates per hard line on the breaker was removed
//    again. Rebuilding them is a tokenise plus one cached dictionary lookup
//    per word, tens of nanoseconds against the hundreds of microseconds a
//    break spends measuring, and keeping them alive measured slower.
//  - The '25 paragraphs in a list' row moved from 0.47x to about 0.60x when
//    the aimed search landed, and that is not work this package does. In that
//    row every frame builds 25 fresh paragraphs whose breaks are already
//    cached: instrumentation shows zero breaker constructions, zero
//    breakText calls and zero dictionary lookups per frame after the first,
//    and the rendered strings are byte-identical either way. The difference
//    survives a 600-frame warmup and disappears when the same pre-broken
//    strings are timed through a plain `Text`, so it is VM/engine state
//    seeded by the first break, not steady-state cost. Reverting the
//    (never-executed) breaker file is the only thing that moves it; moving
//    the cold path behind `vm:never-inline` and reordering the file do not.
//    Note the realistic reuse case, 'relayout, same width', improved instead:
//    that row keeps its render object, as a scrolling list does, while this
//    one re-creates all 25 every frame.

import 'package:bench_press/bench_press.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/test_dictionaries.dart';
import 'support/comparison.dart';
import 'support/widget_harness.dart';

/// Text long enough that line breaking dominates the measurement.
const String kSampleText =
    'Programming with Flutter is an interesting and entertaining occupation. '
    'Internationalization of an application guarantees the immediate '
    'availability of its content. The direct interaction of a user with the '
    'interface demands extraordinary attention to typography and to '
    'hyphenation. The improvement of computational systems continues '
    'uninterrupted, and performance remains the determining factor.';

/// Layout benchmarks are far slower than the microbenchmarks bench_press is
/// tuned for, so the budgets are widened to keep a run to a few seconds while
/// still collecting enough trials for a meaningful interval.
const BenchmarkConfig kLayoutConfig = BenchmarkConfig(
  trials: 10,
  minWarmupIterations: 3,
  maxWarmupIterations: 30,
  targetBatchDuration: Duration(milliseconds: 50),
  maxWarmupDurationSeconds: 3,
);

void main() {
  final comparisons = <LayoutComparison>[];
  late Hyphenator hyphenator;

  setUpAll(() => hyphenator = loadEnglishHyphenator());

  /// Measures [plain] against [hyphen] and records the comparison.
  ///
  /// Both variants are declared in one [BenchmarkGroup] so bench_press runs
  /// them back to back, under the same thermal and GC conditions.
  Future<void> compare(
    String name,
    void Function() plain,
    void Function() hyphen, {
    BenchmarkConfig config = kLayoutConfig,
  }) async {
    final group = BenchmarkGroup.compare(
      name: name,
      baseline: ('Text', plain),
      candidates: <String, dynamic Function()>{'HyphenText': hyphen},
      config: config,
    );
    final results = <BenchmarkResult>[];
    for (final variant in group.variants) {
      results.add(await variant.report(config: config));
    }
    comparisons.add(LayoutComparison(name, results[0], results[1]));
  }

  tearDownAll(() {
    final buffer = StringBuffer()
      ..writeln()
      ..writeln('=' * 76)
      ..writeln(
        '  Text vs HyphenText   (median us/op, Fieller 95% CI on the '
        'ratio)',
      )
      ..writeln('=' * 76)
      ..writeln(
        '${'scenario'.padRight(32)}${'Text'.padLeft(9)}'
        '${'HyphenText'.padLeft(11)}${'ratio'.padLeft(8)}${'95% CI'.padLeft(16)}',
      )
      ..writeln('-' * 76);
    for (final comparison in comparisons) {
      buffer.writeln(comparison.row);
    }
    buffer
      ..writeln('=' * 76)
      ..writeln(
        'Sample: ${kSampleText.length} characters, '
        '${kSampleText.split(' ').length} words. '
        'Lower is better; ratio > 1 means HyphenText is slower.',
      )
      ..writeln('=' * 76);
    // ignore: avoid_print
    print(buffer);
  });

  group('layout', () {
    testWidgets('first layout, warm dictionary', (WidgetTester tester) async {
      // A paragraph appearing for the first time, with the app's shared
      // hyphenator already warm. This is the realistic "new screen" cost,
      // because a real app registers one dictionary at startup and every
      // widget shares its word cache.
      var seed = 0;

      void pump(Widget child) {
        // A fresh key forces a new render object, so no per-widget state is
        // carried between iterations.
        pumpSync(
          tester,
          buildHost(
            KeyedSubtree(key: ValueKey<int>(seed++), child: child),
            320,
          ),
        );
      }

      await compare(
        'first layout, warm dict',
        () => pump(const Text(kSampleText, style: kStyle)),
        () => pump(
          HyphenText(kSampleText, style: kStyle, hyphenator: hyphenator),
        ),
      );
      expect(comparisons, isNotEmpty);
    });

    testWidgets('first layout, cold dictionary', (WidgetTester tester) async {
      // The genuine worst case, and a deliberately pessimistic one: a fresh
      // Hyphenator per iteration means no word has ever been looked up, which
      // in a real app happens only for the very first paragraph after startup.
      // It shares the parsed dictionary, so this isolates lookup cost from the
      // one-off cost of parsing the .dic file.
      //
      // The dictionary lookups are a small part of this (see the 'dictionary'
      // group below for the per-word cost); most of it is breaking the lines
      // from scratch, the same work as the 'new width' row plus the lookups.
      // Every later paragraph shares the cache and lands on the rows above.
      var seed = 0;

      void pump(Widget child) {
        pumpSync(
          tester,
          buildHost(
            KeyedSubtree(key: ValueKey<int>(seed++), child: child),
            320,
          ),
        );
      }

      await compare(
        'first layout, cold dict',
        () => pump(const Text(kSampleText, style: kStyle)),
        () => pump(
          HyphenText(
            kSampleText,
            style: kStyle,
            hyphenator: Hyphenator(hyphenator.dictionary),
          ),
        ),
      );
    });

    testWidgets('break from scratch, warm dictionary', (
      WidgetTester tester,
    ) async {
      // The cost of the line breaking itself. Every word is already in the
      // dictionary cache, but the render object is new and the width has
      // never been seen, so no break cache can answer and the breaker has to
      // measure candidate lines from nothing. This is the cost the other rows
      // hide once their cycle of widths has been cached, and the row to watch
      // when changing the breaker.
      var width = 240.0;
      var seed = 0;

      void pump(Widget child) {
        width += 0.01;
        pumpSync(
          tester,
          buildHost(
            KeyedSubtree(key: ValueKey<int>(seed++), child: child),
            width,
          ),
        );
      }

      await compare(
        'break from scratch, warm dict',
        () => pump(const Text(kSampleText, style: kStyle)),
        () => pump(
          HyphenText(kSampleText, style: kStyle, hyphenator: hyphenator),
        ),
      );
    });

    testWidgets('relayout at an unchanged width', (WidgetTester tester) async {
      // The common case in a scrolling list or on any rebuild: the same text
      // at the same width. Everything here should be served from cache.
      await tester.pumpWidget(
        buildHost(const Text(kSampleText, style: kStyle), 320),
      );
      final plainRender = tester.renderObject<RenderBox>(
        find.byType(RichText),
      );

      void relayoutPlain() {
        plainRender.markNeedsLayout();
        tester.binding.scheduleFrame();
        tester.binding.handleBeginFrame(null);
        tester.binding.handleDrawFrame();
      }

      // Measure the plain widget first, then swap the tree and measure ours,
      // rather than rebuilding between every iteration.
      final plainResult = await BenchmarkVariant(
        'Text',
        relayoutPlain,
        isBaseline: true,
      ).report(config: kLayoutConfig);

      await tester.pumpWidget(
        buildHost(
          HyphenText(kSampleText, style: kStyle, hyphenator: hyphenator),
          320,
        ),
      );
      final hyphenRender = tester.renderObject<RenderBox>(
        find.byType(HyphenParagraph),
      );

      void relayoutHyphen() {
        hyphenRender.markNeedsLayout();
        tester.binding.scheduleFrame();
        tester.binding.handleBeginFrame(null);
        tester.binding.handleDrawFrame();
      }

      final hyphenResult = await BenchmarkVariant(
        'HyphenText',
        relayoutHyphen,
      ).report(config: kLayoutConfig);

      comparisons.add(
        LayoutComparison('relayout, same width', plainResult, hyphenResult),
      );
    });

    testWidgets('relayout at a changing width', (WidgetTester tester) async {
      // The worst case for caching: a resizing window or an animating column,
      // where the break points have to be recomputed every frame.
      var width = 240.0;

      void pump(Widget child) {
        width = 240.0 + ((width + 1) % 40);
        pumpSync(tester, buildHost(child, width));
      }

      await compare(
        'relayout, changing width',
        () => pump(const Text(kSampleText, style: kStyle)),
        () => pump(
          HyphenText(kSampleText, style: kStyle, hyphenator: hyphenator),
        ),
      );
    });

    testWidgets('many paragraphs in a list', (WidgetTester tester) async {
      // A realistic screen: a column of paragraphs laid out in one frame.
      const count = 25;
      var seed = 0;

      void pump(Widget Function(int) build) {
        pumpSync(
          tester,
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 320,
              child: ListView.builder(
                key: ValueKey<int>(seed++),
                itemCount: count,
                itemBuilder: (BuildContext context, int index) => build(index),
              ),
            ),
          ),
        );
      }

      await compare(
        '$count paragraphs in a list',
        () => pump(
          (int index) => Text('$index $kSampleText', style: kStyle),
        ),
        () => pump(
          (int index) => HyphenText(
            '$index $kSampleText',
            style: kStyle,
            hyphenator: hyphenator,
          ),
        ),
      );
    });

    testWidgets('a list of repeated paragraphs', (WidgetTester tester) async {
      // The same string shown many times, which is what a rebuilt list or a
      // repeated label looks like. Marking the text is memoised per string, so
      // only the first paragraph pays for it.
      const count = 25;
      var seed = 0;

      void pump(Widget Function(int) build) {
        pumpSync(
          tester,
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 320,
              child: ListView.builder(
                key: ValueKey<int>(seed++),
                itemCount: count,
                itemBuilder: (BuildContext context, int index) => build(index),
              ),
            ),
          ),
        );
      }

      await compare(
        '$count repeated paragraphs',
        () => pump((int index) => const Text(kSampleText, style: kStyle)),
        () => pump(
          (int index) =>
              HyphenText(kSampleText, style: kStyle, hyphenator: hyphenator),
        ),
      );
    });

    testWidgets('intrinsic width', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildHost(const Text(kSampleText, style: kStyle), 320),
      );
      final plainRender = tester.renderObject<RenderBox>(find.byType(RichText));
      final plainResult = await BenchmarkVariant(
        'Text',
        () => plainRender.getMinIntrinsicWidth(double.infinity),
        isBaseline: true,
      ).report();

      await tester.pumpWidget(
        buildHost(
          HyphenText(kSampleText, style: kStyle, hyphenator: hyphenator),
          320,
        ),
      );
      final hyphenRender = tester.renderObject<RenderBox>(
        find.byType(HyphenParagraph),
      );
      final hyphenResult = await BenchmarkVariant(
        'HyphenText',
        () => hyphenRender.getMinIntrinsicWidth(double.infinity),
      ).report();

      comparisons.add(
        LayoutComparison('getMinIntrinsicWidth', plainResult, hyphenResult),
      );
    });
  });

  group('dictionary', () {
    test('cached versus uncached lookups', () async {
      final words = kSampleText
          .split(RegExp(r'\s+'))
          .where((String word) => word.isNotEmpty)
          .toList();

      // Cache disabled: every word is a fresh dictionary walk.
      final cold = Hyphenator(hyphenator.dictionary, maxCacheSize: 0);
      // Cache enabled and pre-warmed.
      final warm = Hyphenator(hyphenator.dictionary);
      for (final word in words) {
        warm.breakOffsets(word);
      }

      final coldResult = await BenchmarkVariant('uncached', () {
        for (final word in words) {
          Blackhole.consume(cold.breakOffsets(word));
        }
      }, isBaseline: true).report();

      final warmResult = await BenchmarkVariant('cached', () {
        for (final word in words) {
          Blackhole.consume(warm.breakOffsets(word));
        }
      }).report();

      final perWordCold = coldResult.metrics.medianNs / words.length;
      final perWordWarm = warmResult.metrics.medianNs / words.length;
      // ignore: avoid_print
      print(
        '\nDictionary lookups over ${words.length} words:\n'
        '  uncached: ${perWordCold.toStringAsFixed(0)} ns/word\n'
        '  cached:   ${perWordWarm.toStringAsFixed(0)} ns/word\n'
        '  speedup:  ${(perWordCold / perWordWarm).toStringAsFixed(1)}x',
      );

      // The cache is what makes HyphenText usable in a scrolling list, so a
      // regression here is a real regression.
      expect(
        perWordWarm,
        lessThan(perWordCold),
        reason: 'the cache must beat an uncached lookup',
      );
    });
  });
}
