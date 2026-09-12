import 'package:example/dangling_words.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

/// The Russian dictionary bundled with this example.
///
/// Generate your own with `substrings.pl` from the legacy engine, or grab a
/// pattern file from CTAN. See the package README.
const String kRussianDictionary = 'assets/dictionary/hyph_ru_RU.dic';

// The dangling-word list and the glue that applies it live in
// `lib/dangling_words.dart`, so `benchmark/dangling_words_benchmark.dart` can
// measure them without pulling in the app.

Future<void> main() async {
  // Marionette lets an agent drive this demo (tap, screenshot, hot reload)
  // over the VM service. It is debug-only and changes nothing about how the
  // widgets below behave.
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  // Registering here makes every HyphenText in the app hyphenate without any
  // further plumbing.
  await HyphenationRegistry.instance.registerAsset(
    const Locale('ru', 'RU'),
    kRussianDictionary,
  );
  runApp(const HyphenDemoApp());
}

class HyphenDemoApp extends StatelessWidget {
  const HyphenDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_hyphen',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  static const String _sample =
      'Программирование на Flutter это интересное и увлекательное '
      'занятие. Конституция Российской Федерации гарантирует '
      'непосредственное действие прав и свобод человека.';

  double _width = 180;
  double _fontSize = 18;
  bool _justify = true;
  bool _noDangling = true;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(fontSize: _fontSize, height: 1.3);
    final align = _justify ? TextAlign.justify : TextAlign.start;
    final text = _noDangling ? preventDanglingWords(_sample) : _sample;

    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_hyphen'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _Controls(
            width: _width,
            fontSize: _fontSize,
            justify: _justify,
            onWidth: (double value) => setState(() => _width = value),
            onFontSize: (double value) => setState(() => _fontSize = value),
            onJustify: (bool value) => setState(() => _justify = value),
            noDangling: _noDangling,
            onNoDangling: (bool value) => setState(() => _noDangling = value),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Column(
                title: 'Text',
                subtitle: 'no hyphenation',
                width: _width,
                child: Text(text, style: textStyle, textAlign: align),
              ),
              const SizedBox(width: 16),
              _Column(
                title: 'HyphenText',
                subtitle: 'dictionary hyphenation',
                width: _width,
                child: HyphenText(text, style: textStyle, textAlign: align),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _RenderedLines(text: text, width: _width, style: textStyle),
          const SizedBox(height: 24),
          const _WordList(),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.width,
    required this.fontSize,
    required this.justify,
    required this.onWidth,
    required this.onFontSize,
    required this.onJustify,
    required this.noDangling,
    required this.onNoDangling,
  });

  final double width;
  final double fontSize;
  final bool justify;
  final ValueChanged<double> onWidth;
  final ValueChanged<double> onFontSize;
  final ValueChanged<bool> onJustify;
  final bool noDangling;
  final ValueChanged<bool> onNoDangling;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                const SizedBox(width: 80, child: Text('Width')),
                Expanded(
                  child: Slider(
                    value: width,
                    min: 80,
                    max: 400,
                    onChanged: onWidth,
                  ),
                ),
                Text(width.round().toString()),
              ],
            ),
            Row(
              children: <Widget>[
                const SizedBox(width: 80, child: Text('Font size')),
                Expanded(
                  child: Slider(
                    value: fontSize,
                    min: 10,
                    max: 40,
                    onChanged: onFontSize,
                  ),
                ),
                Text(fontSize.round().toString()),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Justify'),
              value: justify,
              onChanged: onJustify,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('No hanging prepositions'),
              subtitle: const Text('glue short words with U+00A0'),
              value: noDangling,
              onChanged: onNoDangling,
            ),
          ],
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.title,
    required this.subtitle,
    required this.width,
    required this.child,
  });

  final String title;
  final String subtitle;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: theme.textTheme.titleMedium),
        Text(subtitle, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Container(
          width: width,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        ),
      ],
    );
  }
}

/// Shows the lines a [HyphenText] actually paints for the sample text.
///
/// This makes the effect legible as text rather than pixels, which is handy
/// when driving the demo from a tool.
class _RenderedLines extends StatelessWidget {
  const _RenderedLines({
    required this.text,
    required this.width,
    required this.style,
  });

  final String text;
  final double width;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final hyphenator = HyphenationRegistry.instance.resolve(
      const Locale('ru', 'RU'),
    );
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

/// Shows how individual words are split by the dictionary.
class _WordList extends StatelessWidget {
  const _WordList();

  static const List<String> _words = <String>[
    'программирование',
    'Конституция',
    'непосредственное',
    'увлекательное',
    'Федерации',
  ];

  @override
  Widget build(BuildContext context) {
    final hyphenator = HyphenationRegistry.instance.resolve(
      const Locale('ru', 'RU'),
    );
    if (hyphenator == null) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Dictionary break points',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final String word in _words)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('$word  →  ${hyphenator.split(word).join('-')}'),
              ),
          ],
        ),
      ),
    );
  }
}
