// Explicit minima document the controlled configuration.
// ignore_for_file: avoid_redundant_argument_values
// Flutter-dependent adapters for controlled benchmark fixtures.
import 'dart:convert';

import 'package:hyphenator_impure/hyphenator.dart' as impure;
import 'package:hyphenatorx/hyphenatorx.dart' as hyphenatorx;
import 'package:hyphenatorx/languages/languageconfig.dart' as hyphenatorx;

/// Mirrors the package loader on one-token-per-line controlled TeX input.
final class ImpureFileLoader extends impure.ResourceLoader {
  ImpureFileLoader(String source) {
    final lines = source
        .split('\n')
        .where((e) => e.isNotEmpty && !e.startsWith('%'))
        .map((e) => e.trim());
    var isNextPattern = false;
    var isNextException = false;
    for (final line in lines) {
      if (line.startsWith('}')) {
        isNextPattern = false;
        isNextException = false;
      } else if (!isNextPattern && line.startsWith(r'\patterns')) {
        isNextPattern = true;
      } else if (!isNextException && line.startsWith(r'\hyphenation')) {
        isNextException = true;
      } else if (isNextPattern && !isNextException) {
        _patterns.add(line);
      } else if (isNextException) {
        _exceptions.add(line);
      }
    }
  }

  final List<String> _patterns = <String>[];
  final List<String> _exceptions = <String>[];

  @override
  Iterable<String> get patternsStrings => _patterns;

  @override
  Iterable<String> get exceptionsStrings => _exceptions;
}

/// Builds a `hyphenatorx` hyphenator from its bundled JSON, skipping only the
/// `rootBundle` read that a benchmark binding cannot serve.
hyphenatorx.Hyphenator buildHyphenatorx(String configSource) =>
    hyphenatorx.Hyphenator(
      hyphenatorx.LanguageConfig(
        json.decode(configSource) as Map<String, dynamic>,
      ),
      minLetterCount: 3,
      minWordLength: 5,
    );
