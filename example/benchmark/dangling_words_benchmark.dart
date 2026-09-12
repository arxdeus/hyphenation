// Benchmark for [preventDanglingWords], the typographic pass that glues short
// words to the next one so they cannot hang at the end of a line.
//
// Run it with:
//
// ```bash
// cd example && flutter test benchmark/dangling_words_benchmark.dart
// ```
//
// Measurement is done by [bench_press](https://pub.dev/packages/bench_press),
// which calibrates a batch size so timer quantisation is negligible, detects
// steady state instead of guessing a warmup count, runs repeated trials, and
// reports a Fieller 95% confidence interval for the ratio between the naive
// and the optimised implementation.
//
// The pass runs on every rebuild that changes the text, so it sits on the
// same path as layout. [_naivePreventDanglingWords] below is the original
// implementation, kept verbatim as the baseline; the one under test is in
// `lib/dangling_words.dart`.
//
// What the numbers say, measured on an M-series Mac:
//
//  - On realistic Russian prose the optimised version is about 7x faster, and
//    the worst case (every token is a listed word, so every gap is rewritten)
//    is about 10x.
//  - Text with nothing to glue runs at roughly 900 Mchar/s and allocates
//    nothing at all: the input instance is handed straight back. That is the
//    speed of the scan itself, and it bounds every other row.
//  - Rows that do glue run at roughly 400 Mchar/s. The difference is one
//    buffer allocation, one copy and one string construction, which is what
//    producing a new string costs; the matching is no longer visible.
//
// Where the time went in the naive version, and what replaced it:
//
//  - The prefilter is the biggest single win. A token can only be glued if it
//    is one character long or no longer than the longest listed word (9), so
//    an ordinary word is rejected by one integer comparison without reading a
//    character. In prose that is almost every token.
//  - Three substrings per token (`token`, `spaces`, `_wordCore`) plus a
//    `toLowerCase()`, all discarded immediately. The optimised scan never
//    materialises a token: it works on code-unit ranges of the input.
//  - A `StringBuffer` written for every token and every space run, even when
//    the result was byte-identical to the input. Output is now lazy, and
//    since gluing only ever swaps one space for one no-break space the result
//    is exactly as long as the input, so it is a single mutable copy patched
//    in place instead of a concatenation. This is what fixed the worst case,
//    which was 1.0x (no better than naive) while it still concatenated a
//    slice per glue: 1.0x -> 6.8x.
//  - `words.contains(core.toLowerCase())` hashed a freshly allocated string
//    per token. The word list is compiled once into an open-addressed
//    `Int32List` table, probed with a hash computed over the input in place
//    and confirmed by comparing code units, so the lookup is exact and
//    allocation-free. Against a `Map<int, Object>` of buckets that was worth
//    6.8x -> 9.0x on the worst case.
//  - Case folding went from the general `String.toLowerCase()` to a branch on
//    the code unit for ASCII and Cyrillic, with a fallback to the general
//    version for anything else, so correctness does not depend on the
//    alphabet. The folded token is written to a reusable scratch buffer so
//    verification does not fold it a second time.
//
// Tried and rejected:
//
//  - Packing the folded code units into a single int key (6 bits per
//    character) to get a `Set<int>` probe. The alphabet actually needed is
//    Latin, Cyrillic, digits and the hyphen, which is over 64 symbols, so the
//    packing needs more bits than a 9-character word leaves in a 64-bit int.
//    The probe table is the same cost and stays exact.
//  - Skipping the verification and trusting the hash. It removes a loop over
//    at most 9 units on the rare tokens that reach it, which does not show up
//    against the prefilter, and it turns a collision into a silently wrong
//    document.
//  - Returning early on the first non-word unit of a token. Tokens are
//    rejected by length before that, so the check never paid for itself.
//  - `Uint16List.fromList(text.codeUnits)` for the copy. `codeUnits` is a
//    `List<int>` view whose `[]` is a virtual call per character; an explicit
//    loop over `codeUnitAt` is worth about 10% on the rows that glue.
//  - Specialising the copy to `Uint8List` when the input is Latin-1, to halve
//    the memory traffic. It needs a running check over every character of
//    every token, which costs the rows it cannot help, and Cyrillic text, the
//    reason this pass exists, is never Latin-1.

import 'package:bench_press/bench_press.dart';
import 'package:example/dangling_words.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Baseline: the original implementation, unchanged.
// ---------------------------------------------------------------------------

String _naivePreventDanglingWords(
  String text, {
  Set<String> words = kRussianDanglingWords,
}) {
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
    while (index < text.length && !_naiveIsPlainSpace(text.codeUnitAt(index))) {
      index++;
    }
    final token = text.substring(start, index);
    buffer.write(token);
    // A run of plain spaces right after the token is the candidate to freeze.
    final spaceStart = index;
    while (index < text.length && _naiveIsPlainSpace(text.codeUnitAt(index))) {
      index++;
    }
    final spaces = text.substring(spaceStart, index);
    final core = _naiveWordCore(token);
    final glue =
        atWordStart &&
        spaces == ' ' &&
        core.isNotEmpty &&
        core.length == token.length && // no trailing comma, dot, dash…
        (words.contains(core.toLowerCase()) || core.length == 1);
    buffer.write(glue ? '\u00A0' : spaces);
    atWordStart = spaces.isNotEmpty;
  }
  return buffer.toString();
}

bool _naiveIsPlainSpace(int unit) => unit == 0x20;

/// Strips edge punctuation so `«в` and `в,` are still recognised.
String _naiveWordCore(String token) {
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

// ---------------------------------------------------------------------------
// Corpora.
// ---------------------------------------------------------------------------

/// Realistic Russian prose: a normal density of short words to glue.
const String kProse =
    'Программирование на Flutter это интересное и увлекательное занятие. '
    'Конституция Российской Федерации гарантирует непосредственное действие '
    'прав и свобод человека. Непосредственное взаимодействие пользователя с '
    'интерфейсом требует внимательного отношения к типографике и переносам. '
    'Совершенствование вычислительных систем продолжается непрерывно, и '
    'производительность остаётся определяющим фактором. Из-за особенностей '
    'верстки текст под заголовком, а также перед иллюстрацией, выглядит '
    'лучше, если ни один предлог не остался висеть в конце строки.';

/// Nothing to glue: long words only, so the pass is pure overhead.
const String kNoMatches =
    'Internationalization frameworks generally require careful consideration '
    'whenever typography interacts with localisation, because hyphenation '
    'dictionaries describe intraword opportunities exclusively, never '
    'addressing interword relationships between neighbouring constituents.';

/// Worst case: every token is a listed word, so every gap gets rewritten.
final String kAllShort = List<String>.filled(120, 'на и в по от же что').join(
  ' ',
);

/// A long document, the size at which this pass would actually be noticed.
final String kDocument = List<String>.filled(40, kProse).join(' ');

/// Punctuation-heavy text, which exercises the rejection paths.
const String kPunctuated =
    '«В» — это, по-моему, не (совсем) то; «из-за» и «из-под» тоже: '
    'см. стр. 42, п. 3.1, а также А. С. Пушкин, «Медный всадник» [1837].';

/// Microbenchmarks are cheap, so more trials cost little and tighten the
/// interval.
const BenchmarkConfig kConfig = BenchmarkConfig(
  trials: 25,
  targetBatchDuration: Duration(milliseconds: 20),
);

/// One naive versus optimised comparison.
class Comparison {
  Comparison(this.name, this.input, this.naive, this.fast);

  /// What was compared.
  final String name;

  /// The text the pass ran over, used to report throughput.
  final String input;

  /// Result for [_naivePreventDanglingWords].
  final BenchmarkResult naive;

  /// Result for [preventDanglingWords].
  final BenchmarkResult fast;

  /// Ratio of the means, with a Fieller 95% confidence interval.
  FiellerInterval get interval => FiellerInterval.compute(
    sampleA: fast.rawTrialLatenciesNs,
    sampleB: naive.rawTrialLatenciesNs,
  );

  String get row {
    final ratio = interval;
    final naiveUs = (naive.metrics.medianNs / 1000).toStringAsFixed(2);
    final fastUs = (fast.metrics.medianNs / 1000).toStringAsFixed(2);
    // Characters per second, in millions, for the optimised version.
    final mcps = input.length / fast.metrics.medianNs * 1000;
    final ci = ratio.isValid
        ? '[${(1 / ratio.upperBound).toStringAsFixed(1)}, '
              '${(1 / ratio.lowerBound).toStringAsFixed(1)}]'
        : 'n/a';
    return '${name.padRight(26)}'
        '${input.length.toString().padLeft(7)}'
        '${naiveUs.padLeft(11)}'
        '${fastUs.padLeft(11)}'
        '${'${(1 / ratio.ratio).toStringAsFixed(1)}x'.padLeft(8)}'
        '${ci.padLeft(14)}'
        '${mcps.toStringAsFixed(0).padLeft(10)}';
  }
}

void main() {
  final comparisons = <Comparison>[];

  /// Measures both implementations over [input] and records the comparison.
  ///
  /// Both variants are declared in one [BenchmarkGroup] so bench_press runs
  /// them back to back, under the same thermal and GC conditions.
  Future<void> compare(String name, String input) async {
    // A mistake here would make the benchmark meaningless, so the two are
    // checked against each other before either is timed.
    expect(
      preventDanglingWords(input),
      _naivePreventDanglingWords(input),
      reason: '$name: the optimised version must agree with the baseline',
    );

    final group = BenchmarkGroup.compare(
      name: name,
      baseline: ('naive', () {
        Blackhole.consume(_naivePreventDanglingWords(input));
      }),
      candidates: <String, dynamic Function()>{
        'optimised': () => Blackhole.consume(preventDanglingWords(input)),
      },
      config: kConfig,
    );
    final results = <BenchmarkResult>[];
    for (final variant in group.variants) {
      results.add(await variant.report(config: kConfig));
    }
    comparisons.add(Comparison(name, input, results[0], results[1]));
  }

  tearDownAll(() {
    final buffer = StringBuffer()
      ..writeln()
      ..writeln('=' * 87)
      ..writeln(
        '  preventDanglingWords   (median us/op, Fieller 95% CI on the '
        'speedup)',
      )
      ..writeln('=' * 87)
      ..writeln(
        '${'corpus'.padRight(26)}${'chars'.padLeft(7)}${'naive'.padLeft(11)}'
        '${'optimised'.padLeft(11)}${'speedup'.padLeft(8)}'
        '${'95% CI'.padLeft(14)}${'Mchar/s'.padLeft(10)}',
      )
      ..writeln('-' * 87);
    for (final comparison in comparisons) {
      buffer.writeln(comparison.row);
    }
    buffer
      ..writeln('=' * 87)
      ..writeln('Higher speedup is better; the last column is the optimised '
          'version only.')
      ..writeln('=' * 87);
    // ignore: avoid_print
    print(buffer);
  });

  group('equivalence', () {
    // The optimisation is only worth anything if the output is unchanged, so
    // agreement with the baseline is asserted far more widely than the
    // benchmark corpora cover.
    test('agrees with the baseline on the corpora', () {
      for (final input in <String>[
        '',
        ' ',
        '   ',
        '\n',
        '\t',
        'в',
        'в ',
        ' в ',
        'в  x',
        'в\tx',
        'в\nx',
        'в x',
        'В X',
        'ИЗ-ЗА чего',
        '«в» слово',
        'в, слово',
        'a.b c',
        '- x',
        '1 x',
        'x' * 200,
        kProse,
        kNoMatches,
        kAllShort,
        kPunctuated,
        kDocument,
      ]) {
        expect(
          preventDanglingWords(input),
          _naivePreventDanglingWords(input),
          reason: 'mismatch on ${input.length} chars: '
              '${input.length > 40 ? '${input.substring(0, 40)}…' : input}',
        );
      }
    });

    test('agrees with the baseline on random text', () {
      // A deterministic seed keeps a failure reproducible.
      var state = 0x2545F491;
      int next(int bound) {
        state = (state * 1103515245 + 12345) & 0x3FFFFFFF;
        return state % bound;
      }

              const alphabet = ' \t\n.,«»-абвгдеёжзиклмнопрстуABCxyz01';
      for (var trial = 0; trial < 4000; trial++) {
        final length = next(40);
        final buffer = StringBuffer();
        for (var i = 0; i < length; i++) {
          buffer.write(alphabet[next(alphabet.length)]);
        }
        final input = buffer.toString();
        expect(
          preventDanglingWords(input),
          _naivePreventDanglingWords(input),
          reason: 'mismatch on ${input.codeUnits}',
        );
      }
    });

    test('agrees with the baseline on a custom word list', () {
      const custom = <String>{'the', 'of', 'IGNORED', 'a-b'};
      const input = 'The quick brown fox of a-b and THE end of it';
      expect(
        preventDanglingWords(input, words: custom),
        _naivePreventDanglingWords(input, words: custom),
      );
      // Switching lists between calls must not be answered from the cache.
      expect(
        preventDanglingWords(input),
        _naivePreventDanglingWords(input),
      );
      expect(
        preventDanglingWords(input, words: custom),
        _naivePreventDanglingWords(input, words: custom),
      );
    });

    test('returns the same instance when nothing is glued', () {
      // This is what makes the pass free on text it cannot improve, and it is
      // the property the 'nothing to glue' row measures.
      expect(identical(preventDanglingWords(kNoMatches), kNoMatches), isTrue);
    });
  });

  group('throughput', () {
    test('prose', () => compare('prose', kProse));
    test('document', () => compare('document (40x prose)', kDocument));
    test('no matches', () => compare('nothing to glue', kNoMatches));
    test('all short', () => compare('every word glued', kAllShort));
    test('punctuated', () => compare('punctuation heavy', kPunctuated));

    test('the optimised version wins on every corpus', () {
      expect(comparisons, hasLength(5));
      for (final comparison in comparisons) {
        expect(
          comparison.fast.metrics.medianNs,
          lessThan(comparison.naive.metrics.medianNs),
          reason: '${comparison.name} regressed below the naive version',
        );
      }
    });
  });
}
