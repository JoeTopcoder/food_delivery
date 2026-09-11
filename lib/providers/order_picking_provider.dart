import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/pick_model.dart';
import '../services/order_picking_service.dart';

final orderPickingServiceProvider = Provider<OrderPickingService>((ref) {
  return OrderPickingService(SupabaseConfig.client);
});

/// The pick list for one order. Refreshes in real time when the order's items
/// change, so a second picker's progress (or a manual edit) shows up live.
final pickListProvider = FutureProvider.family
    .autoDispose<List<PickLine>, String>((ref, orderId) {
      final channel = Supabase.instance.client.realtime.channel(
        'pick_list_$orderId',
      );
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'order_items',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'order_id',
              value: orderId,
            ),
            callback: (_) => ref.invalidateSelf(),
          )
          .subscribe();
      ref.onDispose(
        () => Supabase.instance.client.realtime.removeChannel(channel),
      );

      return ref.watch(orderPickingServiceProvider).getPickList(orderId);
    });
