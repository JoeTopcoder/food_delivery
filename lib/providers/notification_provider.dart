import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';
import '../services/realtime_service.dart';

/// Notification model for displaying in UI
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  bool isRead;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.timestamp,
    this.isRead = false,
  });

  AppNotification copyWith({
    String? id,
    String? type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return AppNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }
}

/// Notification service provider
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

/// Realtime service provider
final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  return RealtimeService();
});

/// Notifications list state notifier
class NotificationNotifier extends StateNotifier<List<AppNotification>> {
  NotificationNotifier() : super([]);

  /// Add notification
  void addNotification(AppNotification notification) {
    state = [notification, ...state];
  }

  /// Mark notification as read
  void markAsRead(String notificationId) {
    state = state.map((notification) {
      if (notification.id == notificationId) {
        return notification.copyWith(isRead: true);
      }
      return notification;
    }).toList();
  }

  /// Remove notification
  void removeNotification(String notificationId) {
    state = state
        .where((notification) => notification.id != notificationId)
        .toList();
  }

  /// Clear all notifications
  void clearAll() {
    state = [];
  }

  /// Get unread count
  int getUnreadCount() {
    return state.where((notification) => !notification.isRead).length;
  }
}

/// Notifications state provider
final notificationNotifierProvider =
    StateNotifierProvider<NotificationNotifier, List<AppNotification>>((ref) {
      return NotificationNotifier();
    });

/// Unread notification count provider
final unreadNotificationCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationNotifierProvider);
  return notifications.where((notification) => !notification.isRead).length;
});

/// Initialize notification service provider
final initNotificationProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(notificationServiceProvider);
  await service.initialize();
});

/// Subscribe to order updates (example usage)
final orderUpdatesStreamProvider =
    StreamProvider.family<Map<String, dynamic>, String>((ref, orderId) async* {
      final realtimeService = ref.watch(realtimeServiceProvider);
      final stream = await realtimeService.subscribeToOrderUpdates(orderId);

      if (stream != null) {
        yield* stream;
      }
    });

/// Subscribe to user orders (example usage)
final userOrdersStreamProvider =
    StreamProvider.family<
      Map<String, dynamic>,
      (String userId, String userRole)
    >((ref, params) async* {
      final realtimeService = ref.watch(realtimeServiceProvider);
      final (userId, userRole) = params;
      final stream = await realtimeService.subscribeToUserOrders(
        userId,
        userRole,
      );

      if (stream != null) {
        yield* stream;
      }
    });

/// Subscribe to driver deliveries (example usage)
final driverDeliveriesStreamProvider =
    StreamProvider.family<Map<String, dynamic>, String>((ref, driverId) async* {
      final realtimeService = ref.watch(realtimeServiceProvider);
      final stream = await realtimeService.subscribeToDriverDeliveries(
        driverId,
      );

      if (stream != null) {
        yield* stream;
      }
    });
