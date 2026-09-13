# Comparison fixtures and input policy

## Controlled comparison

The algorithm comparison uses the pattern tokens extracted from `hyph-en-us.tex`,
as bundled by `hyphenator_impure` 0.1.4. The same source rules are converted to TeX,
`hyphenatorx` JSON records, and a UTF-8 Hunspell dictionary with the required
substring-weight preprocessing by
`benchmark/support/corpora.dart`. Preprocessing expands Hunspell records so their implied rules are not lost;
raw TeX tokens alone are not a semantically equivalent Hunspell dictionary.
All controlled variants use explicit 3/3 edge
minimums and exclude exceptions consistently. Conversion and disk I/O occur
outside the parse/compile timing. Construction from the prepared format is timed.

This is a controlled pattern-only English workload, **not** a comparison of the
packages' bundled defaults or a claim of identical output. Output agreement is
reported separately without treating any package as a correctness oracle.

The old report's equality claim was incorrect: the repository example's
`ushyph1.tex` contains 4,447 unique patterns, while this fixture contains 4,938.
The old `language_en_us.json` encodes the larger set, not the example's smaller set.

| File | Provenance | Role |
| --- | --- | --- |
| `hyph-en-us.tex` | `hyphenator_impure` 0.1.4, originally [hyph-utf8](https://ctan.org/pkg/hyph-utf8) | Source for controlled pattern conversion |
| `language_en_us.json` | `hyphenatorx` 1.5.11 | Historical bundled-default fixture, not the controlled source |
| `hyph_en_US.dic` | [LibreOffice dictionaries](https://github.com/LibreOffice/dictionaries/tree/master/en) | Historical bundled-default fixture, not the controlled source |

The TeX file retains its copyright and distribution notice. Its notice permits
copying and distribution, with or without modification, provided the notices are
preserved. No blanket MIT license is claimed for these dictionary data. Refer to
upstream notices for reuse of the historical fixtures.

## Corpus

The 32-word and ten-long-word lists and sample paragraph are fixed in source.
They are technical English samples, not statistically representative prose.
The larger unique-word workload is generated deterministically from the fixed
list and alphabetic suffixes. It is **synthetic**, not a system dictionary, and
repeated warm passes are not a streaming/eviction benchmark. There is no silent
fallback to repeated words if a host dictionary is missing.

`results/environment.json` records SHA-256 hashes of fixtures, source files and
the dependency lockfile for each complete run.
