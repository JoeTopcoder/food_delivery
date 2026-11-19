import 'package:flutter/material.dart';

/// Shared cooking-gas brand tokens + the HotBite-logo app bar used across the
/// gas screens so they read as one system and match HotBite branding.
class GasBrand {
  static const orange = Color(0xFFFF5A1F);
  static const red = Color(0xFFD7263D);
  static const green = Color(0xFF059669);
  static const greenDark = Color(0xFF047857);

  static const LinearGradient flameGradient = LinearGradient(
    colors: [orange, red],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// App bar with the HotBite logo centered (matches the rest of the app).
  static PreferredSizeWidget appBar(BuildContext context, {List<Widget>? actions}) {
    return AppBar(
      centerTitle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      title: Image.asset('assets/images/hotbite_logo.png', height: 30,
          errorBuilder: (_, __, ___) => const Text('HotBite',
              style: TextStyle(fontWeight: FontWeight.w900, color: red))),
      actions: actions,
    );
  }

  /// Brand accent color for a cylinder brand (used for the cylinder thumbnails).
  static Color brandColor(String brand) {
    final b = brand.toUpperCase();
    if (b.contains('IGL')) return const Color(0xFFF59E0B); // yellow
    if (b.contains('FESGAS') || b.contains('FES')) return const Color(0xFF2563EB); // blue
    return orange; // GasPro / default
  }

  /// A brand-colored cylinder thumbnail tile (stands in for a product photo).
  static Widget cylinderTile({required String brand, double size = 64, String? imageUrl, double radius = 14}) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(imageUrl, width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _cylinderFallback(brand, size, radius)),
      );
    }
    return _cylinderFallback(brand, size, radius);
  }

  static Widget _cylinderFallback(String brand, double size, double radius) {
    final c = brandColor(brand);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(radius)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.propane_tank_rounded, color: c, size: size * 0.46),
          Text(brand.length > 7 ? brand.substring(0, 7) : brand,
              style: TextStyle(color: c, fontSize: size * 0.14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  /// The orange→red flame cylinder avatar used on supplier cards.
  static Widget flameAvatar({double size = 52, String? logoUrl}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: flameGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl != null && logoUrl.isNotEmpty
          ? Image.network(logoUrl, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.local_fire_department_rounded, color: Colors.white))
          : Icon(Icons.local_fire_department_rounded, color: Colors.white, size: size * 0.5),
    );
  }
}
