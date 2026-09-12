// The TeX engine's hot paths, measured against the same workloads the `.dic`
// engine was measured with.
//
//   dart run bench_press run -t jit -t aot benchmark/tex_engine_benchmark.dart
//
// The scenario names match `engine_hot_path_benchmark.dart` so the two saved
// result files can be diffed benchmark by benchmark.
import 'dart:io';

import 'package:bench_press/bench_press.dart';
import 'package:flutter_hyphen/src/tex/tex_hyphenation_patterns.dart';

import 'support/engine_workloads.dart';

String _patternSource() =>
    File(assetPath('example/assets/patterns/ushyph1.tex')).readAsStringSync();

TexHyphenationPatterns? _shared;
TexHyphenationPatterns _sharedPatterns() =>
    _shared ??= TexHyphenationPatterns.parse(_patternSource());

/// Marks every word of [words] once per [run].
final class TexMarkBenchmark extends Benchmark {
  TexMarkBenchmark(super.name, {required this.words});

  final List<String> words;
  late TexHyphenationPatterns _patterns;

  @override
  Throughput get throughput => Throughput.elements(words.length);

  @override
  void setup() => _patterns = _sharedPatterns();

  @override
  void run() {
    for (final word in words) {
      // The offsets are owned by the marker and overwritten by the next
      // call, so reading the list is what keeps this from being optimised
      // away.
      final breaks = _patterns.breakOffsets(word, leftMin: 2, rightMin: 2);
      Blackhole.consume(breaks.length);
    }
  }
}

/// Splits every word of [words] once per [run], allocating the parts.
final class TexSplitBenchmark extends Benchmark {
  TexSplitBenchmark(super.name, {required this.words});

  final List<String> words;
  late TexHyphenationPatterns _patterns;

  @override
  Throughput get throughput => Throughput.elements(words.length);

  @override
  void setup() => _patterns = _sharedPatterns();

  @override
  void run() {
    for (final word in words) {
      Blackhole.consume(_patterns.split(word, leftMin: 2, rightMin: 2));
    }
  }
}

/// Compiles the pattern file once per [run]. This is startup cost, so
/// nothing is cached between iterations.
final class TexParseBenchmark extends Benchmark {
  TexParseBenchmark() : super('parse_en_US');

  late String _source;

  @override
  void setup() => _source = _patternSource();

  @override
  void run() => Blackhole.consume(TexHyphenationPatterns.parse(_source));
}

Future<void> main(List<String> args) async {
  await mainBenchmarkSuite(<Benchmark>[
    TexParseBenchmark(),
    TexMarkBenchmark('english_mark', words: kProse),
    TexSplitBenchmark('english_split', words: kProse),
    TexMarkBenchmark('compounds_mark', words: kCompounds),
    TexMarkBenchmark('unicode_mark', words: kUnicode),
  ], args);
}
