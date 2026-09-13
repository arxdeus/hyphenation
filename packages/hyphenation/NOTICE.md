# Third-party notices
## Hyphenation patterns

The engine implements Liang's hyphenation algorithm, published in Franklin
Mark Liang's 1983 Stanford dissertation *Word Hy-phen-a-tion by Com-put-er*,
and reads the TeX pattern format. Both are public; no third-party source is
incorporated, and the MIT license above covers the whole package.

Pattern files are data, not code, and each carries its own license. None are
bundled with the package. The two copied verbatim into
`example/assets/patterns/` for the example app and the tests are:

- `ushyph1.tex` — Knuth's Plain TeX hyphenation tables. "Unlimited copying
  and redistribution of this file are permitted as long as this file is not
  modified." The copy here is unmodified.
- `ushyphmax.tex` — Copyright (C) 1990, 2004, 2005 Gerard D.C. Kuiken.
  "Copying and distribution of this file, with or without modification, are
  permitted in any medium without royalty provided the copyright notice and
  this notice are preserved." The copy here preserves it.

Patterns for other languages come from the hyph-utf8 collection on CTAN and
carry their own, per-language licenses. Check the one you ship.
