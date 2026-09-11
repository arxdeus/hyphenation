import 'package:flutter/widgets.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_dictionaries.dart';

void main() {
  late Hyphenator latin;
  late Hyphenator russian;

  setUp(() {
    latin = loadTestLatinHyphenator();
    russian = loadRussianHyphenator();
    HyphenationRegistry.instance.clear();
  });

  tearDown(HyphenationRegistry.instance.clear);

  group('HyphenationRegistry', () {
    test('resolves an exact locale', () {
      HyphenationRegistry.instance.register(const Locale('ru', 'RU'), russian);
      expect(
        HyphenationRegistry.instance.resolve(const Locale('ru', 'RU')),
        same(russian),
      );
    });

    test('falls back from a country to a bare language', () {
      HyphenationRegistry.instance.register(const Locale('en'), latin);
      expect(
        HyphenationRegistry.instance.resolve(const Locale('en', 'GB')),
        same(latin),
      );
    });

    test('prefers the most specific match', () {
      HyphenationRegistry.instance
        ..register(const Locale('en'), latin)
        ..register(const Locale('en', 'US'), russian);
      expect(
        HyphenationRegistry.instance.resolve(const Locale('en', 'US')),
        same(russian),
      );
      expect(
        HyphenationRegistry.instance.resolve(const Locale('en', 'GB')),
        same(latin),
      );
    });

    test('the first registration becomes the fallback', () {
      HyphenationRegistry.instance.register(const Locale('en'), latin);
      expect(HyphenationRegistry.instance.fallback, same(latin));
      expect(
        HyphenationRegistry.instance.resolve(const Locale('de')),
        same(latin),
      );
    });

    test('an explicit fallback can be set and beats nothing else', () {
      HyphenationRegistry.instance
        ..register(const Locale('en'), latin)
        ..register(null, russian);
      expect(HyphenationRegistry.instance.fallback, same(russian));
      expect(
        HyphenationRegistry.instance.resolve(const Locale('en')),
        same(latin),
      );
      expect(
        HyphenationRegistry.instance.resolve(const Locale('fr')),
        same(russian),
      );
    });

    test('resolve(null) returns the fallback', () {
      HyphenationRegistry.instance.register(null, latin);
      expect(HyphenationRegistry.instance.resolve(null), same(latin));
    });

    test('resolve returns null when empty', () {
      expect(HyphenationRegistry.instance.resolve(const Locale('en')), isNull);
      expect(HyphenationRegistry.instance.resolve(null), isNull);
    });

    test('handles locales with a script code', () {
      HyphenationRegistry.instance.register(const Locale('sr'), latin);
      expect(
        HyphenationRegistry.instance.resolve(
          const Locale.fromSubtags(
            languageCode: 'sr',
            scriptCode: 'Latn',
            countryCode: 'RS',
          ),
        ),
        same(latin),
      );
    });

    test('unregister removes a dictionary', () {
      HyphenationRegistry.instance.register(const Locale('en'), latin);
      HyphenationRegistry.instance.unregister(const Locale('en'));
      expect(HyphenationRegistry.instance.resolve(const Locale('en')), isNull);
    });

    test('locales lists what is registered', () {
      HyphenationRegistry.instance
        ..register(const Locale('en', 'US'), latin)
        ..register(const Locale('ru'), russian);
      expect(
        HyphenationRegistry.instance.locales,
        containsAll(<Locale>[const Locale('en', 'US'), const Locale('ru')]),
      );
    });

    test('notifies listeners on change', () {
      var notifications = 0;
      void listener() => notifications++;
      HyphenationRegistry.instance.addListener(listener);
      addTearDown(
        () => HyphenationRegistry.instance.removeListener(listener),
      );

      HyphenationRegistry.instance.register(const Locale('en'), latin);
      HyphenationRegistry.instance.unregister(const Locale('en'));
      expect(notifications, 2);
    });
  });

  group('HyphenScope', () {
    testWidgets('maybeOf finds the nearest scope', (WidgetTester tester) async {
      late Hyphenator? found;
      await tester.pumpWidget(
        HyphenScope(
          hyphenator: latin,
          child: Builder(
            builder: (BuildContext context) {
              found = HyphenScope.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(found, same(latin));
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
          hyphenator: latin,
          child: HyphenScope(
            hyphenator: russian,
            child: Builder(
              builder: (BuildContext context) {
                found = HyphenScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(found, same(russian));
    });

    testWidgets('resolve falls back to the registry', (
      WidgetTester tester,
    ) async {
      HyphenationRegistry.instance.register(const Locale('ru'), russian);
      late Hyphenator? found;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            found = HyphenScope.resolve(context, locale: const Locale('ru'));
            return const SizedBox();
          },
        ),
      );
      expect(found, same(russian));
    });

    testWidgets('a scope with a null hyphenator shadows the registry', (
      WidgetTester tester,
    ) async {
      HyphenationRegistry.instance.register(null, russian);
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
        hyphenator: latin,
        child: const SizedBox(),
      );
      expect(
        scope.updateShouldNotify(
          HyphenScope(hyphenator: latin, child: const SizedBox()),
        ),
        isFalse,
      );
      expect(
        scope.updateShouldNotify(
          HyphenScope(hyphenator: russian, child: const SizedBox()),
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

      await tester.pumpWidget(build(latin));
      await tester.pumpWidget(build(russian));
      await tester.pumpWidget(build(null));
      expect(seen, <Hyphenator?>[latin, russian, null]);
    });
  });
}
