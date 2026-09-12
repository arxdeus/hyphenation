// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_dictionaries.dart';
import '../support/widget_harness.dart';

void main() {
  late Hyphenator testDict;
  late Hyphenator english;

  /// A dictionary with no patterns at all, used where a test needs a
  /// hyphenator that cannot break anything.
  late Hyphenator empty;

  setUp(() {
    testDict = loadTestHyphenator();
    english = loadEnglishHyphenator();
    empty = Hyphenator.fromBytes(const <int>[]);
    HyphenationRegistry.instance.clear();
  });

  tearDown(HyphenationRegistry.instance.clear);

  group('hyphenated layout', () {
    testWidgets('splits a word that does not fit', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          HyphenText(
            'hyphenation',
            style: const TextStyle(fontSize: 20),
            hyphenator: testDict,
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
            hyphenator: testDict,
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
          hyphenator: testDict,
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
          HyphenText('hyphenation', style: style, hyphenator: testDict),
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
            hyphenator: testDict,
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
            hyphenator: testDict,
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
            hyphenator: testDict,
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
            hyphenator: testDict,
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
              hyphenator: testDict,
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
          hyphenator: which ?? testDict,
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
            HyphenText(text, style: style, hyphenator: testDict),
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
              hyphenator: testDict,
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
                  hyphenator: testDict,
                ),
              ),
              SizedBox(
                width: 120,
                child: HyphenText(
                  text,
                  style: const TextStyle(fontSize: 16),
                  hyphenator: testDict,
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
      await tester.pumpWidget(host(HyphenText('', hyphenator: testDict)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(host(HyphenText('   ', hyphenator: testDict)));
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
              HyphenText('hyphenation', hyphenator: testDict),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(renderedTextOf(tester), 'hyphenation');
    });
  });
}
