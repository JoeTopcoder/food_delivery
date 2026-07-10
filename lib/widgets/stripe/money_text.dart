import 'package:flutter/material.dart';

/// Renders a monetary amount from integer cents.
///
/// Example:
/// ```dart
/// MoneyText(1599) // renders "$15.99"
/// ```
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.cents, {
    super.key,
    this.currency = 'usd',
    this.style,
    this.color,
    this.showSign = false,
  });

  final int cents;
  final String currency;
  final TextStyle? style;
  final Color? color;

  /// If true, prefix positive amounts with "+" (useful for ledger entries).
  final bool showSign;

  String _format() {
    final dollars = cents.abs() / 100;
    final sign = showSign && cents > 0 ? '+' : (cents < 0 ? '-' : '');
    return '$sign\$${dollars.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _format(),
      style: (style ?? const TextStyle()).copyWith(color: color),
    );
  }
}
