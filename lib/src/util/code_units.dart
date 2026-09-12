/// Character classification shared by the hyphenator, the line breaker and the
/// dangling-word matcher.
///
/// All three have to agree on what counts as a letter: if they did not, a word
/// the breaker treats as one token could be tokenised differently by the
/// matcher, and a word would be glued to the wrong neighbour. The predicates
/// live here rather than being duplicated per file.
///
/// This library is internal; nothing here is exported from
/// `package:flutter_hyphen/flutter_hyphen.dart`.
library;

/// Whether [unit] is a hyphen a line may be broken after.
bool isHardHyphen(int unit) =>
    unit == 0x2D || // hyphen-minus
    unit == 0x2010 || // hyphen
    unit == 0x2011; // non-breaking hyphen (kept, but still a break point)

/// Whether [unit] is part of a word, for hyphenation purposes.
///
/// Digits are deliberately excluded: a dictionary has nothing to say about
/// them. [isDanglingWordUnit] includes them, because a word list may.
bool isWordCharacter(int unit) {
  if (unit >= 0x41 && unit <= 0x5A) {
    return true;
  }
  if (unit >= 0x61 && unit <= 0x7A) {
    return true;
  }
  if (unit < 0x80) {
    return false;
  }
  // Everything outside ASCII that is not punctuation or whitespace is
  // treated as a letter. Dictionaries decide what is actually breakable.
  return !isNonWordHighCodeUnit(unit);
}

/// Whether [unit] may appear inside an entry of a dangling-word list.
///
/// The same as [isWordCharacter], plus digits and the hyphen, so entries like
/// `out-of` and tokens like `1` are recognised.
bool isDanglingWordUnit(int unit) {
  if (unit >= 0x30 && unit <= 0x39) {
    return true;
  }
  if (unit == 0x2D) {
    return true;
  }
  return isWordCharacter(unit);
}

/// Whether [unit] is a non-ASCII character that separates or decorates words
/// rather than forming one.
bool isNonWordHighCodeUnit(int unit) {
  switch (unit) {
    case 0x00A0: // no-break space
    case 0x00AB: // «
    case 0x00BB: // »
    case 0x2000:
    case 0x2001:
    case 0x2002:
    case 0x2003:
    case 0x2004:
    case 0x2005:
    case 0x2006:
    case 0x2007:
    case 0x2008:
    case 0x2009:
    case 0x200A:
    case 0x2012: // figure dash
    case 0x2013: // en dash
    case 0x2014: // em dash
    case 0x2018: // ‘
    case 0x201C: // “
    case 0x201D: // ”
    case 0x201E: // „
    case 0x2026: // …
    case 0x3000: // ideographic space
      return true;
    default:
      return false;
  }
}
