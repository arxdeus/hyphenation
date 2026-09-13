/// A realistic English list for the tests that need one.
///
/// The package ships no default list, so the suite carries its own rather
/// than asserting against something a user is expected to supply.
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
