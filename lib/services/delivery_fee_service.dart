import 'dart:convert';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../utils/app_logger.dart';

/// Structured result from the `calculate-delivery-fee` Edge Function.
class DeliveryFeeResult {
  final double deliveryFee;
  final double driverPay;
  final double platformFee;
  final double driverPayPercent;
  final double? distanceKm;
  final double? distanceMiles;
  final String calculation; // 'distance_based' | 'flat_fee'
  final double surgeMultiplier;
  final double? baseFee;
  final double? perKmFee;
  final double? baseKm;
  final double? extraKm;
  final double? minFee;
  final double? restaurantOverride;
  final bool cached;

  const DeliveryFeeResult({
    required this.deliveryFee,
    required this.driverPay,
    required this.platformFee,
    required this.driverPayPercent,
    this.distanceKm,
    this.distanceMiles,
    required this.calculation,
    required this.surgeMultiplier,
    this.baseFee,
    this.perKmFee,
    this.baseKm,
    this.extraKm,
    this.minFee,
    this.restaurantOverride,
    this.cached = false,
  });

  factory DeliveryFeeResult.fromJson(Map<String, dynamic> json) {
    final fee = (json['delivery_fee'] as num).toDouble();
    final dPay = (json['driver_pay'] as num?)?.toDouble() ?? fee * 0.80;
    return DeliveryFeeResult(
      deliveryFee: fee,
      driverPay: dPay,
      platformFee: (json['platform_fee'] as num?)?.toDouble() ?? (fee - dPay),
      driverPayPercent:
          (json['driver_pay_percent'] as num?)?.toDouble() ?? 0.80,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      distanceMiles: (json['distance_miles'] as num?)?.toDouble(),
      calculation: json['calculation'] as String? ?? 'distance_based',
      surgeMultiplier: (json['surge_multiplier'] as num?)?.toDouble() ?? 1.0,
      baseFee: (json['base_fee'] as num?)?.toDouble(),
      perKmFee: (json['per_km_fee'] as num?)?.toDouble(),
      baseKm: (json['base_km'] as num?)?.toDouble(),
      extraKm: (json['extra_km'] as num?)?.toDouble(),
      minFee: (json['min_fee'] as num?)?.toDouble(),
      restaurantOverride: (json['restaurant_override'] as num?)?.toDouble(),
      cached: json['cached'] as bool? ?? false,
    );
  }

  /// True when a surge multiplier is active (> 1.0).
  bool get hasSurge => surgeMultiplier > 1.0;

  /// Human-readable distance string (miles with km fallback).
  String get distanceLabel {
    if (distanceMiles != null) return '${distanceMiles!.toStringAsFixed(1)} mi';
    if (distanceKm != null) return '${distanceKm!.toStringAsFixed(1)} km';
    return '—';
  }
}

/// Client-side service wrapping the `calculate-delivery-fee` Edge Function.
///
/// Usage:
/// ```dart
/// final svc = DeliveryFeeService(Supabase.instance.client);
/// final result = await svc.calculate(
///   restaurantId: 'abc',
///   deliveryLatitude: 19.2869,
///   deliveryLongitude: -81.3812,
/// );
/// ```
class DeliveryFeeService {
  final SupabaseClient _client;
  DeliveryFeeService(this._client);

  /// In-memory cache keyed by "restaurantId|roundedLat|roundedLng"
  final Map<String, _CacheEntry> _memCache = {};
  static const _memCacheTtl = Duration(minutes: 5);

  /// Calculates the delivery fee for a restaurant → delivery address pair.
  ///
  /// Tries the Edge Function first, then falls back to client-side haversine
  /// calculation using admin config from [AppConstants].
  Future<DeliveryFeeResult?> calculate({
    required String restaurantId,
    required double deliveryLatitude,
    required double deliveryLongitude,
    double? restaurantLatitude,
    double? restaurantLongitude,
    double? restaurantDeliveryFee,
    bool skipCache = false,
  }) async {
    // ── In-memory cache ──────────────────────────────────────────────────────
    final cacheKey = _cacheKey(
      restaurantId,
      deliveryLatitude,
      deliveryLongitude,
    );
    if (!skipCache) {
      final mem = _memCache[cacheKey];
      if (mem != null && DateTime.now().isBefore(mem.expiresAt)) {
        return mem.result;
      }
    }

    // ── Local-first: instant calculation using admin config ─────────────────
    // When restaurant coordinates are available, compute locally using the
    // admin pricing loaded into AppConstants at startup (haversine + base/km
    // fees). This avoids waiting for the Edge Function and ensures the fee
    // displays immediately when switching restaurants.
    if (restaurantLatitude != null && restaurantLongitude != null) {
      return _calculateLocal(
        restaurantLatitude: restaurantLatitude,
        restaurantLongitude: restaurantLongitude,
        deliveryLatitude: deliveryLatitude,
        deliveryLongitude: deliveryLongitude,
        restaurantDeliveryFee: restaurantDeliveryFee,
        cacheKey: cacheKey,
      );
    }

    // ── Edge Function fallback (no restaurant coords) ────────────────────────
    try {
      final response = await _client.functions
          .invoke(
            'calculate-delivery-fee',
            body: {
              'restaurant_id': restaurantId,
              'delivery_latitude': deliveryLatitude,
              'delivery_longitude': deliveryLongitude,
              'skip_cache': skipCache,
            },
          )
          .timeout(const Duration(seconds: 4));

      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      if (data['error'] == null) {
        final result = DeliveryFeeResult.fromJson(data);
        _memCache[cacheKey] = _CacheEntry(
          result: result,
          expiresAt: DateTime.now().add(_memCacheTtl),
        );
        return result;
      }
      AppLogger.warning('DeliveryFeeService edge fn: ${data['error']}');
    } catch (e) {
      AppLogger.warning('DeliveryFeeService edge fn error: $e');
    }

    // ── Final fallback: flat fee from admin config ───────────────────────────
    return _calculateLocal(
      restaurantLatitude: null,
      restaurantLongitude: null,
      deliveryLatitude: deliveryLatitude,
      deliveryLongitude: deliveryLongitude,
      restaurantDeliveryFee: restaurantDeliveryFee,
      cacheKey: cacheKey,
    );
  }

  DeliveryFeeResult? _calculateLocal({
    required double? restaurantLatitude,
    required double? restaurantLongitude,
    required double deliveryLatitude,
    required double deliveryLongitude,
    required double? restaurantDeliveryFee,
    required String cacheKey,
  }) {
    final baseFee = AppConstants.deliveryBaseFee;
    // $2.00/mile standard, $2.50/mile peak
    final perMileFee = AppConstants.isPeakHour
        ? AppConstants.deliveryPerMileFeePeak
        : AppConstants.deliveryPerMileFee;
    final baseMiles = AppConstants.deliveryBaseMiles;
    final surge = AppConstants.deliverySurgeMultiplier;
    final driverPayPct = AppConstants.driverPayPercent;
    final minFee = AppConstants.minDeliveryFee;

    // If we have both coordinates, compute distance-based fee
    if (restaurantLatitude != null && restaurantLongitude != null) {
      final distanceKm = haversineKm(
        restaurantLatitude,
        restaurantLongitude,
        deliveryLatitude,
        deliveryLongitude,
      );

      // Reject if beyond admin-configured max distance
      final maxKm = AppConstants.deliveryMaxKm;
      if (distanceKm > maxKm) return null;

      final distRounded = (distanceKm * 10).round() / 10;
      final distanceMiles = distanceKm * 0.621371;
      final extraMiles = math.max(0.0, distanceMiles - baseMiles);
      final rawFee = (baseFee + extraMiles * perMileFee) * surge;
      final finalFee = _round2(math.max(rawFee, minFee));
      final driverPay = _round2(finalFee * driverPayPct);

      final calcType = extraMiles > 0 ? 'distance_based' : 'base_fee';

      final result = DeliveryFeeResult(
        deliveryFee: finalFee,
        driverPay: driverPay,
        platformFee: _round2(finalFee - driverPay),
        driverPayPercent: driverPayPct,
        distanceKm: distRounded,
        distanceMiles: _round2(distanceMiles),
        calculation: calcType,
        surgeMultiplier: surge,
        baseFee: baseFee,
        perKmFee: perMileFee, // per-mile rate (legacy field name)
        baseKm: baseMiles, // base miles (legacy field name)
        extraKm: _round2(extraMiles), // extra miles (legacy field name)
        minFee: minFee,
      );

      _memCache[cacheKey] = _CacheEntry(
        result: result,
        expiresAt: DateTime.now().add(_memCacheTtl),
      );
      return result;
    }

    // No restaurant coordinates — use admin default delivery fee
    final flatFee = _round2(
      math.max(AppConstants.defaultDeliveryFee * surge, minFee),
    );
    final driverPay = _round2(flatFee * driverPayPct);

    final result = DeliveryFeeResult(
      deliveryFee: flatFee,
      driverPay: driverPay,
      platformFee: _round2(flatFee - driverPay),
      driverPayPercent: driverPayPct,
      calculation: 'flat_fee',
      surgeMultiplier: surge,
      minFee: minFee,
    );

    _memCache[cacheKey] = _CacheEntry(
      result: result,
      expiresAt: DateTime.now().add(_memCacheTtl),
    );
    return result;
  }

  /// Haversine distance in km between two lat/lng points.
  static double haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _deg2rad(double deg) => deg * math.pi / 180;
  static double _round2(double n) => (n * 100).round() / 100;

  /// Clears the in-memory fee cache. Useful after admin changes pricing.
  void clearCache() => _memCache.clear();

  /// Returns the client-side fallback fee if the edge function is unreachable.
  static double get fallbackFee => AppConstants.defaultDeliveryFee;

  String _cacheKey(String rid, double lat, double lng) {
    // Round to 4 decimal places (~11 m precision) to match server-side rounding
    final rLat = (lat * 10000).round() / 10000;
    final rLng = (lng * 10000).round() / 10000;
    return '$rid|$rLat|$rLng';
  }
}

class _CacheEntry {
  final DeliveryFeeResult result;
  final DateTime expiresAt;
  const _CacheEntry({required this.result, required this.expiresAt});
}
