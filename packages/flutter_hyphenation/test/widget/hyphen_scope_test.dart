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
