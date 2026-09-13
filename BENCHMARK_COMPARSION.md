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
| load en-US dictionary | 561.351 |
| split 32 prose words, warm | 1.491 |
| split 32 prose words, cold | 15.284 |
| split 2000 distinct words | 109.380 |
| hyphenate a paragraph, common adapter (396 chars) | 23.957 |

## Engines (Flutter debug test runtime)

| Workload | hyphenation | hyphenatorx | hyphenator_impure | hyphen |
| --- | ---: | ---: | ---: | ---: |
| load en-US dictionary | 577.006 ⚠ | 3,874.140 | 4,295.363 | 4,697.346 ⚠ |
| split 32 prose words, warm | 1.615 | 0.75492 | 6,673.964 | 58.931 |
| split 10 long words, warm | 0.82649 | 0.19808 | 4,050.243 | 31.460 |
| split 32 prose words, cold | 16.425 | 6,381.872 | 6,519.410 | 57.151 |
| split 2000 distinct words | 116.424 | 67.167 ⚠ | 467,680.375 | 4,046.190 |
| hyphenate a paragraph, common adapter (396 chars) | 25.505 | 23.984 | 5,396.940 | 87.724 |

## Flutter layout (µs per test pump, not device FPS)

| Workload | flutter_hyphenation (local) | auto_hyphenating_text | hyphenatorx wrap | Text control | hyphen + precomputed SHY |
| --- | ---: | ---: | ---: | ---: | ---: |
| warm same width | 42.825 ⚠ | 3,809.745 | 3,199.861 | 29.046 ⚠ | 28.984 ⚠ |
| warm remount | 98.589 ⚠ | 3,884.157 | 3,180.032 | 98.870 ⚠ | 90.966 ⚠ |
| warm cycling 120 widths | 51.070 ⚠ | 4,048.692 | 3,114.684 | 76.728 ⚠ | 79.597 ⚠ |
| cold result caches remount | 685.657 | 3,795.498 | 7,043.370 | 87.612 ⚠ | — |
| uncached layout, warm words | 667.196 ⚠ | 3,838.380 | 3,181.171 | 83.460 ⚠ | 104.640 ⚠ |

Text does not hyphenate. SHY uses precomputed text and a different rendering contract. The x wrap adapter excludes async widget startup.

## Where ours loses

All lower-median alternatives are included. Ratios use **our mean / their mean**, not medians. Approximate 95% intervals describe local sampling only.

| Workload | Faster median alternative | Our mean / theirs (95% interval) | Evidence |
| --- | --- | ---: | --- |
| engine: split 32 prose words, warm | hyphenatorx | 2.128× (2.101–2.155) | Local loss |
| engine: split 10 long words, warm | hyphenatorx | 4.187× (4.113–4.263) | Local loss |
| engine: split 2000 distinct words | hyphenatorx | 1.607× (1.385–1.914) | Local loss ⚠ |
| engine: hyphenate a paragraph, common adapter | hyphenatorx | 1.057× (1.036–1.079) | Local loss |
| flutter: warm same width | Text (no hyphens) | 1.189× (0.909–1.581) | Inconclusive, different-feature control ⚠ |
| flutter: warm same width | hyphen (precomputed SHY adapter) | 1.317× (1.012–1.734) | Local loss, different-feature control ⚠ |
| flutter: warm remount | hyphen (precomputed SHY adapter) | 1.055× (0.962–1.157) | Inconclusive, different-feature control ⚠ |
| flutter: cold result caches remount | Text (no hyphens) | 7.727× (7.129–8.416) | Local loss, different-feature control ⚠ |
| flutter: uncached layout, warm words | Text (no hyphens) | 7.671× (6.823–8.670) | Local loss, different-feature control ⚠ |
| flutter: uncached layout, warm words | hyphen (precomputed SHY adapter) | 6.728× (6.022–7.543) | Local loss, different-feature control ⚠ |

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
