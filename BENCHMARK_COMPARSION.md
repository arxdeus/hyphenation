# Benchmark comparison

Measured 2026-09-13 · Apple M5 Pro · Dart 3.13.2 / Flutter 3.47.2.

**Median µs per workload, lower is faster.** ⚠ = CV > 5%. Selected pinned packages, not an exhaustive survey.

## Pure Dart (VM JIT)

| Package | Version | Public import compiles without Flutter |
| --- | --- | --- |
| hyphenation | 1.0.0 (local) | Yes |
| hyphenatorx | 1.5.11 | No: dart:ui |
| hyphenator_impure | 0.1.4 | No: dart:ui |
| auto_hyphenating_text | 0.3.2 | No: dart:ui |
| hyphen | 0.4.0 | No: dart:ui |
| flutter_hyphenation | 1.0.0 | No: dart:ui |

Only our engine was timed here. Import compilation does not test standalone dependency resolution or runtime behavior.

| Workload | hyphenation |
| --- | ---: |
| load en-US dictionary | 619.156 |
| split 32 prose words, warm | 1.631 |
| split 32 prose words, cold | 15.373 |
| split 2000 distinct words | 118.290 |
| hyphenate a paragraph, common adapter (396 chars) | 23.055 ⚠ |

## Engines (Flutter debug test runtime)

| Workload | hyphenation | hyphenation (cacheSplitParts) | hyphenatorx | hyphenator_impure | hyphen |
| --- | ---: | ---: | ---: | ---: | ---: |
| load en-US dictionary | 639.258 | — | 4,075.307 | 4,281.540 | 5,246.068 |
| split 32 prose words, warm | 1.738 | — | 0.75427 | 6,666.052 | 62.491 |
| split 10 long words, warm | 1.000 | — | 0.23308 | 4,573.242 | 38.982 |
| split 32 prose words, cold | 19.233 | — | 7,405.445 | 7,454.418 | 72.077 |
| split 2000 distinct words | 146.619 | 43.816 | 70.083 ⚠ | 517,644.958 | 4,966.488 |
| hyphenate a paragraph, common adapter (396 chars) | 28.492 ⚠ | — | 26.865 ⚠ | 5,930.935 ⚠ | 109.633 |

`cacheSplitParts` is an opt-in variant of our engine, not the default: it retains finished part lists per word, as hyphenatorx does, and costs roughly 3.5x the word-cache bytes. A dash means the variant does not apply to that workload.

## Flutter layout (µs per test pump, not device FPS)

| Workload | flutter_hyphenation (local) | auto_hyphenating_text | hyphenatorx wrap | Text control | hyphen + precomputed SHY |
| --- | ---: | ---: | ---: | ---: | ---: |
| warm same width | 47.125 ⚠ | 5,018.019 | 4,243.766 | 39.208 ⚠ | 36.369 ⚠ |
| warm remount | 114.847 ⚠ | 5,190.562 | 4,250.323 | 128.431 ⚠ | 137.547 ⚠ |
| warm cycling 120 widths | 78.108 ⚠ | 5,373.910 | 4,106.228 | 93.783 ⚠ | 96.919 ⚠ |
| cold result caches remount | 959.486 ⚠ | 5,198.932 | 9,217.190 | 125.310 ⚠ | — |
| uncached layout, warm words | 857.780 | 5,204.599 | 4,301.230 | 129.359 ⚠ | 124.132 ⚠ |

Text does not hyphenate. SHY uses precomputed text and a different rendering contract. The x wrap adapter excludes async widget startup.

## Where ours loses

All lower-median alternatives are included. Ratios use **our mean / their mean**, not medians. Approximate 95% intervals describe local sampling only.

| Workload | Faster median alternative | Our mean / theirs (95% interval) | Evidence |
| --- | --- | ---: | --- |
| engine: split 32 prose words, warm | hyphenatorx | 2.273× (2.232–2.315) | Local loss |
| engine: split 10 long words, warm | hyphenatorx | 4.334× (4.190–4.483) | Local loss |
| engine: split 2000 distinct words | hyphenatorx | 1.395× (unbounded) | Inconclusive ⚠ |
| engine: hyphenate a paragraph, common adapter | hyphenatorx | 1.077× (1.016–1.142) | Local loss ⚠ |
| flutter: warm same width | Text (no hyphens) | 1.117× (0.874–1.441) | Inconclusive, different-feature control ⚠ |
| flutter: warm same width | hyphen (precomputed SHY adapter) | 1.185× (0.923–1.541) | Inconclusive, different-feature control ⚠ |
| flutter: cold result caches remount | Text (no hyphens) | 7.669× (7.128–8.276) | Local loss, different-feature control ⚠ |
| flutter: uncached layout, warm words | Text (no hyphens) | 6.732× (5.901–7.818) | Local loss, different-feature control ⚠ |
| flutter: uncached layout, warm words | hyphen (precomputed SHY adapter) | 6.916× (6.274–7.689) | Local loss, different-feature control ⚠ |

Setup disadvantage: we require externally sourced dictionaries, while x and impure bundle them. The remaining warm-word deficits are allocation in `split`, which builds fresh parts per call rather than retaining them; `cacheSplitParts` trades memory to remove that, as the engine table shows.

## Output agreement (not accuracy)

1042 observations, including 1,000 synthetic tokens. More breaks is not necessarily better.

| A | B | Identical outputs |
| --- | --- | ---: |
| hyphenation | hyphenatorx | 88.48% |
| hyphenation | hyphenator_impure | 88.48% |
| hyphenation | hyphen | 100.00% |
| hyphenatorx | hyphenator_impure | 100.00% |
| hyphenatorx | hyphen | 88.48% |
| hyphenator_impure | hyphen | 88.48% |

## Conditions

- Same English source rules, no exceptions, minima 3/3. Hunspell preprocessing is checked against the official compiler golden. Outputs can still differ.
- Load excludes file I/O and format conversion. Engine cold includes cache reset/front-object allocation, not dictionary parsing. Paragraph adapters share tokenization and reconstruction, without whole-paragraph caching.
- The 2,000-word set is synthetic and fits our cache. Widths cycle through 120 values. Widget cold resets are outside timing. These do not test cache eviction.
- Rotated trials: engines get 300 ms warmup plus three untimed batch rounds, widgets get 2 seconds per candidate plus 240 pumps per trial. All samples retained. Small noisy differences are inconclusive, no multiple-comparison correction.
- Local JIT/debug tests only. No release/device, linguistic accuracy, memory or app-size conclusions.
