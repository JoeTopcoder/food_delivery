import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../services/driver/driver_service.dart';
import '../services/notification_service.dart';
import '../config/supabase_config.dart';
import '../config/app_constants.dart';
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

/// Fetches a driver's public display info (name, photo) by drivers.id.
/// Used on the customer order tracking screen to show who is delivering.
final driverPublicInfoProvider = FutureProvider.autoDispose
    .family<Map<String, String?>, String>((ref, driverId) async {
      final response = await SupabaseConfig.client
          .from('drivers')
          .select('users!inner(name, profile_image_url)')
          .eq('id', driverId)
          .single();
      final user = response['users'] as Map<String, dynamic>? ?? {};
      return {
        'name': user['name'] as String?,
        'profileImageUrl': user['profile_image_url'] as String?,
      };
    });

// Available Orders Provider (takes driverId + driver location for 2km proximity filter)
final availableOrdersProvider = FutureProvider.autoDispose
    .family<List<Order>, ({String? driverId, double? lat, double? lng})>((
      ref,
      params,
    ) async {
      final driverService = ref.watch(driverServiceProvider);
      return driverService.getAvailableOrders(
        driverId: params.driverId,
        driverLat: params.lat,
        driverLng: params.lng,
      );
    });

/// Realtime listener that auto-refreshes available orders for drivers.
/// Filtered to INSERT events with status 'ready' — avoids broadcasting
/// every platform-wide order mutation to every connected driver.
final driverOrderRealtimeProvider = Provider.autoDispose<void>((ref) {
  final channel = SupabaseConfig.client
      .channel('driver_available_orders')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'status',
          value: 'ready',
        ),
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

/// Active multi-restaurant delivery tasks for a driver.
/// Returns tasks with status 'assigned' or 'in_progress', with all stops.
final activeDeliveryTasksProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, driverId) async {
      final rows = await SupabaseConfig.client
          .from('delivery_tasks')
          .select('''
            id, order_group_id, delivery_status, driver_earning,
            total_distance_km, estimated_duration_minutes,
            delivery_stops(
              id, stop_type, sequence_number, status, address,
              latitude, longitude, restaurant_id, order_id,
              arrived_at, completed_at
            ),
            order_groups(customer_id, delivery_address)
          ''')
          .eq('driver_id', driverId)
          .inFilter('delivery_status', ['assigned', 'in_progress'])
          .order('created_at');
      return (rows as List).cast<Map<String, dynamic>>();
    });

/// Realtime listener for delivery_tasks — invalidates activeDeliveryTasksProvider
/// whenever the driver's task is inserted or updated (e.g. newly assigned).
final deliveryTaskRealtimeProvider =
    Provider.autoDispose.family<void, String>((ref, driverId) {
  final channel = SupabaseConfig.client
      .channel('driver_tasks_$driverId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'delivery_tasks',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'driver_id',
          value: driverId,
        ),
        callback: (payload) {
          AppLogger.info('Realtime: delivery task change for driver $driverId');
          ref.invalidate(activeDeliveryTasksProvider(driverId));
          // Only show a local notification on INSERT (new assignment)
          if (payload.eventType == PostgresChangeEvent.insert) {
            NotificationService().showNotification(
              title: 'New Multi-Stop Delivery! 🛵',
              body: 'You have been assigned a multi-restaurant delivery.',
              data: {'type': 'new_multi_delivery'},
            );
            NotificationService.onNewOrderReceived?.call();
          }
        },
      )
      .subscribe();

  ref.onDispose(() => SupabaseConfig.client.removeChannel(channel));
});

/// Realtime listener that auto-refreshes driver earnings data.
/// Watches:
/// - `drivers` table for profile changes (cash_float, total_paid_out, rating)
/// - `orders` table for completed deliveries (new earnings, tips)
final driverEarningsRealtimeProvider = Provider.autoDispose.family<void, String>((
  ref,
  driverId,
) {
  final client = SupabaseConfig.client;

  // Watch driver profile changes (cash_float, total_paid_out, rating, etc.)
  final driverChannel = client
      .channel('driver_profile_$driverId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: AppConstants.tableDrivers,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: driverId,
        ),
        callback: (_) {
          AppLogger.info(
            'Realtime: driver profile updated — refreshing earnings',
          );
          // Find the userId for this driver to invalidate the profile provider
          final userId = client.auth.currentUser?.id;
          if (userId != null) {
            ref.invalidate(driverProfileProvider(userId));
          }
        },
      )
      .subscribe();

  // Watch orders table for this driver (new deliveries, status changes, tips)
  final ordersChannel = client
      .channel('driver_orders_$driverId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: AppConstants.tableOrders,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'driver_id',
          value: driverId,
        ),
        callback: (_) {
          AppLogger.info(
            'Realtime: driver orders changed — refreshing history',
          );
          ref.invalidate(deliveryHistoryProvider(driverId));
          ref.invalidate(activeDeliveriesProvider(driverId));
        },
      )
      .subscribe();

  ref.onDispose(() {
    client.removeChannel(driverChannel);
    client.removeChannel(ordersChannel);
  });
});

// Driver Availability State
class DriverAvailabilityNotifier extends StateNotifier<bool> {
  final DriverService _driverService;
  final String _driverId;

  DriverAvailabilityNotifier(
    this._driverService,
    this._driverId, {
    bool initialState = false,
  }) : super(initialState);

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
      // Seed the availability state from the cached driver profile if available
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      bool initialAvailable = false;
      if (userId != null) {
        final cachedDriver = ref
            .read(driverProfileProvider(userId))
            .valueOrNull;
        if (cachedDriver != null && cachedDriver.id == driverId) {
          initialAvailable = cachedDriver.isAvailable;
        }
      }
      return DriverAvailabilityNotifier(
        driverService,
        driverId,
        initialState: initialAvailable,
      );
    });

// ── Verification document providers ───────────────────────────────────────────

final driverVerificationDocsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, driverId) async {
      final driverService = ref.watch(driverServiceProvider);
      return driverService.getVerificationDocuments(driverId);
    });

// Fetches drivers pending admin review (driver_status IN pending_review, under_review)
final pendingVerificationDriversProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final response = await SupabaseConfig.client
          .from('drivers')
          .select('*, users!inner(name, email)')
          .inFilter('driver_status', ['pending_review', 'under_review'])
          .order('submitted_at', ascending: true);
      return List<Map<String, dynamic>>.from(response as List);
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
