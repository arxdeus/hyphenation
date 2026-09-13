import 'dart:io';

import 'package:flutter_hyphenate/flutter_hyphenate.dart';

/// The English pattern file shipped with the example app, relative to the
/// repository root.
const String kEnglishPatternRelativePath =
    'example/assets/patterns/ushyph1.tex';

/// The English pattern file, found from whatever directory the test or
/// benchmark was started in: the package root, the workspace root, or the
/// directory a compiled binary happens to sit in.
String get kEnglishPatternPath {
  var directory = Directory.current.absolute;
  while (true) {
    final candidate = File('${directory.path}/$kEnglishPatternRelativePath');
    if (candidate.existsSync()) {
      return candidate.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'could not find $kEnglishPatternRelativePath above '
        '${Directory.current}',
      );
    }
    directory = parent;
  }
}

/// Loads the example English patterns from disk.
///
/// Widget tests cannot read real assets through `rootBundle`, so the text is
/// read from the repository instead.
Hyphenator loadEnglishHyphenator({
  int leftMin = 2,
  int rightMin = 2,
  int minWordLength = 5,
  Iterable<String> danglingWords = const <String>[],
}) => Hyphenator.fromSource(
  File(kEnglishPatternPath).readAsStringSync(),
  leftMin: leftMin,
  rightMin: rightMin,
  minWordLength: minWordLength,
  danglingWords: danglingWords,
);

/// A pattern set that breaks a handful of English words, built inline so the
/// tests do not depend on the example pattern file.
///
/// Standard TeX pattern syntax: odd digits mark a hyphenation point after
/// the preceding character.
///
/// The minimums are declared as 1/1 so that a test asking for `leftMin: 2`
/// gets exactly that. A pattern set states its own floor and the caller may
/// only raise it, so a fixture that declared English's 2/3 would silently
/// override every test that wanted something looser.
///
/// `na3tion` is deliberately absent. It would match inside `hyphenation`
/// ("hyphe|nation") and break it as `hy-phen-a-tion`, which is correct for
/// the pattern but not what the line-breaking tests are about: they use
/// `hyphenation` as a word with exactly two break points.
Hyphenator loadTestHyphenator({
  int minWordLength = 5,
  int leftMin = 2,
  int rightMin = 2,
  Iterable<String> danglingWords = const <String>[],
}) => Hyphenator(
  TexHyphenationPatterns.parse(
    r'''
\patterns{
hy3phen
hyphen5ation
in3ter
al3ways
won3der
der3ful
ex3tra
tra3or
or3di
di3nary
com3pu
pu3ter
}
''',
    leftMin: 1,
    rightMin: 1,
  ),
  minWordLength: minWordLength,
  leftMin: leftMin,
  rightMin: rightMin,
  danglingWords: danglingWords,
);
