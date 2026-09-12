import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  group('text changes', () {
    testWidgets('changing the data re-hyphenates', (WidgetTester tester) async {
      Widget build(String data) => host(
        HyphenText(
          data,
          style: const TextStyle(fontSize: 20),
          hyphenator: testDict,
        ),
        width: 100,
      );

      await tester.pumpWidget(build('hyphenation'));
      expect(renderedTextOf(tester).replaceAll('-\n', ''), 'hyphenation');

      await tester.pumpWidget(build('extraordinary'));
      expect(renderedTextOf(tester).replaceAll('-\n', ''), 'extraordinary');
    });

    testWidgets('changing the style re-measures', (WidgetTester tester) async {
      Widget build(double fontSize) => host(
        HyphenText(
          'hyphenation',
          style: TextStyle(fontSize: fontSize),
          hyphenator: testDict,
        ),
        width: 100,
      );

      await tester.pumpWidget(build(8));
      expect(renderedTextOf(tester), 'hyphenation');

      await tester.pumpWidget(build(24));
      expect(renderedTextOf(tester), contains('-\n'));
    });

    testWidgets('a paint-only style change keeps the breaks without '
        're-breaking', (WidgetTester tester) async {
      final counting = CountingHyphenator(testDict.dictionary);
      Widget build(Color color) => host(
        HyphenText(
          'wonderful hyphenation',
          style: TextStyle(fontSize: 20, color: color),
          hyphenator: counting,
        ),
        width: 120,
      );

      await tester.pumpWidget(build(const Color(0xFF000000)));
      final before = renderedTextOf(tester);
      expect(before, contains('-\n'));
      expect(counting.breaks, 1);

      await tester.pumpWidget(build(const Color(0xFFFF0000)));
      expect(renderedTextOf(tester), before);
      expect(counting.breaks, 1, reason: 'colour does not move glyphs');
      final render = tester.renderObject<RenderHyphenParagraph>(
        find.byType(HyphenParagraph),
      );
      expect((render.text as TextSpan).style?.color, const Color(0xFFFF0000));

      await tester.pumpWidget(
        host(
          HyphenText(
            'wonderful hyphenation',
            style: const TextStyle(fontSize: 21),
            hyphenator: counting,
          ),
          width: 120,
        ),
      );
      expect(counting.breaks, 2, reason: 'a font size change re-breaks');
    });

    testWidgets('a dry layout at another width does not evict the painted '
        'width', (WidgetTester tester) async {
      final counting = CountingHyphenator(testDict.dictionary);
      await tester.pumpWidget(
        host(
          HyphenText(
            'wonderful hyphenation',
            style: const TextStyle(fontSize: 20),
            hyphenator: counting,
          ),
          width: 120,
        ),
      );
      final render = tester.renderObject<RenderHyphenParagraph>(
        find.byType(HyphenParagraph),
      );
      expect(counting.breaks, 1);

      render.getDryLayout(const BoxConstraints(maxWidth: 80));
      expect(counting.breaks, 2);

      render.markNeedsLayout();
      await tester.pump();
      expect(counting.breaks, 2, reason: 'the painted width is still cached');
    });

    testWidgets('changing the text scaler re-measures', (
      WidgetTester tester,
    ) async {
      Widget build(double scale) => MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: host(
          HyphenText(
            'hyphenation',
            style: const TextStyle(fontSize: 10),
            hyphenator: testDict,
          ),
          width: 100,
        ),
      );

      await tester.pumpWidget(build(0.5));
      expect(renderedTextOf(tester), 'hyphenation');

      await tester.pumpWidget(build(3));
      expect(renderedTextOf(tester), contains('-\n'));
    });
  });
}
