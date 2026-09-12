import 'package:flutter/widgets.dart';
import 'package:flutter_hyphen/src/service/hyphenation_registry.dart';
import 'package:flutter_hyphen/src/service/hyphenator.dart';

/// Provides a [Hyphenator] to the [HyphenText] widgets below it.
///
/// A scope takes precedence over [HyphenationRegistry.instance], which makes
/// it easy to use a different dictionary for one subtree, or to disable
/// hyphenation for one by passing a `null` [hyphenator].
///
/// ```dart
/// HyphenScope(
///   hyphenator: technicalHyphenator,
///   child: const HyphenText('antidisestablishmentarianism'),
/// )
/// ```
class HyphenScope extends InheritedWidget {
  /// Creates a scope that provides [hyphenator] to its descendants.
  const HyphenScope({
    required super.child,
    this.hyphenator,
    super.key,
  });

  /// The hyphenator descendants should use, or `null` to disable hyphenation
  /// for the subtree.
  final Hyphenator? hyphenator;

  /// Returns the hyphenator provided by the nearest enclosing [HyphenScope],
  /// or `null` when there is none.
  ///
  /// This does not fall back to [HyphenationRegistry]; use [resolve] for that.
  static Hyphenator? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HyphenScope>()?.hyphenator;

  /// Resolves the hyphenator for [context] and [locale].
  ///
  /// The nearest [HyphenScope] wins. Without one, the dictionary registered
  /// in [HyphenationRegistry] for [locale] is used, falling back to the
  /// ambient [Localizations] locale and then to
  /// [HyphenationRegistry.fallback].
  static Hyphenator? resolve(BuildContext context, {Locale? locale}) {
    final scope = context.dependOnInheritedWidgetOfExactType<HyphenScope>();
    if (scope != null) {
      return scope.hyphenator;
    }
    return HyphenationRegistry.instance.resolve(
      locale ?? Localizations.maybeLocaleOf(context),
    );
  }

  @override
  bool updateShouldNotify(HyphenScope oldWidget) =>
      !identical(hyphenator, oldWidget.hyphenator);
}
