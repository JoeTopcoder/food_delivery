import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/delivery_region_model.dart';
import '../services/driver/delivery_region_service.dart';

final deliveryRegionServiceProvider = Provider<DeliveryRegionService>((ref) {
  return DeliveryRegionService(Supabase.instance.client);
});

/// All regions (admin view) — refreshes in real time via Supabase Realtime.
final allRegionsProvider = FutureProvider.autoDispose<List<DeliveryRegion>>((ref) {
  final channel = Supabase.instance.client.realtime.channel('regions_all');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'delivery_regions',
        callback: (_) => ref.invalidateSelf(),
      )
      .subscribe();
  ref.onDispose(() => Supabase.instance.client.realtime.removeChannel(channel));

  return ref.watch(deliveryRegionServiceProvider).getAll();
});

/// Tax settings for a delivery lat/lng — keyed as "lat|lng".
/// Returns (taxEnabled, taxRate) for the matching zone.
final zoneTaxProvider = FutureProvider.autoDispose
    .family<({bool taxEnabled, double taxRate}), String>((ref, key) async {
  final parts = key.split('|');
  final lat = double.parse(parts[0]);
  final lng = double.parse(parts[1]);
  return ref
      .watch(deliveryRegionServiceProvider)
      .getTaxForLocation(lat, lng);
});

/// Whether a delivery lat/lng falls inside an active delivery zone — keyed as
/// "lat|lng". Used to block checkout for addresses outside the served area.
/// Returns true when no zones are configured (delivery is open everywhere).
final addressInZoneProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, key) async {
  final parts = key.split('|');
  final lat = double.tryParse(parts[0]);
  final lng = double.tryParse(parts.length > 1 ? parts[1] : '');
  if (lat == null || lng == null) return false; // no coordinates → not serviceable
  return ref.watch(deliveryRegionServiceProvider).isInsideActiveRegion(lat, lng);
});

/// Active regions only (used for the customer zone check) — also real time.
final activeRegionsProvider = FutureProvider.autoDispose<List<DeliveryRegion>>((ref) {
  ref.keepAlive();
  final channel = Supabase.instance.client.realtime.channel('regions_active');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'delivery_regions',
        callback: (_) => ref.invalidateSelf(),
      )
      .subscribe();
  ref.onDispose(() => Supabase.instance.client.realtime.removeChannel(channel));

  return ref.watch(deliveryRegionServiceProvider).getActive();
});
