import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_logger.dart';

class SurgeService {
  final SupabaseClient _client;
  SurgeService(this._client);

  // Get current surge multiplier for a location
  Future<double> getSurgeMultiplier({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final zones = await _client
          .from('surge_zones')
          .select()
          .eq('is_active', true)
          .or('ends_at.is.null,ends_at.gt.$now');

      AppLogger.info(
        'Surge query for ($latitude, $longitude): ${zones.length} active zone(s)',
      );

      double maxMultiplier = 1.0;
      for (final zone in (zones as List)) {
        final lat = (zone['latitude'] as num).toDouble();
        final lng = (zone['longitude'] as num).toDouble();
        final radius = (zone['radius_km'] as num).toDouble();
        final multiplier = (zone['multiplier'] as num).toDouble();

        final distance = _haversine(latitude, longitude, lat, lng);
        AppLogger.info(
          'Zone "${zone['name']}": dist=${distance.toStringAsFixed(2)} km, '
          'radius=$radius km, multiplier=$multiplier '
          '→ ${distance > radius ? "OUTSIDE ZONE – SURGE" : "inside zone – no surge"}',
        );
        if (distance > radius && multiplier > maxMultiplier) {
          maxMultiplier = multiplier;
        }
      }
      AppLogger.info('Surge multiplier result: $maxMultiplier');
      return maxMultiplier;
    } catch (e) {
      AppLogger.error('Error fetching surge: $e');
      return 1.0;
    }
  }

  // Admin: create surge zone
  Future<bool> createSurgeZone({
    required String name,
    required double latitude,
    required double longitude,
    required double radiusKm,
    required double multiplier,
    String? reason,
    DateTime? endsAt,
  }) async {
    try {
      await _client.from('surge_zones').insert({
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius_km': radiusKm,
        'multiplier': multiplier,
        'is_active': true,
        'reason': reason,
        if (endsAt != null) 'ends_at': endsAt.toIso8601String(),
      });
      return true;
    } catch (e) {
      AppLogger.error('Error creating surge zone: $e');
      return false;
    }
  }

  // Admin: get all surge zones
  Future<List<Map<String, dynamic>>> getAllSurgeZones() async {
    try {
      final response = await _client
          .from('surge_zones')
          .select()
          .order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.error('Error fetching surge zones: $e');
      return [];
    }
  }

  // Admin: toggle surge zone
  Future<bool> toggleSurgeZone(String zoneId, bool isActive) async {
    try {
      await _client
          .from('surge_zones')
          .update({'is_active': isActive})
          .eq('id', zoneId);
      return true;
    } catch (e) {
      AppLogger.error('Error toggling surge zone: $e');
      return false;
    }
  }

  // Admin: delete surge zone
  Future<bool> deleteSurgeZone(String zoneId) async {
    try {
      await _client.from('surge_zones').delete().eq('id', zoneId);
      return true;
    } catch (e) {
      AppLogger.error('Error deleting surge zone: $e');
      return false;
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRad(double deg) => deg * pi / 180;
}
