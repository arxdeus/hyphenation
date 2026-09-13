import 'package:hyphenation/hyphenation.dart';
import 'package:hyphenation/src/cache/lru_cache.dart';
import 'package:test/test.dart';

import '../support/test_dictionaries.dart';

void main() {
  test(
    'LRU last hit, equal keys, misses, replacement and clear stay coherent',
    () {
      final cache = LruCache<Object?, Object>(2);
      final a = Object();
      final b = Object();
      cache[null] = a;
      expect(cache[null], same(a));
      cache[('b', 1)] = b;
      expect(cache[('b', 1)], same(b));
      expect(cache['absent'], isNull);
      expect(cache[null], same(a));
      cache['c'] = Object();
      expect(cache[('b', 1)], isNull);
      cache[null] = b;
      expect(cache[null], same(b));
      cache.clear();
      expect(cache[null], isNull);
      expect(cache.length, 0);
    },
  );

  test(
    'weighted admission evicts by recency and rejects oversized entries',
    () {
      final cache = LruCache<String, String>(10, maxWeight: 10);
      cache.put('a', 'a', weight: 4);
      cache.put('b', 'b', weight: 4);
      expect(cache['a'], 'a');
      cache.put('c', 'c', weight: 5);
      expect(cache['b'], isNull);
      expect(cache.estimatedWeight, 9);
      cache.put('huge', 'huge', weight: 11);
      expect(cache.length, 2);
      cache.put('a', 'oversized replacement', weight: 11);
      expect(cache['a'], isNull);
      expect(cache.estimatedWeight, 5);
      cache.clear();
      expect(cache.estimatedWeight, 0);
      expect(cache['c'], isNull);
      for (final disabled in [
        LruCache<String, String>(0),
        LruCache<String, String>(10, maxWeight: 0),
      ]) {
        disabled['a'] = 'a';
        expect(disabled['a'], isNull);
        expect(disabled.length, 0);
      }
    },
  );

  test('word admission preserves offsets and FIFO identity on cheap hits', () {
    final dictionary = loadEnglishHyphenator().patterns;
    final h = Hyphenator(dictionary, maxCacheSize: 2, maxCachedWordLength: 12);
    final first = h.breakOffsets('hyphenation');
    final second = h.breakOffsets('programming');
    expect(h.breakOffsets('hyphenation'), same(first));
    h.breakOffsets('dictionary');
    expect(h.breakOffsets('programming'), same(second));
    expect(h.breakOffsets('hyphenation'), isNot(same(first)));
    final before = h.cacheCounts.$1;
    const long = 'internationalization';
    expect(h.breakOffsets(long), Hyphenator(dictionary).breakOffsets(long));
    expect(h.cacheCounts.$1, before);
    expect(h.cacheEstimatedBytes.words, greaterThan(0));
    h.clearCache();
    expect(h.cacheEstimatedBytes, (words: 0, marked: 0, broken: 0));
  });

  test('paragraph byte limits protect hot entries against giant inputs', () {
    final h = Hyphenator(
      loadTestHyphenator().patterns,
      maxParagraphCacheBytes: 512,
    );
    final small = h.hyphenate('abc');
    expect(h.hyphenate('abc'), same(small));
    h.hyphenate(List.filled(1000, 'cat ').join());
    expect(h.cacheCounts.$2, 1);
    expect(h.cacheEstimatedBytes.marked, lessThanOrEqualTo(512));
    h.cacheBreak('small', 'result', sourceLength: 10);
    h.cacheBreak('huge source', 'x', sourceLength: 1000);
    expect(h.cachedBreak('small'), 'result');
    expect(h.cachedBreak('huge source'), isNull);
    expect(h.cacheEstimatedBytes.broken, 160);
    h.clearCache();
    expect(h.cacheCounts, (0, 0, 0));
    expect(h.cacheEstimatedBytes, (words: 0, marked: 0, broken: 0));
  });

  test('no-cache and no-change preserve source and whitespace behavior', () {
    final h = Hyphenator(
      loadEnglishHyphenator().patterns,
      maxCacheSize: 0,
      maxParagraphCacheBytes: 0,
    );
    final text = ['cat', '\t\n\u2000', 'dog'].join();
    expect(h.hyphenate(text), same(text));
    const breaking = 'cat\t hyphenation\n programming  dog';
    expect(
      h.hyphenate(breaking, separator: '|'),
      'cat\t hy|phen|ation\n pro|gram|ming  dog',
    );
    expect(h.hyphenate(breaking, separator: ''), same(breaking));
    h.cacheBreak('key', 'value');
    expect(h.cacheCounts, (0, 0, 0));
  });

}
