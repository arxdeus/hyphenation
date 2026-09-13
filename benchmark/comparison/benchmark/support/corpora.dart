import 'dart:convert';
import 'dart:io';

/// Locates a repository file from whatever directory the suite was started in.
String repoPath(String relative) {
  var directory = Directory.current.absolute;
  while (true) {
    final candidate = File('${directory.path}/$relative');
    if (candidate.existsSync()) {
      return candidate.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('could not find $relative above ${Directory.current}');
    }
    directory = parent;
  }
}

/// Shared main-comparison data, bundled by hyphenator_impure 0.1.4.
String ourPatternSource() => controlledPatternSource();

/// Pattern tokens only. Exceptions are excluded in every controlled adapter.
List<String> controlledPatternTokens() {
  final source = impurePatternSource().replaceAll(RegExp(r'%[^\n]*'), '');
  final body = RegExp(
    r'\\patterns\s*\{([^}]*)\}',
    dotAll: true,
  ).firstMatch(source)!.group(1)!;
  return body.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
}

String controlledPatternSource() =>
    '\\patterns{\n${controlledPatternTokens().join('\n')}\n}\n';

String controlledHyphenatorxSource() => jsonEncode({
  'pattern': [
    for (final token in controlledPatternTokens()) _jsonPattern(token),
  ],
  'exception': <String, Object?>{},
});

Map<String, Object> _jsonPattern(String token) {
  final letters = StringBuffer();
  final levels = <int>[0];
  for (final code in token.codeUnits) {
    if (code >= 48 && code <= 57) {
      levels[levels.length - 1] = code - 48;
    } else {
      letters.writeCharCode(code);
      levels.add(0);
    }
  }
  return {'result': letters.toString(), 'levels': levels};
}

/// Hunspell needs substring-closed automaton outputs, not raw TeX tokens.
List<int> controlledHunspellBytes() =>
    compileHunspellPatterns(controlledPatternTokens());

/// ASCII, standard-pattern subset of Hunspell's substrings.pl preprocessing.
/// Source: https://github.com/hunspell/hyphen/blob/0d69357820f1fe0d79a1e7705a8a7a07b2968a97/substrings.pl
/// Merge duplicate rules, then expand embedded rules into prefix states.
/// Conversion is outside timing, like the precompiled JSON representation.
List<int> compileHunspellPatterns(Iterable<String> tokens) {
  final rules = <String, List<int>>{};
  for (final token in tokens) {
    if (!RegExp(r'^[.a-z0-9]+$').hasMatch(token)) {
      throw ArgumentError.value(token, 'token', 'standard ASCII patterns only');
    }
    final pattern = _jsonPattern(token);
    final letters = pattern['result']! as String;
    final levels = pattern['levels']! as List<int>;
    final merged = rules.putIfAbsent(
      letters,
      () => List.filled(levels.length, 0),
    );
    for (var i = 0; i < levels.length; i++) {
      if (levels[i] > merged[i]) merged[i] = levels[i];
    }
  }
  final states = <String, List<int>>{};
  for (final letters in rules.keys) {
    for (var start = 0; start < letters.length; start++) {
      for (var end = start + 1; end <= letters.length; end++) {
        final suffix = letters.substring(start, end);
        final embedded = rules[suffix];
        if (embedded == null) continue;
        final prefix = letters.substring(0, end);
        final existing = states[prefix];
        if (existing == null) {
          states[prefix] = [...List<int>.filled(start, 0), ...embedded];
        } else {
          for (
            var position = 0;
            position <= prefix.length - suffix.length;
            position++
          ) {
            if (prefix.substring(position, position + suffix.length) !=
                suffix) {
              continue;
            }
            for (var i = 0; i < embedded.length; i++) {
              if (embedded[i] > existing[position + i]) {
                existing[position + i] = embedded[i];
              }
            }
          }
        }
      }
    }
  }
  final output = StringBuffer('UTF-8\nLEFTHYPHENMIN 3\nRIGHTHYPHENMIN 3\n');
  for (final letters in states.keys.toList()..sort()) {
    final levels = states[letters]!;
    for (var i = 0; i <= letters.length; i++) {
      if (levels[i] != 0) output.write(levels[i]);
      if (i < letters.length) output.write(letters[i]);
    }
    output.writeln();
  }
  return utf8.encode(output.toString());
}

/// `hyph-en-us.tex` as `hyphenator_impure` bundles it.
String impurePatternSource() =>
    File(repoPath('benchmark/comparison/assets/hyph-en-us.tex'))
        .readAsStringSync();

/// `language_en_us.json` as `hyphenatorx` bundles it.
String hyphenatorxConfigSource() =>
    File(repoPath('benchmark/comparison/assets/language_en_us.json'))
        .readAsStringSync();

/// The Hunspell `hyph_en_US.dic` dictionary `hyphen` consumes.
List<int> hyphenDictionaryBytes() =>
    File(repoPath('benchmark/comparison/assets/hyph_en_US.dic'))
        .readAsBytesSync();

/// Fixed hand-selected vocabulary with many long technical words.
const List<String> kProse = <String>[
  'Internationalization',
  'localization',
  'complementary',
  'disciplines',
  'determine',
  'whether',
  'application',
  'feels',
  'native',
  'people',
  'Typography',
  'impression',
  'justified',
  'columns',
  'unhyphenated',
  'whitespace',
  'paragraph',
  'unusually',
  'technical',
  'vocabulary',
  'container',
  'Dictionary',
  'hyphenation',
  'computed',
  'incrementally',
  'memoised',
  'implementation',
  'responsibilities',
  'considerations',
  'representations',
  'unquestionably',
  'straightforwardly',
];

/// Fixed hand-selected long words, not a representative prose distribution.
const List<String> kLongWords = <String>[
  'internationalization',
  'responsibilities',
  'straightforwardly',
  'unquestionably',
  'incomprehensibilities',
  'counterrevolutionaries',
  'electroencephalography',
  'interdisciplinarity',
  'antidisestablishmentarianism',
  'uncharacteristically',
];

/// Prose long enough that line breaking dominates a layout measurement.
const String kSampleParagraph =
    'Programming with Flutter is an interesting and entertaining occupation. '
    'Internationalization of an application guarantees the immediate '
    'availability of its content. The direct interaction of a user with the '
    'interface demands extraordinary attention to typography and to '
    'hyphenation. The improvement of computational systems continues '
    'uninterrupted, and performance remains the determining factor.';

/// Frozen synthetic ASCII corpus, not representative natural-language prose.
List<String> uniqueWords(int count) {
  if (count < 0 || count > kProse.length * 26 * 26) {
    throw RangeError.range(count, 0, kProse.length * 26 * 26);
  }
  return List<String>.generate(count, (i) {
    final suffix = i ~/ kProse.length;
    return '${kProse[i % kProse.length].toLowerCase()}'
        '${String.fromCharCode(97 + suffix ~/ 26)}'
        '${String.fromCharCode(97 + suffix % 26)}';
  }, growable: false);
}

/// Identical tokenization and reassembly for the ASCII paragraph fixture.
String hyphenateParagraph(String text, List<String> Function(String) split) =>
    text.replaceAllMapped(
      RegExp('[A-Za-z]+'),
      (match) => split(match[0]!).join('\u00ad'),
    );

/// Where a suite writes its JSON results, next to this package.
String resultPath(String fileName) {
  final root = File(repoPath('benchmark/comparison/pubspec.yaml')).parent;
  return '${root.path}/results/$fileName';
}
