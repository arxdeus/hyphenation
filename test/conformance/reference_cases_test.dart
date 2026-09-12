// Does this engine still agree with the implementation it descends from?
//
// `recorded_cases.json` holds 2688 answers taken from the reference C
// library: for each word, the priority it gave every character and the parts
// it split the word into. Nothing here is an expectation someone wrote down
// — it is all measurement, which is what makes it the thing to run first
// after touching anything in `lib/src/hyphenation/`.
//
// The dictionaries under `dictionaries/` are not language dictionaries. Each
// one isolates a single hazard of the format: a file with nothing in it, one
// with only a charset line, declared minimum distances, malformed pattern
// lines, two compound levels, a suppression list, and the pair of lines that
// sit either side of the length the format can read.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_hyphen/src/model/hyphenation_dictionary.dart';
import 'package:flutter_test/flutter_test.dart';

const String _recordedCases = 'test/fixture/recorded_cases.json';
const String _dictionaries = 'test/fixture/dictionary';

/// Exactly what the recording holds. Asserted rather than bounded: a
/// truncated file has to fail loudly instead of quietly covering less.
const int _expectedCaseCount = 2688;

/// Eight dictionaries, six sets of minimum distances each.
const int _expectedGroupCount = 48;

void main() {
  final recorded = jsonDecode(
    File(_recordedCases).readAsStringSync(),
  ) as Map<String, Object?>;
  final names = (recorded['dictionaries']! as List).cast<String>();
  final cases = (recorded['cases']! as List).cast<Map<String, Object?>>();

  test('the recording is whole', () {
    expect(cases.length, _expectedCaseCount);
    expect(recorded['recordedFrom'], isNotEmpty);
  });

  test('every dictionary it names is on disk, and no others', () {
    final onDisk =
        Directory(_dictionaries)
            .listSync()
            .whereType<File>()
            .map((File file) => file.uri.pathSegments.last)
            .where((String name) => name.endsWith('.dic'))
            .map((String name) => name.substring(0, name.length - 4))
            .toList()
          ..sort();
    expect(onDisk, names);
  });

  final dictionaries = <String, HyphenationDictionary>{
    for (final name in names)
      name: HyphenationDictionary.parse(
        File('$_dictionaries/$name.dic').readAsBytesSync(),
      ),
  };

  // Grouped so a failure points at one dictionary and one set of minimums,
  // but asserted one case at a time so the message names the word.
  final groups = <String, List<Map<String, Object?>>>{};
  for (final recording in cases) {
    groups
        .putIfAbsent(
          '${recording['dictionary']}/${recording['limits']}',
          () => <Map<String, Object?>>[],
        )
        .add(recording);
  }

  test('every dictionary and every set of minimums is represented', () {
    expect(groups.length, _expectedGroupCount);
  });

  groups.forEach((String group, List<Map<String, Object?>> recordings) {
    test('$group (${recordings.length} words)', () {
      for (final recording in recordings) {
        final dictionary = dictionaries[recording['dictionary']]!;
        final word = recording['word']! as String;
        final limits = recording['limits']! as String;
        final reason = '$group word=${jsonEncode(word)}';

        if (recording.containsKey('throws')) {
          // Text that cannot be written one byte per character, against a
          // dictionary that only speaks that. Nothing else is recorded for
          // these, because nothing else happened.
          expect(
            () => _split(dictionary, word, limits),
            throwsArgumentError,
            reason: reason,
          );
          continue;
        }

        expect(
          _split(dictionary, word, limits),
          recording['parts']! as List<Object?>,
          reason: reason,
        );
        expect(
          _priorities(dictionary, word, limits),
          recording['priorities']! as List<Object?>,
          reason: reason,
        );
      }
    });
  });
}

/// One word replayed for its parts. [limits] is either `declared` — the
/// dictionary's own minimum distances — or
/// `raised(left,right,compoundLeft,compoundRight)`.
List<String> _split(
  HyphenationDictionary dictionary,
  String word,
  String limits,
) {
  if (limits == 'declared') {
    return dictionary.split(word);
  }
  final raised = _raised(limits);
  return dictionary.split(
    word,
    leftMin: raised[0],
    rightMin: raised[1],
    compoundLeftMin: raised[2],
    compoundRightMin: raised[3],
  );
}

/// The same word replayed for the priorities themselves — the whole buffer
/// the matcher wrote, not only the part of it that is still meaningful once
/// a multi-byte word has been squeezed down to characters.
List<int> _priorities(
  HyphenationDictionary dictionary,
  String word,
  String limits,
) {
  if (limits == 'declared') {
    dictionary.markWord(word);
  } else {
    final raised = _raised(limits);
    dictionary.markWord(
      word,
      leftMin: raised[0],
      rightMin: raised[1],
      compoundLeftMin: raised[2],
      compoundRightMin: raised[3],
    );
  }
  return dictionary.marks.sublist(0, dictionary.markedByteLength);
}

/// Reads only what is inside the parentheses. Sweeping the whole label for
/// numbers also catches any digit in the word `raised`, which would shift
/// every value one place along.
List<int> _raised(String limits) {
  final inner = limits.substring(
    limits.indexOf('(') + 1,
    limits.indexOf(')'),
  );
  return inner.split(',').map(int.parse).toList();
}
