import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/delivery_region_model.dart';
import '../services/delivery_region_service.dart';

final deliveryRegionServiceProvider = Provider<DeliveryRegionService>((ref) {
  return DeliveryRegionService(Supabase.instance.client);
});

/// All regions (admin view) — refreshes in real time via Supabase Realtime.
final allRegionsProvider = FutureProvider<List<DeliveryRegion>>((ref) {
  final channel = Supabase.instance.client.realtime.channel(
    'regions_all_${DateTime.now().microsecondsSinceEpoch}',
  );
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

/// Active regions only (used for the customer zone check) — also real time.
final activeRegionsProvider = FutureProvider<List<DeliveryRegion>>((ref) {
  final channel = Supabase.instance.client.realtime.channel(
    'regions_active_${DateTime.now().microsecondsSinceEpoch}',
  );
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
