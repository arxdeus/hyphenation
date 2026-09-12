// The TeX pattern reader, one hazard of the format at a time.
import 'package:flutter_hyphen/src/tex/tex_pattern_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseTexPatterns', () {
    test('reads the patterns of a group', () {
      final source = parseTexPatterns(r'\patterns{ .ach4 .ad4der hy3ph }');
      expect(source.patterns, <String>['.ach4', '.ad4der', 'hy3ph']);
    });

    test('skips the comment header a real file opens with', () {
      final source = parseTexPatterns('''
% title: Hyphenation patterns
% copyright: someone
\\patterns{
a1b
}
''');
      expect(source.patterns, <String>['a1b']);
    });

    test('a comment inside a group ends the token, not the group', () {
      final source = parseTexPatterns('''
\\patterns{ % just type <return> if you are not using INITEX
a1b
c1d
}
''');
      expect(source.patterns, <String>['a1b', 'c1d']);
    });

    test('reads exceptions as offsets with the hyphens removed', () {
      final source = parseTexPatterns(r'\hyphenation{ as-so-ciate ta-ble }');
      expect(source.exceptions['associate'], <int>[2, 4]);
      expect(source.exceptions['table'], <int>[2]);
    });

    test('an exception with no hyphens forbids every break', () {
      final source = parseTexPatterns(r'\hyphenation{ present }');
      expect(source.exceptions['present'], isEmpty);
    });

    test('exceptions are keyed lower case', () {
      final source = parseTexPatterns(r'\hyphenation{ Ta-ble }');
      expect(source.exceptions.containsKey('table'), isTrue);
    });

    test('reads both groups from one file', () {
      final source = parseTexPatterns(r'''
\patterns{ a1b }
\hyphenation{ ta-ble }
''');
      expect(source.patterns, <String>['a1b']);
      expect(source.exceptions['table'], <int>[2]);
    });

    test('unrelated control sequences are stepped over', () {
      // `\message` opens a group of its own, and a naive reader that looked
      // for the next `{` would take its contents for patterns.
      final source = parseTexPatterns(r'''
\message{Loading patterns}
\patterns{ a1b }
\endinput
''');
      expect(source.patterns, <String>['a1b']);
    });

    test('a file with neither group yields nothing', () {
      final source = parseTexPatterns('% nothing here\n');
      expect(source.patterns, isEmpty);
      expect(source.exceptions, isEmpty);
    });
  });

  group('parsePattern', () {
    test('splits letters from the priorities between them', () {
      final parsed = parsePattern('hy3ph');
      expect(String.fromCharCodes(parsed.letters), 'hyph');
      expect(parsed.priorities, <int>[0, 0, 3, 0, 0]);
    });

    test('keeps the anchoring dot as a letter', () {
      final parsed = parsePattern('.ach4');
      expect(String.fromCharCodes(parsed.letters), '.ach');
      expect(parsed.priorities, <int>[0, 0, 0, 0, 4]);
    });

    test('a priority before the first letter is kept', () {
      final parsed = parsePattern('4ach');
      expect(parsed.priorities.first, 4);
    });

    test('there is one more priority than there are letters', () {
      final parsed = parsePattern('abc');
      expect(parsed.letters, hasLength(3));
      expect(parsed.priorities, hasLength(4));
    });
  });
}
