# Changelog

## 1.0.2

- The SDK constraint is now `^3.5.0` and the Flutter constraint `^1.17.0`, so
  the package resolves on older stable Dart releases. No API or behaviour
  changes.
- Depends on `hyphenation: ^1.0.2`.

## 1.0.1

- The LICENSE file is now the plain MIT text so pub.dev recognizes it; the
  pattern-file notices moved to `NOTICE.md`.
- The package ships a runnable `example/` Flutter app.

## 1.0.0

Initial release.

- `HyphenText`, a drop-in replacement for `Text` that hyphenates long words
  using TeX hyphenation patterns, and `HyphenParagraph`, the render object
  behind it.
- `HyphenScope`, providing a hyphenator to a subtree, and
  `HyphenationRegistry`, holding app-wide pattern sets keyed by locale.
- `HyphenatorAsset.fromAsset`, loading and compiling a hyphenator from the
  asset bundle.
- An asset transformer entry point that rewrites a pattern file as nothing but
  its pattern groups, so the TeX prose never reaches the app bundle.
- Broken lines are memoised per width, style, scaler, strut, direction and
  locale on the shared hyphenator.
