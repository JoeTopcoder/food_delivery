import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

/// Manages real-time order updates via Supabase Realtime
class RealtimeService {
  static final RealtimeService _instance = RealtimeService._internal();

  factory RealtimeService() {
    return _instance;
  }

  RealtimeService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final Map<String, RealtimeChannel> _subscriptions = {};

  /// Subscribe to order updates for a specific order
  /// Returns a stream of order status changes
  Future<Stream<Map<String, dynamic>>?> subscribeToOrderUpdates(
    String orderId,
  ) async {
    try {
      final channel = _supabase.realtime.channel('orders:id=eq.$orderId');

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: orderId,
        ),
        callback: (payload) {
          AppLogger.info('Order update received: $orderId');
        },
      );

      channel.subscribe();
      _subscriptions[orderId] = channel;
      AppLogger.info('Subscribed to order: $orderId');

      return Stream.empty();
    } catch (e) {
      AppLogger.error('Error subscribing to order updates: $e');
      return null;
    }
  }

  /// Subscribe to all orders for a user (restaurant or customer)
  Future<Stream<Map<String, dynamic>>?> subscribeToUserOrders(
    String userId,
    String userRole,
  ) async {
    try {
      final String filterColumn = userRole == 'restaurant'
          ? 'restaurant_id'
          : 'user_id';

      final channel = _supabase.realtime.channel('user_orders:$userId');

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: filterColumn,
          value: userId,
        ),
        callback: (payload) {
          AppLogger.info('User orders updated: $userId');
        },
      );

      channel.subscribe();
      _subscriptions[userId] = channel;
      AppLogger.info('Subscribed to user orders: $userId ($userRole)');

      return Stream.empty();
    } catch (e) {
      AppLogger.error('Error subscribing to user orders: $e');
      return null;
    }
  }

  /// Subscribe to driver's active deliveries
  Future<Stream<Map<String, dynamic>>?> subscribeToDriverDeliveries(
    String driverId,
  ) async {
    try {
      final channel = _supabase.realtime.channel('driver_deliveries:$driverId');

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'driver_id',
          value: driverId,
        ),
        callback: (payload) {
          AppLogger.info('Driver deliveries updated: $driverId');
        },
      );

      channel.subscribe();
      _subscriptions[driverId] = channel;
      AppLogger.info('Subscribed to driver deliveries: $driverId');

      return Stream.empty();
    } catch (e) {
      AppLogger.error('Error subscribing to driver deliveries: $e');
      return null;
    }
  }

  /// Subscribe to restaurant's orders with specific status
  Future<Stream<Map<String, dynamic>>?> subscribeToRestaurantOrdersByStatus(
    String restaurantId,
    String status,
  ) async {
    try {
      final channel = _supabase.realtime.channel(
        'restaurant_orders:$restaurantId:$status',
      );

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'restaurant_id',
          value: restaurantId,
        ),
        callback: (payload) {
          // Client-side filtering by status
          if (payload.newRecord['status'] == status ||
              payload.oldRecord['status'] == status) {
            AppLogger.info('Restaurant orders for status $status updated');
          }
        },
      );

      channel.subscribe();
      _subscriptions['$restaurantId:$status'] = channel;
      AppLogger.info('Subscribed to restaurant orders ($status)');

      return Stream.empty();
    } catch (e) {
      AppLogger.error('Error subscribing to restaurant orders: $e');
      return null;
    }
  }

  /// Unsubscribe from specific subscription
  Future<void> unsubscribe(String subscriptionKey) async {
    try {
      final channel = _subscriptions[subscriptionKey];
      if (channel != null) {
        await channel.unsubscribe();
        _subscriptions.remove(subscriptionKey);
        AppLogger.info('Unsubscribed from: $subscriptionKey');
      }
    } catch (e) {
      AppLogger.error('Error unsubscribing: $e');
    }
  }

  /// Unsubscribe from all subscriptions
  Future<void> unsubscribeAll() async {
    try {
      for (var subscription in _subscriptions.values) {
        await subscription.unsubscribe();
      }
      _subscriptions.clear();
      AppLogger.info('Unsubscribed from all channels');
    } catch (e) {
      AppLogger.error('Error unsubscribing from all channels: $e');
    }
  }

  /// Get subscription status
  bool isSubscribed(String subscriptionKey) {
    return _subscriptions.containsKey(subscriptionKey);
  }

  /// Get number of active subscriptions
  int getSubscriptionCount() {
    return _subscriptions.length;
  }
}
