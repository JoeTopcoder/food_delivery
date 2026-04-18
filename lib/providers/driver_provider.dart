import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../services/driver_service.dart';
import '../services/notification_service.dart';
import '../config/supabase_config.dart';
import '../utils/app_logger.dart';

// Driver Service Provider
final driverServiceProvider = Provider<DriverService>((ref) {
  return DriverService(SupabaseConfig.client);
});

// Driver Profile Provider
final driverProfileProvider = FutureProvider.family
    .autoDispose<Driver?, String>((ref, userId) async {
      final driverService = ref.watch(driverServiceProvider);
      return driverService.getDriverByUserId(userId);
    });

// Available Orders Provider (takes driverId to filter out recently declined)
final availableOrdersProvider = FutureProvider.autoDispose
    .family<List<Order>, String?>((ref, driverId) async {
      final driverService = ref.watch(driverServiceProvider);
      return driverService.getAvailableOrders(driverId: driverId);
    });

/// Realtime listener that auto-refreshes available orders for drivers.
final driverOrderRealtimeProvider = Provider.autoDispose<void>((ref) {
  final channel = SupabaseConfig.client
      .channel('driver_available_orders')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        callback: (_) => ref.invalidate(availableOrdersProvider),
      )
      .subscribe();
  ref.onDispose(() => SupabaseConfig.client.removeChannel(channel));
});

// Active Deliveries Provider
final activeDeliveriesProvider = FutureProvider.family
    .autoDispose<List<Order>, String>((ref, driverId) async {
      final driverService = ref.watch(driverServiceProvider);
      return driverService.getActiveDeliveries(driverId);
    });

// Delivery History Provider
final deliveryHistoryProvider = FutureProvider.family
    .autoDispose<List<Order>, String>((ref, driverId) async {
      final driverService = ref.watch(driverServiceProvider);
      return driverService.getDeliveryHistory(driverId);
    });

// Driver Availability State
class DriverAvailabilityNotifier extends StateNotifier<bool> {
  final DriverService _driverService;
  final String _driverId;

  DriverAvailabilityNotifier(this._driverService, this._driverId)
    : super(false);

  Future<void> toggleAvailability() async {
    try {
      final newState = !state;
      await _driverService.updateDriverAvailability(_driverId, newState);
      state = newState;
    } catch (e) {
      rethrow;
    }
  }
}

final driverAvailabilityProvider =
    StateNotifierProvider.family<DriverAvailabilityNotifier, bool, String>((
      ref,
      driverId,
    ) {
      final driverService = ref.watch(driverServiceProvider);
      return DriverAvailabilityNotifier(driverService, driverId);
    });

/// Watches the orders table via Supabase Realtime for new available orders.
/// When a new order appears (INSERT with status ready/pending, or UPDATE to ready
/// with no driver), it shows a local notification and invalidates availableOrdersProvider.
final newOrderRealtimeProvider = Provider.autoDispose<void>((ref) {
  final channel = SupabaseConfig.client.realtime.channel('driver_new_orders');

  channel.onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: 'orders',
    callback: (payload) {
      final record = payload.newRecord;
      final status = record['status'] as String?;
      final driverId = record['driver_id'];

      if (driverId == null && (status == 'ready' || status == 'pending')) {
        AppLogger.info('Realtime: new available order detected');
        // Show in-app local notification
        NotificationService().showNotification(
          title: 'New Order Available! 🍔',
          body: 'A new delivery order is waiting for you.',
          data: {'type': 'new_order', 'order_id': record['id'] ?? ''},
        );
        // Refresh the available orders list
        ref.invalidate(availableOrdersProvider);
        // Fire the callback (e.g. to play a sound or update badge)
        NotificationService.onNewOrderReceived?.call();
      }
    },
  );

  channel.onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'orders',
    callback: (payload) {
      final record = payload.newRecord;
      final oldRecord = payload.oldRecord;
      final newStatus = record['status'] as String?;
      final oldStatus = oldRecord['status'] as String?;
      final driverId = record['driver_id'];

      // Order just became ready (restaurant marked it) and no driver yet
      if (newStatus == 'ready' && oldStatus != 'ready' && driverId == null) {
        AppLogger.info('Realtime: order became ready for pickup');
        NotificationService().showNotification(
          title: 'Order Ready for Pickup! 📦',
          body: 'A restaurant order is ready and needs a driver.',
          data: {'type': 'new_order', 'order_id': record['id'] ?? ''},
        );
        ref.invalidate(availableOrdersProvider);
        NotificationService.onNewOrderReceived?.call();
      }

      // An order was claimed by another driver — refresh list
      if (driverId != null && oldRecord['driver_id'] == null) {
        ref.invalidate(availableOrdersProvider);
      }
    },
  );

  channel.subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
    AppLogger.info('Realtime: driver_new_orders channel disposed');
  });
});
