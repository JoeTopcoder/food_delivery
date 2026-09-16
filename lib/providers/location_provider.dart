import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  final s = LocationService(Supabase.instance.client);
  ref.onDispose(s.dispose);
  return s;
});

/// One-shot fetch of the device's current GPS position (null if unavailable /
/// permission denied). Used to center driver-facing maps on the driver.
final currentPositionProvider = FutureProvider.autoDispose<Position?>((ref) {
  return ref.watch(locationServiceProvider).getCurrentPosition();
});

/// Whether the driver is currently broadcasting GPS.
final isTrackingProvider = StateProvider<bool>((ref) => false);

/// Stream of the driver's live location map from Supabase.
final driverLocationStreamProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, driverId) {
      return ref.watch(locationServiceProvider).watchDriverLocation(driverId);
    });

/// Stream of a specific order's real-time status from Supabase.
final orderRealtimeStreamProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, orderId) {
      return ref.watch(locationServiceProvider).watchOrder(orderId);
    });
