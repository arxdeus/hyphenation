// The asset transformer entry point.
//
// Flutter's `pubspec.yaml` can pipe an asset through a Dart program at build
// time:
//
// ```yaml
// flutter:
//   assets:
//     - path: assets/patterns/ushyph1.tex
//       transformers:
//         - package: flutter_hyphenation
//           args: ['--layout=lines']
// ```
//
// The tool is handed `--input=<file> --output=<file>` and is expected to
// write the transformed asset to the output path. Here that means rewriting
// the pattern file as nothing but its `\patterns` and `\hyphenation`
// groups, so the licence header, the changelog and the rest of the TeX
// plumbing never reach the app bundle. `--verbose` reports what that saved,
// which is worth checking: the figure ranges from 1% to 70% depending on
// how much prose the language's file happens to carry.
//
// The licence of a pattern file usually asks that its notice be preserved,
// so `--keep-header` is offered and the header of the source file is copied
// through verbatim when it is passed.

import 'dart:convert';
import 'dart:io';

import 'package:hyphenation/hyphenation.dart';

Future<void> main(List<String> arguments) async {
  final Map<String, String> options;
  try {
    options = _parseArguments(arguments);
  } on FormatException catch (error) {
    stderr.writeln('flutter_hyphenation: ${error.message}');
    stderr.writeln(_usage);
    exitCode = 2;
    return;
  }

  final inputPath = options['input'];
  final outputPath = options['output'];
  if (inputPath == null || outputPath == null) {
    stderr.writeln('flutter_hyphenation: --input and --output are required.');
    stderr.writeln(_usage);
    exitCode = 2;
    return;
  }

  final input = File(inputPath);
  if (!input.existsSync()) {
    stderr.writeln('flutter_hyphenation: no such file: $inputPath');
    exitCode = 2;
    return;
  }

  final source = await input.readAsString();
  final layoutName = options['layout'] ?? 'lines';
  final layout = switch (layoutName) {
    'lines' => TexMinifyLayout.lines,
    'wrapped' => TexMinifyLayout.wrapped,
    _ => null,
  };
  if (layout == null) {
    stderr.writeln('flutter_hyphenation: unknown layout: $layoutName');
    stderr.writeln(_usage);
    exitCode = 2;
    return;
  }

  final width = int.tryParse(options['width'] ?? '80');
  if (width == null || width <= 0) {
    stderr.writeln('flutter_hyphenation: --width must be a positive integer.');
    exitCode = 2;
    return;
  }

  final result = minifyTexPatterns(
    source,
    options: TexMinifyOptions(
      layout: layout,
      width: width,
      keepExceptions: !options.containsKey('drop-exceptions'),
    ),
  );

  if (result.patternCount == 0) {
    // Better to fail the build than to ship a dictionary that hyphenates
    // nothing: an empty result means the file was not a pattern file, or
    // was already consumed by another transformer.
    stderr.writeln('flutter_hyphenation: no \\patterns group found in $inputPath');
    exitCode = 1;
    return;
  }

  final header = options.containsKey('keep-header')
      ? _leadingComments(source)
      : '';

  final output = File(outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString(header + result.source);

  if (options.containsKey('verbose')) {
    // Sizes on disk, not string lengths: a pattern file is UTF-8, and for
    // anything but English the two differ.
    final before = input.lengthSync();
    final after = output.lengthSync();
    final saved = before == 0 ? 0 : (100 * (before - after) / before).round();
    stdout.writeln(
      'flutter_hyphenation: $inputPath ${before}B -> ${after}B (-$saved%), '
      '${result.patternCount} patterns, ${result.exceptionCount} exceptions',
    );
  }
}

/// The run of `%` comment lines a pattern file opens with, licence included.
String _leadingComments(String source) {
  final kept = StringBuffer();
  for (final line in const LineSplitter().convert(source)) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) {
      continue;
    }
    if (!trimmed.startsWith('%')) {
      break;
    }
    kept
      ..write(line.trimRight())
      ..write('\n');
  }
  return kept.toString();
}

/// Reads `--name=value` and `--flag`, in any order.
Map<String, String> _parseArguments(List<String> arguments) {
  final options = <String, String>{};
  for (final argument in arguments) {
    if (!argument.startsWith('--')) {
      throw FormatException('unexpected argument: $argument');
    }
    final body = argument.substring(2);
    final equals = body.indexOf('=');
    if (equals < 0) {
      options[body] = '';
    } else {
      options[body.substring(0, equals)] = body.substring(equals + 1);
    }
  }
  return options;
}

const String _usage = r'''
Usage: dart run flutter_hyphenation --input=<file> --output=<file>

  --layout=lines|wrapped  Token layout in the output. Default: lines.
  --width=<n>             Line width for --layout=wrapped. Default: 80.
  --drop-exceptions       Omit the \hyphenation group.
  --keep-header           Copy the source file's leading comments through.
  --verbose               Report the size saved.
''';
