import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod_pkg;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/admin_service.dart';
import '../services/notification_service.dart';
import '../config/supabase_config.dart';
import '../utils/app_logger.dart';
import '../models/user_model.dart' as user_models;
import '../models/restaurant_model.dart';
import '../models/driver_model.dart';

/// Admin service provider
final adminServiceProvider = riverpod_pkg.Provider<AdminService>((ref) {
  final supabase = Supabase.instance.client;
  return AdminService(supabase);
});

// ==================== USER PROVIDERS ====================

/// All users provider
final allUsersProvider =
    riverpod_pkg.FutureProvider.family<
      List<user_models.User>,
      (int offset, int limit)
    >((ref, params) async {
      final adminService = ref.watch(adminServiceProvider);
      final (offset, limit) = params;
      return adminService.getAllUsers(offset: offset, limit: limit);
    });

/// Users search provider
final userSearchProvider =
    riverpod_pkg.FutureProvider.family<List<user_models.User>, String>((
      ref,
      query,
    ) async {
      final adminService = ref.watch(adminServiceProvider);
      return adminService.searchUsers(query);
    });

/// Users by role provider
final usersByRoleProvider =
    riverpod_pkg.FutureProvider.family<List<user_models.User>, String>((
      ref,
      role,
    ) async {
      final adminService = ref.watch(adminServiceProvider);
      return adminService.getUsersByRole(role);
    });

/// User statistics provider
final userStatisticsProvider =
    riverpod_pkg.FutureProvider<Map<String, dynamic>>((ref) async {
      final adminService = ref.watch(adminServiceProvider);
      return adminService.getUserStatistics();
    });

// ==================== RESTAURANT PROVIDERS ====================

/// All restaurants provider
final allRestaurantsAdminProvider =
    riverpod_pkg.FutureProvider.family<
      List<Restaurant>,
      (int offset, int limit)
    >((ref, params) async {
      final adminService = ref.watch(adminServiceProvider);
      final (offset, limit) = params;
      return adminService.getAllRestaurants(offset: offset, limit: limit);
    });

/// Pending restaurants provider
final pendingRestaurantsProvider =
    riverpod_pkg.FutureProvider<List<Restaurant>>((ref) async {
      final adminService = ref.watch(adminServiceProvider);
      return adminService.getPendingVerificationRestaurants();
    });

/// Restaurant statistics provider
final restaurantStatisticsProvider =
    riverpod_pkg.FutureProvider<Map<String, dynamic>>((ref) async {
      final adminService = ref.watch(adminServiceProvider);
      return adminService.getRestaurantStatistics();
    });

// ==================== DRIVER PROVIDERS ====================

/// All drivers provider
final allDriversAdminProvider =
    riverpod_pkg.FutureProvider.family<List<Driver>, (int offset, int limit)>((
      ref,
      params,
    ) async {
      final adminService = ref.watch(adminServiceProvider);
      final (offset, limit) = params;
      return adminService.getAllDrivers(offset: offset, limit: limit);
    });

/// Pending drivers provider
final pendingDriversProvider = riverpod_pkg.FutureProvider<List<Driver>>((
  ref,
) async {
  final adminService = ref.watch(adminServiceProvider);
  return adminService.getPendingDrivers();
});

/// Driver statistics provider
final driverStatisticsProvider =
    riverpod_pkg.FutureProvider<Map<String, dynamic>>((ref) async {
      final adminService = ref.watch(adminServiceProvider);
      return adminService.getDriverStatistics();
    });

// ==================== ANALYTICS PROVIDERS ====================

/// Revenue statistics provider
final revenueStatisticsProvider =
    riverpod_pkg.FutureProvider<Map<String, dynamic>>((ref) async {
      final adminService = ref.watch(adminServiceProvider);
      return adminService.getRevenueStatistics();
    });

/// Order statistics provider
final orderStatisticsProvider =
    riverpod_pkg.FutureProvider<Map<String, dynamic>>((ref) async {
      final adminService = ref.watch(adminServiceProvider);
      return adminService.getOrderStatistics();
    });

/// Dashboard summary provider
final dashboardSummaryProvider =
    riverpod_pkg.FutureProvider<Map<String, dynamic>>((ref) async {
      final adminService = ref.watch(adminServiceProvider);
      return adminService.getDashboardSummary();
    });

/// Financial statistics provider
final financialStatisticsProvider =
    riverpod_pkg.FutureProvider<Map<String, dynamic>>((ref) async {
      final adminService = ref.watch(adminServiceProvider);
      return adminService.getFinancialStatistics();
    });

// ==================== DISPUTE PROVIDERS ====================

/// Pending disputes provider
final pendingDisputesProvider =
    riverpod_pkg.FutureProvider<List<Map<String, dynamic>>>((ref) async {
      final adminService = ref.watch(adminServiceProvider);
      return adminService.getPendingDisputes();
    });

// ==================== REALTIME NOTIFICATIONS ====================

/// Watches the orders table via Supabase Realtime for any new orders.
/// Notifies admin in-app whenever a customer places an order.
final adminNewOrderRealtimeProvider = riverpod_pkg.Provider.autoDispose<void>((
  ref,
) {
  final channel = SupabaseConfig.client.realtime.channel('admin_new_orders');

  channel.onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: 'orders',
    callback: (payload) {
      final record = payload.newRecord;
      final orderId = record['id'] ?? '';
      final shortId = orderId.toString().length >= 8
          ? orderId.toString().substring(0, 8).toUpperCase()
          : orderId.toString().toUpperCase();
      final status = record['status'] as String?;

      AppLogger.info(
        'Admin Realtime: new order #$shortId placed (status: $status)',
      );
      NotificationService().showNotification(
        title: 'New Order Placed! 🛒',
        body: 'Order #$shortId has been placed by a customer.',
        data: {'type': 'new_order_admin', 'order_id': orderId.toString()},
      );
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(orderStatisticsProvider);
      NotificationService.onNewOrderForAdmin?.call();
    },
  );

  channel.subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
    AppLogger.info('Admin Realtime: admin_new_orders channel disposed');
  });
});
