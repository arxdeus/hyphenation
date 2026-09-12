import 'package:flutter/material.dart';
import 'package:flutter_hyphen/flutter_hyphen.dart';

import '../constant/demo_dictionary.dart';
import '../widget/demo_controls.dart';
import '../widget/demo_column.dart';
import '../widget/rendered_lines.dart';
import '../widget/word_list.dart';

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
          DemoControls(
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
              DemoColumn(
                title: 'Text',
                subtitle: 'no hyphenation',
                width: _width,
                child: Text(text, style: textStyle, textAlign: align),
              ),
              const SizedBox(width: 16),
              DemoColumn(
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
          RenderedLines(
            text: text,
            width: _width,
            style: textStyle,
            hyphenator: hyphenator,
          ),
          const SizedBox(height: 24),
          const WordList(),
        ],
      ),
    );
  }
}
