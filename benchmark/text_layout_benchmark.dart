// Benchmark comparing the layout cost of `Text` and `HyphenText`.
//
// Run it with:
//
// ```bash
// flutter test benchmark/text_layout_benchmark.dart --plain-name benchmark
// ```
//
// The numbers are wall-clock times from the Flutter test binding, so they are
// comparable within one run but not across machines. What matters is the ratio
// between the two widgets, which is what the report prints.
//
// What the numbers say, measured on an M-series Mac:
//
//  - Re-laying out at an unchanged width costs about the same as a plain
//    `Text`. This is the case that matters for scrolling and for ordinary
//    rebuilds, and it is why `RenderHyphenParagraph` memoises the broken text
//    per width.
//  - A first layout costs roughly 4-5x a plain `Text`. The cost is dominated
//    by measuring candidate lines with a `TextPainter`: each distinct string
//    is a fresh paragraph layout (~20us), and the breaker needs O(log n) of
//    them per line to binary-search the longest line that fits.
//  - Dictionary lookups are not the bottleneck. Cached lookups run in tens of
//    nanoseconds, and even uncached ones are a few microseconds, which is why
//    the cold and warm first-layout rows are so close together.
//
// An earlier attempt to estimate line widths from cached per-segment
// measurements, and only confirm near the answer, made things roughly twice
// as slow: the extra per-segment measurements cost more than the handful of
// binary-search probes they were meant to save. The straightforward binary
// search is kept for that reason.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/test_dictionaries.dart';

/// A single measured scenario.
class BenchmarkResult {
  BenchmarkResult({
    required this.name,
    required this.plain,
    required this.hyphen,
    required this.iterations,
  });

  /// What was measured.
  final String name;

  /// Total time spent by the plain [Text] variant.
  final Duration plain;

  /// Total time spent by the [HyphenText] variant.
  final Duration hyphen;

  /// How many times the scenario ran.
  final int iterations;

  double get plainMicros => plain.inMicroseconds / iterations;

  double get hyphenMicros => hyphen.inMicroseconds / iterations;

  /// How much slower `HyphenText` is. Below 1 means it is faster.
  double get ratio =>
      plainMicros == 0 ? double.nan : hyphenMicros / plainMicros;

  String get row {
    final plainText = plainMicros.toStringAsFixed(1).padLeft(10);
    final hyphenText = hyphenMicros.toStringAsFixed(1).padLeft(11);
    final ratioText = '${ratio.toStringAsFixed(2)}x'.padLeft(8);
    return '${name.padRight(38)}$plainText$hyphenText$ratioText';
  }
}

/// Text long enough that line breaking dominates the measurement.
const String kSampleText =
    'Программирование на Flutter это интересное и увлекательное занятие. '
    'Конституция Российской Федерации гарантирует непосредственное действие '
    'прав и свобод человека. Непосредственное взаимодействие пользователя с '
    'интерфейсом требует внимательного отношения к типографике и переносам. '
    'Совершенствование вычислительных систем продолжается непрерывно, и '
    'производительность остаётся определяющим фактором.';

const TextStyle kStyle = TextStyle(fontSize: 16, height: 1.3);

/// Builds the widget under test inside a fixed-width column.
Widget buildHost(Widget child, double width) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: SizedBox(width: width, child: child),
  ),
);

/// Runs [body] [iterations] times and returns the elapsed time, discarding a
/// warmup pass so JIT compilation does not land in the measurement.
Future<Duration> measure(
  int iterations,
  Future<void> Function(int) body, {
  int warmup = 3,
}) async {
  for (var i = 0; i < warmup; i++) {
    await body(i);
  }
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    await body(i);
  }
  stopwatch.stop();
  return stopwatch.elapsed;
}

void main() {
  final results = <BenchmarkResult>[];
  late Hyphenator hyphenator;

  setUpAll(() => hyphenator = loadRussianHyphenator());

  tearDownAll(() {
    final buffer = StringBuffer()
      ..writeln()
      ..writeln('=' * 68)
      ..writeln('  Text vs HyphenText  (microseconds per iteration)')
      ..writeln('=' * 68)
      ..writeln(
        '${'scenario'.padRight(38)}${'Text'.padLeft(10)}'
        '${'HyphenText'.padLeft(11)}${'ratio'.padLeft(8)}',
      )
      ..writeln('-' * 68);
    for (final result in results) {
      buffer.writeln(result.row);
    }
    buffer
      ..writeln('=' * 68)
      ..writeln(
        'Sample: ${kSampleText.length} characters, '
        '${kSampleText.split(' ').length} words.',
      )
      ..writeln('=' * 68);
    // ignore: avoid_print
    print(buffer);
  });

  group('benchmark', () {
    testWidgets('first layout of a new paragraph', (WidgetTester tester) async {
      // A paragraph appearing for the first time, with the app's shared
      // hyphenator already warm. This is the realistic "new screen" cost,
      // because a real app registers one dictionary at startup and every
      // widget shares its word cache.
      const iterations = 40;

      Future<void> run(Widget child, int i) async {
        // A fresh key forces a new render object, so nothing is cached.
        await tester.pumpWidget(
          buildHost(KeyedSubtree(key: ValueKey<int>(i), child: child), 320),
        );
      }

      final plain = await measure(
        iterations,
        (int i) => run(const Text(kSampleText, style: kStyle), i),
      );
      final hyphen = await measure(
        iterations,
        (int i) => run(
          HyphenText(kSampleText, style: kStyle, hyphenator: hyphenator),
          i,
        ),
      );

      results.add(
        BenchmarkResult(
          name: 'first layout, warm dictionary',
          plain: plain,
          hyphen: hyphen,
          iterations: iterations,
        ),
      );
      expect(results.last.hyphenMicros, greaterThan(0));
    });

    testWidgets('first layout with a cold dictionary', (
      WidgetTester tester,
    ) async {
      // The genuine worst case: the very first paragraph after startup, when
      // no word has been looked up yet. A fresh Hyphenator per iteration means
      // every word is a cache miss, which is what makes this so much slower
      // than the warm case above.
      const iterations = 15;

      final plain = await measure(iterations, (int i) async {
        await tester.pumpWidget(
          buildHost(
            KeyedSubtree(
              key: ValueKey<int>(i),
              child: const Text(kSampleText, style: kStyle),
            ),
            320,
          ),
        );
      });
      final hyphen = await measure(iterations, (int i) async {
        // Sharing the parsed dictionary but not the word cache isolates the
        // lookup cost from the one-off cost of parsing the .dic file.
        final cold = Hyphenator(hyphenator.hyphen);
        await tester.pumpWidget(
          buildHost(
            KeyedSubtree(
              key: ValueKey<int>(i),
              child: HyphenText(
                kSampleText,
                style: kStyle,
                hyphenator: cold,
              ),
            ),
            320,
          ),
        );
      });

      results.add(
        BenchmarkResult(
          name: 'first layout, cold dictionary',
          plain: plain,
          hyphen: hyphen,
          iterations: iterations,
        ),
      );
    });

    testWidgets('relayout at an unchanged width', (WidgetTester tester) async {
      // The common case in a scrolling list or on any rebuild: the same text
      // at the same width. Everything here should be served from cache.
      const iterations = 200;

      Future<Duration> runFor(Widget child) async {
        await tester.pumpWidget(buildHost(child, 320));
        final render = tester.renderObject<RenderBox>(
          find.byType(child is HyphenText ? HyphenParagraph : RichText),
        );
        return measure(iterations, (int i) async {
          render.markNeedsLayout();
          await tester.pump();
        });
      }

      final plain = await runFor(const Text(kSampleText, style: kStyle));
      final hyphen = await runFor(
        HyphenText(kSampleText, style: kStyle, hyphenator: hyphenator),
      );

      results.add(
        BenchmarkResult(
          name: 'relayout, same width (warm)',
          plain: plain,
          hyphen: hyphen,
          iterations: iterations,
        ),
      );
    });

    testWidgets('relayout at a changing width', (WidgetTester tester) async {
      // The worst case: a resizing window or an animating column, where the
      // break points have to be recomputed every frame.
      const iterations = 60;

      Future<Duration> runFor(Widget Function() build) async {
        await tester.pumpWidget(buildHost(build(), 320));
        return measure(
          iterations,
          (int i) => tester.pumpWidget(buildHost(build(), 240.0 + (i % 40))),
        );
      }

      final plain = await runFor(() => const Text(kSampleText, style: kStyle));
      final hyphen = await runFor(
        () => HyphenText(kSampleText, style: kStyle, hyphenator: hyphenator),
      );

      results.add(
        BenchmarkResult(
          name: 'relayout, changing width',
          plain: plain,
          hyphen: hyphen,
          iterations: iterations,
        ),
      );
    });

    testWidgets('many paragraphs in a list', (WidgetTester tester) async {
      // A realistic screen: a column of paragraphs laid out in one frame.
      const iterations = 10;
      const count = 25;

      Future<Duration> runFor(Widget Function(int) build) => measure(
        iterations,
        (int i) => tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 320,
              child: ListView.builder(
                key: ValueKey<int>(i),
                itemCount: count,
                itemBuilder: (BuildContext context, int index) => build(index),
              ),
            ),
          ),
        ),
      );

      final plain = await runFor(
        (int index) => Text('$index $kSampleText', style: kStyle),
      );
      final hyphen = await runFor(
        (int index) => HyphenText(
          '$index $kSampleText',
          style: kStyle,
          hyphenator: hyphenator,
        ),
      );

      results.add(
        BenchmarkResult(
          name: '$count paragraphs in a ListView',
          plain: plain,
          hyphen: hyphen,
          iterations: iterations,
        ),
      );
    });

    testWidgets('intrinsic width', (WidgetTester tester) async {
      const iterations = 40;

      Future<Duration> runFor(Widget child) async {
        await tester.pumpWidget(buildHost(child, 320));
        final render = tester.renderObject<RenderBox>(
          find.byType(child is HyphenText ? HyphenParagraph : RichText),
        );
        return measure(iterations, (int i) async {
          render.getMinIntrinsicWidth(double.infinity);
        });
      }

      final plain = await runFor(const Text(kSampleText, style: kStyle));
      final hyphen = await runFor(
        HyphenText(kSampleText, style: kStyle, hyphenator: hyphenator),
      );

      results.add(
        BenchmarkResult(
          name: 'getMinIntrinsicWidth',
          plain: plain,
          hyphen: hyphen,
          iterations: iterations,
        ),
      );
    });
  });

  group('hyphenation cost in isolation', () {
    test('dictionary lookup throughput', () {
      final words = kSampleText
          .split(RegExp(r'\s+'))
          .where((String w) => w.isNotEmpty)
          .toList();

      // Cold: every word is a cache miss.
      final cold = Hyphenator(hyphenator.hyphen, maxCacheSize: 0);
      final coldWatch = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        for (final word in words) {
          cold.breakOffsets(word);
        }
      }
      coldWatch.stop();

      // Warm: the cache serves every word after the first pass.
      final warm = Hyphenator(hyphenator.hyphen);
      for (final word in words) {
        warm.breakOffsets(word);
      }
      final warmWatch = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        for (final word in words) {
          warm.breakOffsets(word);
        }
      }
      warmWatch.stop();

      final lookups = words.length * 200;
      final coldNanos = coldWatch.elapsed.inMicroseconds * 1000 / lookups;
      final warmNanos = warmWatch.elapsed.inMicroseconds * 1000 / lookups;

      // ignore: avoid_print
      print(
        '\nDictionary lookups (${words.length} words x 200):\n'
        '  uncached: ${coldNanos.toStringAsFixed(0)} ns/word\n'
        '  cached:   ${warmNanos.toStringAsFixed(0)} ns/word\n'
        '  speedup:  ${(coldNanos / warmNanos).toStringAsFixed(1)}x',
      );

      // The cache is the reason HyphenText is usable in a scrolling list, so
      // a regression here is a real regression.
      expect(
        warmNanos,
        lessThan(coldNanos),
        reason: 'the cache must beat a cold lookup',
      );
    });
  });

  group('regression guards', () {
    testWidgets('a warm relayout is not dramatically slower than Text', (
      WidgetTester tester,
    ) async {
      // Guards the property that actually matters for scrolling: once the
      // widths are cached, re-laying out the same text at the same width must
      // stay in the same order of magnitude as a plain Text.
      const iterations = 150;

      Future<Duration> runFor(Widget child) async {
        await tester.pumpWidget(buildHost(child, 320));
        final render = tester.renderObject<RenderBox>(
          find.byType(child is HyphenText ? HyphenParagraph : RichText),
        );
        return measure(iterations, (int i) async {
          render.markNeedsLayout();
          await tester.pump();
        });
      }

      final plain = await runFor(const Text(kSampleText, style: kStyle));
      final hyphen = await runFor(
        HyphenText(kSampleText, style: kStyle, hyphenator: hyphenator),
      );
      final ratio = hyphen.inMicroseconds / plain.inMicroseconds;

      // A generous bound: CI machines are noisy, and the point is to catch a
      // change that makes hyphenation cost orders of magnitude more, not to
      // police a few percent.
      expect(
        ratio,
        lessThan(12),
        reason: 'warm relayout was ${ratio.toStringAsFixed(1)}x plain Text',
      );
    }, skip: Platform.environment['CI'] == 'true');
  });
}
