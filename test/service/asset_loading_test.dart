// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_dictionaries.dart';

/// A bundle that serves the example's English dictionary from disk, standing
/// in for the real asset bundle.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final file = File(
      key == 'assets/dictionary/hyph_en_US.dic' ? kEnglishDictionaryPath : key,
    );
    if (!file.existsSync()) {
      throw FlutterError('Asset not found: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(file.readAsBytesSync()));
  }
}

void main() {
  setUp(HyphenationRegistry.instance.clear);
  tearDown(HyphenationRegistry.instance.clear);

  testWidgets('registerAsset loads a dictionary through the bundle', (
    WidgetTester tester,
  ) async {
    final hyphenator = await HyphenationRegistry.instance.registerAsset(
      const Locale('en', 'US'),
      'assets/dictionary/hyph_en_US.dic',
      bundle: _DiskBundle(),
    );
    expect(hyphenator.split('internationalization').length, greaterThan(1));
    expect(
      HyphenationRegistry.instance.resolve(const Locale('en', 'US')),
      same(hyphenator),
    );
  });

  testWidgets('Hyphenator.fromAsset reports a missing dictionary', (
    WidgetTester tester,
  ) async {
    await expectLater(
      Hyphenator.fromAsset('assets/missing.dic', bundle: _DiskBundle()),
      throwsA(isA<FlutterError>()),
    );
  });

  testWidgets('a registered dictionary hyphenates without any scope', (
    WidgetTester tester,
  ) async {
    await HyphenationRegistry.instance.registerAsset(
      const Locale('en', 'US'),
      'assets/dictionary/hyph_en_US.dic',
      bundle: _DiskBundle(),
    );

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 120,
            child: HyphenText(
              'internationalization',
              style: TextStyle(fontSize: 20),
              locale: Locale('en', 'US'),
            ),
          ),
        ),
      ),
    );

    final render = tester.renderObject<RenderHyphenParagraph>(
      find.byType(HyphenParagraph),
    );
    expect(render.renderedText, contains('-\n'));
  });
}
