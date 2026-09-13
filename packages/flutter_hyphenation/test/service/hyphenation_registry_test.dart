import 'package:flutter/widgets.dart';
import 'package:flutter_hyphenation/flutter_hyphenation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_dictionaries.dart';

void main() {
  late Hyphenator testDict;
  late Hyphenator english;

  setUp(() {
    testDict = loadTestHyphenator();
    english = loadEnglishHyphenator();
    HyphenationRegistry.instance.clear();
  });

  tearDown(HyphenationRegistry.instance.clear);
  group('HyphenationRegistry', () {
    test('resolves an exact locale', () {
      HyphenationRegistry.instance.register(const Locale('en', 'US'), english);
      expect(
        HyphenationRegistry.instance.resolve(const Locale('en', 'US')),
        same(english),
      );
    });

    test('falls back from a country to a bare language', () {
      HyphenationRegistry.instance.register(const Locale('en'), testDict);
      expect(
        HyphenationRegistry.instance.resolve(const Locale('en', 'GB')),
        same(testDict),
      );
    });

    test('prefers the most specific match', () {
      HyphenationRegistry.instance
        ..register(const Locale('en'), testDict)
        ..register(const Locale('en', 'US'), english);
      expect(
        HyphenationRegistry.instance.resolve(const Locale('en', 'US')),
        same(english),
      );
      expect(
        HyphenationRegistry.instance.resolve(const Locale('en', 'GB')),
        same(testDict),
      );
    });

    test('the first registration becomes the fallback', () {
      HyphenationRegistry.instance.register(const Locale('en'), testDict);
      expect(HyphenationRegistry.instance.fallback, same(testDict));
      expect(
        HyphenationRegistry.instance.resolve(const Locale('zxx')),
        same(testDict),
      );
    });

    test('an explicit fallback can be set and beats nothing else', () {
      HyphenationRegistry.instance
        ..register(const Locale('en'), testDict)
        ..register(null, english);
      expect(HyphenationRegistry.instance.fallback, same(english));
      expect(
        HyphenationRegistry.instance.resolve(const Locale('en')),
        same(testDict),
      );
      expect(
        HyphenationRegistry.instance.resolve(const Locale('zxx')),
        same(english),
      );
    });

    test('resolve(null) returns the fallback', () {
      HyphenationRegistry.instance.register(null, testDict);
      expect(HyphenationRegistry.instance.resolve(null), same(testDict));
    });

    test('resolve returns null when empty', () {
      expect(HyphenationRegistry.instance.resolve(const Locale('en')), isNull);
      expect(HyphenationRegistry.instance.resolve(null), isNull);
    });

    test('handles locales with a script code', () {
      HyphenationRegistry.instance.register(const Locale('en'), testDict);
      expect(
        HyphenationRegistry.instance.resolve(
          const Locale.fromSubtags(
            languageCode: 'en',
            scriptCode: 'Latn',
            countryCode: 'US',
          ),
        ),
        same(testDict),
      );
    });

    test('unregister removes a dictionary', () {
      HyphenationRegistry.instance.register(const Locale('en'), testDict);
      HyphenationRegistry.instance.unregister(const Locale('en'));
      expect(HyphenationRegistry.instance.resolve(const Locale('en')), isNull);
    });

    test('locales lists what is registered', () {
      HyphenationRegistry.instance
        ..register(const Locale('en', 'US'), testDict)
        ..register(const Locale('en', 'GB'), english);
      expect(
        HyphenationRegistry.instance.locales,
        containsAll(<Locale>[
          const Locale('en', 'US'),
          const Locale('en', 'GB'),
        ]),
      );
    });

    test('notifies listeners on change', () {
      var notifications = 0;
      void listener() => notifications++;
      HyphenationRegistry.instance.addListener(listener);
      addTearDown(
        () => HyphenationRegistry.instance.removeListener(listener),
      );

      HyphenationRegistry.instance.register(const Locale('en'), testDict);
      HyphenationRegistry.instance.unregister(const Locale('en'));
      expect(notifications, 2);
    });
  });

  group('fallback ownership', () {
    final registry = HyphenationRegistry.instance;
    setUp(registry.clear);
    tearDown(registry.clear);
    test('replacing automatic fallback owner releases old dictionary', () {
      final old = loadTestHyphenator();
      final replacement = loadTestHyphenator();
      registry.register(const Locale('en'), old);
      registry.register(const Locale('en'), replacement);
      expect(registry.fallback, same(replacement));
      registry.unregister(const Locale('en'));
      expect(registry.fallback, isNull);
    });
    test('alias removal does not clear fallback owned by another locale', () {
      final h = loadTestHyphenator();
      registry.register(const Locale('en'), h);
      registry.register(const Locale('fr'), h);
      registry.unregister(const Locale('fr'));
      expect(registry.fallback, same(h));
    });
    test('explicit fallback survives locale replacement and removal', () {
      final h = loadTestHyphenator();
      registry.register(const Locale('en'), h);
      registry.register(null, h);
      registry.register(const Locale('en'), loadTestHyphenator());
      expect(registry.fallback, same(h));
      registry.unregister(const Locale('en'));
      expect(registry.fallback, same(h));
    });
  });
}
