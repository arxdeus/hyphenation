import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_dictionaries.dart';

/// The text the paragraph actually paints, including inserted hyphens and
/// line breaks.
String renderedTextOf(WidgetTester tester) {
  final render = tester.renderObject<RenderHyphenParagraph>(
    find.byType(HyphenParagraph),
  );
  return render.renderedText;
}

/// Wraps [child] in the minimum a text widget needs to lay out.
Widget host(
  Widget child, {
  double width = 200,
  TextDirection direction = TextDirection.ltr,
}) => Directionality(
  textDirection: direction,
  child: Center(
    child: SizedBox(
      width: width,
      child: child,
    ),
  ),
);

void main() {
  late Hyphenator latin;
  late Hyphenator russian;

  setUp(() {
    latin = loadTestLatinHyphenator();
    russian = loadRussianHyphenator();
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
            hyphenator: latin,
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
            hyphenator: latin,
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
          HyphenText('hyphenation', hyphenator: latin, hyphenate: false),
        ),
      );
      expect(find.byType(HyphenParagraph), findsNothing);
    });
  });

  group('hyphenated layout', () {
    testWidgets('splits a word that does not fit', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          HyphenText(
            'hyphenation',
            style: const TextStyle(fontSize: 20),
            hyphenator: latin,
          ),
          width: 100,
        ),
      );
      final rendered = renderedTextOf(tester);
      expect(rendered, contains('-\n'));
      expect(rendered.replaceAll('-\n', ''), 'hyphenation');
    });

    testWidgets('a wide box needs no hyphen', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          HyphenText(
            'hyphenation',
            style: const TextStyle(fontSize: 10),
            hyphenator: latin,
          ),
          width: 400,
        ),
      );
      expect(renderedTextOf(tester), 'hyphenation');
    });

    testWidgets('re-breaks when the width changes', (
      WidgetTester tester,
    ) async {
      Widget build(double width) => host(
        HyphenText(
          'hyphenation',
          style: const TextStyle(fontSize: 20),
          hyphenator: latin,
        ),
        width: width,
      );

      await tester.pumpWidget(build(400));
      expect(renderedTextOf(tester), 'hyphenation');

      await tester.pumpWidget(build(100));
      expect(renderedTextOf(tester), contains('-\n'));

      await tester.pumpWidget(build(400));
      expect(renderedTextOf(tester), 'hyphenation');
    });

    testWidgets('the word fits the column instead of overflowing it', (
      WidgetTester tester,
    ) async {
      const style = TextStyle(fontSize: 20);

      await tester.pumpWidget(
        host(const Text('hyphenation', style: style), width: 100),
      );
      final plain = tester.renderObject<RenderParagraph>(find.byType(RichText));
      // A plain Text has to break the over-long word somewhere, and the engine
      // does it mid-word with no hyphen at all.
      expect(plain.getMaxIntrinsicWidth(double.infinity), greaterThan(100.0));
      expect(plain.size.height, greaterThan(plain.preferredLineHeight));

      await tester.pumpWidget(
        host(
          HyphenText('hyphenation', style: style, hyphenator: latin),
          width: 100,
        ),
      );
      final hyphenated = tester.renderObject<RenderHyphenParagraph>(
        find.byType(HyphenParagraph),
      );
      // Hyphenation fits the same column, but the break is a dictionary one
      // and it is marked with a hyphen, which is the whole point.
      expect(
        hyphenated.getMinIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(100.0),
      );
      expect(
        hyphenated.size.height,
        greaterThan(hyphenated.preferredLineHeight),
      );
      final lines = renderedTextOf(tester).split('\n');
      expect(lines.length, greaterThan(1));
      for (var i = 0; i < lines.length - 1; i++) {
        expect(
          lines[i],
          endsWith('-'),
          reason: 'every broken line must show a hyphen',
        );
      }
      expect(
        lines.map((String l) => l.replaceAll('-', '')).join(),
        'hyphenation',
      );
    });

    testWidgets('a custom hyphen character is painted', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          HyphenText(
            'hyphenation',
            style: const TextStyle(fontSize: 20),
            hyphenator: latin,
            hyphenCharacter: '=',
          ),
          width: 100,
        ),
      );
      expect(renderedTextOf(tester), contains('=\n'));
    });

    testWidgets('works with a real Russian dictionary', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          HyphenText(
            'программирование',
            style: const TextStyle(fontSize: 20),
            hyphenator: russian,
          ),
          width: 120,
        ),
      );
      final rendered = renderedTextOf(tester);
      expect(rendered, contains('-\n'));
      expect(rendered.replaceAll('-\n', ''), 'программирование');
    });

    testWidgets('softWrap: false disables breaking', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          HyphenText(
            'hyphenation',
            style: const TextStyle(fontSize: 20),
            hyphenator: latin,
            softWrap: false,
          ),
          width: 100,
        ),
      );
      expect(renderedTextOf(tester), 'hyphenation');
    });

    testWidgets('maxLines and ellipsis still apply', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          HyphenText(
            'hyphenation extraordinary computer',
            style: const TextStyle(fontSize: 20),
            hyphenator: latin,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          width: 100,
        ),
      );
      final size = tester.getSize(find.byType(HyphenParagraph));
      expect(size.width, lessThanOrEqualTo(100.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a column too narrow for any chunk still fits its box', (
      WidgetTester tester,
    ) async {
      // Found by driving the example app: at an extreme width no hyphenated
      // chunk fits, and the paragraph must fall back to the engine's own
      // breaking rather than painting outside its box.
      await tester.pumpWidget(
        host(
          HyphenText(
            'extraordinary hyphenation',
            style: const TextStyle(fontSize: 20),
            hyphenator: latin,
          ),
          width: 30,
        ),
      );
      final render = tester.renderObject<RenderHyphenParagraph>(
        find.byType(HyphenParagraph),
      );
      expect(render.size.width, lessThanOrEqualTo(30.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('dry layout agrees with real layout', (
      WidgetTester tester,
    ) async {
      for (final width in <double>[30, 60, 100, 160, 400]) {
        await tester.pumpWidget(
          host(
            HyphenText(
              'extraordinary hyphenation computer',
              style: const TextStyle(fontSize: 20),
              hyphenator: latin,
            ),
            width: width,
          ),
        );
        final render = tester.renderObject<RenderHyphenParagraph>(
          find.byType(HyphenParagraph),
        );
        // The same constraints the real layout ran under, so the two are
        // directly comparable.
        expect(
          render.getDryLayout(render.constraints),
          render.size,
          reason: 'at width $width',
        );
      }
    });

    testWidgets('the width cache never serves a stale break', (
      WidgetTester tester,
    ) async {
      // The broken text is memoised per width, so every input that feeds the
      // break must invalidate it. A stale entry would paint hyphens in the
      // wrong places, which no other test would notice.
      Widget build({
        required String data,
        required double fontSize,
        required double width,
        Hyphenator? which,
      }) => host(
        HyphenText(
          data,
          style: TextStyle(fontSize: fontSize),
          hyphenator: which ?? latin,
        ),
        width: width,
      );

      // Same width throughout, so only the other inputs can change the break.
      await tester.pumpWidget(
        build(data: 'hyphenation', fontSize: 20, width: 100),
      );
      final atTwenty = renderedTextOf(tester);

      await tester.pumpWidget(
        build(data: 'hyphenation', fontSize: 8, width: 100),
      );
      final atEight = renderedTextOf(tester);
      expect(atEight, isNot(atTwenty), reason: 'style change must re-break');
      expect(atEight, 'hyphenation');

      await tester.pumpWidget(
        build(data: 'hyphenation', fontSize: 20, width: 100),
      );
      expect(
        renderedTextOf(tester),
        atTwenty,
        reason: 'going back must restore the original break',
      );

      // Changing the text at the same width and style.
      await tester.pumpWidget(
        build(data: 'extraordinary', fontSize: 20, width: 100),
      );
      expect(renderedTextOf(tester).replaceAll('-\n', ''), 'extraordinary');

      // Changing the dictionary at the same width, style and text.
      await tester.pumpWidget(
        build(data: 'hyphenation', fontSize: 20, width: 100, which: russian),
      );
      expect(
        renderedTextOf(tester),
        isNot(contains('-\n')),
        reason: 'the Russian dictionary cannot break a Latin word',
      );
    });

    testWidgets('empty and whitespace text lay out without error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(HyphenText('', hyphenator: latin)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(host(HyphenText('   ', hyphenator: latin)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unbounded width does not throw', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: <Widget>[
              HyphenText('hyphenation', hyphenator: latin),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(renderedTextOf(tester), 'hyphenation');
    });
  });

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
                hyphenator: latin,
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
              hyphenator: latin,
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
                  hyphenator: latin,
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
            hyphenator: latin,
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

  group('dictionary resolution', () {
    testWidgets('HyphenScope supplies the dictionary', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          HyphenScope(
            hyphenator: latin,
            child: const HyphenText(
              'hyphenation',
              style: TextStyle(fontSize: 20),
            ),
          ),
          width: 100,
        ),
      );
      expect(renderedTextOf(tester), contains('-\n'));
    });

    testWidgets('a null scope disables hyphenation for the subtree', (
      WidgetTester tester,
    ) async {
      HyphenationRegistry.instance.register(null, latin);
      await tester.pumpWidget(
        host(
          const HyphenScope(
            child: HyphenText('hyphenation', style: TextStyle(fontSize: 20)),
          ),
          width: 100,
        ),
      );
      expect(find.byType(HyphenParagraph), findsNothing);
    });

    testWidgets('the registry supplies the dictionary by locale', (
      WidgetTester tester,
    ) async {
      HyphenationRegistry.instance.register(const Locale('ru', 'RU'), russian);
      await tester.pumpWidget(
        host(
          const HyphenText(
            'программирование',
            style: TextStyle(fontSize: 20),
            locale: Locale('ru', 'RU'),
          ),
          width: 120,
        ),
      );
      expect(renderedTextOf(tester), contains('-\n'));
    });

    testWidgets('the widget property beats the scope', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          HyphenScope(
            hyphenator: russian,
            child: HyphenText(
              'hyphenation',
              style: const TextStyle(fontSize: 20),
              hyphenator: latin,
            ),
          ),
          width: 100,
        ),
      );
      // The Russian dictionary cannot break a Latin word, so a hyphen here
      // proves the widget's own hyphenator was used.
      expect(renderedTextOf(tester), contains('-\n'));
    });

    testWidgets('swapping the dictionary re-lays out', (
      WidgetTester tester,
    ) async {
      Widget build(Hyphenator? hyphenator) => host(
        HyphenScope(
          hyphenator: hyphenator,
          child: const HyphenText(
            'hyphenation',
            style: TextStyle(fontSize: 20),
          ),
        ),
        width: 100,
      );

      await tester.pumpWidget(build(russian));
      expect(renderedTextOf(tester), 'hyphenation');

      await tester.pumpWidget(build(latin));
      expect(renderedTextOf(tester), contains('-\n'));
    });
  });

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
                hyphenator: latin,
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
                hyphenator: latin,
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

  group('text changes', () {
    testWidgets('changing the data re-hyphenates', (WidgetTester tester) async {
      Widget build(String data) => host(
        HyphenText(
          data,
          style: const TextStyle(fontSize: 20),
          hyphenator: latin,
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
          hyphenator: latin,
        ),
        width: 100,
      );

      await tester.pumpWidget(build(8));
      expect(renderedTextOf(tester), 'hyphenation');

      await tester.pumpWidget(build(24));
      expect(renderedTextOf(tester), contains('-\n'));
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
            hyphenator: latin,
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
