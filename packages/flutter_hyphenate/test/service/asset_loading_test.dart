import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hyphenate/flutter_hyphenate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_dictionaries.dart';

/// A bundle that serves the example's English dictionary from disk, standing
/// in for the real asset bundle.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final file = File(
      key == 'assets/patterns/ushyph1.tex' ? kEnglishPatternPath : key,
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

  testWidgets('registerAsset loads a pattern set through the bundle', (
    WidgetTester tester,
  ) async {
    final hyphenator = await HyphenationRegistry.instance.registerAsset(
      const Locale('en', 'US'),
      'assets/patterns/ushyph1.tex',
      bundle: _DiskBundle(),
    );
    expect(hyphenator.split('internationalization').length, greaterThan(1));
    expect(
      HyphenationRegistry.instance.resolve(const Locale('en', 'US')),
      same(hyphenator),
    );
  });

  test(
    'registerAsset forwards cache budgets through both loading factories',
    () async {
      final h = await HyphenationRegistry.instance.registerAsset(
        const Locale('en'),
        'assets/patterns/ushyph1.tex',
        bundle: _DiskBundle(),
        maxCacheSize: 7,
        maxParagraphCacheSize: 3,
        maxParagraphCacheBytes: 256,
        maxCachedWordLength: 4,
      );
      expect(h.maxCacheSize, 7);
      expect(h.maxParagraphCacheSize, 3);
      expect(h.maxParagraphCacheBytes, 256);
      expect(h.maxCachedWordLength, 4);
      expect(h.breakOffsets('hyphenation'), isNotEmpty);
      expect(h.cacheCounts.$1, 0);
    },
  );

  testWidgets('HyphenatorAsset.fromAsset reports a missing pattern file', (
    WidgetTester tester,
  ) async {
    await expectLater(
      HyphenatorAsset.fromAsset('assets/missing.tex', bundle: _DiskBundle()),
      throwsA(isA<FlutterError>()),
    );
  });

  testWidgets('a registered pattern set hyphenates without any scope', (
    WidgetTester tester,
  ) async {
    await HyphenationRegistry.instance.registerAsset(
      const Locale('en', 'US'),
      'assets/patterns/ushyph1.tex',
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
