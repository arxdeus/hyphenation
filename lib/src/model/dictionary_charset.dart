import 'dart:typed_data';

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

/// Encodes words into the byte form a dictionary's patterns are written in,
/// reusing one buffer across calls.
///
/// The buffer is the reason this is an object rather than a function: a word
/// is encoded for every distinct word of every paragraph, and
/// `utf8.encode`/`latin1.encode` allocate a fresh list each time. It also
/// counts characters while it goes, which the caller would otherwise have to
/// recover afterwards.
class WordEncoder {
  /// The encoded bytes. Only the first [byteLength] are this word's, and
  /// they are overwritten by the next [encode].
  Uint8List bytes = Uint8List(64);

  /// How many bytes the last [encode] produced.
  int byteLength = 0;

  /// How many characters — code points, not code units and not grapheme
  /// clusters — the last [encode] produced.
  int characterCount = 0;

  /// Encodes [text] in [charset].
  ///
  /// Throws [ArgumentError] when [text] cannot be represented in
  /// [DictionaryCharset.latin1], which is what `latin1.encode` does and what
  /// callers of this package already handle.
  void encode(String text, DictionaryCharset charset) {
    if (charset == DictionaryCharset.latin1) {
      _encodeLatin1(text);
    } else {
      _encodeUtf8(text);
    }
  }

  void _reserve(int size) {
    if (bytes.length >= size) {
      return;
    }
    bytes = Uint8List(size < 64 ? 64 : size * 2);
  }

  void _encodeLatin1(String text) {
    final length = text.length;
    _reserve(length);
    final out = bytes;
    for (var i = 0; i < length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit > 0xFF) {
        throw ArgumentError.value(
          text,
          'string',
          'Contains invalid characters.',
        );
      }
      out[i] = unit;
    }
    byteLength = length;
    characterCount = length;
  }

  void _encodeUtf8(String text) {
    final length = text.length;
    // Three bytes per code unit is the worst case. A surrogate pair is two
    // units and four bytes, so it cannot beat the bound either.
    _reserve(length * 3);
    final out = bytes;
    var written = 0;
    var characters = 0;
    for (var i = 0; i < length; i++) {
      final unit = text.codeUnitAt(i);
      characters++;
      if (unit < 0x80) {
        out[written++] = unit;
      } else if (unit < 0x800) {
        out[written++] = 0xC0 | (unit >> 6);
        out[written++] = 0x80 | (unit & 0x3F);
      } else if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < length) {
        final low = text.codeUnitAt(i + 1);
        if (low >= 0xDC00 && low <= 0xDFFF) {
          final rune = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
          out[written++] = 0xF0 | (rune >> 18);
          out[written++] = 0x80 | ((rune >> 12) & 0x3F);
          out[written++] = 0x80 | ((rune >> 6) & 0x3F);
          out[written++] = 0x80 | (rune & 0x3F);
          i++;
          continue;
        }
        written = _writeReplacement(out, written);
      } else if (unit >= 0xD800 && unit <= 0xDFFF) {
        written = _writeReplacement(out, written);
      } else {
        out[written++] = 0xE0 | (unit >> 12);
        out[written++] = 0x80 | ((unit >> 6) & 0x3F);
        out[written++] = 0x80 | (unit & 0x3F);
      }
    }
    byteLength = written;
    characterCount = characters;
  }

  /// U+FFFD, which is what Dart's own encoder substitutes for an unpaired
  /// surrogate. Matching it matters: a word carrying one must hyphenate the
  /// same way here as it did through `utf8.encode`.
  static int _writeReplacement(Uint8List out, int at) {
    out[at] = 0xEF;
    out[at + 1] = 0xBF;
    out[at + 2] = 0xBD;
    return at + 3;
  }
}

/// Thrown when a dictionary cannot be read.
class DictionaryFormatException implements Exception {
  DictionaryFormatException(this.message);

  final String message;

  @override
  String toString() => 'DictionaryFormatException: $message';
}
