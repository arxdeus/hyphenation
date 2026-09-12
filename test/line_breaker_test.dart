import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_dictionaries.dart';

/// A measure function where every character is exactly 10 wide, so the
/// expected line breaks can be reasoned about by counting characters.
double measureByCharacter(String text) => text.length * 10.0;

void main() {
  group('HyphenLineBreaker', () {
    late Hyphenator latin;

    setUp(() => latin = loadTestLatinHyphenator());

    HyphenLineBreaker breakerFor(Hyphenator? hyphenator) => HyphenLineBreaker(
      measure: measureByCharacter,
      hyphenator: hyphenator,
    );

    test('breaks at whitespace when the words fit', () {
      final breaker = breakerFor(null);
      expect(
        breaker.breakText('aa bb cc', 50),
        <String>['aa bb', 'cc'],
      );
    });

    test('splits a long word and paints a hyphen', () {
      final breaker = breakerFor(latin);
      // 'hyphenation' breaks as hy-phen-ation. At width 70 the longest prefix
      // that fits once the hyphen is added is 'hyphen-' (7 characters).
      expect(breaker.breakText('hyphenation', 70), <String>[
        'hyphen-',
        'ation',
      ]);
    });

    test('a wider column keeps more of the word on the first line', () {
      final breaker = breakerFor(latin);
      // At 60 'hyphen-' no longer fits, so the earlier break point wins.
      expect(
        breaker.breakText('hyphenation', 60),
        <String>['hy-', 'phen-', 'ation'],
      );
      // Wide enough for everything: no hyphen at all.
      expect(breaker.breakText('hyphenation', 200), <String>['hyphenation']);
    });

    test('without a hyphenator the word moves whole', () {
      final breaker = breakerFor(null);
      expect(
        breaker.breakText('aa hyphenation', 60),
        <String>['aa', 'hyphenation'],
      );
    });

    test('no line exceeds the requested width where a break exists', () {
      final breaker = breakerFor(latin);
      const text = 'always wonderful extraordinary computer hyphenation';
      for (final width in <double>[40, 70, 100, 130]) {
        for (final line in breaker.breakText(text, width)) {
          // 'always' has no break point in the test dictionary, so a line may
          // only overflow when it holds a single unbreakable chunk.
          if (measureByCharacter(line) > width) {
            expect(
              line.contains(' '),
              isFalse,
              reason: 'overflowing line "$line" should be one chunk',
            );
          }
        }
      }
    });

    test('the original text survives the round trip', () {
      final breaker = breakerFor(latin);
      const text = 'always wonderful extraordinary computer hyphenation';
      for (final width in <double>[30, 55, 80, 200]) {
        final rebuilt = breaker
            .breakText(text, width)
            .map(
              (String line) => line.endsWith('-')
                  ? line.substring(0, line.length - 1)
                  : '$line ',
            )
            .join()
            .trim();
        expect(rebuilt, text, reason: 'at width $width');
      }
    });

    test('hard newlines are preserved', () {
      final breaker = breakerFor(latin);
      expect(breaker.breakText('aa\nbb', 100), <String>['aa', 'bb']);
      expect(breaker.breakText('aa\n\nbb', 100), <String>['aa', '', 'bb']);
    });

    test('a trailing newline yields a trailing empty line', () {
      final breaker = breakerFor(latin);
      expect(breaker.breakText('aa\n', 100), <String>['aa', '']);
    });

    test('soft hyphens are consumed, never painted', () {
      final breaker = breakerFor(latin);
      final lines = breaker.breakText('wonder${kSoftHyphen}land', 70);
      expect(lines, <String>['wonder-', 'land']);
      for (final line in lines) {
        expect(line.contains(kSoftHyphen), isFalse);
      }
    });

    test('an existing hyphen is not doubled', () {
      final breaker = breakerFor(latin);
      expect(breaker.breakText('e-mail', 20), <String>['e-', 'mail']);
    });

    test('an unbreakable word overflows rather than vanishing', () {
      final breaker = breakerFor(null);
      expect(breaker.breakText('unbreakable', 20), <String>['unbreakable']);
    });

    test('empty text yields one empty line', () {
      expect(breakerFor(latin).breakText('', 100), <String>['']);
    });

    test('minIntrinsicWidth is the widest unbreakable chunk', () {
      final breaker = breakerFor(latin);
      // Every chunk is measured with the hyphen it would carry: 'al-' (3),
      // 'ways' (4), 'hy-' (3), 'phen-' (5) and 'ation' (5). The widest is 5
      // characters at 10 each.
      expect(breaker.minIntrinsicWidth('always hyphenation'), 50.0);
      // Hyphenation makes the minimum far narrower than the longest word.
      expect(
        breaker.minIntrinsicWidth('hyphenation'),
        lessThan(measureByCharacter('hyphenation')),
      );
    });

    test('minIntrinsicWidth matches an exhaustive measurement', () {
      // The implementation sorts the chunks by length and stops once no
      // shorter chunk can win, which is only sound if the bound it uses is
      // conservative. Checked here against measuring every chunk.
      final breaker = breakerFor(latin);
      for (final text in <String>[
        'hyphenation extraordinary computer always wonderful',
        'always',
        'a bb ccc dddd eeeee',
        'hyphenation\nextraordinary',
        '',
      ]) {
        var exhaustive = 0.0;
        for (final line in text.split('\n')) {
          for (final word in line.split(' ')) {
            if (word.isEmpty) {
              continue;
            }
            // The widest a chunk of this word can be is the whole word, and
            // the narrowest is bounded below by any of its hyphenated parts.
            for (final part in latin.split(word)) {
              final width = measureByCharacter(part);
              if (width > exhaustive) {
                exhaustive = width;
              }
            }
          }
        }
        // The breaker's answer must be at least the widest unbreakable part,
        // or a word would not fit the column it reports as sufficient.
        expect(
          breaker.minIntrinsicWidth(text),
          greaterThanOrEqualTo(exhaustive),
          reason: 'minIntrinsicWidth under-reports for "$text"',
        );
      }
    });

    test('the aimed search matches a brute-force greedy at every width', () {
      // Glyphs of uneven width make the running average a poor predictor,
      // which is exactly when the gallop around the guess has to do work.
      double uneven(String text) {
        var width = 0.0;
        for (final unit in text.codeUnits) {
          width += switch (unit) {
            0x20 => 4.0,
            0x2D => 5.0,
            0x61 || 0x65 || 0x69 || 0x6F || 0x75 => 6.0,
            0x6D || 0x77 => 15.0,
            _ => 11.0,
          };
        }
        return width;
      }

      // Reference: scan every candidate linearly and keep the longest fit.
      List<String> reference(String text, double maxWidth) {
        final words = text.split(' ');
        final ends = <(int, bool)>[];
        var offset = 0;
        for (final word in words) {
          for (final cut in latin.breakOffsets(word)) {
            ends.add((offset + cut, true));
          }
          offset += word.length;
          ends.add((offset, false));
          offset += 1;
        }
        final lines = <String>[];
        var start = 0;
        var first = 0;
        while (first < ends.length) {
          var chosen = first;
          for (var i = first; i < ends.length; i++) {
            final (end, hyphen) = ends[i];
            final line = text.substring(start, end) + (hyphen ? '-' : '');
            if (uneven(line) <= maxWidth) {
              chosen = i;
            } else {
              break;
            }
          }
          final (end, hyphen) = ends[chosen];
          lines.add(text.substring(start, end) + (hyphen ? '-' : ''));
          start = hyphen ? end : end + 1;
          first = chosen + 1;
        }
        return lines;
      }

      const texts = <String>[
        'always wonderful extraordinary computer hyphenation',
        'hyphenation hyphenation hyphenation wonderful international',
        'a bb ccc extraordinary d hyphenation ee computer f wonderful',
      ];
      for (final text in texts) {
        // One breaker per text so its running estimate evolves across widths
        // the way it does across a resize.
        final breaker = HyphenLineBreaker(measure: uneven, hyphenator: latin);
        for (var width = 20.0; width <= 320; width += 3) {
          expect(
            breaker.breakText(text, width),
            reference(text, width),
            reason: '"$text" at width $width',
          );
        }
      }
    });

    test('the measurement cache is bounded across widths', () {
      // A breaker outlives a width change, so an animating column must not
      // grow it without limit.
      final breaker = HyphenLineBreaker(
        measure: measureByCharacter,
        hyphenator: latin,
        maxMeasurementCacheSize: 8,
      );
      const text = 'always wonderful extraordinary computer hyphenation';
      for (var width = 30.0; width < 400; width += 1) {
        breaker.breakText(text, width);
      }
      expect(breaker.measurementCacheSize, lessThanOrEqualTo(8));
      // Still correct once entries are being evicted.
      expect(
        breaker.breakText(text, 200).join(' ').replaceAll('- ', ''),
        text,
      );
    });

    test('measurements are cached but results stay correct', () {
      var calls = 0;
      final breaker = HyphenLineBreaker(
        measure: (String text) {
          calls++;
          return measureByCharacter(text);
        },
        hyphenator: latin,
      );
      final first = breaker.breakText('hyphenation hyphenation', 60);
      final callsAfterFirst = calls;
      final second = breaker.breakText('hyphenation hyphenation', 60);
      expect(second, first);
      expect(
        calls,
        callsAfterFirst,
        reason: 'the second pass should hit the cache',
      );
      breaker.clearCache();
      expect(breaker.breakText('hyphenation hyphenation', 60), first);
    });
  });
}
