import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'address_provider.dart';
import 'location_provider.dart';

/// A restaurant surfaced in the premium "HotBite Now" fast-prep section.
/// Backed by the `get_hotbite_now_restaurants` RPC — all fields are real
/// Supabase data, no mock values.
class HotBiteNowRestaurant {
  final String id;
  final String name;
  final String? imageUrl;
  final String? cuisineType;
  final double rating;
  final int reviewCount;

  /// Restaurant-committed prep time (minutes) — the headline promise.
  final int prepMinutes;

  /// Standard delivery estimate (minutes), if the restaurant sets one.
  final int? estimatedDeliveryMinutes;

  /// Observed average confirmed→ready minutes over the last 30 days (may be
  /// null when there is not enough history). Used for internal/admin insight.
  final double? avgPrepMinutes;

  /// Distance from the customer in km, when a location was available.
  final double? distanceKm;

  const HotBiteNowRestaurant({
    required this.id,
    required this.name,
    this.imageUrl,
    this.cuisineType,
    required this.rating,
    required this.reviewCount,
    required this.prepMinutes,
    this.estimatedDeliveryMinutes,
    this.avgPrepMinutes,
    this.distanceKm,
  });

  factory HotBiteNowRestaurant.fromJson(Map<String, dynamic> j) {
    double? asDouble(dynamic v) =>
        v == null ? null : (v as num).toDouble();
    return HotBiteNowRestaurant(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'Restaurant',
      imageUrl: j['image_url'] as String?,
      cuisineType: j['cuisine_type'] as String?,
      rating: asDouble(j['rating']) ?? 0.0,
      reviewCount: (j['review_count'] as num?)?.toInt() ?? 0,
      prepMinutes: (j['hotbite_now_prep_minutes'] as num?)?.toInt() ?? 15,
      estimatedDeliveryMinutes:
          (j['estimated_delivery_time'] as num?)?.toInt(),
      avgPrepMinutes: asDouble(j['avg_prep_minutes']),
      distanceKm: asDouble(j['distance_km']),
    );
  }

  /// Customer-facing "get it in ~X min" estimate: committed prep plus the
  /// delivery leg when known, otherwise prep alone.
  int get totalEtaMinutes => prepMinutes + (estimatedDeliveryMinutes ?? 0);
}

/// Eligibility-filtered HotBite Now feed for the customer home screen.
/// Passes the customer's coordinates so the RPC can distance-filter; falls
/// back to a location-agnostic feed when no position is available.
final hotBiteNowRestaurantsProvider =
    FutureProvider.autoDispose<List<HotBiteNowRestaurant>>((ref) async {
  // Prefer the customer's selected delivery address — that's the location the
  // rest of the home feed is keyed to. Fall back to device GPS, then to a
  // location-agnostic feed. Never let a location error hide the section.
  double? lat;
  double? lng;

  final address = ref.watch(selectedAddressProvider);
  if (address?.latitude != null && address?.longitude != null) {
    lat = address!.latitude;
    lng = address.longitude;
  } else {
    try {
      final position = await ref.watch(currentPositionProvider.future);
      lat = position?.latitude;
      lng = position?.longitude;
    } catch (_) {
      // ignore — fall through to a location-agnostic feed
    }
  }

  final params = <String, dynamic>{
    'p_lat': lat,
    'p_lng': lng,
    'p_radius_km': 15.0,
    'p_limit': 15,
  };

  try {
    final res = await Supabase.instance.client
        .rpc('get_hotbite_now_restaurants', params: params);
    final list = (res as List?) ?? const [];
    return list
        .map((e) => HotBiteNowRestaurant.fromJson(
            Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (_) {
    // Never break the home screen if the feed fails — just show nothing.
    return const [];
  }
});
