import 'dart:io';

/// Locates a repository asset from whatever directory a benchmark was started
/// in. The CLI runs from the package root, a compiled AOT binary need not.
String assetPath(String relative) {
  var directory = Directory.current.absolute;
  while (true) {
    final candidate = File('${directory.path}/$relative');
    if (candidate.existsSync()) {
      return candidate.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('could not find $relative above ${Directory.current}');
    }
    directory = parent;
  }
}

/// The bundled English pattern file, as text.
String englishPatternSource() =>
    File(assetPath('example/assets/patterns/ushyph1.tex')).readAsStringSync();

/// Words with the length profile of running prose.
const List<String> kProse = <String>[
  'Internationalization',
  'localization',
  'complementary',
  'disciplines',
  'determine',
  'whether',
  'application',
  'feels',
  'native',
  'people',
  'Typography',
  'impression',
  'justified',
  'columns',
  'unhyphenated',
  'whitespace',
  'paragraph',
  'unusually',
  'technical',
  'vocabulary',
  'container',
  'Dictionary',
  'hyphenation',
  'computed',
  'incrementally',
  'memoised',
  'implementation',
  'responsibilities',
  'considerations',
  'representations',
  'unquestionably',
  'straightforwardly',
];

/// Hyphenated and multi-part words, which drive the compound recursion.
const List<String> kCompounds = <String>[
  'dictionary-based',
  'straightforwardly-unquestionably',
  'well-known',
  'state-of-the-art',
  'mother-in-law',
];

/// Words that leave the single-byte fast path.
const List<String> kUnicode = <String>[
  'naïveté',
  'café',
  'überraschung',
  'программирование',
  '日本語',
  'a😀hyphenation',
  'ﬃnancial',
];

/// Words the rewrite dictionary has something to say about.
const List<String> kRewrites = <String>[
  'addze',
  'aaddze',
  'abaddze',
  'addze-addze',
  'äöaddze',
  'plain',
];

/// Prose long enough that line breaking dominates a layout measurement.
const String kSampleParagraph =
    'Programming with Flutter is an interesting and entertaining occupation. '
    'Internationalization of an application guarantees the immediate '
    'availability of its content. The direct interaction of a user with the '
    'interface demands extraordinary attention to typography and to '
    'hyphenation. The improvement of computational systems continues '
    'uninterrupted, and performance remains the determining factor.';
