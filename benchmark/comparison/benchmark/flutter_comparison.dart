// This is a flutter_test suite outside test/; fresh widgets are intentional.
// ignore_for_file: invalid_use_of_visible_for_testing_member, prefer_const_constructors

// Debug/test-binding synchronous widget work, NOT device FPS or raster time.
// Run: cd benchmark/comparison && flutter test benchmark/flutter_comparison.dart
// Dictionary loading is excluded for every candidate. Adapters are explicitly
// named below and are not equivalent output/quality or full-package benchmarks.
import 'dart:convert';
import 'dart:io';

import 'package:auto_hyphenating_text/auto_hyphenating_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hyphenation/flutter_hyphenation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyphen/hyphen.dart' as hyphen_pkg;
import 'package:hyphenator_impure/hyphenator.dart' as impure;
import 'package:hyphenatorx/hyphenatorx.dart' as hyphenatorx;

import 'support/corpora.dart';
import 'support/flutter_adapters.dart';
import 'support/measure.dart';
import 'support/reporting.dart';

const TextStyle kStyle = TextStyle(
  inherit: false,
  color: Colors.black,
  fontSize: 16,
  height: 1.3,
);
const double kWidth = 320;
const int widthCount = 120;
double cyclingWidth(int i) => 240 + (i % widthCount) * 0.5;

/// Synchronous adapter for hyphenatorx.wrap. Excludes the stock widget's
/// FutureBuilder and asset load. Uses its wrap algorithm, not its lifecycle.
class HyphenatorxText extends StatelessWidget {
  const HyphenatorxText(this.text, this.hyphenator, {super.key});
  final String text;
  final hyphenatorx.Hyphenator hyphenator;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Text(
      hyphenator
          .wrap(Text(text, style: kStyle), kStyle, constraints.maxWidth)
          .textStr,
      style: kStyle,
    ),
  );
}

void pumpSync(WidgetTester tester, Widget widget) {
  tester.binding
    ..attachRootWidget(tester.binding.wrapWithDefaultView(widget))
    ..scheduleFrame()
    ..handleBeginFrame(null)
    ..handleDrawFrame();
}

Widget host(Widget child, double width) => MediaQuery(
  data: const MediaQueryData(textScaler: TextScaler.noScaling),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: DefaultTextStyle(
      style: kStyle,
      child: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

/// All four caches are independent. Clearing just the string caches leaves
/// syllablesWord (used by wrap) warm and invalidates a purported cold row.
void resetX(hyphenatorx.Hyphenator x) {
  x.calc.cacheHyphendWords.clear();
  x.calc.cacheNonHyphendWords.clear();
  x.calc.cacheHyphenateSyllables.clear();
  x.calc.cacheNonHyphenateSyllables.clear();
}

List<Map<dynamic, dynamic>> xCaches(hyphenatorx.Hyphenator x) => [
  x.calc.cacheHyphendWords,
  x.calc.cacheNonHyphendWords,
  x.calc.cacheHyphenateSyllables,
  x.calc.cacheNonHyphenateSyllables,
];

String content(String text) =>
    text.replaceAll(RegExp(r'[\s\-\u00ad\u2010]'), '');

/// Checks the actual laid-out paragraph, not merely dictionary output. This
/// proves content and visible geometry, not pixel-perfect glyph/raster parity.
String checkRendered(
  WidgetTester tester,
  double width, {
  bool checkGlyphs = false,
}) {
  expect(tester.takeException(), isNull);
  expect(find.byType(ErrorWidget), findsNothing);
  final paragraphs = tester.allRenderObjects
      .whereType<RenderParagraph>()
      .toSet()
      .toList();
  expect(paragraphs, hasLength(1));
  final paragraph = paragraphs.single;
  final text = paragraph is RenderHyphenParagraph
      ? paragraph.renderedText
      : paragraph.text.toPlainText();
  expect(content(text), content(kSampleParagraph));
  expect(paragraph.attached, isTrue);
  expect(paragraph.constraints.maxWidth, width);
  expect(paragraph.textDirection, TextDirection.ltr);
  expect(paragraph.textScaler.scale(16), 16);
  expect(paragraph.maxLines, isNull);
  expect(paragraph.size.width, closeTo(width, 0.001));
  expect(paragraph.size.height, greaterThan(0));
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.text.style?.fontSize, kStyle.fontSize);
  expect(paragraph.text.style?.height, kStyle.height);
  expect(paragraph.text.style?.color, Colors.black);
  final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(2000));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(boxes, isNotEmpty);
  for (final box in boxes) {
    expect(box.left, greaterThanOrEqualTo(-0.01));
    // Selection boxes include trailing whitespace beyond the column edge.
    // Check viewport visibility, not a false glyph-overflow proxy.
    expect(rect.left + box.right, lessThanOrEqualTo(800));
    expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.01));
  }
  expect(boxes.any((b) => b.right > b.left && b.bottom > b.top), isTrue);
  if (checkGlyphs) {
    for (var i = 0; i < text.length; i++) {
      if (RegExp(r'[\s\u00ad]').hasMatch(text[i])) continue;
      final glyphBoxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      expect(glyphBoxes, isNotEmpty, reason: 'Missing glyph at $i in $text');
      for (final box in glyphBoxes) {
        expect(
          box.right,
          lessThanOrEqualTo(width + 0.01),
          reason: 'Clipped glyph at $i in $text',
        );
        expect(box.left, greaterThanOrEqualTo(-0.01));
      }
    }
  }
  return text;
}

void main() {
  final report = ComparisonReport(
    'Flutter widgets (debug test binding, not FPS)',
  );
  final rendered = <String, String>{};
  late Hyphenator ours;
  late Hyphenator uncachedLayout;
  late hyphenatorx.Hyphenator x;
  late impure.Hyphenator imp;
  late String soft;
  var completedScenarios = 0;

  setUpAll(() {
    ours = Hyphenator(
      TexHyphenationPatterns.parse(
        controlledPatternSource(),
        leftMin: 3,
        // ignore: avoid_redundant_argument_values
        rightMin: 3,
      ),
      leftMin: 3,
      rightMin: 3,
    );
    uncachedLayout = Hyphenator(
      ours.patterns,
      leftMin: 3,
      rightMin: 3,
      maxParagraphCacheSize: 0,
    );
    x = buildHyphenatorx(controlledHyphenatorxSource());
    imp = impure.Hyphenator(
      resource: ImpureFileLoader(controlledPatternSource()),
      // ignore: avoid_redundant_argument_values
      minLetterCount: 3,
    );
    final hunspell = hyphen_pkg.Hyphen.fromDictionaryBytes(
      controlledHunspellBytes(),
    );
    soft = kSampleParagraph
        .split(' ')
        .map(
          (word) => hunspell.hyphenate(word, lhmin: 3, rhmin: 3).join('\u00AD'),
        )
        .join(' ');
  });

  Map<String, Widget Function()> builders({
    bool cold = false,
    bool noLayoutCache = false,
  }) => {
    // Deliberately non-const: every candidate gets a fresh widget instance.
    'Text (no hyphens)': () => Text(kSampleParagraph, style: kStyle),
    'flutter_hyphenation': () => HyphenText(
      kSampleParagraph,
      style: kStyle,
      hyphenator: noLayoutCache ? uncachedLayout : ours,
    ),
    'auto_hyphenating_text': () => AutoHyphenatingText(
      kSampleParagraph,
      style: kStyle,
      customHyphenator: imp,
      hyphenationCharacter: '-',
      scaler: TextScaler.noScaling,
    ),
    'hyphenatorx (wrap adapter)': () => HyphenatorxText(kSampleParagraph, x),
    if (!cold)
      'hyphen (precomputed SHY adapter)': () => Text(soft, style: kStyle),
  };

  void reset() {
    ours.clearCache();
    uncachedLayout.clearCache();
    resetX(x);
    // hyphenator_impure has no result memoisation, only compiled patterns
    // and dictionary exceptions. Those are retained for all candidates.
    expect(ours.cacheCounts, (0, 0, 0));
    expect(uncachedLayout.cacheCounts, (0, 0, 0));
    for (final cache in xCaches(x)) {
      expect(cache, isEmpty);
    }
  }

  Future<void> setupView(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets(
    'adapters render complete visible content and cache reset works',
    (tester) async {
      await setupView(tester);
      // Seed every x cache, including caches not necessarily used by wrap.
      for (final cache in xCaches(x)) {
        expect(cache, isEmpty);
      }
      x.hyphenateWord('internationalization');
      x.hyphenateWord('zzzzzzzz');
      x.syllablesWord('internationalization');
      x.syllablesWord('zzzzzzzz');
      for (final cache in xCaches(x)) {
        expect(cache, isNotEmpty);
      }
      reset();
      for (final entry in builders().entries) {
        final first = entry.value();
        expect(identical(first, entry.value()), isFalse);
        for (final width in [240.0, 299.5, kWidth]) {
          pumpSync(
            tester,
            host(KeyedSubtree(key: UniqueKey(), child: entry.value()), width),
          );
          rendered['${entry.key}@$width'] = checkRendered(
            tester,
            width,
            checkGlyphs: true,
          );
        }
      }
      // Functional preflight for the uncached-layout scenario, without timing.
      for (var i = 0; i < 2; i++) {
        pumpSync(
          tester,
          host(
            KeyedSubtree(
              key: UniqueKey(),
              child: builders(noLayoutCache: true)['flutter_hyphenation']!(),
            ),
            kWidth,
          ),
        );
        rendered['flutter_hyphenation uncached layout@$kWidth'] = checkRendered(
          tester,
          kWidth,
          checkGlyphs: true,
        );
      }
      expect(uncachedLayout.cacheCounts.$1, greaterThan(0));
      uncachedLayout.cacheBreak('probe', 'must not be retained');
      expect(uncachedLayout.cachedBreak('probe'), isNull);
      expect(uncachedLayout.cacheCounts.$2, 0);
      expect(uncachedLayout.cacheCounts.$3, 0);
      expect(ours.cacheCounts.$1, greaterThan(0));
      expect(ours.cacheCounts.$3, greaterThan(0));
      expect(xCaches(x).any((cache) => cache.isNotEmpty), isTrue);
      reset();
    },
  );

  for (final scenario in [
    'warm same width',
    'warm remount',
    'warm cycling 120 widths',
    'cold result caches remount',
    'uncached layout, warm words',
  ]) {
    testWidgets(scenario, (tester) async {
      await setupView(tester);
      final cold = scenario.startsWith('cold');
      final noLayoutCache = scenario == 'uncached layout, warm words';
      final remount = cold || noLayoutCache || scenario == 'warm remount';
      final cycling = scenario == 'warm cycling 120 widths';
      final entries = builders(
        cold: cold,
        noLayoutCache: noLayoutCache,
      ).entries.toList();
      final samples = {for (final entry in entries) entry.key: <double>[]};
      // Equal wall-clock JIT warmup BEFORE any timed sample. A fixed count
      // alone gives cheap Text only milliseconds while slow adapters get
      // seconds, leaving the fastest candidates' first trials uncompiled.
      for (final entry in entries) {
        reset();
        final warmup = Stopwatch()..start();
        var iteration = 0;
        do {
          if (cold) reset();
          pumpSync(
            tester,
            host(
              KeyedSubtree(
                key: remount ? UniqueKey() : const ValueKey('retained'),
                child: entry.value(),
              ),
              cycling ? cyclingWidth(iteration) : kWidth,
            ),
          );
          iteration++;
          expect(tester.takeException(), isNull);
        } while (warmup.elapsed < const Duration(seconds: 2));
        warmup.stop();
        checkRendered(tester, cycling ? cyclingWidth(iteration - 1) : kWidth);
      }
      // Rotate order across trials to reduce fixed-order JIT/thermal bias.
      for (var trial = 0; trial < 10; trial++) {
        for (var offset = 0; offset < entries.length; offset++) {
          final entry = entries[(trial + offset) % entries.length];
          reset();
          var iteration = 0;
          Widget frame() => host(
            KeyedSubtree(
              key: remount ? UniqueKey() : const ValueKey('retained'),
              child: entry.value(),
            ),
            cycling ? cyclingWidth(iteration++) : kWidth,
          );
          // Every candidate starts each trial with the full working set
          // exercised twice. Capacities/eviction remain package-specific.
          for (var i = 0; i < 2 * widthCount; i++) {
            if (cold) reset();
            pumpSync(tester, frame());
            expect(tester.takeException(), isNull);
          }
          checkRendered(
            tester,
            cycling ? cyclingWidth(widthCount - 1) : kWidth,
          );
          if (noLayoutCache && entry.key == 'flutter_hyphenation') {
            expect(uncachedLayout.cacheCounts.$1, greaterThan(0));
            expect(uncachedLayout.cacheCounts.$2, 0);
            expect(uncachedLayout.cacheCounts.$3, 0);
            uncachedLayout.cacheBreak('probe', 'must not be retained');
            expect(uncachedLayout.cachedBreak('probe'), isNull);
          }
          // Fixed equal workload. Reset and correctness checks are outside
          // timing, but their allocations can still influence later GC.
          var elapsedNs = 0.0;
          final watch = Stopwatch();
          for (var i = 0; i < widthCount; i++) {
            if (cold) reset();
            watch
              ..reset()
              ..start();
            pumpSync(tester, frame());
            watch.stop();
            elapsedNs += watch.elapsedTicks * 1e9 / watch.frequency;
            expect(tester.takeException(), isNull);
          }
          checkRendered(
            tester,
            cycling ? cyclingWidth(widthCount - 1) : kWidth,
          );
          samples[entry.key]!.add(elapsedNs / widthCount);
        }
      }
      final results = {
        for (final entry in entries)
          entry.key: Measurement(entry.key, samples[entry.key]!, widthCount),
      };
      report.add(
        ComparisonRow(
          name: scenario,
          units: 'test pumps',
          unitCount: 1,
          results: results,
          note:
              '${cold ? "All result caches reset outside timing before each remount; compiled dictionaries retained. Impure has no result cache. Precomputed SHY excluded from cold." : "All adapters pre-exercised for 240 pumps before each trial; shared caches retained. Fresh non-const widget instances for all."} '
              '${cycling ? "Widths cycle through 120 values, NOT unseen widths or guaranteed cache misses. Capacity/eviction differs." : "Width 320."} '
              '${noLayoutCache ? "Ours paragraph/marked/break caches disabled via maxParagraphCacheSize:0, word cache warm. Every candidate remounted; x word/syllable caches warm, impure has no result memoisation. This tests uncached layout without dictionary/word cold cost." : ""} '
              'Debug JIT test-binding CPU work, no raster/device FPS claim. '
              'Text has no hyphenation; wrap adapter excludes async asset lifecycle; '
              'SHY precomputation excluded and glyph behavior is platform-dependent. '
              'Controlled common pattern tokens, exceptions omitted, 3/3 minima. '
              'Algorithms can still produce different line breaks. '
              'Each candidate gets 2 seconds wall-clock JIT warmup per scenario '
              'before any timed sample, then 240 pumps before each trial. '
              'Candidate order rotates across 10 trials of 120 operations. '
              'Checks/resets excluded from timing but can affect GC.',
        ),
      );
      completedScenarios++;
    }, timeout: const Timeout(Duration(minutes: 20)));
  }

  tearDownAll(() {
    if (completedScenarios != 5) return; // Never publish partial suite results.
    // ignore: avoid_print
    print(report.render());
    final target = File(resultPath('flutter.json'));
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        ...report.toJson(),
        'rendered_paragraphs': rendered,
        'validation':
            'Every pump checked for Flutter exceptions outside timing. '
            'After warmup and each sample: no ErrorWidget, complete normalized rendered text, visible '
            'paragraph geometry and selection boxes, matching width/style. '
            'Separate adapter test checks each non-whitespace/non-SHY glyph box '
            'fits the column at three widths. Test font, not a pixel golden or '
            'hyphenation-quality equivalence test.',
      }),
    );
  });
}
