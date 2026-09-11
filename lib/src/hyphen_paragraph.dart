import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hyphen/src/hyphenator.dart';
import 'package:flutter_hyphen/src/line_breaker.dart';

/// The paragraph widget behind [HyphenText].
///
/// It behaves like [RichText] with a plain string, except that the string is
/// re-broken into lines during layout so that words which do not fit are split
/// at dictionary-approved points and a hyphen is painted.
class HyphenParagraph extends LeafRenderObjectWidget {
  /// Creates a hyphenating paragraph.
  const HyphenParagraph({
    required this.data,
    required this.hyphenator,
    required this.textDirection,
    required this.textAlign,
    required this.softWrap,
    required this.overflow,
    required this.textScaler,
    required this.textWidthBasis,
    this.style,
    this.hyphenCharacter = '-',
    this.strutStyle,
    this.locale,
    this.maxLines,
    this.textHeightBehavior,
    this.selectionColor,
    this.selectionRegistrar,
    super.key,
  }) : assert(maxLines == null || maxLines > 0, 'maxLines must be positive');

  /// The string to display.
  final String data;

  /// The style applied to [data].
  final TextStyle? style;

  /// The dictionary used to find break points.
  final Hyphenator hyphenator;

  /// The character painted where a word is split.
  final String hyphenCharacter;

  /// See [Text.textDirection].
  final TextDirection textDirection;

  /// See [Text.textAlign].
  final TextAlign textAlign;

  /// See [Text.softWrap].
  final bool softWrap;

  /// See [Text.overflow].
  final TextOverflow overflow;

  /// See [Text.textScaler].
  final TextScaler textScaler;

  /// See [Text.textWidthBasis].
  final TextWidthBasis textWidthBasis;

  /// See [Text.strutStyle].
  final StrutStyle? strutStyle;

  /// See [Text.locale].
  final Locale? locale;

  /// See [Text.maxLines].
  final int? maxLines;

  /// See [Text.textHeightBehavior].
  final TextHeightBehavior? textHeightBehavior;

  /// See [Text.selectionColor].
  final Color? selectionColor;

  /// The registrar this paragraph registers its selectables with.
  final SelectionRegistrar? selectionRegistrar;

  TextSpan get _span => TextSpan(text: data, style: style, locale: locale);

  @override
  RenderHyphenParagraph createRenderObject(BuildContext context) =>
      RenderHyphenParagraph(
        _span,
        hyphenator: hyphenator,
        hyphenCharacter: hyphenCharacter,
        textAlign: textAlign,
        textDirection: textDirection,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        strutStyle: strutStyle,
        locale: locale,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
        registrar: selectionRegistrar,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHyphenParagraph renderObject,
  ) {
    renderObject
      ..text = _span
      ..hyphenator = hyphenator
      ..hyphenCharacter = hyphenCharacter
      ..textAlign = textAlign
      ..textDirection = textDirection
      ..softWrap = softWrap
      ..overflow = overflow
      ..textScaler = textScaler
      ..maxLines = maxLines
      ..strutStyle = strutStyle
      ..locale = locale
      ..textWidthBasis = textWidthBasis
      ..textHeightBehavior = textHeightBehavior
      ..selectionColor = selectionColor
      ..registrar = selectionRegistrar;
  }
}

/// A [RenderParagraph] that hyphenates the text it lays out.
///
/// The render object keeps the caller's text in [text] and derives the string
/// it actually paints from the incoming constraints during layout. That makes
/// the hyphenation width-aware while keeping intrinsic sizes, dry layout and
/// baselines correct, which a `LayoutBuilder`-based approach cannot offer.
class RenderHyphenParagraph extends RenderParagraph
    with RenderObjectWithLayoutCallbackMixin {
  /// Creates a hyphenating paragraph render object.
  RenderHyphenParagraph(
    TextSpan super.text, {
    required Hyphenator hyphenator,
    required super.textDirection,
    String hyphenCharacter = '-',
    super.textAlign,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.strutStyle,
    super.locale,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
    super.registrar,
    // The three fields below back public getters/setters that do extra work,
    // so they cannot be initializing formals.
    // ignore: prefer_initializing_formals
  }) : _hyphenator = hyphenator,
       // ignore: prefer_initializing_formals
       _hyphenCharacter = hyphenCharacter,
       _sourceSpan = text;

  /// The span as supplied by the widget, before any line breaking.
  TextSpan _sourceSpan;

  /// The text as the caller wrote it, without hyphens or inserted newlines.
  String get sourceText => _sourceSpan.text ?? '';

  /// The string currently being painted, including hyphens.
  ///
  /// This is only meaningful after layout and exists for tests and debugging.
  @visibleForTesting
  String get renderedText => (super.text as TextSpan).text ?? '';

  @override
  set text(InlineSpan value) {
    final span = value as TextSpan;
    if (_sourceSpan.text == span.text &&
        _sourceSpan.style == span.style &&
        _sourceSpan.locale == span.locale) {
      return;
    }
    _sourceSpan = span;
    _invalidateBreaks();
    // The painted text is recomputed in the layout callback; installing the
    // source text here keeps semantics, intrinsics and `toStringDeep` honest
    // until then.
    super.text = span;
  }

  /// The dictionary used to find break points.
  Hyphenator get hyphenator => _hyphenator;
  Hyphenator _hyphenator;

  set hyphenator(Hyphenator value) {
    if (identical(_hyphenator, value)) {
      return;
    }
    _hyphenator = value;
    _invalidateBreaks();
    markNeedsLayout();
  }

  /// The character painted where a word is split.
  String get hyphenCharacter => _hyphenCharacter;
  String _hyphenCharacter;

  set hyphenCharacter(String value) {
    if (_hyphenCharacter == value) {
      return;
    }
    _hyphenCharacter = value;
    _invalidateBreaks();
    markNeedsLayout();
  }

  @override
  set textScaler(TextScaler value) {
    if (textScaler != value) {
      _invalidateBreaks();
    }
    super.textScaler = value;
  }

  @override
  set strutStyle(StrutStyle? value) {
    if (strutStyle != value) {
      _invalidateBreaks();
    }
    super.strutStyle = value;
  }

  @override
  set textHeightBehavior(TextHeightBehavior? value) {
    if (textHeightBehavior != value) {
      _invalidateBreaks();
    }
    super.textHeightBehavior = value;
  }

  HyphenLineBreaker? _breaker;
  TextPainter? _measurePainter;
  TextPainter? _dryPainter;

  /// Memoised result of the last break, keyed by the width it was made for.
  ///
  /// Re-laying out at an unchanged width is by far the most common case (any
  /// rebuild, and every frame of a scroll), and breaking the text again there
  /// costs far more than the paragraph layout itself.
  double? _cachedWidth;
  String? _cachedBroken;

  /// Drops everything derived from the text, the style or the dictionary.
  void _invalidateBreaks() {
    _breaker = null;
    _cachedWidth = null;
    _cachedBroken = null;
  }

  HyphenLineBreaker get _lineBreaker => _breaker ??= HyphenLineBreaker(
    measure: _measure,
    hyphenator: _hyphenator,
    hyphenCharacter: _hyphenCharacter,
  );

  double _measure(String text) {
    final painter = _measurePainter ??= TextPainter();
    painter
      ..text = TextSpan(
        text: text,
        style: _sourceSpan.style,
        locale: _sourceSpan.locale,
      )
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..strutStyle = strutStyle
      ..textHeightBehavior = textHeightBehavior
      ..textWidthBasis = TextWidthBasis.parent
      ..maxLines = null
      ..ellipsis = null
      ..layout();
    return painter.width;
  }

  /// The text to paint when laid out into [maxWidth].
  String _brokenTextFor(double maxWidth) {
    final source = sourceText;
    if (source.isEmpty || !maxWidth.isFinite || !softWrap) {
      return source;
    }
    if (_cachedWidth == maxWidth && _cachedBroken != null) {
      return _cachedBroken!;
    }
    final broken = _lineBreaker.breakIntoString(source, maxWidth);
    _cachedWidth = maxWidth;
    _cachedBroken = broken;
    return broken;
  }

  TextSpan _spanFor(double maxWidth) => TextSpan(
    text: _brokenTextFor(maxWidth),
    style: _sourceSpan.style,
    locale: _sourceSpan.locale,
  );

  /// Lays out a scratch painter with the broken text, for dry layout,
  /// baselines and intrinsic heights.
  TextPainter _layoutDry(BoxConstraints constraints) {
    final painter = _dryPainter ??= TextPainter();
    painter
      ..text = _spanFor(constraints.maxWidth)
      ..textAlign = textAlign
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..maxLines = maxLines
      ..ellipsis = overflow == TextOverflow.ellipsis ? '\u2026' : null
      ..locale = locale
      ..strutStyle = strutStyle
      ..textWidthBasis = textWidthBasis
      ..textHeightBehavior = textHeightBehavior
      ..layout(
        minWidth: constraints.minWidth,
        // Mirror RenderParagraph's own `_adjustMaxWidth`, so dry layout and
        // real layout agree. The text is pre-broken, but the paragraph is
        // still allowed to wrap: a chunk that cannot be hyphenated small
        // enough must fall back to the engine's own breaking, exactly as it
        // would in a plain Text.
        maxWidth: softWrap || overflow == TextOverflow.ellipsis
            ? constraints.maxWidth
            : double.infinity,
      );
    return painter;
  }

  @override
  void layoutCallback() {
    // Assigning the text marks this object as needing layout again, which is
    // only legal inside a layout callback. That is exactly what the mixin
    // buys us, and it is how LayoutBuilder rebuilds its subtree.
    super.text = _spanFor(constraints.maxWidth);
  }

  @override
  void performLayout() {
    runLayoutCallback();
    super.performLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    if (!softWrap) {
      return super.computeMinIntrinsicWidth(height);
    }
    // The narrowest sensible width is the widest chunk that cannot be broken
    // any further, which is what hyphenation buys: much narrower columns than
    // whole-word wrapping allows.
    return _lineBreaker.minIntrinsicWidth(sourceText);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _layoutDry(
    BoxConstraints(maxWidth: width),
  ).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_layoutDry(constraints).size);

  @override
  double computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) =>
      _layoutDry(constraints)
          .computeDistanceToActualBaseline(TextBaseline.alphabetic);

  @override
  void dispose() {
    _measurePainter?.dispose();
    _dryPainter?.dispose();
    _measurePainter = null;
    _dryPainter = null;
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('sourceText', sourceText));
    properties.add(StringProperty('hyphenCharacter', _hyphenCharacter));
  }
}
