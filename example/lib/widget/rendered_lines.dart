import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';

/// Shows the lines a [HyphenText] actually paints for the sample text.
///
/// This makes the effect legible as text rather than pixels, which is handy
/// when driving the demo from a tool.
class RenderedLines extends StatelessWidget {
  const RenderedLines({
    required this.text,
    required this.width,
    required this.style,
    required this.hyphenator,
  });

  final String text;
  final double width;
  final TextStyle style;

  /// The hyphenator to break with, or `null` to use the registered one.
  final Hyphenator? hyphenator;

  @override
  Widget build(BuildContext context) {
    final hyphenator =
        this.hyphenator ??
        HyphenationRegistry.instance.resolve(const Locale('en', 'US'));
    if (hyphenator == null) {
      return const SizedBox.shrink();
    }
    final painter = TextPainter(textDirection: TextDirection.ltr);
    double measure(String value) {
      painter
        ..text = TextSpan(text: value, style: style)
        ..layout();
      return painter.width;
    }

    final lines = HyphenLineBreaker(
      measure: measure,
      hyphenator: hyphenator,
    ).breakText(text, width - 18);
    painter.dispose();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Painted lines (${lines.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final String line in lines)
              Text(line, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}
