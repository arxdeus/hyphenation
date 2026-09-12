// Run with: flutter test --concurrency=1 benchmark/line_breaker_benchmark.dart
// Prints JSON for before/after comparisons with identical input/width traces.
import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/test_dictionaries.dart';

const _sample =
    'Programming with Flutter is an interesting and entertaining occupation. '
    'Internationalization of an application guarantees the immediate '
    'availability of its content. The direct interaction of a user with the '
    'interface demands extraordinary attention to typography and to '
    'hyphenation. The improvement of computational systems continues '
    'uninterrupted, and performance remains the determining factor.';

void main() {
  testWidgets('cold breaking and resize CPU work', (tester) async {
    final hyphenator = loadEnglishHyphenator();
    // Warm only dictionary offsets, not widths or broken paragraphs.
    hyphenator.hyphenate(_sample);
    final painter = TextPainter(textDirection: TextDirection.ltr);
    addTearDown(painter.dispose);
    var calls = 0;
    var measuredUnits = 0;
    var largestProbe = 0;
    double measure(String text) {
      calls++;
      measuredUnits += text.length;
      if (text.length > largestProbe) {
        largestProbe = text.length;
      }
      painter
        ..text = TextSpan(text: text, style: const TextStyle(fontSize: 16))
        ..layout();
      return painter.width;
    }

    for (final repeats in <int>[1, 10, 100]) {
      final text = List<String>.filled(repeats, _sample).join(' ');
      List<String> run() => HyphenLineBreaker(
        measure: measure,
        hyphenator: hyphenator,
      ).breakText(text, 320);
      // Fresh breaker on every invocation, with stable engine warmup.
      for (var i = 0; i < 3; i++) {
        run();
      }
      final micros = <int>[];
      for (var i = 0; i < 7; i++) {
        final watch = Stopwatch()..start();
        final lines = run();
        watch.stop();
        expect(lines, isNotEmpty);
        micros.add(watch.elapsedMicroseconds);
      }
      micros.sort();
      calls = 0;
      measuredUnits = 0;
      largestProbe = 0;
      final lines = run();
      // ignore: avoid_print
      print(
        'LINE_BENCH ${jsonEncode(<String, Object>{
          'scenario': 'cold',
          'characters': text.length,
          'median_us': micros[micros.length ~/ 2],
          'measure_calls': calls,
          'measured_code_units': measuredUnits,
          'largest_probe': largestProbe,
          'lines': lines.length,
          'output_hash': _checksum(lines.join('\n')),
        })}',
      );
    }

    final breaker = HyphenLineBreaker(measure: measure, hyphenator: hyphenator);
    final durations = <int>[];
    for (var trial = 0; trial < 7; trial++) {
      final watch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        breaker.breakText(_sample, 240 + (i % 40).toDouble());
      }
      watch.stop();
      durations.add(watch.elapsedMicroseconds);
    }
    durations.sort();
    // ignore: avoid_print
    print(
      'LINE_BENCH ${jsonEncode(<String, Object>{
        'scenario': 'warm_resize_100',
        'median_us': durations[durations.length ~/ 2],
        // Benchmark diagnostics intentionally use the test-only counter.
        // ignore: invalid_use_of_visible_for_testing_member
        'measurement_entries': breaker.measurementCacheSize,
      })}',
    );
  });
}

int _checksum(String text) {
  var hash = 0;
  for (final unit in text.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  return hash;
}
