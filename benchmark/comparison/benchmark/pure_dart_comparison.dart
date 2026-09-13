// Explicit minima document the controlled configuration.
// ignore_for_file: avoid_redundant_argument_values
// Selected public entrypoint compile probes and this engine's plain-VM timings.
import 'dart:convert';
import 'dart:io';

import 'package:hyphenation/hyphenation.dart' as ours;

import 'support/corpora.dart';
import 'support/measure.dart';
import 'support/reporting.dart';

const entrypoints = <String, String>{
  'hyphenation': 'hyphenation.dart',
  'hyphenatorx': 'hyphenatorx.dart',
  'hyphenator_impure': 'hyphenator.dart',
  'auto_hyphenating_text': 'auto_hyphenating_text.dart',
  'hyphen': 'hyphen.dart',
  'flutter_hyphenation': 'flutter_hyphenation.dart',
};

/// Compiles the selected public import, not every library in each package.
Map<String, Object?> probe(String name, String entrypoint) {
  final root = File(repoPath('benchmark/comparison/pubspec.yaml')).parent;
  final directory = Directory('${root.path}/.dart_tool/portability_probes')
    ..createSync(recursive: true);
  final source = File(
    '${directory.path}/$name.dart',
  )..writeAsStringSync("import 'package:$name/$entrypoint';\nvoid main() {}\n");
  final result = Process.runSync(Platform.resolvedExecutable, [
    'compile',
    'kernel',
    '--packages=${root.path}/.dart_tool/package_config.json',
    source.path,
    '-o',
    '${directory.path}/$name.dill',
  ], workingDirectory: root.path);
  final diagnostics = '${result.stdout}\n${result.stderr}'.trim();
  return {
    'package': name,
    'entrypoint': 'package:$name/$entrypoint',
    'plain_dart_compile_succeeded': result.exitCode == 0,
    'exit_code': result.exitCode,
    'diagnostics': diagnostics.split('\n').take(20).join('\n'),
    'diagnostics_truncated': diagnostics.split('\n').length > 20,
  };
}

void main() {
  final portability = [
    for (final e in entrypoints.entries) probe(e.key, e.value),
  ];
  for (final p in portability) {
    print('${p['entrypoint']}: compile ${p['plain_dart_compile_succeeded']}');
  }
  final report = ComparisonReport('pure Dart (selected engine, JIT)');
  final source = controlledPatternSource();
  final patterns = ours.TexHyphenationPatterns.parse(
    source,
    leftMin: 3,
    rightMin: 3,
  );
  final hyphenator = ours.Hyphenator(patterns, leftMin: 3, rightMin: 3);
  final distinct = uniqueWords(2000);
  report.outputs['hyphenation'] = hyphenator
      .split('internationalization')
      .join('-');

  void add(
    String name,
    String units,
    int count,
    void Function() body, {
    int trials = 10,
    Duration batch = const Duration(milliseconds: 50),
    String? note,
  }) {
    report.add(
      ComparisonRow(
        name: name,
        units: units,
        unitCount: count,
        results: {
          'hyphenation': measure(
            'hyphenation',
            body,
            trials: trials,
            targetBatchDuration: batch,
          ),
        },
        note: note,
      ),
    );
  }

  add(
    'load en-US dictionary',
    'dictionaries',
    1,
    () => Blackhole.consume(
      ours.Hyphenator(
        ours.TexHyphenationPatterns.parse(source, leftMin: 3, rightMin: 3),
        leftMin: 3,
        rightMin: 3,
      ),
    ),
    trials: 5,
    batch: const Duration(milliseconds: 200),
    note: 'Controlled pattern-only fixture, minima 3/3; file read and conversion excluded.',
  );
  add('split 32 prose words, warm', 'words', kProse.length, () {
    for (final word in kProse) {
      Blackhole.consume(hyphenator.split(word));
    }
  });
  add(
    'split 32 prose words, cold',
    'words',
    kProse.length,
    () {
      final fresh = ours.Hyphenator(patterns, leftMin: 3, rightMin: 3);
      for (final word in kProse) {
        Blackhole.consume(fresh.split(word));
      }
    },
    trials: 5,
    batch: const Duration(milliseconds: 200),
    note: 'Fresh front object/cache, compiled dictionary reused.',
  );
  add(
    'split 2000 distinct words',
    'words',
    distinct.length,
    () {
      for (final word in distinct) {
        Blackhole.consume(hyphenator.split(word));
      }
    },
    trials: 5,
    batch: const Duration(milliseconds: 300),
    note:
        'Frozen synthetic corpus, repeated passes; not natural-language prose.',
  );
  add(
    'hyphenate a paragraph, common adapter',
    'chars',
    kSampleParagraph.length,
    () => Blackhole.consume(
      hyphenateParagraph(kSampleParagraph, hyphenator.split),
    ),
    note: 'Same adapter as engine suite, no whole-paragraph cache.',
  );
  print(report.render());
  print('Blackhole retained ${Blackhole.value.runtimeType}');
  final target = File(resultPath('pure_dart.json'));
  target.parent.createSync(recursive: true);
  target.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'portability_scope': 'Only listed public entrypoints at locked versions. Compile-only, not all package libraries or runtime behavior.',
      'portability': portability,
      ...report.toJson(),
      'dart_version': Platform.version,
    }),
  );
}
