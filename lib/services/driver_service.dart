import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../utils/app_logger.dart';

class DriverService {
  final SupabaseClient _supabaseClient;

  DriverService(this._supabaseClient);

  // Create driver profile
  Future<Driver?> createDriverProfile({
    required String userId,
    String? vehicleType,
    String? vehicleNumber,
    String? licenseNumber,
  }) async {
    try {
      AppLogger.info('Creating driver profile for user: $userId');

      final response = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .insert({
            'user_id': userId,
            'vehicle_type': vehicleType ?? 'motorcycle',
            'vehicle_number': vehicleNumber ?? '',
            'license_number': licenseNumber ?? '',
            'is_available': false,
            'completed_deliveries': 0,
            'rating': 0.0,
            'documents_status': 'pending',
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final driver = Driver.fromJson(response);
      AppLogger.info('Driver profile created successfully');
      return driver;
    } catch (e) {
      AppLogger.error('Error creating driver profile: $e');
      rethrow;
    }
  }

  // Get driver by user ID — auto-creates a profile if none exists
  Future<Driver?> getDriverByUserId(String userId) async {
    try {
      AppLogger.info('Fetching driver profile for user: $userId');

      final response = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null) {
        final driver = Driver.fromJson(response);
        AppLogger.info('Driver profile fetched successfully');
        return driver;
      }

      // No profile found — auto-create one
      AppLogger.info('No driver profile found, creating one for user: $userId');
      final created = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .insert({
            'user_id': userId,
            'vehicle_type': 'motorcycle',
            'vehicle_number': '',
            'license_number': '',
            'is_available': false,
            'completed_deliveries': 0,
            'rating': 0.0,
            'documents_status': 'pending',
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      return Driver.fromJson(created);
    } catch (e) {
      AppLogger.error('Error fetching/creating driver profile: $e');
      rethrow;
    }
  }

  // Update driver profile
  Future<Driver?> updateDriverProfile({
    required String driverId,
    String? vehicleType,
    String? vehicleNumber,
    String? licenseNumber,
  }) async {
    try {
      AppLogger.info('Updating driver profile: $driverId');

      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (vehicleType != null) updateData['vehicle_type'] = vehicleType;
      if (vehicleNumber != null) updateData['vehicle_number'] = vehicleNumber;
      if (licenseNumber != null) updateData['license_number'] = licenseNumber;

      final response = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .update(updateData)
          .eq('id', driverId)
          .select()
          .single();

      final driver = Driver.fromJson(response);
      AppLogger.info('Driver profile updated successfully');
      return driver;
    } catch (e) {
      AppLogger.error('Error updating driver profile: $e');
      rethrow;
    }
  }

  // Update driver availability
  Future<void> updateDriverAvailability(
    String driverId,
    bool isAvailable,
  ) async {
    try {
      AppLogger.info('Updating driver availability: $driverId -> $isAvailable');

      await _supabaseClient
          .from(AppConstants.tableDrivers)
          .update({
            'is_available': isAvailable,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);

      AppLogger.info('Driver availability updated');
    } catch (e) {
      AppLogger.error('Error updating driver availability: $e');
      rethrow;
    }
  }

  // Update driver location via Edge Function (lightweight, low latency)
  Future<void> updateDriverLocation({
    required String driverId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _supabaseClient.functions.invoke(
        'update-driver-location',
        body: {
          'driver_id': driverId,
          'latitude': latitude,
          'longitude': longitude,
        },
      );
    } catch (e) {
      // Fallback to direct DB update if edge function fails
      try {
        await _supabaseClient
            .from(AppConstants.tableDrivers)
            .update({
              'current_latitude': latitude,
              'current_longitude': longitude,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', driverId);
      } catch (e2) {
        AppLogger.error('Error updating driver location: $e2');
        rethrow;
      }
    }
  }

  // Decline an order – hides it from this driver for 5 minutes
  Future<void> declineOrder(String orderId, String driverId) async {
    try {
      await _supabaseClient.from('driver_declined_orders').upsert({
        'driver_id': driverId,
        'order_id': orderId,
        'declined_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'driver_id,order_id');
      AppLogger.info('Driver $driverId declined order $orderId');
    } catch (e) {
      AppLogger.error('Error declining order: $e');
      rethrow;
    }
  }

  // Get available orders for delivery
  // Shows: all "ready" orders + "pending" orders older than 30 minutes (no driver assigned)
  // Excludes orders declined by this driver within the last 5 minutes
  Future<List<Order>> getAvailableOrders({String? driverId}) async {
    try {
      AppLogger.info('Fetching available orders for delivery');

      // Fetch recently declined order IDs for this driver
      Set<String> declinedOrderIds = {};
      if (driverId != null) {
        final fiveMinAgo = DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String();
        final declinedRows = await _supabaseClient
            .from('driver_declined_orders')
            .select('order_id')
            .eq('driver_id', driverId)
            .gte('declined_at', fiveMinAgo);
        declinedOrderIds = (declinedRows as List)
            .map((r) => r['order_id'] as String)
            .toSet();
      }

      final cutoff = DateTime.now()
          .subtract(
            Duration(minutes: AppConstants.orderAssignmentCutoffMinutes),
          )
          .toUtc()
          .toIso8601String();

      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select()
          .filter('driver_id', 'is', null)
          .eq('is_pickup', false)
          .inFilter('status', [
            AppConstants.orderReady,
            AppConstants.orderPreparing,
            AppConstants.orderConfirmed,
            AppConstants.orderPending,
          ])
          .order('ordered_at', ascending: false)
          .limit(20); // fetch extra to account for declined filtering

      final orders = <Order>[];
      for (var orderData in response as List) {
        // Skip orders this driver recently declined
        if (declinedOrderIds.contains(orderData['id'])) continue;

        // Cap at 5 orders per driver
        if (orders.length >= 5) break;

        final itemsResponse = await _supabaseClient
            .from(AppConstants.tableOrderItems)
            .select()
            .eq('order_id', orderData['id']);

        final items = <OrderItem>[];
        for (final itemJson in (itemsResponse as List)) {
          final sidesResponse = await _supabaseClient
              .from(AppConstants.tableOrderItemSides)
              .select()
              .eq('order_item_id', itemJson['id']);
          final sides = (sidesResponse as List)
              .map((s) => OrderItemSide.fromJson(s))
              .toList();
          items.add(
            OrderItem.fromJson({
              ...itemJson,
              'sides': sides.map((s) => s.toJson()).toList(),
            }),
          );
        }

        orders.add(
          Order.fromJson({
            ...orderData,
            'items': items.map((item) => item.toJson()).toList(),
          }),
        );
      }

      AppLogger.info('Fetched ${orders.length} available orders');
      return orders;
    } catch (e) {
      AppLogger.error('Error fetching available orders: $e');
      rethrow;
    }
  }

  // Accept delivery order (atomic – prevents two drivers claiming the same order)
  Future<bool> acceptDelivery(String orderId, String driverId) async {
    try {
      AppLogger.info('Accepting delivery for order: $orderId');

      final result = await _supabaseClient.rpc(
        'claim_order',
        params: {'p_order_id': orderId, 'p_driver_id': driverId},
      );

      final claimed = result == true;
      if (claimed) {
        AppLogger.info('Delivery accepted');
        // Notify customer that a driver is on the way
        try {
          final order = await _supabaseClient
              .from(AppConstants.tableOrders)
              .select('user_id')
              .eq('id', orderId)
              .maybeSingle();
          final customerId = order?['user_id'] as String?;
          if (customerId != null) {
            final userRow = await _supabaseClient
                .from('users')
                .select('fcm_token')
                .eq('id', customerId)
                .maybeSingle();
            final fcmToken = userRow?['fcm_token'] as String?;
            if (fcmToken != null && fcmToken.isNotEmpty) {
              _supabaseClient.functions.invoke(
                'send-fcm-notification',
                body: {
                  'token': fcmToken,
                  'title': 'Driver Assigned!',
                  'body':
                      'Order #${orderId.substring(0, 8).toUpperCase()} — a driver is heading to pick it up',
                  'data': {
                    'type': AppConstants.notificationTypeOrderStatus,
                    'order_id': orderId,
                    'status': 'driver_assigned',
                    'user_id': customerId,
                  },
                },
              );
            }
          }
        } catch (e) {
          AppLogger.error('Error notifying customer of driver assignment: $e');
        }
      } else {
        AppLogger.warning('Order already taken by another driver');
      }
      return claimed;
    } catch (e) {
      AppLogger.error('Error accepting delivery: $e');
      rethrow;
    }
  }

  // Get driver's active deliveries
  Future<List<Order>> getActiveDeliveries(String driverId) async {
    try {
      AppLogger.info('Fetching active deliveries for driver: $driverId');

      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select()
          .eq('driver_id', driverId)
          .neq('status', AppConstants.orderDelivered)
          .neq('status', AppConstants.orderCancelled)
          .order('ordered_at', ascending: false);

      final orders = <Order>[];
      for (var orderData in response as List) {
        final itemsResponse = await _supabaseClient
            .from(AppConstants.tableOrderItems)
            .select()
            .eq('order_id', orderData['id']);

        final items = <OrderItem>[];
        for (final itemJson in (itemsResponse as List)) {
          final sidesResponse = await _supabaseClient
              .from(AppConstants.tableOrderItemSides)
              .select()
              .eq('order_item_id', itemJson['id']);
          final sides = (sidesResponse as List)
              .map((s) => OrderItemSide.fromJson(s))
              .toList();
          items.add(
            OrderItem.fromJson({
              ...itemJson,
              'sides': sides.map((s) => s.toJson()).toList(),
            }),
          );
        }

        orders.add(
          Order.fromJson({
            ...orderData,
            'items': items.map((item) => item.toJson()).toList(),
          }),
        );
      }

      AppLogger.info('Fetched ${orders.length} active deliveries');
      return orders;
    } catch (e) {
      AppLogger.error('Error fetching active deliveries: $e');
      rethrow;
    }
  }

  // Mark delivery as completed via Edge Function (single round-trip)
  // Handles: status update, driver stats, cash float, notifications, referral earnings
  Future<void> completeDelivery(String orderId) async {
    try {
      AppLogger.info('Completing delivery via Edge Function: $orderId');

      final response = await _supabaseClient.functions.invoke(
        'complete-delivery',
        body: {'order_id': orderId},
      );

      if (response.status != 200) {
        final errorData = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        throw Exception(
          errorData?['error'] ??
              'Failed to complete delivery (${response.status})',
        );
      }

      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Delivery completion failed');
      }

      AppLogger.info('Delivery completed via Edge Function: $orderId');
    } catch (e) {
      AppLogger.error('Error completing delivery via Edge Function: $e');
      rethrow;
    }
  }

  /// Increment the driver's cash float by the given amount (atomic)
  Future<void> _incrementCashFloat(String driverId, double amount) async {
    try {
      await _supabaseClient.rpc(
        'increment_cash_float',
        params: {'p_driver_id': driverId, 'p_amount': amount},
      );
      AppLogger.info('Cash float incremented by $amount for driver $driverId');
    } catch (e) {
      // Fallback to non-atomic update if RPC doesn't exist yet
      try {
        final driver = await _supabaseClient
            .from(AppConstants.tableDrivers)
            .select('cash_float')
            .eq('id', driverId)
            .single();
        final currentFloat = (driver['cash_float'] as num?)?.toDouble() ?? 0.0;
        await _supabaseClient
            .from(AppConstants.tableDrivers)
            .update({
              'cash_float': currentFloat + amount,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', driverId);
        AppLogger.info(
          'Cash float incremented (fallback) by $amount for driver $driverId',
        );
      } catch (e2) {
        AppLogger.error('Error incrementing cash float: $e2');
      }
    }
  }

  /// Recalculate and update driver performance stats from orders.
  Future<void> updateDriverStats(String driverId) async {
    try {
      // Count completed deliveries — fetch delivery_fee, tip, payment_method
      final deliveries = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select(
            'id, driver_rating, driver_tip, delivery_fee, payment_method, total_amount, ordered_at, completed_at',
          )
          .eq('driver_id', driverId)
          .eq('status', AppConstants.orderDelivered);

      final count = (deliveries as List).length;

      // Count cancelled deliveries (only orders that had this driver assigned)
      final cancelledOrders = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('id')
          .eq('driver_id', driverId)
          .eq('status', AppConstants.orderCancelled);
      final cancelledCount = (cancelledOrders as List).length;

      // Compute average rating from orders that have a driver_rating
      final rated = deliveries
          .where((d) => d['driver_rating'] != null)
          .toList();
      double? avgRating;
      if (rated.isNotEmpty) {
        final sum = rated.fold<double>(
          0.0,
          (s, d) => s + (d['driver_rating'] as num).toDouble(),
        );
        avgRating = sum / rated.length;
      }

      // Compute total tips
      final totalTips = deliveries.fold<double>(
        0.0,
        (s, d) => s + ((d['driver_tip'] as num?)?.toDouble() ?? 0.0),
      );

      // Compute total earnings: driver keeps driverPayPercent of each delivery fee + tips
      final totalDriverPay = deliveries.fold<double>(
        0.0,
        (s, d) =>
            s +
            (((d['delivery_fee'] as num?)?.toDouble() ??
                    AppConstants.driverFeePerDelivery) *
                AppConstants.driverPayPercent),
      );
      final totalEarnings = totalDriverPay + totalTips;

      // Recalculate total_paid_out from all active payouts
      // (pending, approved, processing, completed — excludes rejected/failed)
      final payoutRows = await _supabaseClient
          .from('payout_requests')
          .select('amount')
          .eq('driver_id', driverId)
          .not('status', 'in', '(rejected,failed)');
      final totalPaidOut = (payoutRows as List).fold<double>(
        0.0,
        (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0),
      );

      final updateData = <String, dynamic>{
        'completed_deliveries': count,
        'cancelled_deliveries': cancelledCount,
        'total_earnings': totalEarnings,
        'total_paid_out': totalPaidOut,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (avgRating != null) {
        updateData['rating'] = double.parse(avgRating.toStringAsFixed(2));
      }

      await _supabaseClient
          .from(AppConstants.tableDrivers)
          .update(updateData)
          .eq('id', driverId);

      AppLogger.info(
        'Driver $driverId stats updated: $count deliveries, '
        '$cancelledCount cancelled, '
        'rating=${avgRating?.toStringAsFixed(2)}, earnings=$totalEarnings',
      );
    } catch (e) {
      // Non-fatal — log but don't fail the delivery
      AppLogger.error('Error updating driver stats: $e');
    }
  }

  // Get driver's delivery history
  Future<List<Order>> getDeliveryHistory(String driverId) async {
    try {
      AppLogger.info('Fetching delivery history for driver: $driverId');

      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select()
          .eq('driver_id', driverId)
          .eq('status', AppConstants.orderDelivered)
          .order('completed_at', ascending: false);

      final orders = <Order>[];
      for (var orderData in response as List) {
        final itemsResponse = await _supabaseClient
            .from(AppConstants.tableOrderItems)
            .select()
            .eq('order_id', orderData['id']);

        final items = <OrderItem>[];
        for (final itemJson in (itemsResponse as List)) {
          final sidesResponse = await _supabaseClient
              .from(AppConstants.tableOrderItemSides)
              .select()
              .eq('order_item_id', itemJson['id']);
          final sides = (sidesResponse as List)
              .map((s) => OrderItemSide.fromJson(s))
              .toList();
          items.add(
            OrderItem.fromJson({
              ...itemJson,
              'sides': sides.map((s) => s.toJson()).toList(),
            }),
          );
        }

        orders.add(
          Order.fromJson({
            ...orderData,
            'items': items.map((item) => item.toJson()).toList(),
          }),
        );
      }

      AppLogger.info('Fetched ${orders.length} completed deliveries');
      return orders;
    } catch (e) {
      AppLogger.error('Error fetching delivery history: $e');
      rethrow;
    }
  }

  // Update driver rating
  Future<void> updateDriverRating(String driverId, double rating) async {
    try {
      AppLogger.info('Updating driver rating: $driverId -> $rating');

      await _supabaseClient
          .from(AppConstants.tableDrivers)
          .update({
            'rating': rating,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);

      AppLogger.info('Driver rating updated');
    } catch (e) {
      AppLogger.error('Error updating driver rating: $e');
      rethrow;
    }
  }

  // Increment completed deliveries
  Future<void> incrementCompletedDeliveries(String driverId) async {
    try {
      await _supabaseClient.rpc(
        'increment_completed_deliveries',
        params: {'driver_id_param': driverId},
      );
    } catch (e) {
      // Fallback to non-atomic if RPC doesn't exist
      try {
        final driver = await _supabaseClient
            .from(AppConstants.tableDrivers)
            .select('completed_deliveries')
            .eq('id', driverId)
            .single();

        final completedCount = (driver['completed_deliveries'] ?? 0) + 1;

        await _supabaseClient
            .from(AppConstants.tableDrivers)
            .update({'completed_deliveries': completedCount})
            .eq('id', driverId);
      } catch (e2) {
        AppLogger.error('Error incrementing completed deliveries: $e2');
        rethrow;
      }
    }
  }

  /// Verify delivery OTP
  Future<bool> verifyDeliveryOtp(String orderId, String otp) async {
    try {
      final order = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('delivery_otp')
          .eq('id', orderId)
          .single();

      if (order['delivery_otp'] == otp) {
        await _supabaseClient
            .from(AppConstants.tableOrders)
            .update({'delivery_otp_verified': true})
            .eq('id', orderId);
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.error('Error verifying delivery OTP: $e');
      return false;
    }
  }

  /// Upload delivery proof photo URL
  Future<void> uploadDeliveryProof(String orderId, String photoUrl) async {
    try {
      await _supabaseClient
          .from(AppConstants.tableOrders)
          .update({'delivery_photo_url': photoUrl})
          .eq('id', orderId);
    } catch (e) {
      AppLogger.error('Error uploading delivery proof: $e');
      rethrow;
    }
  }

  /// Get driver leaderboard
  Future<List<Map<String, dynamic>>> getLeaderboard({int limit = 20}) async {
    try {
      final res = await _supabaseClient
          .from('driver_leaderboard')
          .select()
          .limit(limit);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      AppLogger.error('Error fetching leaderboard: $e');
      return [];
    }
  }

  /// Collect (reset) cash float from a driver — called by admin
  Future<void> collectFloat(String driverId, {double? amount}) async {
    try {
      AppLogger.info('Collecting float from driver: $driverId');

      if (amount != null && amount > 0) {
        // Partial collection — subtract the amount
        final driver = await _supabaseClient
            .from(AppConstants.tableDrivers)
            .select('cash_float')
            .eq('id', driverId)
            .single();
        final currentFloat = (driver['cash_float'] as num?)?.toDouble() ?? 0.0;
        final newFloat = (currentFloat - amount).clamp(0.0, double.infinity);
        await _supabaseClient
            .from(AppConstants.tableDrivers)
            .update({
              'cash_float': newFloat,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', driverId);
      } else {
        // Full collection — reset to 0
        await _supabaseClient
            .from(AppConstants.tableDrivers)
            .update({
              'cash_float': 0.0,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', driverId);
      }

      AppLogger.info('Float collected from driver $driverId');
    } catch (e) {
      AppLogger.error('Error collecting float: $e');
      rethrow;
    }
  }
}
