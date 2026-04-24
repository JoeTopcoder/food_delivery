import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_constants.dart';
import 'app_logger.dart';

/// Fetches the app color palette from the get-theme edge function.
/// Falls back to compile-time defaults if network fails.
class RemoteTheme {
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color errorColor;
  final Color successColor;
  final Color warningColor;
  final Color priceColor;
  final Color textPrimary;
  final Color textSecondary;
  final Color textLight;
  final Color borderColor;
  final Color dividerColor;

  const RemoteTheme({
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.errorColor,
    required this.successColor,
    required this.warningColor,
    required this.priceColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.textLight,
    required this.borderColor,
    required this.dividerColor,
  });

  static Color _hex(String hex, Color fallback) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  factory RemoteTheme.fromJson(Map<String, dynamic> c) => RemoteTheme(
    primaryColor: _hex(c['primaryColor'] ?? '', const Color(0xFF7C3AED)),
    secondaryColor: _hex(c['secondaryColor'] ?? '', const Color(0xFF004E89)),
    accentColor: _hex(c['accentColor'] ?? '', const Color(0xFFE74C3C)),
    backgroundColor: _hex(c['backgroundColor'] ?? '', const Color(0xFFF7F8FA)),
    errorColor: _hex(c['errorColor'] ?? '', const Color(0xFFE63946)),
    successColor: _hex(c['successColor'] ?? '', const Color(0xFF06A77D)),
    warningColor: _hex(c['warningColor'] ?? '', const Color(0xFFFFA630)),
    priceColor: _hex(c['priceColor'] ?? '', const Color(0xFFE74C3C)),
    textPrimary: _hex(c['textPrimary'] ?? '', const Color(0xFF111827)),
    textSecondary: _hex(c['textSecondary'] ?? '', const Color(0xFF374151)),
    textLight: _hex(c['textLight'] ?? '', const Color(0xFF4B5563)),
    borderColor: _hex(c['borderColor'] ?? '', const Color(0xFFE5E7EB)),
    dividerColor: _hex(c['dividerColor'] ?? '', const Color(0xFFF3F4F6)),
  );

  static RemoteTheme get defaults => RemoteTheme(
    primaryColor: const Color(0xFF7C3AED),
    secondaryColor: const Color(0xFF004E89),
    accentColor: const Color(0xFFE74C3C),
    backgroundColor: const Color(0xFFF7F8FA),
    errorColor: const Color(0xFFE63946),
    successColor: const Color(0xFF06A77D),
    warningColor: const Color(0xFFFFA630),
    priceColor: const Color(0xFFE74C3C),
    textPrimary: const Color(0xFF111827),
    textSecondary: const Color(0xFF374151),
    textLight: const Color(0xFF4B5563),
    borderColor: const Color(0xFFE5E7EB),
    dividerColor: const Color(0xFFF3F4F6),
  );
}

class ThemeService {
  ThemeService._();
  static RemoteTheme _current = RemoteTheme.defaults;
  static RemoteTheme get current => _current;

  /// Call once at startup (before runApp). Non-fatal — always resolves.
  static Future<void> load() async {
    try {
      final url = '${AppConstants.supabaseFunctionsBaseUrl}/get-theme';
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final colors = body['colors'] as Map<String, dynamic>? ?? {};
        _current = RemoteTheme.fromJson(colors);
        AppLogger.info(
          '[ThemeService] Loaded remote theme (${body['source']})',
        );
      }
    } catch (e) {
      AppLogger.warning('[ThemeService] Using default theme: $e');
    }
  }
}
