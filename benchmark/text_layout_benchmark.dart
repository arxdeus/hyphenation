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
//  - Re-laying out at an unchanged width costs about 1.2x a plain `Text`.
//    This is the case that matters for scrolling and for ordinary rebuilds,
//    and it is why `RenderHyphenParagraph` memoises the broken text per width:
//    a rebuild at the same width does no hyphenation work at all.
//  - A first layout costs roughly 11x a plain `Text`, about 2 ms for the
//    paragraph below. The cost is dominated by measuring candidate lines with
//    a `TextPainter`: each distinct string is a fresh paragraph layout, and
//    the breaker needs O(log n) of them per line to binary-search the longest
//    line that fits.
//  - Dictionary lookups are not the bottleneck, but they are not free either.
//    A cached lookup takes about 15 ns against roughly 3.5 us uncached, which
//    is the gap between the warm and cold first-layout rows.
//
// An earlier attempt to estimate line widths from cached per-segment
// measurements, and only confirm near the answer, measured roughly twice as
// slow: the extra per-segment measurements cost more than the handful of
// binary-search probes they were meant to save. The straightforward binary
// search is kept for that reason.
import 'package:bench_press/bench_press.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/test_dictionaries.dart';

/// Text long enough that line breaking dominates the measurement.
const String kSampleText =
    'Программирование на Flutter это интересное и увлекательное занятие. '
    'Конституция Российской Федерации гарантирует непосредственное действие '
    'прав и свобод человека. Непосредственное взаимодействие пользователя с '
    'интерфейсом требует внимательного отношения к типографике и переносам. '
    'Совершенствование вычислительных систем продолжается непрерывно, и '
    'производительность остаётся определяющим фактором.';

const TextStyle kStyle = TextStyle(fontSize: 16, height: 1.3);

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

/// One `Text` versus `HyphenText` comparison.
class Comparison {
  Comparison(this.name, this.plain, this.hyphen);

  /// What was compared.
  final String name;

  /// Result for the plain [Text] variant.
  final BenchmarkResult plain;

  /// Result for the [HyphenText] variant.
  final BenchmarkResult hyphen;

  /// Ratio of the means, with a Fieller 95% confidence interval.
  FiellerInterval get interval => FiellerInterval.compute(
    sampleA: hyphen.rawTrialLatenciesNs,
    sampleB: plain.rawTrialLatenciesNs,
  );

  String get row {
    final ratio = interval;
    final plainUs = (plain.metrics.medianNs / 1000).toStringAsFixed(1);
    final hyphenUs = (hyphen.metrics.medianNs / 1000).toStringAsFixed(1);
    final ci = ratio.isValid
        ? '[${ratio.lowerBound.toStringAsFixed(2)}, '
              '${ratio.upperBound.toStringAsFixed(2)}]'
        : 'n/a';
    return '${name.padRight(32)}'
        '${plainUs.padLeft(9)}'
        '${hyphenUs.padLeft(11)}'
        '${'${ratio.ratio.toStringAsFixed(2)}x'.padLeft(8)}'
        '${ci.padLeft(16)}';
  }
}

/// Builds the widget under test inside a fixed-width column.
Widget buildHost(Widget child, double width) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: SizedBox(width: width, child: child),
  ),
);

/// Attaches [widget] to the tree and pumps one frame, synchronously.
///
/// `WidgetTester.pumpWidget` is async and guarded, so bench_press cannot call
/// it from a synchronous benchmark body. Driving the binding directly does the
/// same work, and has the side benefit of measuring only build plus layout
/// plus paint, without the test framework's bookkeeping.
void pumpSync(WidgetTester tester, Widget widget) {
  // The same steps `pumpWidget` takes, minus its async guard: the widget has
  // to be wrapped in the binding's default View or the render tree has no root
  // to attach to.
  tester.binding.attachRootWidget(tester.binding.wrapWithDefaultView(widget));
  tester.binding.scheduleFrame();
  tester.binding.handleBeginFrame(null);
  tester.binding.handleDrawFrame();
}

void main() {
  final comparisons = <Comparison>[];
  late Hyphenator hyphenator;

  setUpAll(() => hyphenator = loadRussianHyphenator());

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
    comparisons.add(Comparison(name, results[0], results[1]));
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
      // The genuine worst case: the very first paragraph after startup, when
      // no word has been looked up yet. A fresh Hyphenator per iteration means
      // every word is a cache miss. It shares the parsed dictionary, so this
      // isolates lookup cost from the one-off cost of parsing the .dic file.
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
            hyphenator: Hyphenator(hyphenator.hyphen),
          ),
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
        Comparison('relayout, same width', plainResult, hyphenResult),
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
        Comparison('getMinIntrinsicWidth', plainResult, hyphenResult),
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
      final cold = Hyphenator(hyphenator.hyphen, maxCacheSize: 0);
      // Cache enabled and pre-warmed.
      final warm = Hyphenator(hyphenator.hyphen);
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
