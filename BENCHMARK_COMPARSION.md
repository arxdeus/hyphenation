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
| load en-US dictionary | 599.049 |
| split 32 prose words, warm | 1.599 |
| split 32 prose words, cold | 15.206 |
| split 2000 distinct words | 120.967 |
| hyphenate a paragraph, common adapter (396 chars) | 24.405 ⚠ |

## Engines (Flutter debug test runtime)

| Workload | hyphenation | hyphenation (cacheSplitParts) | hyphenatorx | hyphenator_impure | hyphen |
| --- | ---: | ---: | ---: | ---: | ---: |
| load en-US dictionary | 632.645 | — | 4,082.743 | 4,246.023 | 5,186.786 |
| split 32 prose words, warm | 1.753 | — | 0.74168 | 7,171.378 | 64.185 |
| split 10 long words, warm | 0.91512 | — | 0.20250 | 4,293.533 | 32.890 |
| split 32 prose words, cold | 16.830 | — | 6,991.932 | 7,131.341 | 61.855 |
| split 2000 distinct words | 129.247 | 40.836 | 67.875 ⚠ | 507,247.458 | 4,403.701 |
| hyphenate a paragraph, common adapter (396 chars) | 26.462 | — | 24.762 ⚠ | 5,912.898 | 93.141 |

`cacheSplitParts` is an opt-in variant of our engine, not the default: it retains finished part lists per word, as hyphenatorx does, and costs roughly 3.5x the word-cache bytes. A dash means the variant does not apply to that workload.

## Flutter layout (µs per test pump, not device FPS)

| Workload | flutter_hyphenation (local) | auto_hyphenating_text | hyphenatorx wrap | Text control | hyphen + precomputed SHY |
| --- | ---: | ---: | ---: | ---: | ---: |
| warm same width | 43.823 ⚠ | 4,246.923 | 3,586.191 | 32.484 ⚠ | 31.514 ⚠ |
| warm remount | 84.565 ⚠ | 3,982.202 | 3,267.861 | 98.600 ⚠ | 101.218 ⚠ |
| warm cycling 120 widths | 64.340 ⚠ | 4,079.731 | 3,208.492 | 73.485 ⚠ | 76.058 ⚠ |
| cold result caches remount | 713.376 ⚠ | 3,888.742 | 7,147.005 | 93.451 ⚠ | — |
| uncached layout, warm words | 667.660 ⚠ | 3,898.746 | 3,281.414 ⚠ | 93.465 ⚠ | 91.054 ⚠ |

Text does not hyphenate. SHY uses precomputed text and a different rendering contract. The x wrap adapter excludes async widget startup.

## Where ours loses

All lower-median alternatives are included. Ratios use **our mean / their mean**, not medians. Approximate 95% intervals describe local sampling only.

| Workload | Faster median alternative | Our mean / theirs (95% interval) | Evidence |
| --- | --- | ---: | --- |
| engine: split 32 prose words, warm | hyphenatorx | 2.370× (2.337–2.404) | Local loss |
| engine: split 10 long words, warm | hyphenatorx | 4.502× (4.419–4.588) | Local loss |
| engine: split 2000 distinct words | hyphenatorx | 1.945× (1.793–2.126) | Local loss ⚠ |
| engine: hyphenate a paragraph, common adapter | hyphenatorx | 1.090× (1.048–1.137) | Local loss ⚠ |
| flutter: warm same width | Text (no hyphens) | 1.159× (0.876–1.564) | Inconclusive, different-feature control ⚠ |
| flutter: warm same width | hyphen (precomputed SHY adapter) | 1.280× (0.965–1.732) | Inconclusive, different-feature control ⚠ |
| flutter: cold result caches remount | Text (no hyphens) | 7.745× (7.141–8.394) | Local loss, different-feature control ⚠ |
| flutter: uncached layout, warm words | Text (no hyphens) | 7.221× (6.658–7.849) | Local loss, different-feature control ⚠ |
| flutter: uncached layout, warm words | hyphen (precomputed SHY adapter) | 7.263× (6.538–8.129) | Local loss, different-feature control ⚠ |

Setup disadvantage: we require externally sourced dictionaries, while x and impure bundle them. Remaining warm-word deficits are allocation in `split`, which returns fresh parts instead of retaining finished lists per word as hyphenatorx does.

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
