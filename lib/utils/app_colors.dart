import 'package:flutter/material.dart';

/// Named color constants for brand/accent colors that should NOT be
/// theme-adapted (they remain the same in both light and dark mode).
///
/// For adaptive colors (backgrounds, text, borders, dividers) use
/// `Theme.of(context).colorScheme.*` directly in your widgets.
class AppColors {
  AppColors._();

  // ── Brand / Primary ────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1E40AF);
  static const Color primaryLight = Color(0xFF3B82F6);

  // ── Status ─────────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF10B981);
  static const Color successAlt = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // ── Driver module (intentionally always-dark backgrounds) ──────────────────
  static const Color driverDark = Color(0xFF121212);
  static const Color driverDarkCard = Color(0xFF1E1E1E);
  static const Color driverDarkSurface = Color(0xFF2A2A2A);
  static const Color driverDarkAccent = Color(0xFFF59E0B);
  static const Color driverDarkTextSecondary = Color(0xFFAAAAAA);

  // ── Payment / Wallet branding ──────────────────────────────────────────────
  static const Color paymentNavy = Color(0xFF004E89);
  static const Color paymentBlue = Color(0xFF0077C8);
  static const Color paymentBg = Color(0xFFF4F6F9);
  static const Color paymentText = Color(0xFF1A1A2E);
  static const Color paymentCardDark = Color(0xFF1A237E);
  static const Color paymentCardMid = Color(0xFF283593);

  // ── Ride / Taxi module ─────────────────────────────────────────────────────
  static const Color rideAccent = Color(0xFF4CAF50);
  static const Color rideAmber = Color(0xFFFFC107);
  static const Color rideBlue = Color(0xFF2196F3);
  static const Color rideDark = Color(0xFF1A1A2E);

  // ── Gradient helpers ───────────────────────────────────────────────────────
  static const Color gradientStart = Color(0xFF667EEA);
  static const Color gradientEnd = Color(0xFF764BA2);

  // ── Misc accent ───────────────────────────────────────────────────────────
  static const Color orange = Color(0xFFFF6B35);
  static const Color amber = Color(0xFFFFAB00);
  static const Color purple = Color(0xFF9C27B0);
  static const Color teal = Color(0xFF009688);
}
