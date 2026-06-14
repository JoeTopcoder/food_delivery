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

  static String _sanitizeQuery(String q) =>
      q.replaceAll(RegExp(r'[%_(),.\\]'), '');

  /// Less aggressive sanitizer for admin lookups — keeps . @ + - needed for
  /// emails and phone numbers, only strips PostgREST wildcards.
  static String _sanitizeLookup(String q) =>
      q.replaceAll(RegExp(r'[%_\\]'), '');

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
          .or(
            'email.ilike.%${_sanitizeQuery(query)}%,name.ilike.%${_sanitizeQuery(query)}%',
          )
          .limit(50);
      return (response as List)
          .map((user) => user_models.User.fromJson(user))
          .toList();
    } catch (e) {
      AppLogger.error('Error searching users: $e');
      return [];
    }
  }

  /// Get users by role (capped at 500 — use getAllUsers with pagination for full lists)
  Future<List<user_models.User>> getUsersByRole(String role) async {
    try {
      AppLogger.info('Fetching users by role: $role');

      final response = await _supabaseClient
          .from(AppConstants.tableUsers)
          .select()
          .eq('role', role)
          .order('created_at', ascending: false)
          .limit(500);

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

  /// Ban/unban user – uses a server-side RPC that guarantees exactly one row
  /// is updated, verifies admin permissions, and prevents self-ban.
  Future<void> toggleUserStatus(String userId, bool isActive) async {
    try {
      if (userId.isEmpty) {
        throw Exception('User ID cannot be empty');
      }
      AppLogger.info(
        'Toggling user status via RPC: userId=$userId -> isActive=$isActive',
      );

      final updatedId = await _supabaseClient.rpc(
        'admin_toggle_user_status',
        params: {'p_user_id': userId, 'p_is_active': isActive},
      );

      AppLogger.info(
        'User status updated successfully: returned id=$updatedId',
      );
    } catch (e) {
      AppLogger.error('Error toggling user status for $userId: $e');
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
          .neq('status', 'rejected')
          .order('created_at', ascending: true)
          .limit(200);

      final restaurants = (response as List)
          .map((rest) => Restaurant.fromJson(rest))
          .toList();

      return restaurants;
    } catch (e) {
      AppLogger.error('Error fetching pending restaurants: $e');
      return [];
    }
  }

  /// Get restaurants that were rejected by admin
  Future<List<Restaurant>> getRejectedRestaurants() async {
    try {
      AppLogger.info('Fetching rejected restaurants');

      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .eq('is_verified', false)
          .eq('status', 'rejected')
          .order('updated_at', ascending: false)
          .limit(200);

      return (response as List).map((r) => Restaurant.fromJson(r)).toList();
    } catch (e) {
      AppLogger.error('Error fetching rejected restaurants: $e');
      return [];
    }
  }

  /// Verify/reject restaurant via the admin-verify-restaurant Edge Function,
  /// which uses the service_role key to bypass RLS on the restaurants table.
  Future<void> verifyRestaurant(String restaurantId, bool isVerified) async {
    AppLogger.info('Verifying restaurant: $restaurantId -> $isVerified');

    final session = _supabaseClient.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    final res = await http.post(
      Uri.parse(
        '${AppConstants.supabaseFunctionsBaseUrl}/admin-verify-restaurant',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${session.accessToken}',
      },
      body: jsonEncode({
        'restaurant_id': restaurantId,
        'is_verified': isVerified,
      }),
    );

    AppLogger.info(
      'verifyRestaurant response: ${res.statusCode} ${res.body}',
    );

    if (res.statusCode == 404) {
      // Edge Function not deployed yet — fall back to direct update
      AppLogger.info('Edge function not found, using direct update');
      await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .update({'is_verified': isVerified})
          .eq('id', restaurantId);
      return;
    }

    if (res.statusCode != 200) {
      Map<String, dynamic> responseBody = {};
      try {
        responseBody = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      throw Exception(
        responseBody['error'] as String? ??
            'HTTP ${res.statusCode}: ${res.body}',
      );
    }

    AppLogger.info('Restaurant verification updated via Edge Function');
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

  // Update restaurant service fee (pickup fee)
  Future<void> updateRestaurantServiceFee(
    String restaurantId,
    double serviceFee,
  ) async {
    try {
      AppLogger.info(
        'Updating service fee for restaurant $restaurantId to $serviceFee',
      );

      await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .update({'service_fee': serviceFee})
          .eq('id', restaurantId);

      AppLogger.info('Service fee updated');
    } catch (e) {
      AppLogger.error('Error updating service fee: $e');
      rethrow;
    }
  }

  // ==================== RESTAURANT ADS ====================

  /// Get all ads (optionally filtered by restaurant)
  Future<List<Map<String, dynamic>>> getRestaurantAds({
    String? restaurantId,
  }) async {
    try {
      PostgrestFilterBuilder query = _supabaseClient
          .from('restaurant_ads')
          .select('*, restaurants(name, image_url, cuisine_type)');

      if (restaurantId != null) {
        query = query.eq('restaurant_id', restaurantId);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(500);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      AppLogger.error('Error fetching restaurant ads: $e');
      rethrow;
    }
  }

  /// Get only active ads (for customer-facing display)
  Future<List<Map<String, dynamic>>> getActiveAds() async {
    try {
      final response = await _supabaseClient
          .from('restaurant_ads')
          .select('*, restaurants(name, image_url, cuisine_type)')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      AppLogger.error('Error fetching active ads: $e');
      rethrow;
    }
  }

  /// Create a new ad for a restaurant
  Future<void> createRestaurantAd({
    required String restaurantId,
    required String title,
    String? description,
    String? imageUrl,
    DateTime? endsAt,
  }) async {
    try {
      AppLogger.info('Creating ad for restaurant $restaurantId');
      await _supabaseClient.from('restaurant_ads').insert({
        'restaurant_id': restaurantId,
        'title': title,
        if (description != null) 'description': description,
        if (imageUrl != null) 'image_url': imageUrl,
        if (endsAt != null) 'ends_at': endsAt.toIso8601String(),
      });
      AppLogger.info('Ad created');
    } catch (e) {
      AppLogger.error('Error creating ad: $e');
      rethrow;
    }
  }

  /// Toggle ad active/inactive
  Future<void> toggleAdActive(String adId, bool isActive) async {
    try {
      await _supabaseClient
          .from('restaurant_ads')
          .update({'is_active': isActive})
          .eq('id', adId);
    } catch (e) {
      AppLogger.error('Error toggling ad: $e');
      rethrow;
    }
  }

  /// Delete an ad
  Future<void> deleteRestaurantAd(String adId) async {
    try {
      await _supabaseClient.from('restaurant_ads').delete().eq('id', adId);
    } catch (e) {
      AppLogger.error('Error deleting ad: $e');
      rethrow;
    }
  }

  /// Get financial statistics for admin dashboard — uses DB-side aggregates
  /// to avoid fetching millions of order rows into Flutter memory.
  Future<Map<String, dynamic>> getFinancialStatistics() async {
    try {
      AppLogger.info('Fetching financial statistics via RPC');

      final result = await _supabaseClient.rpc('get_financial_statistics');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      // Fallback: return empty map if RPC not yet deployed
      return {};
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

  /// Get drivers pending admin review (submitted but not yet approved/rejected)
  Future<List<Driver>> getPendingDrivers() async {
    try {
      AppLogger.info('Fetching drivers pending verification');
      final response = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .select()
          .inFilter('driver_status', ['pending_review', 'under_review', 'draft'])
          .order('created_at', ascending: true)
          .limit(200);
      return (response as List).map((d) => Driver.fromJson(d)).toList();
    } catch (e) {
      AppLogger.error('Error fetching pending drivers: $e');
      return [];
    }
  }

  /// Get approved/verified drivers
  Future<List<Driver>> getApprovedDrivers() async {
    try {
      AppLogger.info('Fetching approved drivers');
      final response = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .select()
          .eq('driver_status', 'approved')
          .order('approved_at', ascending: false)
          .limit(200);
      return (response as List).map((d) => Driver.fromJson(d)).toList();
    } catch (e) {
      AppLogger.error('Error fetching approved drivers: $e');
      return [];
    }
  }

  /// Get drivers that were rejected by admin
  Future<List<Driver>> getRejectedDrivers() async {
    try {
      AppLogger.info('Fetching rejected drivers');
      final response = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .select()
          .eq('driver_status', 'rejected')
          .order('updated_at', ascending: false)
          .limit(200);
      return (response as List).map((d) => Driver.fromJson(d)).toList();
    } catch (e) {
      AppLogger.error('Error fetching rejected drivers: $e');
      return [];
    }
  }

  /// Approve or reject a driver — updates driver_status, is_verified, and
  /// is_food_driver_approved so the driver can immediately go online if approved.
  Future<void> verifyDriver(String driverId, bool approve) async {
    try {
      AppLogger.info('verifyDriver: $driverId approve=$approve');
      final now = DateTime.now().toIso8601String();
      await _supabaseClient.from(AppConstants.tableDrivers).update(
        approve
            ? {
                'driver_status': 'approved',
                'is_verified': true,
                'is_food_driver_approved': true,
                'approved_at': now,
                'updated_at': now,
              }
            : {
                'driver_status': 'rejected',
                'is_verified': false,
                'is_food_driver_approved': false,
                'updated_at': now,
              },
      ).eq('id', driverId);
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
          .select('total_amount, delivery_fee, commission_amount, status')
          .eq('status', 'delivered');

      double totalRevenue = 0;
      double totalDeliveryFees = 0;
      double totalPlatformFees = 0;
      for (var order in response as List) {
        totalRevenue += (order['total_amount'] ?? 0).toDouble();
        totalDeliveryFees += (order['delivery_fee'] ?? 0).toDouble();
        totalPlatformFees += (order['commission_amount'] ?? 0).toDouble();
      }

      return {
        'total_revenue': totalRevenue,
        'platform_fees': totalPlatformFees,
        'delivery_fees': totalDeliveryFees,
        'avg_order_value': response.isNotEmpty
            ? totalRevenue / response.length
            : 0.0,
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

      final results = await Future.wait([
        _supabaseClient.from(AppConstants.tableOrders).select('id').count(),
        _supabaseClient.from(AppConstants.tableOrders).select('id').eq('status', 'delivered').count(),
        _supabaseClient.from(AppConstants.tableOrders).select('id').eq('status', 'cancelled').count(),
        _supabaseClient.from(AppConstants.tableOrders).select('id').eq('status', 'pending').count(),
        _supabaseClient.from(AppConstants.tableOrders).select('id')
            .inFilter('status', ['confirmed', 'preparing', 'ready', 'picked_up', 'out_for_delivery', 'on_the_way']).count(),
      ]);

      final totalOrders = results[0].count;
      final deliveredOrders = results[1].count;
      final cancelledOrders = results[2].count;
      final pendingOrders = results[3].count;
      final activeOrders = results[4].count;

      return {
        'total_orders': totalOrders,
        'delivered_orders': deliveredOrders,
        'cancelled_orders': cancelledOrders,
        'pending_orders': pendingOrders,
        'active_orders': activeOrders,
      };
    } catch (e) {
      AppLogger.error('Error fetching order stats: $e');
      return {};
    }
  }

  /// Get dashboard summary — nested map consumed by AdminDashboardScreen.
  Future<Map<String, dynamic>> getDashboardSummary() async {
    try {
      AppLogger.info('Fetching dashboard summary');

      final monthStart = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        1,
      ).toIso8601String();

      // Map stats — all Future<Map<String, dynamic>>
      final stats = await Future.wait<Map<String, dynamic>>([
        getUserStatistics(),
        getRestaurantStatistics(),
        getDriverStatistics(),
        getOrderStatistics(),
        getRevenueStatistics(),
      ]);

      // Count queries (different return type) + monthly revenue list
      final countResults = await Future.wait([
        _supabaseClient.from('laundry_bookings').select('id').count(),
        _supabaseClient
            .from('laundry_bookings')
            .select('id')
            .inFilter('status', ['confirmed', 'picked_up', 'in_progress', 'out_for_delivery'])
            .count(),
        _supabaseClient.from('car_service_bookings').select('id').count(),
        _supabaseClient
            .from('car_service_bookings')
            .select('id')
            .inFilter('status', ['confirmed', 'in_progress'])
            .count(),
        _supabaseClient.from('ride_requests').select('id').count(),
        _supabaseClient
            .from('ride_requests')
            .select('id')
            .inFilter('status', ['accepted', 'arrived', 'started'])
            .count(),
      ]);

      final monthlyOrdersResp = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('total_amount')
          .eq('status', 'delivered')
          .gte('ordered_at', monthStart);

      final users   = stats[0];
      final rests   = stats[1];
      final drivers = stats[2];
      final orders  = stats[3];
      final revenue = stats[4];

      double monthlyRevenue = 0;
      for (final o in monthlyOrdersResp as List) {
        monthlyRevenue += ((o['total_amount'] ?? 0) as num).toDouble();
      }

      final totalOrders     = (orders['total_orders']     ?? 0) as int;
      final deliveredOrders = (orders['delivered_orders'] ?? 0) as int;
      final completionRate  = totalOrders > 0
          ? (deliveredOrders / totalOrders * 100)
          : 0.0;

      return {
        'users': {
          'total_users': users['total_users'] ?? 0,
        },
        'restaurants': {
          'total_restaurants': rests['total_restaurants'] ?? 0,
          'pending':           rests['pending']           ?? 0,
        },
        'drivers': {
          'total_drivers': drivers['total_drivers'] ?? 0,
          'pending':       drivers['pending']       ?? 0,
        },
        'orders': {
          'total_orders':   orders['total_orders']  ?? 0,
          'active_orders':  orders['active_orders'] ?? 0,
          'completion_rate': completionRate,
        },
        'revenue': {
          'total_revenue':   revenue['total_revenue'] ?? 0.0,
          'monthly_revenue': monthlyRevenue,
        },
        'laundry': {
          'total_bookings':  countResults[0].count,
          'active_bookings': countResults[1].count,
        },
        'car_services': {
          'total_bookings':  countResults[2].count,
          'active_bookings': countResults[3].count,
        },
        'rides': {
          'total_rides':  countResults[4].count,
          'active_rides': countResults[5].count,
        },
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
  /// Creates a user with role via the admin-create-user Edge Function.
  /// The service_role key stays server-side — never in client code.
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

    final session = _supabaseClient.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    final res = await http.post(
      Uri.parse('${AppConstants.supabaseFunctionsBaseUrl}/admin-create-user'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${session.accessToken}',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'name': name,
        'role': role,
        'vehicleType': vehicleType,
        'vehicleNumber': vehicleNumber,
        'licenseNumber': licenseNumber,
        'restaurantName': restaurantName,
        'cuisineType': cuisineType,
        'address': address,
        'phone': phone,
      }),
    );

    if (res.statusCode != 200) {
      final body = jsonDecode(res.body);
      throw Exception(body['error'] ?? 'Failed to create user');
    }

    final userId = jsonDecode(res.body)['user_id'] as String;
    AppLogger.info('$role account created: $userId');
    return userId;
  }

  // ==================== DATABASE LOOKUP ====================

  /// Calls the admin-lookup Edge Function. service_role key stays server-side.
  Future<dynamic> _edgeLookup(String action, String query) async {
    final session = _supabaseClient.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    final res = await http.post(
      Uri.parse('${AppConstants.supabaseFunctionsBaseUrl}/admin-lookup'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${session.accessToken}',
      },
      body: jsonEncode({'action': action, 'query': query}),
    );

    if (res.statusCode != 200) {
      final body = jsonDecode(res.body);
      throw Exception(body['error'] ?? 'Lookup failed');
    }

    return jsonDecode(res.body);
  }

  /// Lookup by card last-four digits.
  Future<List<Map<String, dynamic>>> lookupByCard(String lastFour) async {
    try {
      final sanitized = _sanitizeLookup(lastFour).replaceAll(RegExp(r'\D'), '');
      if (sanitized.isEmpty) return [];
      AppLogger.info('Admin lookup by card ending: $sanitized');
      final result = await _edgeLookup('card', sanitized);
      return (result as List).cast<Map<String, dynamic>>();
    } catch (e) {
      AppLogger.error('Error in card lookup: $e');
      return [];
    }
  }

  /// Lookup by order ID (full or partial).
  Future<Map<String, dynamic>?> lookupByOrderId(String orderId) async {
    try {
      final sanitized = _sanitizeLookup(orderId).trim();
      if (sanitized.isEmpty) return null;
      AppLogger.info('Admin lookup by order ID: $sanitized');
      final result = await _edgeLookup('order', sanitized);
      if (result == null) return null;
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      AppLogger.error('Error in order lookup: $e');
      return null;
    }
  }

  /// Lookup by customer email or phone.
  Future<Map<String, dynamic>?> lookupByCustomer(String query) async {
    try {
      final sanitized = _sanitizeLookup(query).trim();
      if (sanitized.isEmpty) return null;
      AppLogger.info('Admin customer lookup: $sanitized');
      final result = await _edgeLookup('customer', sanitized);
      if (result == null) return null;
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      AppLogger.error('Error in customer lookup: $e');
      return null;
    }
  }
}
