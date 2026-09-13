import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:hyphenate/hyphenate.dart';

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
    final previous = _sourceSpan;
    if (previous.text == span.text &&
        previous.style == span.style &&
        previous.locale == span.locale) {
      return;
    }
    _sourceSpan = span;
    // A change that only affects painting (colour, decoration, shadows) moves
    // no glyph, so every break computed so far is still right. Swapping the
    // style under the painted text repaints without a layout, which is what
    // a plain Text does for the same change. TextSpan.compareTo ignores the
    // span's locale, so that is checked separately.
    if (previous.text == span.text &&
        previous.locale == span.locale &&
        previous.compareTo(span).index < RenderComparison.layout.index) {
      // The breaks survive, but the span carrying them has the old style.
      _cachedSpan = null;
      super.text = TextSpan(
        text: renderedText,
        style: span.style,
        locale: span.locale,
      );
      return;
    }
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
  set softWrap(bool value) {
    if (softWrap != value) {
      _invalidateBreaks();
    }
    super.softWrap = value;
  }

  @override
  set textDirection(TextDirection value) {
    if (textDirection != value) {
      _invalidateBreaks();
    }
    super.textDirection = value;
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

  /// The most recently used width and what it broke into.
  ///
  /// Re-laying out at an unchanged width is by far the most common case (any
  /// rebuild, and every frame of a scroll), and breaking the text again there
  /// costs far more than the paragraph layout itself. This slot is plain
  /// fields rather than a map entry because a paragraph that is laid out at
  /// one width, which is the overwhelming majority, must not pay for a hash
  /// map it never needs: a screenful of paragraphs allocates one render
  /// object each, and that allocation showed up in the list benchmark.
  double? _cachedWidth;
  String? _cachedBroken;

  /// The span handed to the engine at [_cachedWidth], so that a relayout at
  /// the same width passes the identical object and `RenderParagraph.text`
  /// short-circuits instead of comparing styles field by field.
  TextSpan? _cachedSpan;

  /// Results for widths other than [_cachedWidth], allocated only once a
  /// second width is seen. A parent's dry layout probes at other widths, and
  /// those must not evict the width the object is actually painted at.
  Map<double, String>? _olderBroken;

  /// How many superseded widths to keep in [_olderBroken].
  static const int _kOlderCacheSize = 7;

  /// Whether the dictionary can break anything in the text at all; null until
  /// asked.
  bool? _breakable;

  /// Minimum intrinsic width, which depends only on the text and the style.
  double? _minIntrinsicWidthCache;

  /// Drops everything derived from the text, the style or the dictionary.
  void _invalidateBreaks() {
    _breaker = null;
    _cachedWidth = null;
    _cachedBroken = null;
    _cachedSpan = null;
    _olderBroken = null;
    _breakable = null;
    _minIntrinsicWidthCache = null;
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
      // Alignment does not change a line's width, but any alignment other
      // than left makes TextPainter lay the paragraph out twice at an
      // infinite width (once to learn the width, once for a finite paint
      // offset). Left-aligning the scratch painter keeps RTL measurement to
      // a single layout, like LTR.
      ..textAlign = TextAlign.left
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
  ///
  /// The expensive part of hyphenation is deciding where the lines end, which
  /// [HyphenLineBreaker] does by measuring candidate lines. Everything here is
  /// memoisation around that: per width on this object, then across widgets on
  /// the [Hyphenator].
  ///
  /// The body is deliberately tiny, and the part that can reach the line
  /// breaker lives behind [_breakFor], which is marked never-inline. Almost
  /// every call is a cache hit, and keeping the cold path out of this method
  /// keeps it small enough for the compiler to inline into the layout
  /// callback. Letting the breaker's call graph bleed in here measured ~15%
  /// slower on a screen of already-broken paragraphs, even though the breaker
  /// never ran.
  String _brokenTextFor(double maxWidth) {
    if (_cachedWidth == maxWidth) {
      return _cachedBroken!;
    }
    return _breakFor(maxWidth);
  }

  @pragma('vm:never-inline')
  String _breakFor(double maxWidth) {
    final source = sourceText;
    if (source.isEmpty || !maxWidth.isFinite || !softWrap) {
      return source;
    }
    final older = _olderBroken?[maxWidth];
    if (older != null) {
      _promote(maxWidth, older);
      return older;
    }

    // Shared across every widget using this dictionary, so two paragraphs
    // with the same text, style and width only break once.
    final sharedKey = _sharedBreakKey(maxWidth);
    var broken = _hyphenator.cachedBreak(sharedKey);
    if (broken == null) {
      // Nothing to hyphenate: let the engine wrap the text as it would a
      // plain Text.
      broken = (_breakable ??= _hyphenator.hasBreakOpportunity(source))
          ? _lineBreaker.breakIntoString(source, maxWidth)
          : source;
      _hyphenator.cacheBreak(sharedKey, broken, sourceLength: source.length);
    }
    _promote(maxWidth, broken);
    return broken;
  }

  /// Makes [maxWidth] the current width, demoting the previous one.
  void _promote(double maxWidth, String broken) {
    final previousWidth = _cachedWidth;
    if (previousWidth != null) {
      final older = _olderBroken ??= <double, String>{};
      if (older.length >= _kOlderCacheSize) {
        older.remove(older.keys.first);
      }
      older[previousWidth] = _cachedBroken!;
    }
    _olderBroken?.remove(maxWidth);
    _cachedWidth = maxWidth;
    _cachedBroken = broken;
    _cachedSpan = null;
  }

  /// Key identifying a break result across widgets.
  ///
  /// Everything that can change where the lines fall has to appear here, or a
  /// widget would pick up another's layout. A record compares its fields with
  /// `==`, so unlike a string built from hash codes it cannot alias two
  /// different styles or scalers.
  Object _sharedBreakKey(double maxWidth) => (
    maxWidth,
    _hyphenCharacter,
    textDirection,
    textScaler,
    strutStyle,
    textHeightBehavior,
    _sourceSpan.style,
    _sourceSpan.locale,
    sourceText,
  );

  TextSpan _spanFor(double maxWidth) {
    final broken = _brokenTextFor(maxWidth);
    // `_brokenTextFor` clears the cached span whenever the current width
    // changes, so a hit here always belongs to `maxWidth`.
    final cached = _cachedSpan;
    if (cached != null && _cachedWidth == maxWidth) {
      return cached;
    }
    final span = TextSpan(
      text: broken,
      style: _sourceSpan.style,
      locale: _sourceSpan.locale,
    );
    if (_cachedWidth == maxWidth) {
      _cachedSpan = span;
    }
    return span;
  }

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
    //
    // The engine cannot answer this: `TextPainter.minIntrinsicWidth` ignores
    // soft hyphens, and laying out at a tiny width makes it break per
    // character instead. So the chunks between break points are measured
    // directly. That is expensive, but it depends only on the text and the
    // style, so it is cached: parents like Center and IntrinsicWidth query
    // intrinsics on every layout pass, and recomputing this each time was the
    // single most expensive thing this class did.
    return _minIntrinsicWidthCache ??= _lineBreaker.minIntrinsicWidth(
      sourceText,
    );
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
  ) => _layoutDry(constraints).computeDistanceToActualBaseline(baseline);

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
