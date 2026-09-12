import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
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

  group('intrinsics', () {
    testWidgets('IntrinsicWidth works and is narrower than the word', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: IntrinsicWidth(
              child: HyphenText(
                'hyphenation',
                style: const TextStyle(fontSize: 20),
                hyphenator: testDict,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('IntrinsicHeight works', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          IntrinsicHeight(
            child: HyphenText(
              'hyphenation extraordinary',
              style: const TextStyle(fontSize: 20),
              hyphenator: testDict,
            ),
          ),
          width: 100,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('baseline alignment works', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              const Text('x'),
              Flexible(
                child: HyphenText(
                  'hyphenation',
                  style: const TextStyle(fontSize: 20),
                  hyphenator: testDict,
                ),
              ),
            ],
          ),
          width: 120,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('min intrinsic width is below the unhyphenated word width', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          HyphenText(
            'hyphenation',
            style: const TextStyle(fontSize: 20),
            hyphenator: testDict,
          ),
        ),
      );
      final render = tester.renderObject<RenderHyphenParagraph>(
        find.byType(HyphenParagraph),
      );
      final minWidth = render.getMinIntrinsicWidth(double.infinity);
      final maxWidth = render.getMaxIntrinsicWidth(double.infinity);
      expect(minWidth, greaterThan(0));
      expect(minWidth, lessThan(maxWidth));
    });
  });
}
