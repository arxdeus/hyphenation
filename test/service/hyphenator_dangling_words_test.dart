// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

import 'package:flutter_test/flutter_test.dart';

import '../support/test_dictionaries.dart';

void main() {
  group('danglingWords', () {
    test('is null when no list is given', () {
      expect(loadTestHyphenator().danglingWords, isNull);
    });

    test('is null when the list is empty', () {
      expect(
        loadTestHyphenator(
          // Passing the default explicitly is the point of the test.
          // ignore: avoid_redundant_argument_values
          danglingWords: const <String>[],
        ).danglingWords,
        isNull,
      );
    });

    test('is compiled when a list is given', () {
      final hyphenator = loadTestHyphenator(
        danglingWords: const <String>['the', 'of'],
      );
      expect(hyphenator.danglingWords, isNotNull);
      expect(hyphenator.danglingWords!.contains('the'), isTrue);
    });

    group('hasBreakOpportunity', () {
      test('is false for unhyphenable text with no list', () {
        // None of these words is in the test dictionary.
        expect(
          loadTestHyphenator().hasBreakOpportunity('in the woods'),
          isFalse,
        );
      });

      test('is true when the text holds a dangling word', () {
        // This is what stops RenderHyphenParagraph from handing the text
        // straight to the engine and ignoring the word list.
        expect(
          loadTestHyphenator(
            danglingWords: const <String>['the'],
          ).hasBreakOpportunity('in the woods'),
          isTrue,
        );
      });

      test('is false when the dangling word is the last token', () {
        // Nothing follows it, so it would not be glued to anything and the
        // breaker has no work to do.
        expect(
          loadTestHyphenator(
            danglingWords: const <String>['the'],
          ).hasBreakOpportunity('woods the'),
          isFalse,
        );
      });

      test('stays true when the dictionary can break a word anyway', () {
        expect(
          loadTestHyphenator(
            danglingWords: const <String>['the'],
          ).hasBreakOpportunity('hyphenation'),
          isTrue,
        );
      });
    });
  });
}
