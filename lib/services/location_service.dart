import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

class LocationService {
  final SupabaseClient _client;
  StreamSubscription<Position>? _positionSub;
  String? _activeDriverId;
  String? _activeOrderId;

  LocationService(this._client);

  Future<bool> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      final ok = await requestPermission();
      if (!ok) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      AppLogger.error('Get position error: $e');
      return null;
    }
  }

  Future<void> startTracking({
    required String driverId,
    String? orderId,
  }) async {
    final ok = await requestPermission();
    if (!ok) {
      AppLogger.warning('Location permission denied');
      return;
    }
    _activeDriverId = driverId;
    _activeOrderId = orderId;
    await _positionSub?.cancel();

    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen(
          (pos) => _push(pos),
          onError: (e) => AppLogger.error('Location stream error: $e'),
        );
    AppLogger.info('Location tracking started');
  }

  Future<void> stopTracking() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _activeDriverId = null;
    _activeOrderId = null;
    AppLogger.info('Location tracking stopped');
  }

  Future<void> _push(Position pos) async {
    if (_activeDriverId == null) return;
    try {
      await _client.from('driver_locations').upsert({
        'driver_id': _activeDriverId,
        'order_id': _activeOrderId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'heading': pos.heading,
        'speed': pos.speed,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'driver_id');
    } catch (e) {
      AppLogger.error('Push location error: $e');
    }
  }

  /// Stream of the driver's live location row from Supabase Realtime.
  Stream<Map<String, dynamic>?> watchDriverLocation(String driverId) {
    return _client
        .from('driver_locations')
        .stream(primaryKey: ['driver_id'])
        .eq('driver_id', driverId)
        .map((rows) => rows.isEmpty ? null : rows.first);
  }

  /// Watch a specific order row for status changes.
  Stream<Map<String, dynamic>?> watchOrder(String orderId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) => rows.isEmpty ? null : rows.first);
  }

  bool get isTracking => _positionSub != null;

  void dispose() {
    _positionSub?.cancel();
  }
}
