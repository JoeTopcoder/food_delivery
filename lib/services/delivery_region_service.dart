import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/delivery_region_model.dart';

class DeliveryRegionService {
  final SupabaseClient _client;
  DeliveryRegionService(this._client);

  // ── CRUD ──────────────────────────────────────────────────────────────

  Future<List<DeliveryRegion>> getAll() async {
    final res = await _client
        .from('delivery_regions')
        .select()
        .order('name', ascending: true);
    return (res as List).map((e) => DeliveryRegion.fromJson(e)).toList();
  }

  Future<List<DeliveryRegion>> getActive() async {
    final res = await _client
        .from('delivery_regions')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);
    return (res as List).map((e) => DeliveryRegion.fromJson(e)).toList();
  }

  Future<DeliveryRegion> create({
    required String name,
    required double latitude,
    required double longitude,
    double radiusKm = 10.0,
    List<LatLng>? polygon,
  }) async {
    final res = await _client
        .from('delivery_regions')
        .insert({
          'name': name,
          'latitude': latitude,
          'longitude': longitude,
          'radius_km': radiusKm,
          'is_active': true,
          if (polygon != null && polygon.length >= 3)
            'polygon': polygon
                .map((p) => {'lat': p.latitude, 'lng': p.longitude})
                .toList(),
        })
        .select()
        .single();
    return DeliveryRegion.fromJson(res);
  }

  Future<void> update(String id, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await _client.from('delivery_regions').update(data).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('delivery_regions').delete().eq('id', id);
  }

  // ── Geo check ─────────────────────────────────────────────────────────

  /// Returns `true` when [lat]/[lng] falls inside **at least one** active
  /// region.  If there are no active regions at all, delivery is allowed
  /// everywhere (fail-open so existing setups keep working).
  Future<bool> isInsideActiveRegion(double lat, double lng) async {
    final regions = await getActive();
    if (regions.isEmpty) return true; // no regions configured → allow all
    return regions.any((r) {
      if (r.hasPolygon) {
        return _pointInPolygon(lat, lng, r.polygon!);
      }
      return _haversineKm(lat, lng, r.latitude, r.longitude) <= r.radiusKm;
    });
  }

  /// Ray-casting point-in-polygon test.
  static bool _pointInPolygon(double lat, double lng, List<LatLng> polygon) {
    bool inside = false;
    final n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].latitude, yi = polygon[i].longitude;
      final xj = polygon[j].latitude, yj = polygon[j].longitude;
      final intersect =
          ((yi > lng) != (yj > lng)) &&
          (lat < (xj - xi) * (lng - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// Haversine distance in km between two lat/lng points.
  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _deg2rad(double deg) => deg * (pi / 180);
}
