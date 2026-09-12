import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_dictionaries.dart';

void main() {
  group('Hyphenator', () {
    late Hyphenator russian;
    late Hyphenator latin;

    setUp(() {
      russian = loadRussianHyphenator();
      latin = loadTestLatinHyphenator();
    });

    test('splits a Russian word at dictionary points', () {
      expect(russian.split('привет'), <String>['при', 'вет']);
      expect(
        russian.split('программирование'),
        <String>['про', 'грам', 'миро', 'ва', 'ние'],
      );
    });

    test('break offsets index into the original word', () {
      const word = 'программирование';
      final offsets = russian.breakOffsets(word);
      expect(offsets, isNotEmpty);
      for (final offset in offsets) {
        expect(offset, greaterThan(0));
        expect(offset, lessThan(word.length));
      }
      expect(offsets, orderedEquals(<int>[...offsets]..sort()));
      // Rebuilding the word from the offsets must reproduce it exactly.
      expect(russian.split(word).join(), word);
    });

    test('hyphenates capitalised and upper-case words', () {
      // The dictionary only holds lowercase patterns, so a widget that did not
      // fold the word would silently stop hyphenating sentence-initial words.
      expect(russian.split('Привет'), <String>['При', 'вет']);
      expect(russian.split('ПРИВЕТ'), <String>['ПРИ', 'ВЕТ']);
    });

    test('leaves short words alone', () {
      final strict = loadRussianHyphenator(minWordLength: 8);
      expect(strict.split('привет'), <String>['привет']);
      expect(russian.split('кот'), <String>['кот']);
    });

    test('respects leftMin and rightMin', () {
      // lhmin/rhmin constrain the distance from the edges of the word, not the
      // size of the inner chunks, so only the first and last part are bounded.
      final wide = loadRussianHyphenator(leftMin: 5, rightMin: 5);
      final parts = wide.split('программирование');
      expect(parts.length, greaterThan(1));
      expect(parts.first.length, greaterThanOrEqualTo(5));
      expect(parts.last.length, greaterThanOrEqualTo(5));
    });

    test('keeps punctuation outside the dictionary lookup', () {
      expect(russian.split('«привет»'), <String>['«при', 'вет»']);
      expect(russian.split('привет,'), <String>['при', 'вет,']);
    });

    test('treats an existing hyphen as a break opportunity', () {
      final offsets = latin.breakOffsets('e-mail');
      expect(offsets, contains(2));
    });

    test('treats a soft hyphen as an author-supplied break', () {
      final offsets = latin.breakOffsets('wonder${kSoftHyphen}land');
      expect(offsets, contains(6));
    });

    test('hyphenate() inserts soft hyphens without changing the letters', () {
      final marked = russian.hyphenate('привет мир');
      expect(marked.replaceAll(kSoftHyphen, ''), 'привет мир');
      expect(marked, contains(kSoftHyphen));
    });

    test('hyphenate() preserves whitespace runs exactly', () {
      const source = 'привет   мир\nпрограммирование';
      expect(
        russian.hyphenate(source).replaceAll(kSoftHyphen, ''),
        source,
      );
    });

    test('caches results without changing them', () {
      final first = russian.breakOffsets('программирование');
      final second = russian.breakOffsets('программирование');
      expect(identical(first, second), isTrue);
      russian.clearCache();
      expect(russian.breakOffsets('программирование'), first);
    });

    test('honours the cache size limit', () {
      final small = Hyphenator(russian.hyphen, maxCacheSize: 2);
      expect(small.split('программирование'), isNotEmpty);
      expect(small.split('конституция'), isNotEmpty);
      expect(small.split('предложение'), isNotEmpty);
      // Still correct after eviction.
      expect(small.split('программирование').join(), 'программирование');
    });

    test('every cache stays within its bound', () {
      final small = Hyphenator(
        russian.hyphen,
        maxCacheSize: 3,
        maxParagraphCacheSize: 2,
      );
      for (var i = 0; i < 50; i++) {
        small.breakOffsets('программирование$i');
        small.hyphenate('конституция страны $i');
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
      final hyphenator = Hyphenator(russian.hyphen);
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
        Hyphenator(russian.hyphen, maxCacheSize: 0).maxParagraphCacheSize,
        0,
      );
    });

    test('eviction drops the least recently used entry, not the oldest', () {
      final small = Hyphenator(russian.hyphen, maxParagraphCacheSize: 2);
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
      const text = 'привет мир программирование';
      final first = russian.hyphenate(text);
      final second = russian.hyphenate(text);
      expect(
        identical(first, second),
        isTrue,
        reason: 'the marked form should be served from cache',
      );
      expect(second.replaceAll(kSoftHyphen, ''), text);

      // A non-default separator must not be served from, or poison, the cache.
      final piped = russian.hyphenate(text, separator: '|');
      expect(piped.replaceAll('|', ''), text);
      expect(russian.hyphenate(text), first);

      russian.clearCache();
      expect(russian.hyphenate(text), first);
    });

    test('the marked cache respects the size limit', () {
      final small = Hyphenator(russian.hyphen, maxCacheSize: 2);
      for (final text in <String>[
        'привет мир',
        'конституция страны',
        'предложение тут',
      ]) {
        expect(small.hyphenate(text).replaceAll(kSoftHyphen, ''), text);
      }
      // Still correct after eviction.
      expect(
        small.hyphenate('привет мир').replaceAll(kSoftHyphen, ''),
        'привет мир',
      );
    });

    test('handles empty and single-character input', () {
      expect(russian.split(''), <String>['']);
      expect(russian.breakOffsets(''), isEmpty);
      expect(russian.split('я'), <String>['я']);
    });

    test('never proposes an offset inside a surrogate pair', () {
      const word = 'при😀вет';
      for (final offset in russian.breakOffsets(word)) {
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
