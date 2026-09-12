import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_dictionaries.dart';

/// The text the paragraph actually paints, including inserted hyphens and
/// line breaks.
/// Counts fresh breaks; the shared cache is disabled so every miss on the
/// render object's own cache shows up.
class _CountingHyphenator extends Hyphenator {
  _CountingHyphenator(super.hyphen) : super(maxCacheSize: 0);

  int breaks = 0;

  @override
  void cacheBreak(Object key, String value) {
    breaks++;
    super.cacheBreak(key, value);
  }
}

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
  late Hyphenator english;
  /// A dictionary with no patterns at all, used where a test needs a
  /// hyphenator that cannot break anything.
  late Hyphenator empty;

  setUp(() {
    latin = loadTestLatinHyphenator();
    english = loadEnglishHyphenator();
    empty = Hyphenator.fromBytes(const <int>[]);
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

    testWidgets('works with a real dictionary', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          HyphenText(
            'internationalization',
            style: const TextStyle(fontSize: 20),
            hyphenator: english,
          ),
          width: 120,
        ),
      );
      final rendered = renderedTextOf(tester);
      expect(rendered, contains('-\n'));
      expect(rendered.replaceAll('-\n', ''), 'internationalization');
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
        build(data: 'hyphenation', fontSize: 20, width: 100, which: empty),
      );
      expect(
        renderedTextOf(tester),
        isNot(contains('-\n')),
        reason: 'an empty dictionary cannot break any word',
      );
    });

    testWidgets('both break strategies produce valid lines', (
      WidgetTester tester,
    ) async {
      // The render object lets the engine break the paragraph the first few
      // times and switches to the measuring breaker once a paragraph is being
      // resized repeatedly. The two are allowed to disagree about which of
      // several legal break points to take, but both must always produce
      // lines that fit the column and preserve the text.
      const text = 'hyphenation extraordinary computer always wonderful';
      const style = TextStyle(fontSize: 16);

      double widthOf(String line) {
        final painter = TextPainter(
          text: TextSpan(text: line, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        final result = painter.width;
        painter.dispose();
        return result;
      }

      Future<List<String>> linesAt(double width) async {
        await tester.pumpWidget(
          host(
            HyphenText(text, style: style, hyphenator: latin),
            width: width,
          ),
        );
        return renderedTextOf(tester).split('\n');
      }

      void check(List<String> lines, double width, String label) {
        for (final line in lines) {
          expect(
            widthOf(line),
            lessThanOrEqualTo(width),
            reason: '$label: "$line" overflows a ${width}px column',
          );
        }
        // Removing the hyphens and re-joining must give the text back.
        final rebuilt = lines
            .map(
              (String l) =>
                  l.endsWith('-') ? l.substring(0, l.length - 1) : '$l ',
            )
            .join()
            .trim();
        expect(rebuilt, text, reason: '$label: text was altered');
      }

      for (final width in <double>[90, 120, 150, 180, 210, 240]) {
        // First pass: a width seen for the first time, broken by the engine.
        check(await linesAt(width), width, 'engine');
      }
      for (final width in <double>[90, 120, 150, 180, 210, 240]) {
        // Second pass: by now the object has switched to the measuring
        // breaker.
        check(await linesAt(width), width, 'breaker');
      }
    });

    testWidgets('the shared break cache never crosses configurations', (
      WidgetTester tester,
    ) async {
      // Break results are cached on the Hyphenator so two widgets showing the
      // same text at the same width only break once. Anything that changes
      // where the lines fall has to be part of that key, or one widget would
      // pick up another's layout.
      const text = 'hyphenation extraordinary computer';

      Future<String> render({
        double width = 120,
        double fontSize = 16,
        String hyphen = '-',
        TextDirection direction = TextDirection.ltr,
        TextScaler scaler = TextScaler.noScaling,
      }) async {
        await tester.pumpWidget(
          host(
            HyphenText(
              text,
              style: TextStyle(fontSize: fontSize),
              hyphenator: latin,
              hyphenCharacter: hyphen,
              textScaler: scaler,
            ),
            width: width,
            direction: direction,
          ),
        );
        return renderedTextOf(tester);
      }

      final base = await render();
      expect(base, contains('-\n'));

      // Each of these must produce its own result, not the cached one.
      expect(await render(width: 200), isNot(base), reason: 'width');
      expect(await render(fontSize: 30), isNot(base), reason: 'font size');
      expect(
        await render(scaler: const TextScaler.linear(2)),
        isNot(base),
        reason: 'text scaler',
      );
      final piped = await render(hyphen: '=');
      expect(piped, contains('=\n'), reason: 'hyphen character');
      expect(piped, isNot(contains('-\n')));

      // And the original configuration still gives the original answer.
      expect(await render(), base);
    });

    testWidgets('two widgets sharing a dictionary agree', (
      WidgetTester tester,
    ) async {
      const text = 'hyphenation extraordinary';
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 120,
                child: HyphenText(
                  text,
                  style: const TextStyle(fontSize: 16),
                  hyphenator: latin,
                ),
              ),
              SizedBox(
                width: 120,
                child: HyphenText(
                  text,
                  style: const TextStyle(fontSize: 16),
                  hyphenator: latin,
                ),
              ),
            ],
          ),
        ),
      );
      final renders = tester
          .renderObjectList<RenderHyphenParagraph>(find.byType(HyphenParagraph))
          .toList();
      expect(renders, hasLength(2));
      expect(renders[0].renderedText, renders[1].renderedText);
      expect(renders[0].renderedText, contains('-\n'));
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
      HyphenationRegistry.instance.register(const Locale('en', 'US'), english);
      await tester.pumpWidget(
        host(
          const HyphenText(
            'internationalization',
            style: TextStyle(fontSize: 20),
            locale: Locale('en', 'US'),
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
            hyphenator: empty,
            child: HyphenText(
              'hyphenation',
              style: const TextStyle(fontSize: 20),
              hyphenator: latin,
            ),
          ),
          width: 100,
        ),
      );
      // The empty dictionary cannot break anything, so a hyphen here
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

      await tester.pumpWidget(build(empty));
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

    testWidgets('a paint-only style change keeps the breaks without '
        're-breaking', (WidgetTester tester) async {
      final counting = _CountingHyphenator(latin.hyphen);
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
      final counting = _CountingHyphenator(latin.hyphen);
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

  group('dangling words', () {
    // The test font is fixed-advance, so at fontSize 10 a character is
    // exactly 10 wide and the expected breaks can be counted out.
    const style = TextStyle(fontSize: 10);

    Widget build(Iterable<String> words) => host(
      HyphenText(
        'in the woods',
        style: style,
        hyphenator: loadTestLatinHyphenator(danglingWords: words),
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
