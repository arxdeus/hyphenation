# Changelog

## 1.0.0

Initial release.

- `Hyphenator`, splitting words with a compiled TeX pattern set, with an LRU
  cache over the words it has already seen.
- `Hyphenator.fromSource` and `TexHyphenationPatterns`, compiling pattern file
  text into a trie held in flat typed arrays and shareable between hyphenators.
- `HyphenLineBreaker`, greedy width-aware line breaking driven by a caller
  supplied measurement function.
- `DanglingWords`, an allocation-free probe table of words to keep with the
  word that follows them.
- `minifyTexPatterns`, stripping a pattern file down to its `\patterns` and
  `\hyphenation` groups.
