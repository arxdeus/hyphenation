# Changelog

## Unreleased

- The LICENSE file is now the plain MIT text so pub.dev recognizes it; the
  pattern-file notices moved to `NOTICE.md`.
- The package ships `example/example.dart`.

- `Hyphenator.cacheSplitParts`, an opt-in bound-sharing cache of the parts
  `split` returns. Off by default: it retains each word's text a second time,
  cut up, in exchange for turning a repeated `split` into a map lookup.
- `split` allocates its result once at its final size, and marking a word no
  longer allocates a lower-cased copy of it to probe an empty exception map.
- Cached break offsets are retained in the narrowest integer width that holds
  them, rather than one tagged word each. They are still unmodifiable.

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
