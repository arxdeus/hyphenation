import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

/// The English dictionary bundled with this example.
///
/// Generate your own with `substrings.pl` from the legacy engine, or grab a
/// pattern file from CTAN. See the package README.
const String kEnglishDictionary = 'assets/dictionary/hyph_en_US.dic';

/// The same dictionary without the dangling-word list, for the demo toggle.
///
/// It shares the parsed [Hyphen] engine with the registered one, so the
/// dictionary is only read and parsed once.
late final Hyphenator kPlainHyphenator;

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
  // `danglingWords` is the whole of the "no hanging prepositions" feature:
  // HyphenLineBreaker stops offering a break after any of these words, so it
  // is carried down to the next line with the word it belongs to. Nothing is
  // inserted into the text. Leave it out to turn the feature off.
  final hyphenator = await HyphenationRegistry.instance.registerAsset(
    const Locale('en', 'US'),
    kEnglishDictionary,
    danglingWords: kEnglishDanglingWords,
  );
  kPlainHyphenator = Hyphenator(hyphenator.dictionary);
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
      'Programming with Flutter is an interesting and entertaining '
      'occupation. Internationalization of an application requires '
      'extraordinary attention to typographical details.';

  double _width = 180;
  double _fontSize = 18;
  bool _justify = true;
  bool _noDangling = true;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(fontSize: _fontSize, height: 1.3);
    final align = _justify ? TextAlign.justify : TextAlign.start;
    // The text never changes: the toggle only swaps which hyphenator is used.
    const text = _sample;
    final hyphenator = _noDangling ? null : kPlainHyphenator;

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
                child: HyphenText(
                  text,
                  style: textStyle,
                  textAlign: align,
                  hyphenator: hyphenator,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _RenderedLines(
            text: text,
            width: _width,
            style: textStyle,
            hyphenator: hyphenator,
          ),
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
              subtitle: const Text('never break after a short word'),
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

/// Shows how individual words are split by the dictionary.
class _WordList extends StatelessWidget {
  const _WordList();

  static const List<String> _words = <String>[
    'programming',
    'Internationalization',
    'extraordinary',
    'entertaining',
    'typographical',
  ];

  @override
  Widget build(BuildContext context) {
    final hyphenator = HyphenationRegistry.instance.resolve(
      const Locale('en', 'US'),
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
