// The pattern minifier: what it throws away, and what it must not.
import 'dart:io';

import 'package:flutter_hyphen/src/tex/tex_hyphenation_patterns.dart';
import 'package:flutter_hyphen/src/tex/tex_pattern_minifier.dart';
import 'package:flutter_hyphen/src/tex/tex_pattern_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('minifyTexPatterns', () {
    test('drops the comment header', () {
      final result = minifyTexPatterns(r'''
% title: Hyphenation patterns
% copyright: someone
\patterns{
a1b
}
''');
      expect(result.source, contains('a1b'));
      expect(result.source, isNot(contains('copyright')));
      expect(result.patternCount, 1);
    });

    test('drops TeX plumbing between the groups', () {
      final result = minifyTexPatterns(r'''
\message{loading}
\patterns{ a1b }
\endinput
''');
      expect(result.source, isNot(contains('message')));
      expect(result.source, isNot(contains('endinput')));
    });

    test('drops the comments inside a group', () {
      final result = minifyTexPatterns(r'''
\patterns{ % just type <return> if you are not using INITEX
a1b
}
''');
      expect(result.source, isNot(contains('INITEX')));
      expect(result.patternCount, 1);
    });

    test('writes exceptions back with their hyphens', () {
      final result = minifyTexPatterns(r'\hyphenation{ as-so-ciate }');
      expect(result.source, contains('as-so-ciate'));
      expect(result.exceptionCount, 1);
    });

    test('an exception with no hyphens survives as the bare word', () {
      final result = minifyTexPatterns(r'\hyphenation{ present }');
      expect(result.source, contains('present'));
      expect(result.source, isNot(contains('pre-sent')));
    });

    test('--drop-exceptions leaves no hyphenation group', () {
      final result = minifyTexPatterns(
        r'\patterns{ a1b } \hyphenation{ ta-ble }',
        options: const TexMinifyOptions(keepExceptions: false),
      );
      expect(result.source, isNot(contains('hyphenation')));
      expect(result.exceptionCount, 0);
    });

    test('a file with no patterns produces nothing to ship', () {
      final result = minifyTexPatterns('% only a comment\n');
      expect(result.source, isEmpty);
      expect(result.patternCount, 0);
    });

    test('wrapped layout keeps to its width', () {
      final result = minifyTexPatterns(
        r'\patterns{ a1b c1d e1f g1h }',
        options: const TexMinifyOptions(
          layout: TexMinifyLayout.wrapped,
          width: 8,
        ),
      );
      for (final line in result.source.trim().split('\n')) {
        expect(line.length, lessThanOrEqualTo(12), reason: line);
      }
    });

    test('a token longer than the width is not broken', () {
      final result = minifyTexPatterns(
        r'\patterns{ abcdefghijkl1m }',
        options: const TexMinifyOptions(
          layout: TexMinifyLayout.wrapped,
          width: 4,
        ),
      );
      expect(result.source, contains('abcdefghijkl1m'));
    });
  });

  group('the rewrite means the same thing', () {
    test('reparsing yields the same patterns and exceptions', () {
      const source = r'''
% a header
\patterns{ .ach4 hy3ph a1b }
\hyphenation{ as-so-ciate present }
''';
      final before = parseTexPatterns(source);
      final after = parseTexPatterns(minifyTexPatterns(source).source);
      expect(after.patterns, before.patterns);
      expect(after.exceptions, before.exceptions);
    });

    test('a real pattern file hyphenates identically', () {
      final path = File('example/assets/patterns/ushyph1.tex');
      if (!path.existsSync()) {
        // The example's assets are not part of a published package.
        return;
      }
      final source = path.readAsStringSync();
      final original = TexHyphenationPatterns.parse(source);

      for (final layout in TexMinifyLayout.values) {
        final minified = minifyTexPatterns(
          source,
          options: TexMinifyOptions(layout: layout),
        );
        expect(
          minified.source.contains('%'),
          isFalse,
          reason: 'no comment should survive',
        );
        final rebuilt = TexHyphenationPatterns.parse(minified.source);
        for (final word in _words) {
          expect(
            rebuilt.split(word).join('-'),
            original.split(word).join('-'),
            reason: '$word under $layout',
          );
        }
      }
    });
  });
}

const List<String> _words = <String>[
  'hyphenation',
  'antidisestablishmentarianism',
  'associate',
  'present',
  'table',
  'internationalization',
  'concatenation',
  'algorithm',
  'typography',
  'philanthropic',
];
