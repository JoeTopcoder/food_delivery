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
}
