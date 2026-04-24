import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

class LocationService {
  final SupabaseClient _client;
  StreamSubscription<Position>? _positionSub;
  String? _activeDriverId;
  String? _activeOrderId;
  DateTime? _lastPushTime;

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
            distanceFilter: 40, // push every 40 m — reduces writes ~4× vs 10 m
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
    // Throttle: skip if last push was less than 5 seconds ago
    final now = DateTime.now();
    if (_lastPushTime != null && now.difference(_lastPushTime!).inSeconds < 5) {
      return;
    }
    _lastPushTime = now;
    try {
      await _client.from('driver_locations').upsert({
        'driver_id': _activeDriverId,
        'order_id': _activeOrderId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'heading': pos.heading,
        'speed': pos.speed,
        'updated_at': now.toIso8601String(),
      }, onConflict: 'driver_id');
    } catch (e) {
      AppLogger.error('Push location error: $e');
    }
  }

  /// Stream of the driver's live location using channel-based Realtime.
  /// Emits the current row immediately (initial fetch), then on every change.
  Stream<Map<String, dynamic>?> watchDriverLocation(String driverId) {
    final controller = StreamController<Map<String, dynamic>?>();
    RealtimeChannel? channel;

    Future<void> init() async {
      // Seed with current value so consumers get data immediately
      try {
        final res = await _client
            .from('driver_locations')
            .select()
            .eq('driver_id', driverId)
            .maybeSingle();
        if (!controller.isClosed) controller.add(res);
      } catch (_) {}

      channel = _client
          .channel('driver_loc_$driverId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'driver_locations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'driver_id',
              value: driverId,
            ),
            callback: (payload) {
              if (!controller.isClosed) {
                controller.add(
                  payload.newRecord.isNotEmpty ? payload.newRecord : null,
                );
              }
            },
          )
          .subscribe();
    }

    init();
    controller.onCancel = () {
      if (channel != null) _client.removeChannel(channel!);
      controller.close();
    };
    return controller.stream;
  }

  /// Watch a specific order row for status changes via filtered Realtime channel.
  /// Emits the current row immediately (initial fetch), then on every change.
  Stream<Map<String, dynamic>?> watchOrder(String orderId) {
    final controller = StreamController<Map<String, dynamic>?>();
    RealtimeChannel? channel;

    Future<void> init() async {
      // Seed with current value so consumers get data immediately
      try {
        final res = await _client
            .from('orders')
            .select()
            .eq('id', orderId)
            .maybeSingle();
        if (!controller.isClosed) controller.add(res);
      } catch (_) {}

      channel = _client
          .channel('order_watch_$orderId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: orderId,
            ),
            callback: (payload) {
              if (!controller.isClosed) {
                controller.add(
                  payload.newRecord.isNotEmpty ? payload.newRecord : null,
                );
              }
            },
          )
          .subscribe();
    }

    init();
    controller.onCancel = () {
      if (channel != null) _client.removeChannel(channel!);
      controller.close();
    };
    return controller.stream;
  }

  bool get isTracking => _positionSub != null;

  void dispose() {
    _positionSub?.cancel();
  }
}
