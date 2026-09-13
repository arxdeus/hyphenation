import 'package:flutter/material.dart';
import 'package:flutter_hyphenation/flutter_hyphenation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_dictionaries.dart';
import '../support/widget_harness.dart';

void main() {
  late Hyphenator testDict;

  setUp(() {
    testDict = loadTestHyphenator();
    HyphenationRegistry.instance.clear();
  });

  tearDown(HyphenationRegistry.instance.clear);

  group('semantics', () {
    testWidgets('exposes the original text, not the hyphenated one', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 100,
              child: HyphenText(
                'hyphenation',
                style: const TextStyle(fontSize: 20),
                hyphenator: testDict,
              ),
            ),
          ),
        ),
      );
      expect(renderedTextOf(tester), contains('-\n'));
      expect(find.bySemanticsLabel('hyphenation'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an explicit semanticsLabel wins', (WidgetTester tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 100,
              child: HyphenText(
                'hyphenation',
                style: const TextStyle(fontSize: 20),
                hyphenator: testDict,
                semanticsLabel: 'custom',
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('custom'), findsOneWidget);
      handle.dispose();
    });
  });
}
