/// English words that should not be left dangling at the end of a line.
///
/// Pass this to [Hyphenator.new] or [HyphenationRegistry.registerAsset]:
///
/// ```dart
/// await HyphenationRegistry.instance.registerAsset(
///   const Locale('en', 'US'),
///   'assets/dictionary/hyph_en_US.dic',
///   danglingWords: kEnglishDanglingWords,
/// );
/// ```
///
/// A hyphenation dictionary cannot express this rule: `hyph_*.dic` patterns
/// only describe break points *inside* a word and never see the spaces between
/// words. "No hanging prepositions or conjunctions" is therefore a property of
/// the word list, not of the dictionary.
///
/// The list is an ordinary [Set], so it can be extended:
/// `{...kEnglishDanglingWords, 'per'}`.
const Set<String> kEnglishDanglingWords = <String>{
  // Articles and prepositions
  'a', 'an', 'the', 'at', 'by', 'for', 'from', 'in', 'into', 'of', 'off',
  'on', 'onto', 'out', 'over', 'to', 'up', 'via', 'with', 'within',
  'without', 'about', 'above', 'across', 'after', 'against', 'along',
  'among', 'around', 'before', 'behind', 'below', 'beneath', 'beside',
  'between', 'beyond', 'during', 'inside', 'near', 'outside', 'past',
  'since', 'through', 'toward', 'towards', 'under', 'until', 'upon',
  // Conjunctions and particles
  'and', 'or', 'nor', 'but', 'so', 'yet', 'as', 'if', 'than', 'that',
  'though', 'unless', 'when', 'where', 'while', 'not', 'no',
};
