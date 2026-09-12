import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hyphen/src/hyphen_paragraph.dart';
import 'package:flutter_hyphen/src/hyphen_scope.dart';
import 'package:flutter_hyphen/src/hyphenator.dart';

/// A drop-in replacement for [Text] that hyphenates words at the end of a
/// line.
///
/// `HyphenText` extends [Text], so it accepts every property [Text] does and
/// can be used anywhere a [Text] is expected. The difference is in how the
/// text is laid out: instead of moving a word that does not fit entirely onto
/// the next line, `HyphenText` splits it at a dictionary-approved point and
/// paints a hyphen.
///
/// ```dart
/// const HyphenText(
///   'antidisestablishmentarianism',
///   style: TextStyle(fontSize: 20),
/// )
/// ```
///
/// ### Where the dictionary comes from
///
/// The hyphenator is resolved in this order:
///
/// 1. the [hyphenator] property, when given;
/// 2. the nearest enclosing [HyphenScope];
/// 3. [HyphenationRegistry.instance], keyed by [locale] or by the ambient
///    [Localizations] locale.
///
/// When none of those yields a dictionary, `HyphenText` renders exactly like
/// [Text]: no hyphens, no layout differences. That makes it safe to use before
/// the dictionaries have finished loading.
///
/// ### Rich text
///
/// Hyphenation applies to the plain [data] string. [HyphenText.rich] renders
/// its span exactly as [Text.rich] does, because splitting a word across
/// styled spans would move their boundaries.
class HyphenText extends Text {
  /// Creates a hyphenating text widget.
  ///
  /// Every argument behaves as it does on [Text].
  const HyphenText(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    @Deprecated(
      'Use textScaler instead. '
      'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
      'This feature was deprecated after v3.12.0-2.0.pre.',
    )
    super.textScaleFactor,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.semanticsIdentifier,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
    this.hyphenator,
    this.hyphenCharacter = '-',
    this.hyphenate = true,
  });

  /// Creates a text widget with an [InlineSpan].
  ///
  /// Rich text is rendered exactly as [Text.rich] renders it. This constructor
  /// exists so that `HyphenText` stays a complete stand-in for [Text].
  const HyphenText.rich(
    super.textSpan, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    @Deprecated(
      'Use textScaler instead. '
      'Use of textScaleFactor was deprecated in preparation for the upcoming nonlinear text scaling support. '
      'This feature was deprecated after v3.12.0-2.0.pre.',
    )
    super.textScaleFactor,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.semanticsIdentifier,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
    this.hyphenator,
    this.hyphenCharacter = '-',
    this.hyphenate = true,
  }) : super.rich();

  /// The dictionary to hyphenate with.
  ///
  /// When null, the hyphenator comes from the nearest [HyphenScope] or from
  /// [HyphenationRegistry.instance].
  final Hyphenator? hyphenator;

  /// The character painted where a word is split. Defaults to `-`.
  final String hyphenCharacter;

  /// Whether to hyphenate at all.
  ///
  /// Setting this to `false` makes the widget behave exactly like [Text],
  /// which is handy for toggling the feature without restructuring the tree.
  final bool hyphenate;

  @override
  Widget build(BuildContext context) {
    final text = data;
    if (!hyphenate || text == null || text.isEmpty) {
      return super.build(context);
    }
    final resolved = hyphenator ?? HyphenScope.resolve(context, locale: locale);
    if (resolved == null) {
      return super.build(context);
    }

    final defaultTextStyle = DefaultTextStyle.of(context);
    var effectiveStyle = style;
    if (style == null || style!.inherit) {
      effectiveStyle = defaultTextStyle.style.merge(style);
    }
    if (MediaQuery.boldTextOf(context)) {
      effectiveStyle = effectiveStyle!.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }

    final effectiveSoftWrap = softWrap ?? defaultTextStyle.softWrap;
    final effectiveOverflow =
        overflow ?? effectiveStyle?.overflow ?? defaultTextStyle.overflow;
    // ignore: deprecated_member_use, mirrors Text's own migration shim.
    final legacyScaleFactor = textScaleFactor;
    final effectiveTextScaler = switch ((textScaler, legacyScaleFactor)) {
      (final TextScaler scaler, _) => scaler,
      (null, final double factor) => TextScaler.linear(factor),
      (null, null) => MediaQuery.textScalerOf(context),
    };

    final Widget result = HyphenParagraph(
      data: text,
      style: effectiveStyle,
      hyphenator: resolved,
      hyphenCharacter: hyphenCharacter,
      textAlign: textAlign ?? defaultTextStyle.textAlign ?? TextAlign.start,
      textDirection: textDirection ?? Directionality.of(context),
      locale: locale ?? Localizations.maybeLocaleOf(context),
      softWrap: effectiveSoftWrap,
      overflow: effectiveOverflow,
      textScaler: effectiveTextScaler,
      maxLines: maxLines ?? defaultTextStyle.maxLines,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis ?? defaultTextStyle.textWidthBasis,
      textHeightBehavior:
          textHeightBehavior ??
          defaultTextStyle.textHeightBehavior ??
          DefaultTextHeightBehavior.maybeOf(context),
      selectionColor:
          selectionColor ??
          DefaultSelectionStyle.of(context).selectionColor ??
          DefaultSelectionStyle.defaultColor,
      selectionRegistrar: SelectionContainer.maybeOf(context),
    );

    // The painted string carries hyphens and hard newlines that the author
    // never wrote, so screen readers must be given the original text instead.
    // `excludeSemantics` folds Text's Semantics + ExcludeSemantics pair into
    // one render object.
    return Semantics(
      textDirection: textDirection,
      label: semanticsLabel ?? text,
      identifier: semanticsIdentifier,
      excludeSemantics: true,
      child: result,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<Hyphenator>(
        'hyphenator',
        hyphenator,
        defaultValue: null,
      ),
    );
    properties.add(
      StringProperty('hyphenCharacter', hyphenCharacter, defaultValue: '-'),
    );
    properties.add(
      FlagProperty(
        'hyphenate',
        value: hyphenate,
        ifFalse: 'hyphenation disabled',
      ),
    );
  }
}
