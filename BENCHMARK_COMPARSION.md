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
| load en-US dictionary | 556.616 |
| split 32 prose words, warm | 1.787 |
| split 32 prose words, cold | 16.413 |
| split 2000 distinct words | 127.253 |
| hyphenate a paragraph, common adapter (396 chars) | 24.044 |

## Engines (Flutter debug test runtime)

| Workload | hyphenation | hyphenatorx | hyphenator_impure | hyphen |
| --- | ---: | ---: | ---: | ---: |
| load en-US dictionary | 546.578 | 3,786.562 | 4,084.925 | 4,494.585 |
| split 32 prose words, warm | 1.834 | 0.76143 | 6,523.151 | 58.256 |
| split 10 long words, warm | 0.99560 | 0.19427 | 3,923.736 | 31.054 |
| split 32 prose words, cold | 17.465 | 6,560.932 | 6,489.194 | 57.975 |
| split 2000 distinct words | 134.326 | 70.958 ⚠ | 463,905.291 | 4,092.725 |
| hyphenate a paragraph, common adapter (396 chars) | 25.541 | 23.853 | 5,351.431 | 88.689 |

## Flutter layout (µs per test pump, not device FPS)

| Workload | flutter_hyphenation (local) | auto_hyphenating_text | hyphenatorx wrap | Text control | hyphen + precomputed SHY |
| --- | ---: | ---: | ---: | ---: | ---: |
| warm same width | 33.111 ⚠ | 3,588.396 | 3,148.166 | 28.179 ⚠ | 28.436 |
| warm remount | 98.874 ⚠ | 3,667.701 | 3,166.685 | 82.379 ⚠ | 96.417 ⚠ |
| warm cycling 120 widths | 68.975 ⚠ | 3,845.481 | 3,142.129 | 63.913 ⚠ | 65.267 ⚠ |
| cold result caches remount | 684.361 | 3,696.297 | 6,588.745 | 86.409 ⚠ | — |
| uncached layout, warm words | 663.729 | 3,688.410 | 3,183.787 | 99.772 ⚠ | 87.071 ⚠ |

Text does not hyphenate. SHY uses precomputed text and a different rendering contract. The x wrap adapter excludes async widget startup.

## Where ours loses

All lower-median alternatives are included. Ratios use **our mean / their mean**, not medians. Approximate 95% intervals describe local sampling only.

| Workload | Faster median alternative | Our mean / theirs (95% interval) | Evidence |
| --- | --- | ---: | --- |
| engine: split 32 prose words, warm | hyphenatorx | 2.390× (2.361–2.419) | Local loss |
| engine: split 10 long words, warm | hyphenatorx | 5.118× (5.085–5.151) | Local loss |
| engine: split 2000 distinct words | hyphenatorx | 1.816× (1.566–2.161) | Local loss ⚠ |
| engine: hyphenate a paragraph, common adapter | hyphenatorx | 1.069× (1.055–1.084) | Local loss |
| flutter: warm same width | Text (no hyphens) | 1.091× (0.855–1.409) | Inconclusive, different-feature control ⚠ |
| flutter: warm same width | hyphen (precomputed SHY adapter) | 1.261× (1.061–1.464) | Local loss, different-feature control ⚠ |
| flutter: warm remount | Text (no hyphens) | 1.096× (0.980–1.227) | Inconclusive, different-feature control ⚠ |
| flutter: warm remount | hyphen (precomputed SHY adapter) | 1.019× (0.917–1.132) | Inconclusive, different-feature control ⚠ |
| flutter: warm cycling 120 widths | Text (no hyphens) | 0.903× (0.767–1.060) | Inconclusive, different-feature control ⚠ |
| flutter: warm cycling 120 widths | hyphen (precomputed SHY adapter) | 0.878× (0.745–1.033) | Inconclusive, different-feature control ⚠ |
| flutter: cold result caches remount | Text (no hyphens) | 7.604× (7.016–8.284) | Local loss, different-feature control ⚠ |
| flutter: uncached layout, warm words | Text (no hyphens) | 6.853× (6.358–7.426) | Local loss, different-feature control ⚠ |
| flutter: uncached layout, warm words | hyphen (precomputed SHY adapter) | 7.395× (6.861–8.015) | Local loss, different-feature control ⚠ |

Setup disadvantage: we require externally sourced dictionaries, while x and impure bundle them. No production optimizations were made.

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
