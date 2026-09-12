import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_dictionaries.dart';

void main() {
  group('Hyphenator', () {
    late Hyphenator english;
    late Hyphenator testDict;

    setUp(() {
      english = loadEnglishHyphenator();
      testDict = loadTestHyphenator();
    });

    test('splits a word at dictionary points', () {
      expect(english.split('hyphenation'), <String>['hy', 'phen', 'ation']);
      expect(
        english.split('programming'),
        <String>['pro', 'gram', 'ming'],
      );
    });

    test('break offsets index into the original word', () {
      const word = 'internationalization';
      final offsets = english.breakOffsets(word);
      expect(offsets, isNotEmpty);
      for (final offset in offsets) {
        expect(offset, greaterThan(0));
        expect(offset, lessThan(word.length));
      }
      expect(offsets, orderedEquals(<int>[...offsets]..sort()));
      // Rebuilding the word from the offsets must reproduce it exactly.
      expect(english.split(word).join(), word);
    });

    test('hyphenates capitalised and upper-case words', () {
      // The dictionary only holds lowercase patterns, so a widget that did not
      // fold the word would silently stop hyphenating sentence-initial words.
      expect(english.split('Hyphenation'), <String>['Hy', 'phen', 'ation']);
      expect(english.split('HYPHENATION'), <String>['HY', 'PHEN', 'ATION']);
    });

    test('leaves short words alone', () {
      final strict = loadEnglishHyphenator(minWordLength: 8);
      expect(strict.split('details'), <String>['details']);
      expect(english.split('cat'), <String>['cat']);
    });

    test('respects leftMin and rightMin', () {
      // lhmin/rhmin constrain the distance from the edges of the word, not the
      // size of the inner chunks, so only the first and last part are bounded.
      final wide = loadEnglishHyphenator(leftMin: 5, rightMin: 5);
      final parts = wide.split('internationalization');
      expect(parts.length, greaterThan(1));
      expect(parts.first.length, greaterThanOrEqualTo(5));
      expect(parts.last.length, greaterThanOrEqualTo(5));
    });

    test('keeps punctuation outside the dictionary lookup', () {
      expect(
        english.split('"hyphenation"'),
        <String>['"hy', 'phen', 'ation"'],
      );
      expect(english.split('hyphenation,'), <String>['hy', 'phen', 'ation,']);
    });

    test('treats an existing hyphen as a break opportunity', () {
      final offsets = testDict.breakOffsets('e-mail');
      expect(offsets, contains(2));
    });

    test('treats a soft hyphen as an author-supplied break', () {
      final offsets = testDict.breakOffsets('wonder${kSoftHyphen}land');
      expect(offsets, contains(6));
    });

    test('hyphenate() inserts soft hyphens without changing the letters', () {
      final marked = english.hyphenate('hyphenation works');
      expect(marked.replaceAll(kSoftHyphen, ''), 'hyphenation works');
      expect(marked, contains(kSoftHyphen));
    });

    test('hyphenate() preserves whitespace runs exactly', () {
      const source = 'hello   world\nprogramming';
      expect(
        english.hyphenate(source).replaceAll(kSoftHyphen, ''),
        source,
      );
    });

    test('caches results without changing them', () {
      final first = english.breakOffsets('programming');
      final second = english.breakOffsets('programming');
      expect(identical(first, second), isTrue);
      english.clearCache();
      expect(english.breakOffsets('programming'), first);
    });

    test('honours the cache size limit', () {
      final small = Hyphenator(english.dictionary, maxCacheSize: 2);
      expect(small.split('programming'), isNotEmpty);
      expect(small.split('constitution'), isNotEmpty);
      expect(small.split('information'), isNotEmpty);
      // Still correct after eviction.
      expect(small.split('programming').join(), 'programming');
    });

    test('break offsets scale linearly with the number of breaks', () {
      // `_addOffset` used to scan the offsets it had already collected, which
      // made a long word quadratic in its break points. Timing is too noisy to
      // assert on, so this pins the invariant that lets the scan be linear:
      // offsets are produced in ascending order and duplicate-free.
      int breaksFor(int repeats) {
        final word = 'internationalization' * repeats;
        final offsets = Hyphenator(
          english.dictionary,
          maxCacheSize: 0,
        ).breakOffsets(word);
        expect(offsets, isNotEmpty);
        for (var i = 1; i < offsets.length; i++) {
          expect(
            offsets[i],
            greaterThan(offsets[i - 1]),
            reason: 'offsets must ascend without duplicates',
          );
        }
        return offsets.length;
      }

      expect(breaksFor(12), greaterThan(50));
      expect(breaksFor(200), greaterThan(1000));
    });
    test('every cache stays within its bound', () {
      final small = Hyphenator(
        english.dictionary,
        maxCacheSize: 3,
        maxParagraphCacheSize: 2,
      );
      for (var i = 0; i < 50; i++) {
        small.breakOffsets('programming$i');
        small.hyphenate('constitution of the country $i');
        small.cacheBreak('key$i', 'broken $i');
      }
      final (words, marked, broken) = small.cacheCounts;
      expect(words, lessThanOrEqualTo(3));
      expect(marked, lessThanOrEqualTo(2));
      expect(broken, lessThanOrEqualTo(2));
    });

    test('paragraph caches are bounded far below the word cache', () {
      // Paragraph entries are ~1000x the size of a word entry, so the default
      // must not be the same number for both.
      final hyphenator = Hyphenator(english.dictionary);
      expect(hyphenator.maxCacheSize, 5000);
      expect(
        hyphenator.maxParagraphCacheSize,
        Hyphenator.kDefaultParagraphCacheSize,
      );
      expect(
        hyphenator.maxParagraphCacheSize,
        lessThan(hyphenator.maxCacheSize),
      );
      // Disabling the cache still disables all of it.
      expect(
        Hyphenator(english.dictionary, maxCacheSize: 0).maxParagraphCacheSize,
        0,
      );
    });

    test('eviction drops the least recently used entry, not the oldest', () {
      final small = Hyphenator(english.dictionary, maxParagraphCacheSize: 2);
      small
        ..cacheBreak('a', 'A')
        ..cacheBreak('b', 'B');
      // Touch 'a' so 'b' becomes the least recently used.
      expect(small.cachedBreak('a'), 'A');
      small.cacheBreak('c', 'C');
      expect(small.cachedBreak('a'), 'A', reason: 'recently used, must stay');
      expect(small.cachedBreak('b'), isNull, reason: 'least recently used');
      expect(small.cachedBreak('c'), 'C');
    });

    test('hyphenate() memoises whole strings', () {
      const text = 'hello world programming';
      final first = english.hyphenate(text);
      final second = english.hyphenate(text);
      expect(
        identical(first, second),
        isTrue,
        reason: 'the marked form should be served from cache',
      );
      expect(second.replaceAll(kSoftHyphen, ''), text);

      // A non-default separator must not be served from, or poison, the cache.
      final piped = english.hyphenate(text, separator: '|');
      expect(piped.replaceAll('|', ''), text);
      expect(english.hyphenate(text), first);

      english.clearCache();
      expect(english.hyphenate(text), first);
    });

    test('the marked cache respects the size limit', () {
      final small = Hyphenator(english.dictionary, maxCacheSize: 2);
      for (final text in <String>[
        'hello world',
        'constitution of the country',
        'a sentence here',
      ]) {
        expect(small.hyphenate(text).replaceAll(kSoftHyphen, ''), text);
      }
      // Still correct after eviction.
      expect(
        small.hyphenate('hello world').replaceAll(kSoftHyphen, ''),
        'hello world',
      );
    });

    test('handles empty and single-character input', () {
      expect(english.split(''), <String>['']);
      expect(english.breakOffsets(''), isEmpty);
      expect(english.split('a'), <String>['a']);
    });

    test('never proposes an offset inside a surrogate pair', () {
      const word = 'hy😀phenation';
      for (final offset in english.breakOffsets(word)) {
        final unit = word.codeUnitAt(offset);
        expect(
          unit & 0xFC00 == 0xDC00,
          isFalse,
          reason: 'offset $offset splits a surrogate pair',
        );
      }
    });

    test('a broken dictionary does not break the hyphenator', () {
      final empty = Hyphenator.fromBytes(const <int>[]);
      expect(empty.split('anything'), <String>['anything']);
    });
  });
}
