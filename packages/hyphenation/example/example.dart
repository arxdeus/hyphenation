// A runnable tour of `package:hyphenation`.
//
// Run it with `dart run example/example.dart` from the package root.
// A real program would load a `hyph-*.tex` file from CTAN; a handful of
// patterns are inlined here so the example needs no download.

import 'package:hyphenation/hyphenation.dart';

/// Standard TeX pattern syntax: an odd digit marks a hyphenation point after
/// the character before it.
const String kPatterns = r'''
\patterns{
hy3phen
hyphen5ation
an3ti
dis3es
es3tab
tab3lish
lish3ment
ment3ar
ar3ian
ian3ism
}
''';

void main() {
  final hyphenator = Hyphenator.fromSource(kPatterns);

  print(hyphenator.split('hyphenation')); // [hy, phen, ation]
  print(hyphenator.breakOffsets('hyphenation')); // [2, 6]

  // Soft hyphens are invisible, so print the escapes rather than the string.
  final marked = hyphenator.hyphenate('hyphenation');
  print(marked.replaceAll('\u00AD', r'\u00AD')); // hy\u00ADphen\u00ADation

  // Breaking lines needs a way to measure text, which is the one thing the
  // package cannot supply itself. A monospace-ish guess stands in for a real
  // text engine here.
  final breaker = HyphenLineBreaker(
    measure: (String s) => s.length * 7.0,
    hyphenator: hyphenator,
  );
  for (final line in breaker.breakText(
    'antidisestablishmentarianism is a long word',
    140,
  )) {
    print(line);
  }
}
