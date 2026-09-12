import 'package:flutter/widgets.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_dictionaries.dart';

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

  group('HyphenScope', () {
    testWidgets('maybeOf finds the nearest scope', (WidgetTester tester) async {
      late Hyphenator? found;
      await tester.pumpWidget(
        HyphenScope(
          hyphenator: testDict,
          child: Builder(
            builder: (BuildContext context) {
              found = HyphenScope.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(found, same(testDict));
    });

    testWidgets('maybeOf returns null without a scope', (
      WidgetTester tester,
    ) async {
      late Hyphenator? found;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            found = HyphenScope.maybeOf(context);
            return const SizedBox();
          },
        ),
      );
      expect(found, isNull);
    });

    testWidgets('the innermost scope wins', (WidgetTester tester) async {
      late Hyphenator? found;
      await tester.pumpWidget(
        HyphenScope(
          hyphenator: testDict,
          child: HyphenScope(
            hyphenator: english,
            child: Builder(
              builder: (BuildContext context) {
                found = HyphenScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(found, same(english));
    });

    testWidgets('resolve falls back to the registry', (
      WidgetTester tester,
    ) async {
      HyphenationRegistry.instance.register(const Locale('en', 'GB'), english);
      late Hyphenator? found;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            found = HyphenScope.resolve(
              context,
              locale: const Locale('en', 'GB'),
            );
            return const SizedBox();
          },
        ),
      );
      expect(found, same(english));
    });

    testWidgets('a scope with a null hyphenator shadows the registry', (
      WidgetTester tester,
    ) async {
      HyphenationRegistry.instance.register(null, english);
      late Hyphenator? found;
      await tester.pumpWidget(
        HyphenScope(
          child: Builder(
            builder: (BuildContext context) {
              found = HyphenScope.resolve(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(found, isNull);
    });

    test('only notifies when the hyphenator actually changes', () {
      final scope = HyphenScope(
        hyphenator: testDict,
        child: const SizedBox(),
      );
      expect(
        scope.updateShouldNotify(
          HyphenScope(hyphenator: testDict, child: const SizedBox()),
        ),
        isFalse,
      );
      expect(
        scope.updateShouldNotify(
          HyphenScope(hyphenator: english, child: const SizedBox()),
        ),
        isTrue,
      );
    });

    testWidgets('dependents see the new hyphenator after a change', (
      WidgetTester tester,
    ) async {
      final seen = <Hyphenator?>[];
      Widget build(Hyphenator? hyphenator) => HyphenScope(
        hyphenator: hyphenator,
        child: Builder(
          builder: (BuildContext context) {
            seen.add(HyphenScope.maybeOf(context));
            return const SizedBox();
          },
        ),
      );

      await tester.pumpWidget(build(testDict));
      await tester.pumpWidget(build(english));
      await tester.pumpWidget(build(null));
      expect(seen, <Hyphenator?>[testDict, english, null]);
    });
  });
}
