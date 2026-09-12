import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_dictionaries.dart';
import '../support/widget_harness.dart';

void main() {
  setUp(HyphenationRegistry.instance.clear);

  tearDown(HyphenationRegistry.instance.clear);

  group('dangling words', () {
    // The test font is fixed-advance, so at fontSize 10 a character is
    // exactly 10 wide and the expected breaks can be counted out.
    const style = TextStyle(fontSize: 10);

    Widget build(Iterable<String> words) => host(
      HyphenText(
        'in the woods',
        style: style,
        hyphenator: loadTestHyphenator(danglingWords: words),
      ),
      width: 70,
    );

    testWidgets('a listed word is carried down with the next one', (
      WidgetTester tester,
    ) async {
      // None of these words is hyphenable, so this also covers the bypass in
      // RenderHyphenParagraph: without the word list there is no break
      // opportunity at all and the text goes straight to the engine.
      await tester.pumpWidget(build(const <String>[]));
      expect(renderedTextOf(tester), 'in the woods');

      await tester.pumpWidget(build(const <String>['the']));
      expect(renderedTextOf(tester), 'in\nthe woods');
    });

    testWidgets('no no-break space is inserted into the painted text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(build(const <String>['the']));
      final rendered = renderedTextOf(tester);
      expect(rendered.contains('\u00A0'), isFalse);
      expect(rendered.replaceAll('\n', ' '), 'in the woods');
    });

    testWidgets('an empty list leaves the text alone', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(build(const <String>['']));
      expect(renderedTextOf(tester), 'in the woods');
    });

    testWidgets('intrinsic width accounts for the glued pair', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(build(const <String>[]));
      final plain = tester
          .renderObject<RenderBox>(find.byType(HyphenParagraph))
          .getMinIntrinsicWidth(double.infinity);

      await tester.pumpWidget(build(const <String>['the']));
      final glued = tester
          .renderObject<RenderBox>(find.byType(HyphenParagraph))
          .getMinIntrinsicWidth(double.infinity);

      // 'the woods' cannot be split, so the paragraph needs 90 rather than
      // the 50 of 'woods' alone.
      expect(plain, 50);
      expect(glued, 90);
    });
  });
}
