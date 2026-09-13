import 'package:flutter/material.dart';
import 'package:flutter_hyphenate/flutter_hyphenate.dart';

/// Shows how individual words are split by the dictionary.
class WordList extends StatelessWidget {
  const WordList({super.key});

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
