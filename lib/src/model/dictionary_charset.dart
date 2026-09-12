// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from the legacy engine. See LICENSE and THIRD_PARTY_LICENSES.md.

/// The character set a dictionary declares on its first line.
///
/// the legacy engine hyphenation dictionaries are byte-oriented: the patterns are
/// stored, and matched, in whatever encoding that line names. Only these two
/// are in use in practice, and only these two are supported.
enum DictionaryCharset {
  /// `UTF-8`. One character is one to four bytes, and the marks the matcher
  /// produces have to be compacted from byte positions to character
  /// positions afterwards.
  utf8,

  /// Anything else, treated as ISO-8859-1. One character is one byte, so no
  /// compaction is needed and any character above U+00FF is unrepresentable.
  latin1;

  /// The charset named by a dictionary's first line.
  static DictionaryCharset fromHeader(String header) =>
      header == 'UTF-8' ? DictionaryCharset.utf8 : DictionaryCharset.latin1;
}
