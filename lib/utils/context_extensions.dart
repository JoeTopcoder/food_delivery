import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Convenience extensions so every widget can write
///   `context.l10n.home`  instead of  `AppLocalizations.of(context).home`
///   `context.theme`      instead of  `Theme.of(context)`
///   `context.colors`     instead of  `Theme.of(context).colorScheme`
extension BuildContextX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get textTheme => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // ── Safe navigation helpers ──────────────────────────────────────────────
  // These use Navigator.maybeOf() so they silently no-op when the context no
  // longer has a Navigator ancestor, preventing the
  // "Navigator operation requested with a context that does not include a
  // Navigator" exception (common when navigating after async gaps or in
  // dialogs/sheets that were already dismissed).

  /// Pop if a Navigator is available and can pop.
  void safePop([Object? result]) {
    final nav = Navigator.maybeOf(this);
    if (nav != null && nav.canPop()) nav.pop(result);
  }

  /// Push a named route, no-op if no Navigator is available.
  Future<T?> safePushNamed<T>(String routeName, {Object? arguments}) {
    final nav = Navigator.maybeOf(this);
    if (nav == null) return Future.value(null);
    return nav.pushNamed<T>(routeName, arguments: arguments);
  }

  /// Replace the entire stack, no-op if no Navigator is available.
  Future<T?> safePushNamedAndRemoveUntil<T>(
    String routeName,
    RoutePredicate predicate, {
    Object? arguments,
  }) {
    final nav = Navigator.maybeOf(this);
    if (nav == null) return Future.value(null);
    return nav.pushNamedAndRemoveUntil<T>(
      routeName,
      predicate,
      arguments: arguments,
    );
  }
}
