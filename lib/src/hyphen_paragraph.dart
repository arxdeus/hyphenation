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

  /// The source text with soft hyphens inserted, cached across widths.
  String? _marked;

  /// Minimum intrinsic width, which depends only on the text and the style.
  double? _minIntrinsicWidthCache;

  /// Painter holding the shaped soft-hyphenated text, reused across widths.
  TextPainter? _breakPainter;
  String? _breakPainterText;

  /// How many times this paragraph has been broken by the engine.
  ///
  /// The two strategies have opposite cost profiles: the engine path is a
  /// flat cost per width, while the measuring breaker is expensive until its
  /// width cache fills and cheap afterwards. A paragraph laid out once or
  /// twice is best served by the engine; one that is being resized every
  /// frame is best served by the cache. Counting the engine breaks switches
  /// from the first to the second once it is clear which case this is.
  int _engineBreaks = 0;

  /// After this many engine breaks, the measuring breaker takes over.
  static const int _maxEngineBreaks = 3;

  /// Drops everything derived from the text, the style or the dictionary.
  void _invalidateBreaks() {
    _breaker = null;
    _cachedWidth = null;
    _cachedBroken = null;
    _marked = null;
    _minIntrinsicWidthCache = null;
    _breakPainterText = null;
    _engineBreaks = 0;
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

  /// The source text with a soft hyphen at every break the dictionary allows.
  ///
  /// Computing this needs no measurement at all, so it only has to be redone
  /// when the text or the dictionary changes, not when the width does.
  String get _markedText => _marked ??= _hyphenator.hyphenate(sourceText);

  /// The text to paint when laid out into [maxWidth].
  ///
  /// The expensive part of hyphenation is deciding where the lines end. Rather
  /// than measuring candidate lines one by one, this hands the engine a string
  /// marked with soft hyphens and lets it break the paragraph in a single
  /// layout: the engine already treats U+00AD as a break opportunity, it just
  /// will not paint a hyphen glyph there. Reading the resulting line starts
  /// back out and re-emitting the text with real hyphens costs one layout
  /// instead of O(lines x log candidates) of them.
  String _brokenTextFor(double maxWidth) {
    final source = sourceText;
    if (source.isEmpty || !maxWidth.isFinite || !softWrap) {
      return source;
    }
    if (_cachedWidth == maxWidth && _cachedBroken != null) {
      return _cachedBroken!;
    }

    final marked = _markedText;
    final String broken;
    if (!marked.contains(kSoftHyphen)) {
      // Nothing to hyphenate: let the engine wrap the text as it would a
      // plain Text.
      broken = source;
    } else if (_engineBreaks < _maxEngineBreaks) {
      // The engine breaks the whole paragraph in one layout, which is much
      // cheaper than measuring candidate lines the first few times a width is
      // seen.
      _engineBreaks++;
      broken = _breakViaEngine(marked, maxWidth);
    } else {
      // Widths keep changing, which means this paragraph is being resized or
      // animated. `HyphenLineBreaker` caches the width of every chunk it has
      // measured, so after a few widths it answers almost entirely from cache
      // and beats the engine path, which has to pay `computeLineMetrics` on
      // every new width.
      broken = _lineBreaker.breakIntoString(source, maxWidth);
    }
    _cachedWidth = maxWidth;
    _cachedBroken = broken;
    return broken;
  }

  /// Lays [marked] out once and rewrites it with a real hyphen wherever the
  /// engine chose to break at a soft hyphen.
  String _breakViaEngine(String marked, double maxWidth) {
    final painter = _breakPainter ??= TextPainter();
    // Assigning `text` throws the shaped paragraph away, so it is only done
    // when the marked text actually changed. Re-shaping the same string on
    // every width change made this call roughly six times more expensive than
    // it needed to be, which is most of what a resizing column pays.
    if (!identical(_breakPainterText, marked)) {
      painter.text = TextSpan(
        text: marked,
        style: _sourceSpan.style,
        locale: _sourceSpan.locale,
      );
      _breakPainterText = marked;
    }
    painter
      ..textAlign = TextAlign.start
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..strutStyle = strutStyle
      ..textHeightBehavior = textHeightBehavior
      ..textWidthBasis = TextWidthBasis.parent
      ..maxLines = null
      ..ellipsis = null
      // Laid out at the real width. Lines the engine ends at a soft hyphen
      // still have to fit the hyphen that will be painted there, which is
      // checked per line below; reserving room on every line instead would
      // waste a hyphen's width on the lines that end at a space, and make
      // this disagree with `HyphenLineBreaker`.
      ..layout(maxWidth: maxWidth);

    final metrics = painter.computeLineMetrics();
    if (metrics.length < 2) {
      return _stripSoftHyphens(marked);
    }

    // Where each line starts, in the marked text, with a trailing sentinel so
    // line `i` always spans `starts[i]` to `starts[i + 1]`.
    final starts = <int>[0];
    for (var i = 1; i < metrics.length; i++) {
      final start = _lineStartOffset(painter, metrics[i]);
      if (start > starts.last) {
        starts.add(start);
      }
    }
    starts.add(marked.length);

    // Only the lines the engine ended at a soft hyphen need rewriting. Every
    // other break it made (at a space, at a newline, or inside an unbreakable
    // run) is already correct and is left untouched, so the engine reproduces
    // it on the real layout.
    //
    // The engine laid each line out without the hyphen it is about to be
    // given, so a line that exactly filled the column would overflow once the
    // hyphen is added. `LineMetrics` already carries each line's width, so
    // that check costs no extra measurement: the break is simply pulled back
    // to the previous opportunity until the hyphen fits.
    // Emit the lines the engine chose, one per output line. Soft hyphens that
    // fall inside a line are dropped, which is correct: the engine had the
    // room and did not need them.
    final buffer = StringBuffer();
    for (var i = 0; i + 1 < starts.length; i++) {
      var end = starts[i + 1];
      var line = marked.substring(starts[i], end);

      // A line the engine ended at a soft hyphen was measured without the
      // hyphen that is about to be painted there, so it can overflow by up to
      // one hyphen. Pull the break back to an earlier opportunity until it
      // fits.
      while (line.endsWith(kSoftHyphen) &&
          _measure(_stripSoftHyphens(line).trimRight() + _hyphenCharacter) >
              maxWidth) {
        final previous = line.lastIndexOf(kSoftHyphen, line.length - 2);
        if (previous < 0) {
          // No earlier opportunity: let it overflow rather than lose text,
          // exactly as a plain Text would.
          break;
        }
        end = starts[i] + previous + 1;
        starts.insert(i + 1, end);
        line = marked.substring(starts[i], end);
      }

      final hyphenated = line.endsWith(kSoftHyphen);
      final raw = _stripSoftHyphens(line);
      final endsWithNewline = raw.endsWith('\n');
      // Trailing spaces at a wrap are not painted, and keeping them would
      // make the line widths disagree with the breaker's.
      final text = endsWithNewline ? raw : raw.trimRight();
      buffer.write(hyphenated ? text + _hyphenCharacter : text);

      if (i + 2 >= starts.length || endsWithNewline) {
        continue;
      }
      // A newline is only written where the engine had a real break
      // opportunity. Where it broke inside an unbreakable run (a CJK sequence,
      // or a word longer than the column) there is nothing to break at, and
      // forcing a newline there would insert whitespace the author never
      // wrote. Those lines are emitted as-is so the engine makes the same
      // choice again on the real layout.
      if (hyphenated || text.length < raw.length) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  /// The offset in the text at which the line described by [metrics] starts.
  ///
  /// `getLineBoundary` is unreliable around hard newlines, so the start is
  /// read by hit-testing the left edge of the line instead.
  static int _lineStartOffset(TextPainter painter, LineMetrics metrics) =>
      painter
          .getPositionForOffset(
            Offset(0, metrics.baseline - metrics.ascent + 1),
          )
          .offset;

  static String _stripSoftHyphens(String text) =>
      text.contains(kSoftHyphen) ? text.replaceAll(kSoftHyphen, '') : text;

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
  ) =>
      _layoutDry(constraints)
          .computeDistanceToActualBaseline(TextBaseline.alphabetic);

  @override
  void dispose() {
    _measurePainter?.dispose();
    _dryPainter?.dispose();
    _breakPainter?.dispose();
    _breakPainter = null;
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
