import 'package:flutter/material.dart';
import 'package:flutter_hyphenate/flutter_hyphenate.dart';
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

  group('HyphenText as a drop-in for Text', () {
    testWidgets('is a Text', (WidgetTester tester) async {
      const widget = HyphenText('hello');
      expect(widget, isA<Text>());
      expect(widget.data, 'hello');
    });

    testWidgets('renders plain Text without a dictionary', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(const HyphenText('hyphenation')));
      expect(find.byType(HyphenParagraph), findsNothing);
      expect(find.text('hyphenation'), findsOneWidget);
    });

    testWidgets('accepts every Text property', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          HyphenText(
            'hyphenation of words',
            style: const TextStyle(fontSize: 14),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            locale: const Locale('en', 'US'),
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            textScaler: const TextScaler.linear(1.2),
            maxLines: 2,
            semanticsLabel: 'label',
            textWidthBasis: TextWidthBasis.parent,
            textHeightBehavior: const TextHeightBehavior(),
            selectionColor: const Color(0xFF00FF00),
            strutStyle: const StrutStyle(fontSize: 14),
            hyphenator: testDict,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(HyphenParagraph), findsOneWidget);
    });

    testWidgets('HyphenText.rich renders its span', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          HyphenText.rich(
            const TextSpan(
              children: <InlineSpan>[
                TextSpan(text: 'one '),
                TextSpan(text: 'two'),
              ],
            ),
            hyphenator: testDict,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(RichText), findsOneWidget);
    });

    testWidgets('hyphenate: false behaves exactly like Text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          HyphenText('hyphenation', hyphenator: testDict, hyphenate: false),
        ),
      );
      expect(find.byType(HyphenParagraph), findsNothing);
    });
  });
}
