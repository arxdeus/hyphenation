import 'package:flutter_hyphen/flutter_hyphen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_dictionaries.dart';

/// A measure function where every character is exactly 10 wide, so the
/// expected line breaks can be reasoned about by counting characters.
double measureByCharacter(String text) => text.length * 10.0;

void main() {
  group('HyphenLineBreaker dangling words', () {
    /// A dictionary that also refuses to leave 'the' at the end of a line.
    HyphenLineBreaker breakerWith(Iterable<String> words) => HyphenLineBreaker(
      measure: measureByCharacter,
      hyphenator: loadTestHyphenator(danglingWords: words),
    );

    test('carries a dangling word down to the next line', () {
      // Without the list, 'in the' (6 characters, 60 wide) is the longest
      // prefix that fits and 'the' is left hanging.
      expect(
        breakerWith(const <String>[]).breakText('in the woods', 60),
        <String>['in the', 'woods'],
      );
      // With it, the break after 'the' is never offered, so the line stops
      // at 'in' and 'the' travels with 'woods'.
      expect(
        breakerWith(const <String>['the']).breakText('in the woods', 60),
        <String>['in', 'the woods'],
      );
    });

    test('the text is never rewritten', () {
      // Nothing is inserted: no no-break space, no change to the characters.
      final lines = breakerWith(
        const <String>['the'],
      ).breakText('in the woods', 60);
      expect(lines.join(' '), 'in the woods');
      expect(lines.any((String line) => line.contains('\u00A0')), isFalse);
    });

    test('a dangling word at the end of a line is kept', () {
      // Nothing follows it, so there is nothing to carry it down to. Dropping
      // its break opportunity here would drop the word itself.
      expect(
        breakerWith(const <String>['the']).breakText('woods the', 60),
        <String>['woods', 'the'],
      );
      expect(
        breakerWith(const <String>['the']).breakText('the', 60),
        <String>['the'],
      );
    });

    test('a glued pair too wide for the column overflows, losing nothing', () {
      // 'the bb' is 60 wide in a 20 wide column. Layout must still make
      // progress and must not swallow the text, exactly as an unbreakable
      // long word does.
      final lines = breakerWith(
        const <String>['the'],
      ).breakText('aa the bb', 20);
      expect(lines.join(' '), 'aa the bb');
      expect(lines, <String>['aa', 'the bb']);
    });

    test('the word after a dangling one can still be hyphenated', () {
      // The pair is glued, but 'hyphenation' keeps its own break points, so
      // the line can still end mid-word. This is what a no-break space would
      // do too.
      expect(
        breakerWith(const <String>['the']).breakText('the hyphenation', 100),
        <String>['the hy-', 'phenation'],
      );
    });

    test('consecutive dangling words are glued as one run', () {
      expect(
        breakerWith(const <String>['in', 'the']).breakText('in the woods', 60),
        <String>['in the woods'],
      );
    });

    test('minIntrinsicWidth treats a glued pair as unbreakable', () {
      // Intrinsics share the candidate list, so the pair is one chunk: nine
      // characters at 10 each rather than the five of 'woods' alone.
      expect(
        breakerWith(const <String>[]).minIntrinsicWidth('the woods'),
        50,
      );
      expect(
        breakerWith(const <String>['the']).minIntrinsicWidth('the woods'),
        90,
      );
    });

    test('an empty list changes nothing', () {
      final plain = breakerWith(const <String>[]);
      final empty = breakerWith(const <String>['']);
      expect(
        empty.breakText('in the woods', 60),
        plain.breakText('in the woods', 60),
      );
    });
  });
}
