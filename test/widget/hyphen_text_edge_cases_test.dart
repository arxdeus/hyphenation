// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
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

  Widget host(
    Widget child, {
    double width = 100,
    TextDirection direction = TextDirection.ltr,
  }) => Directionality(
    textDirection: direction,
    child: Center(
      child: SizedBox(width: width, child: child),
    ),
  );

  RenderHyphenParagraph renderOf(WidgetTester tester) =>
      tester.renderObject<RenderHyphenParagraph>(find.byType(HyphenParagraph));

  testWidgets('lays out right-to-left without error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        HyphenText(
          'hyphenation',
          style: const TextStyle(fontSize: 20),
          hyphenator: testDict,
        ),
        direction: TextDirection.rtl,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(renderOf(tester).renderedText, contains('-\n'));
  });

  testWidgets('works inside a SelectionArea', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SelectionArea(
          child: Center(
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
      ),
    );
    expect(tester.takeException(), isNull);
    expect(renderOf(tester).renderedText, contains('-\n'));
  });

  testWidgets('punctuation-only text is left alone', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(HyphenText('!!! ??? ...', hyphenator: testDict)),
    );
    expect(tester.takeException(), isNull);
    expect(renderOf(tester).sourceText, '!!! ??? ...');
  });

  testWidgets('emoji and symbols survive intact', (
    WidgetTester tester,
  ) async {
    const text = 'internationalization 😀 hyphenation →±';
    await tester.pumpWidget(
      host(
        HyphenText(
          text,
          style: const TextStyle(fontSize: 20),
          hyphenator: english,
        ),
        width: 120,
      ),
    );
    expect(tester.takeException(), isNull);
    final rendered = renderOf(tester).renderedText;
    expect(rendered.replaceAll('-\n', '').replaceAll('\n', ' '), text);
  });

  testWidgets('newlines in the source are preserved', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        HyphenText(
          'one\ntwo\n\nthree',
          style: const TextStyle(fontSize: 10),
          hyphenator: testDict,
        ),
        width: 200,
      ),
    );
    expect(renderOf(tester).renderedText, 'one\ntwo\n\nthree');
  });

  testWidgets('zero and tiny widths do not hang or throw', (
    WidgetTester tester,
  ) async {
    for (final width in <double>[0, 1, 5]) {
      await tester.pumpWidget(
        host(
          HyphenText(
            'hyphenation extraordinary',
            style: const TextStyle(fontSize: 20),
            hyphenator: testDict,
          ),
          width: width,
        ),
      );
      expect(tester.takeException(), isNull, reason: 'at width $width');
    }
  });

  testWidgets('a very long word does not blow up', (WidgetTester tester) async {
    final long = 'hyphenation' * 200;
    await tester.pumpWidget(
      host(
        HyphenText(
          long,
          style: const TextStyle(fontSize: 20),
          hyphenator: testDict,
        ),
        width: 150,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(renderOf(tester).renderedText.replaceAll('-\n', ''), long);
  });

  testWidgets('repeated rebuilds stay stable', (WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pumpWidget(
        host(
          HyphenText(
            'hyphenation extraordinary',
            style: const TextStyle(fontSize: 20),
            hyphenator: testDict,
          ),
          width: 100 + (i % 3),
        ),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal releases the painters', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        HyphenText(
          'hyphenation',
          style: const TextStyle(fontSize: 20),
          hyphenator: testDict,
        ),
      ),
    );
    await tester.pumpWidget(host(const SizedBox()));
    expect(tester.takeException(), isNull);
  });
}
