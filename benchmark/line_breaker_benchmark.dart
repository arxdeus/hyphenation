// Line breaking cost: cold paragraphs and cached resizes.
//
// Run it with:
//
// ```bash
// flutter test --concurrency=1 benchmark/line_breaker_benchmark.dart
// ```
//
// Measurement is done by [bench_press](https://pub.dev/packages/bench_press),
// which calibrates a batch size, detects steady state instead of guessing a
// warmup count, and reports a Fieller 95% confidence interval for the ratio
// between variants. Like the other widget benchmarks here it is driven through
// the library API rather than the bench_press CLI, because measuring a painted
// string needs `dart:ui`, which only exists under the Flutter test binding.
//
// Two things are measured, and they pull in opposite directions:
//
//  1. `cold` - a fresh breaker over a paragraph whose widths have never been
//     seen. This grows with document length, so it is measured at three sizes.
//     The probe counters printed alongside are the point of the row: what the
//     breaker costs is the text it hands the engine to shape, and a search
//     that probes near the middle of a long document shapes half of it.
//  2. `warm_resize` - one breaker over a cycle of widths, which is a resizing
//     window or an animating column. Here the measurement cache is doing the
//     work and the row should stay flat.
//
// The output hash pins the chosen line breaks, so a run that gets faster by
// breaking differently is visible rather than silently welcome.

import 'package:bench_press/bench_press.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/test_dictionaries.dart';
import 'support/engine_workloads.dart';

/// Breaking a long document is slower than the microbenchmarks bench_press is
/// tuned for, so the budgets are widened to keep a run to a few seconds while
/// still collecting enough trials for a meaningful interval.
const BenchmarkConfig kBreakerConfig = BenchmarkConfig(
  trials: 10,
  minWarmupIterations: 3,
  maxWarmupIterations: 30,
  targetBatchDuration: Duration(milliseconds: 50),
  maxWarmupDurationSeconds: 3,
);

/// Counts what the breaker asks the engine to shape.
///
/// The width of a string is what a break costs, so these counters say more
/// about a change to the search than the wall-clock rows do.
class MeasureCounters {
  int calls = 0;
  int codeUnits = 0;
  int largestProbe = 0;

  void reset() {
    calls = 0;
    codeUnits = 0;
    largestProbe = 0;
  }

  @override
  String toString() =>
      '$calls calls, $codeUnits code units, largest probe $largestProbe';
}

void main() {
  late Hyphenator hyphenator;
  late TextPainter painter;
  final counters = MeasureCounters();
  final report = StringBuffer();

  setUpAll(() {
    hyphenator = loadEnglishHyphenator();
    // Warm the dictionary but not the widths: word offsets are shared by every
    // paragraph in an app, cold measurement caches are not.
    hyphenator.hyphenate(kSampleParagraph);
    painter = TextPainter(textDirection: TextDirection.ltr);
  });

  tearDownAll(() {
    painter.dispose();
    // ignore: avoid_print
    print(report);
  });

  double measure(String text) {
    counters.calls++;
    counters.codeUnits += text.length;
    if (text.length > counters.largestProbe) {
      counters.largestProbe = text.length;
    }
    painter
      ..text = TextSpan(text: text, style: const TextStyle(fontSize: 16))
      ..layout();
    return painter.width;
  }

  HyphenLineBreaker newBreaker() =>
      HyphenLineBreaker(measure: measure, hyphenator: hyphenator);

  test('cold breaking scales with the document, not with its length', () async {
    report
      ..writeln()
      ..writeln('=' * 78)
      ..writeln('  Cold line breaking (fresh breaker, unseen width)')
      ..writeln('=' * 78)
      ..writeln(
        '${'characters'.padRight(12)}${'median us'.padLeft(11)}'
        '${'lines'.padLeft(8)}${'probes'.padLeft(9)}'
        '${'shaped units'.padLeft(14)}${'largest'.padLeft(9)}'
        '${'hash'.padLeft(12)}',
      )
      ..writeln('-' * 78);

    for (final repeats in <int>[1, 10, 100]) {
      final text = List<String>.filled(repeats, kSampleParagraph).join(' ');
      final result = await BenchmarkVariant(
        'cold_${text.length}',
        () => Blackhole.consume(newBreaker().breakText(text, 320)),
      ).report(config: kBreakerConfig);

      // One more measured run, uncontended, for the probe counters and the
      // line breaks themselves.
      counters.reset();
      final lines = newBreaker().breakText(text, 320);

      report.writeln(
        '${text.length.toString().padRight(12)}'
        '${(result.metrics.medianNs / 1000).toStringAsFixed(1).padLeft(11)}'
        '${lines.length.toString().padLeft(8)}'
        '${counters.calls.toString().padLeft(9)}'
        '${counters.codeUnits.toString().padLeft(14)}'
        '${counters.largestProbe.toString().padLeft(9)}'
        '${_checksum(lines.join('\n')).toString().padLeft(12)}',
      );

      // A search that probes near the middle of the document would shape half
      // of it. Nothing the breaker hands the engine should grow like that.
      expect(
        counters.largestProbe,
        lessThan(text.length ~/ 2 + kSampleParagraph.length),
        reason: 'a cold probe should not shape a large fraction of the text',
      );
    }
  });

  test('a cached resize stays flat', () async {
    final breaker = newBreaker();
    // Seed every width in the cycle, so this measures hits rather than the
    // first pass over each width.
    for (var i = 0; i < 40; i++) {
      breaker.breakText(kSampleParagraph, 240 + i.toDouble());
    }

    var width = 0;
    final result = await BenchmarkVariant('warm_resize', () {
      width = (width + 1) % 40;
      Blackhole.consume(
        breaker.breakText(kSampleParagraph, 240 + width.toDouble()),
      );
    }).report(config: kBreakerConfig);

    report
      ..writeln('=' * 78)
      ..writeln(
        'Cached resize: '
        '${(result.metrics.medianNs / 1000).toStringAsFixed(2)} us per width, '
        'over a 40-width cycle of a ${kSampleParagraph.length}-character '
        'paragraph.',
      )
      ..writeln('=' * 78);
  });
}

int _checksum(String text) {
  var hash = 0;
  for (final unit in text.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  return hash;
}
