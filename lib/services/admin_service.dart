import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../models/user_model.dart' as user_models;
import '../models/restaurant_model.dart';
import '../models/driver_model.dart';
import '../utils/app_logger.dart';

/// Admin service for dashboard and management
class AdminService {
  final SupabaseClient _supabaseClient;

  AdminService(this._supabaseClient);

  // ==================== USER MANAGEMENT ====================

  /// Get all users with pagination
  Future<List<user_models.User>> getAllUsers({
    int offset = 0,
    int limit = 20,
  }) async {
    try {
      AppLogger.info('Fetching all users: offset=$offset, limit=$limit');

      final response = await _supabaseClient
          .from(AppConstants.tableUsers)
          .select()
          .range(offset, offset + limit - 1)
          .order('created_at', ascending: false);

      final users = (response as List)
          .map((user) => user_models.User.fromJson(user))
          .toList();

      AppLogger.info('Fetched ${users.length} users');
      return users;
    } catch (e) {
      AppLogger.error('Error fetching users: $e');
      rethrow;
    }
  }

  /// Search users by email/name
  Future<List<user_models.User>> searchUsers(String query) async {
    try {
      AppLogger.info('Searching users: $query');
      final response = await _supabaseClient
          .from(AppConstants.tableUsers)
          .select()
          .or('email.ilike.%$query%,name.ilike.%$query%')
          .limit(50);
      return (response as List)
          .map((user) => user_models.User.fromJson(user))
          .toList();
    } catch (e) {
      AppLogger.error('Error searching users: $e');
      return [];
    }
  }

  /// Get users by role
  Future<List<user_models.User>> getUsersByRole(String role) async {
    try {
      AppLogger.info('Fetching users by role: $role');

      final response = await _supabaseClient
          .from(AppConstants.tableUsers)
          .select()
          .eq('role', role)
          .order('created_at', ascending: false);

      final users = (response as List)
          .map((user) => user_models.User.fromJson(user))
          .toList();

      return users;
    } catch (e) {
      AppLogger.error('Error fetching users by role: $e');
      return [];
    }
  }

  /// Get user statistics
  Future<Map<String, dynamic>> getUserStatistics() async {
    try {
      AppLogger.info('Fetching user statistics');

      // Count all users
      final allUsersResponse = await _supabaseClient
          .from(AppConstants.tableUsers)
          .select('*')
          .count();
      final userCount = allUsersResponse.count;

      // Count restaurants
      final restaurantsResponse = await _supabaseClient
          .from(AppConstants.tableUsers)
          .select('*')
          .eq('role', 'restaurant')
          .count();
      final restaurantCount = restaurantsResponse.count;

      // Count drivers
      final driversResponse = await _supabaseClient
          .from(AppConstants.tableUsers)
          .select('*')
          .eq('role', 'driver')
          .count();
      final driverCount = driversResponse.count;

      final customerCount = userCount - restaurantCount - driverCount;

      return {
        'total_users': userCount,
        'restaurants': restaurantCount,
        'drivers': driverCount,
        'customers': customerCount,
      };
    } catch (e) {
      AppLogger.error('Error fetching user statistics: $e');
      return {};
    }
  }

  /// Ban/unban user
  Future<void> toggleUserStatus(String userId, bool isActive) async {
    try {
      AppLogger.info('Toggling user status: $userId -> $isActive');

      await _supabaseClient
          .from(AppConstants.tableUsers)
          .update({'is_active': isActive})
          .eq('id', userId);

      AppLogger.info('User status updated');
    } catch (e) {
      AppLogger.error('Error toggling user status: $e');
      rethrow;
    }
  }

  // ==================== RESTAURANT MANAGEMENT ====================

  /// Get all restaurants
  Future<List<Restaurant>> getAllRestaurants({
    int offset = 0,
    int limit = 20,
  }) async {
    try {
      AppLogger.info('Fetching all restaurants: offset=$offset, limit=$limit');

      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .range(offset, offset + limit - 1)
          .order('created_at', ascending: false);

      final restaurants = (response as List)
          .map((rest) => Restaurant.fromJson(rest))
          .toList();

      return restaurants;
    } catch (e) {
      AppLogger.error('Error fetching restaurants: $e');
      return [];
    }
  }

  /// Get restaurants pending verification
  Future<List<Restaurant>> getPendingVerificationRestaurants() async {
    try {
      AppLogger.info('Fetching restaurants pending verification');

      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .eq('is_verified', false)
          .order('created_at', ascending: true);

      final restaurants = (response as List)
          .map((rest) => Restaurant.fromJson(rest))
          .toList();

      return restaurants;
    } catch (e) {
      AppLogger.error('Error fetching pending restaurants: $e');
      return [];
    }
  }

  /// Verify/reject restaurant
  Future<void> verifyRestaurant(String restaurantId, bool isVerified) async {
    try {
      AppLogger.info('Verifying restaurant: $restaurantId -> $isVerified');

      await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .update({'is_verified': isVerified})
          .eq('id', restaurantId);

      AppLogger.info('Restaurant verification updated');
    } catch (e) {
      AppLogger.error('Error verifying restaurant: $e');
      rethrow;
    }
  }

  /// Update commission rate for a restaurant
  Future<void> updateRestaurantCommission(
    String restaurantId,
    double commissionRate,
  ) async {
    try {
      AppLogger.info(
        'Updating commission for restaurant $restaurantId to $commissionRate',
      );

      await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .update({'commission_rate': commissionRate})
          .eq('id', restaurantId);

      AppLogger.info('Commission rate updated');
    } catch (e) {
      AppLogger.error('Error updating commission: $e');
      rethrow;
    }
  }

  /// Get financial statistics for admin dashboard
  Future<Map<String, dynamic>> getFinancialStatistics() async {
    try {
      AppLogger.info('Fetching financial statistics');

      // Get all delivered orders with commission data
      final orders = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select(
            'total_amount, commission_amount, commission_rate, delivery_fee, driver_tip, restaurant_id, driver_id, status',
          )
          .eq('status', 'delivered');

      double totalSales = 0;
      double totalCommission = 0;
      double totalDeliveryFees = 0;
      double totalDriverTips = 0;
      final Map<String, double> restaurantPayouts = {};
      final Map<String, double> driverPayouts = {};

      for (var order in orders as List) {
        final amount = (order['total_amount'] ?? 0).toDouble();
        final commission = (order['commission_amount'] ?? 0).toDouble();
        final deliveryFee = (order['delivery_fee'] ?? 0).toDouble();
        final driverTip = (order['driver_tip'] ?? 0).toDouble();
        final restaurantId = order['restaurant_id'] as String?;
        final driverId = order['driver_id'] as String?;

        totalSales += amount;
        totalCommission += commission;
        totalDeliveryFees += deliveryFee;
        totalDriverTips += driverTip;

        // Restaurant payout = order total - commission - delivery fee
        if (restaurantId != null) {
          restaurantPayouts[restaurantId] =
              (restaurantPayouts[restaurantId] ?? 0) +
              (amount - commission - deliveryFee);
        }

        // Driver payout = delivery fee + tips
        if (driverId != null) {
          driverPayouts[driverId] =
              (driverPayouts[driverId] ?? 0) + deliveryFee + driverTip;
        }
      }

      final totalRestaurantPayout = restaurantPayouts.values.fold(
        0.0,
        (a, b) => a + b,
      );
      final totalDriverPayout = driverPayouts.values.fold(0.0, (a, b) => a + b);

      // Monthly stats
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
      final monthlyOrders = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('total_amount, commission_amount, delivery_fee, driver_tip')
          .eq('status', 'delivered')
          .gte('ordered_at', monthStart);

      double monthlySales = 0;
      double monthlyCommission = 0;
      for (var order in monthlyOrders as List) {
        monthlySales += (order['total_amount'] ?? 0).toDouble();
        monthlyCommission += (order['commission_amount'] ?? 0).toDouble();
      }

      return {
        'total_sales': totalSales,
        'total_commission': totalCommission,
        'total_delivery_fees': totalDeliveryFees,
        'total_driver_tips': totalDriverTips,
        'total_restaurant_payout': totalRestaurantPayout,
        'total_driver_payout': totalDriverPayout,
        'monthly_sales': monthlySales,
        'monthly_commission': monthlyCommission,
        'order_count': (orders as List).length,
      };
    } catch (e) {
      AppLogger.error('Error fetching financial stats: $e');
      return {};
    }
  }

  /// Get restaurant statistics
  Future<Map<String, dynamic>> getRestaurantStatistics() async {
    try {
      AppLogger.info('Fetching restaurant statistics');

      final totalResponse = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select('*')
          .count();
      final totalCount = totalResponse.count;

      final verifiedResponse = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select('*')
          .eq('is_verified', true)
          .count();
      final verifiedCount = verifiedResponse.count;

      return {
        'total_restaurants': totalCount,
        'verified': verifiedCount,
        'pending': totalCount - verifiedCount,
      };
    } catch (e) {
      AppLogger.error('Error fetching restaurant stats: $e');
      return {};
    }
  }

  // ==================== DRIVER MANAGEMENT ====================

  /// Get all drivers
  Future<List<Driver>> getAllDrivers({int offset = 0, int limit = 20}) async {
    try {
      AppLogger.info('Fetching all drivers: offset=$offset, limit=$limit');

      final response = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .select()
          .range(offset, offset + limit - 1)
          .order('created_at', ascending: false);

      final drivers = (response as List)
          .map((driver) => Driver.fromJson(driver))
          .toList();

      return drivers;
    } catch (e) {
      AppLogger.error('Error fetching drivers: $e');
      return [];
    }
  }

  /// Get drivers pending verification
  Future<List<Driver>> getPendingDrivers() async {
    try {
      AppLogger.info('Fetching drivers pending verification');

      final response = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .select()
          .eq('is_verified', false)
          .order('created_at', ascending: true);

      final drivers = (response as List)
          .map((driver) => Driver.fromJson(driver))
          .toList();

      return drivers;
    } catch (e) {
      AppLogger.error('Error fetching pending drivers: $e');
      return [];
    }
  }

  /// Verify/reject driver
  Future<void> verifyDriver(String driverId, bool isVerified) async {
    try {
      AppLogger.info('Verifying driver: $driverId -> $isVerified');

      await _supabaseClient
          .from(AppConstants.tableDrivers)
          .update({'is_verified': isVerified})
          .eq('id', driverId);

      AppLogger.info('Driver verification updated');
    } catch (e) {
      AppLogger.error('Error verifying driver: $e');
      rethrow;
    }
  }

  /// Get driver statistics
  Future<Map<String, dynamic>> getDriverStatistics() async {
    try {
      AppLogger.info('Fetching driver statistics');

      final totalResponse = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .select('*')
          .count();
      final totalCount = totalResponse.count;

      final verifiedResponse = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .select('*')
          .eq('is_verified', true)
          .count();
      final verifiedCount = verifiedResponse.count;

      final activeResponse = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .select('*')
          .eq('is_available', true)
          .count();
      final activeCount = activeResponse.count;

      return {
        'total_drivers': totalCount,
        'verified': verifiedCount,
        'pending': totalCount - verifiedCount,
        'active': activeCount,
      };
    } catch (e) {
      AppLogger.error('Error fetching driver stats: $e');
      return {};
    }
  }

  // ==================== ORDER & ANALYTICS ====================

  /// Get revenue statistics
  Future<Map<String, dynamic>> getRevenueStatistics() async {
    try {
      AppLogger.info('Fetching revenue statistics');

      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('total_amount, status')
          .eq('status', 'delivered');

      double totalRevenue = 0;
      for (var order in response as List) {
        totalRevenue += (order['total_amount'] ?? 0).toDouble();
      }

      // Monthly revenue — current calendar month only, delivered orders
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
      final monthly = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('total_amount')
          .eq('status', 'delivered')
          .gte('ordered_at', monthStart);

      double monthlyRevenue = 0;
      for (var order in monthly as List) {
        monthlyRevenue += (order['total_amount'] ?? 0).toDouble();
      }

      return {
        'total_revenue': totalRevenue,
        'monthly_revenue': monthlyRevenue,
        'average_order_value': totalRevenue > 0
            ? totalRevenue / response.length
            : 0,
      };
    } catch (e) {
      AppLogger.error('Error fetching revenue stats: $e');
      return {};
    }
  }

  /// Get order statistics
  Future<Map<String, dynamic>> getOrderStatistics() async {
    try {
      AppLogger.info('Fetching order statistics');

      final totalResponse = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('*')
          .count();
      final totalOrders = totalResponse.count;

      final completedResponse = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('*')
          .eq('status', 'delivered')
          .count();
      final completedOrders = completedResponse.count;

      final pendingResponse = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('*')
          .eq('status', 'pending')
          .count();
      final pendingOrders = pendingResponse.count;

      return {
        'total_orders': totalOrders,
        'completed': completedOrders,
        'pending': pendingOrders,
        'completion_rate': totalOrders > 0
            ? (completedOrders / totalOrders) * 100
            : 0,
      };
    } catch (e) {
      AppLogger.error('Error fetching order stats: $e');
      return {};
    }
  }

  /// Get dashboard summary
  Future<Map<String, dynamic>> getDashboardSummary() async {
    try {
      AppLogger.info('Fetching dashboard summary');

      final userStats = await getUserStatistics();
      final restaurantStats = await getRestaurantStatistics();
      final driverStats = await getDriverStatistics();
      final orderStats = await getOrderStatistics();
      final revenueStats = await getRevenueStatistics();

      return {
        'users': userStats,
        'restaurants': restaurantStats,
        'drivers': driverStats,
        'orders': orderStats,
        'revenue': revenueStats,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      AppLogger.error('Error fetching dashboard summary: $e');
      return {};
    }
  }

  // ==================== DISPUTE MANAGEMENT ====================

  /// Get pending disputes
  Future<List<Map<String, dynamic>>> getPendingDisputes() async {
    try {
      AppLogger.info('Fetching pending disputes');

      final response = await _supabaseClient
          .from('disputes')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      AppLogger.error('Error fetching disputes: $e');
      return [];
    }
  }

  /// Resolve dispute
  Future<void> resolveDispute({
    required String disputeId,
    required String resolution,
    required String notes,
  }) async {
    try {
      AppLogger.info('Resolving dispute: $disputeId');

      await _supabaseClient
          .from('disputes')
          .update({
            'status': 'resolved',
            'resolution': resolution,
            'notes': notes,
            'resolved_at': DateTime.now().toIso8601String(),
          })
          .eq('id', disputeId);

      AppLogger.info('Dispute resolved');
    } catch (e) {
      AppLogger.error('Error resolving dispute: $e');
      rethrow;
    }
  }

  // ==================== ADMIN USER CREATION ====================

  /// Admin creates a user account with a specific role (driver or restaurant).
  /// Uses the Supabase Admin Auth API (service role key) to create confirmed
  /// users without sending emails, avoiding free-tier email rate limits.
  Future<String> createUserWithRole({
    required String email,
    required String password,
    required String name,
    required String role,
    // Driver-specific
    String vehicleType = 'motorcycle',
    String vehicleNumber = '',
    String licenseNumber = '',
    // Restaurant-specific
    String restaurantName = '',
    String cuisineType = '',
    String address = '',
    String phone = '',
  }) async {
    AppLogger.info('Admin creating $role account for: $email');

    const serviceRoleKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InloYXJ3ZWxpcnVlbWpleG11dXhuIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTQ0MDUxOCwiZXhwIjoyMDkxMDE2NTE4fQ.v-PMGcTny7Nz5PhPCbi6eZfpFJPwRk6eHMTnZEi6KH8';

    // 1. Create auth user via Admin API (no email sent, auto-confirmed)
    final createRes = await http.post(
      Uri.parse('${AppConstants.supabaseUrl}/auth/v1/admin/users'),
      headers: {
        'Content-Type': 'application/json',
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'email_confirm': true,
        'user_metadata': {'name': name, 'role': role},
      }),
    );

    if (createRes.statusCode != 200) {
      final body = jsonDecode(createRes.body);
      throw Exception(
        body['msg'] ?? body['message'] ?? 'Failed to create user',
      );
    }

    final newUserId = jsonDecode(createRes.body)['id'] as String;

    // 2. Use a service-role client so RLS is bypassed for inserts
    final adminClient = SupabaseClient(
      AppConstants.supabaseUrl,
      serviceRoleKey,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );

    try {
      // Allow trigger time to create public.users row
      await Future.delayed(const Duration(milliseconds: 600));

      if (role == AppConstants.roleDriver) {
        await adminClient.from(AppConstants.tableDrivers).insert({
          'user_id': newUserId,
          'vehicle_type': vehicleType.isEmpty ? 'motorcycle' : vehicleType,
          'vehicle_number': vehicleNumber,
          'license_number': licenseNumber,
          'is_verified': false,
          'is_available': false,
          'completed_deliveries': 0,
          'rating': 0.0,
          'documents_status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        });
      } else if (role == AppConstants.roleRestaurant) {
        await adminClient.from(AppConstants.tableRestaurants).insert({
          'owner_id': newUserId,
          'name': restaurantName.isEmpty ? name : restaurantName,
          'cuisine_type': cuisineType.isEmpty ? null : cuisineType,
          'address': address,
          'phone': phone,
          'is_verified': false,
          'is_open': false,
          'rating': 0.0,
          'delivery_fee': 0.0,
          'estimated_delivery_time': 30,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      AppLogger.info('$role account created: $newUserId');
      return newUserId;
    } catch (e) {
      AppLogger.error('Error creating user with role: $e');
      rethrow;
    } finally {
      await adminClient.dispose();
    }
  }
}
