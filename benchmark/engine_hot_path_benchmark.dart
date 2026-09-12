// Engine hot paths: marking and splitting words against a parsed dictionary.
//
//   dart run bench_press run benchmark/engine_hot_path_benchmark.dart
//   dart run bench_press run -t jit -t aot benchmark/engine_hot_path_benchmark.dart
//   dart run bench_press run --diff HEAD~1 benchmark/engine_hot_path_benchmark.dart
//
// Pure Dart, no Flutter binding, so this runs under every bench_press target.
// One `run` covers a whole word list rather than a single word, which keeps a
// batch long enough to measure and averages over the length profile of prose.
import 'package:bench_press/bench_press.dart';
import 'package:flutter_hyphen/src/model/hyphenation_dictionary.dart';

import 'support/engine_workloads.dart';

/// Marks every word of [words] once per [run].
final class MarkBenchmark extends Benchmark {
  MarkBenchmark(
    super.name, {
    required this.words,
    required this.dictionary,
  });

  final List<String> words;
  final HyphenationDictionary Function() dictionary;

  late HyphenationDictionary _dictionary;

  @override
  Throughput get throughput => Throughput.elements(words.length);

  @override
  void setup() => _dictionary = dictionary();

  @override
  void run() {
    for (final word in words) {
      // The marks are left in a buffer the next call overwrites, so a read of
      // one is what keeps the call from being optimised away.
      Blackhole.consume(_dictionary.markWord(word, leftMin: 2, rightMin: 2));
      Blackhole.consume(_dictionary.marks[1]);
    }
  }
}

/// Splits every word of [words] once per [run], allocating the parts.
final class SplitBenchmark extends Benchmark {
  SplitBenchmark(
    super.name, {
    required this.words,
    required this.dictionary,
  });

  final List<String> words;
  final HyphenationDictionary Function() dictionary;

  late HyphenationDictionary _dictionary;

  @override
  Throughput get throughput => Throughput.elements(words.length);

  @override
  void setup() => _dictionary = dictionary();

  @override
  void run() {
    for (final word in words) {
      Blackhole.consume(_dictionary.split(word, leftMin: 2, rightMin: 2));
    }
  }
}

/// Parses the bundled dictionary once per [run].
///
/// This is startup cost, and the only way to measure it is to keep paying it,
/// so nothing here is cached between iterations.
final class DictionaryParseBenchmark extends Benchmark {
  DictionaryParseBenchmark() : super('parse_en_US');

  late List<int> _bytes;

  @override
  Throughput get throughput => Throughput.bytes(_bytes.length);

  @override
  void setup() => _bytes = englishDictionaryBytes();

  @override
  void run() => Blackhole.consume(HyphenationDictionary.parse(_bytes));
}

Future<void> main(List<String> args) async {
  HyphenationDictionary? english;
  HyphenationDictionary sharedEnglish() =>
      english ??= HyphenationDictionary.parse(englishDictionaryBytes());

  await mainBenchmarkSuite(<Benchmark>[
    DictionaryParseBenchmark(),
    MarkBenchmark('english_mark', words: kProse, dictionary: sharedEnglish),
    SplitBenchmark('english_split', words: kProse, dictionary: sharedEnglish),
    MarkBenchmark(
      'compounds_mark',
      words: kCompounds,
      dictionary: sharedEnglish,
    ),
    MarkBenchmark('unicode_mark', words: kUnicode, dictionary: sharedEnglish),
    MarkBenchmark(
      'rewrites_mark',
      words: kRewrites,
      dictionary: rewriteDictionary,
    ),
  ], args);
}
