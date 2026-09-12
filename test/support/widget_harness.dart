import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The text the paragraph actually paints, including inserted hyphens and
/// line breaks.
/// Counts fresh breaks; the shared cache is disabled so every miss on the
/// render object's own cache shows up.
class CountingHyphenator extends Hyphenator {
  CountingHyphenator(super.dictionary) : super(maxCacheSize: 0);

  int breaks = 0;

  @override
  void cacheBreak(Object key, String value, {int? sourceLength}) {
    breaks++;
    super.cacheBreak(key, value, sourceLength: sourceLength);
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
