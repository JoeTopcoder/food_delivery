import 'dart:convert';
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../models/driver_model.dart';
import '../../models/order_model.dart';
import '../../utils/app_logger.dart';

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

      // Ensure public.users row exists before inserting into drivers (FK).
      try {
        final authUser = _supabaseClient.auth.currentUser;
        final email = authUser?.email ?? '$userId@otp.fooddriver.app';
        final metaName = authUser?.userMetadata?['name'] as String?;
        final name = (metaName != null && metaName.isNotEmpty)
            ? metaName
            : email.split('@').first;
        await _supabaseClient.from(AppConstants.tableUsers).upsert({
          'id': userId,
          'role': 'driver',
          'email': email,
          'name': name,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        AppLogger.warning('createDriverProfile: users upsert failed (continuing): $e');
      }

      final response = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .insert({
            'user_id': userId,
            'is_available': false,
            'completed_deliveries': 0,
            'rating': 0.0,
            'documents_status': {
              'license': 'pending',
              'registration': 'pending',
              'insurance': 'pending',
            },
            'driver_status': 'pending_review',
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

      // No profile found — ensure public.users row exists first (FK requirement),
      // then auto-create the driver record.
      AppLogger.info('No driver profile found, creating one for user: $userId');
      try {
        final authUser = _supabaseClient.auth.currentUser;
        final email = authUser?.email ?? '$userId@otp.fooddriver.app';
        final metaName = authUser?.userMetadata?['name'] as String?;
        final name = (metaName != null && metaName.isNotEmpty)
            ? metaName
            : email.split('@').first;
        await _supabaseClient.from(AppConstants.tableUsers).upsert({
          'id': userId,
          'role': 'driver',
          'email': email,
          'name': name,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        AppLogger.warning('getDriverByUserId: users upsert failed (continuing): $e');
      }

      try {
        final created = await _supabaseClient
            .from(AppConstants.tableDrivers)
            .insert({
              'user_id': userId,
              'is_available': false,
              'completed_deliveries': 0,
              'rating': 0.0,
              'documents_status': {
                'license': 'pending',
                'registration': 'pending',
                'insurance': 'pending',
              },
              'driver_status': 'pending_review',
              'created_at': DateTime.now().toIso8601String(),
            })
            .select()
            .single();
        return Driver.fromJson(created);
      } catch (insertError) {
        AppLogger.error('getDriverByUserId: auto-create failed: $insertError');
        // Return null — the dashboard will show "create profile" rather than
        // crashing the whole screen with a FK/RLS error.
        return null;
      }
    } catch (e) {
      AppLogger.error('Error fetching driver profile: $e');
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

  // Update which service types the driver has enabled
  Future<void> updateDriverActiveServices(
    String driverId,
    List<String> services,
  ) async {
    try {
      AppLogger.info('Updating driver active services: $driverId -> $services');
      await _supabaseClient
          .from(AppConstants.tableDrivers)
          .update({
            'active_services': services,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);
      AppLogger.info('Driver active services updated');
    } catch (e) {
      AppLogger.error('Error updating driver active services: $e');
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
  Future<List<Order>> getAvailableOrders({
    String? driverId,
    double? driverLat,
    double? driverLng,
    double radiusKm = 2.0,
  }) async {
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

      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('*, restaurants(latitude, longitude)')
          .filter('driver_id', 'is', null)
          .filter('order_group_id', 'is', null) // multi-restaurant sub-orders are assigned as a group
          .eq('is_pickup', false)
          .inFilter('status', [
            AppConstants.orderReady,
            AppConstants.orderPreparing,
            AppConstants.orderConfirmed,
            AppConstants.orderPending,
          ])
          .order('ordered_at', ascending: false)
          .limit(50); // fetch extra to account for declined/distance filtering

      final orders = <Order>[];
      for (var orderData in response as List) {
        // Skip orders this driver recently declined
        if (declinedOrderIds.contains(orderData['id'])) continue;

        // Filter by proximity to restaurant (2 km default)
        if (driverLat != null && driverLng != null) {
          final rest = orderData['restaurants'] as Map<String, dynamic>?;
          final rLat = (rest?['latitude'] as num?)?.toDouble();
          final rLng = (rest?['longitude'] as num?)?.toDouble();
          if (rLat != null && rLng != null) {
            final dist = _haversineKm(driverLat, driverLng, rLat, rLng);
            if (dist > radiusKm) continue;
          }
        }

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

      // Compute total earnings: $1.50/mile × distance, with minimum $3/delivery
      final totalDriverPay = deliveries.fold<double>(0.0, (s, d) {
        final distKm = (d['distance_km'] as num?)?.toDouble() ?? 0;
        final distMiles = distKm * AppConstants.kmToMiles;
        final pay = (distMiles * AppConstants.driverRatePerMile).clamp(
          AppConstants.driverMinBasePay,
          double.infinity,
        );
        return s + pay;
      });
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

      // Single query with nested joins — eliminates N+1 round-trips
      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select(
            '*, ${AppConstants.tableOrderItems}(*, ${AppConstants.tableOrderItemSides}(*))',
          )
          .eq('driver_id', driverId)
          .eq('status', AppConstants.orderDelivered)
          .order('completed_at', ascending: false);

      final orders = <Order>[];
      for (final orderData in response as List) {
        final rawItems = orderData[AppConstants.tableOrderItems] as List? ?? [];
        final items = rawItems.map((itemJson) {
          final rawSides =
              itemJson[AppConstants.tableOrderItemSides] as List? ?? [];
          final sides = rawSides.map((s) => OrderItemSide.fromJson(s)).toList();
          return OrderItem.fromJson({
            ...itemJson as Map<String, dynamic>,
            'sides': sides.map((s) => s.toJson()).toList(),
          });
        }).toList();

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

  // ── Verification / onboarding methods ────────────────────────────────────

  Future<Driver?> updateVerificationProfile({
    required String driverId,
    String? fullName,
    String? phoneNumber,
    String? homeAddress,
    DateTime? dateOfBirth,
    String? profilePhotoUrl,
    String? serviceType,
    int? onboardingStep,
  }) async {
    try {
      final data = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (fullName != null) data['full_name'] = fullName;
      if (phoneNumber != null) data['phone_number'] = phoneNumber;
      if (homeAddress != null) data['home_address'] = homeAddress;
      if (dateOfBirth != null) data['date_of_birth'] = dateOfBirth.toIso8601String().substring(0, 10);
      if (profilePhotoUrl != null) data['profile_photo_url'] = profilePhotoUrl;
      if (serviceType != null) data['service_type'] = serviceType;
      if (onboardingStep != null) data['onboarding_step'] = onboardingStep;

      final response = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .update(data)
          .eq('id', driverId)
          .select()
          .single();
      return Driver.fromJson(response);
    } catch (e) {
      AppLogger.error('Error updating verification profile: $e');
      rethrow;
    }
  }

  Future<void> saveIdentityDocument({
    required String driverId,
    required String documentType,
    String? documentNumber,
    String? frontPhotoUrl,
    String? backPhotoUrl,
    DateTime? expiryDate,
  }) async {
    try {
      final existing = await _supabaseClient
          .from('driver_identity_documents')
          .select('id')
          .eq('driver_id', driverId)
          .eq('document_type', documentType)
          .maybeSingle();
      final data = {
        'driver_id': driverId,
        'document_type': documentType,
        if (documentNumber != null) 'document_number': documentNumber,
        if (frontPhotoUrl != null) 'front_photo_url': frontPhotoUrl,
        if (backPhotoUrl != null) 'back_photo_url': backPhotoUrl,
        if (expiryDate != null) 'expiry_date': expiryDate.toIso8601String().substring(0, 10),
        'verification_status': 'pending',
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (existing != null) {
        await _supabaseClient
            .from('driver_identity_documents')
            .update(data)
            .eq('id', existing['id'] as String);
      } else {
        await _supabaseClient.from('driver_identity_documents').insert(data);
      }
    } catch (e) {
      AppLogger.error('Error saving identity document: $e');
      rethrow;
    }
  }

  Future<void> saveDriverLicense({
    required String driverId,
    String? licenseNumber,
    String? licenseClass,
    DateTime? issueDate,
    DateTime? expiryDate,
    String? frontPhotoUrl,
    String? backPhotoUrl,
  }) async {
    try {
      final existing = await _supabaseClient
          .from('driver_licenses')
          .select('id')
          .eq('driver_id', driverId)
          .maybeSingle();
      final data = {
        'driver_id': driverId,
        if (licenseNumber != null) 'license_number': licenseNumber,
        if (licenseClass != null) 'license_class': licenseClass,
        if (issueDate != null) 'issue_date': issueDate.toIso8601String().substring(0, 10),
        if (expiryDate != null) 'expiry_date': expiryDate.toIso8601String().substring(0, 10),
        if (frontPhotoUrl != null) 'front_photo_url': frontPhotoUrl,
        if (backPhotoUrl != null) 'back_photo_url': backPhotoUrl,
        'verification_status': 'pending',
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (existing != null) {
        await _supabaseClient
            .from('driver_licenses')
            .update(data)
            .eq('id', existing['id'] as String);
      } else {
        await _supabaseClient.from('driver_licenses').insert(data);
      }
    } catch (e) {
      AppLogger.error('Error saving driver license: $e');
      rethrow;
    }
  }

  Future<void> saveVehicle({
    required String driverId,
    required String vehicleType,
    String? make,
    String? model,
    int? year,
    String? color,
    String? licensePlate,
    String? vin,
    String? registrationPhotoUrl,
  }) async {
    try {
      final existing = await _supabaseClient
          .from('driver_vehicles')
          .select('id')
          .eq('driver_id', driverId)
          .eq('is_primary', true)
          .maybeSingle();
      final data = {
        'driver_id': driverId,
        'vehicle_type': vehicleType,
        if (make != null) 'make': make,
        if (model != null) 'model': model,
        if (year != null) 'year': year,
        if (color != null) 'color': color,
        if (licensePlate != null) 'license_plate': licensePlate,
        if (vin != null) 'vin': vin,
        if (registrationPhotoUrl != null) 'registration_photo_url': registrationPhotoUrl,
        'is_primary': true,
        'verification_status': 'pending',
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (existing != null) {
        await _supabaseClient
            .from('driver_vehicles')
            .update(data)
            .eq('id', existing['id'] as String);
      } else {
        await _supabaseClient.from('driver_vehicles').insert(data);
      }
    } catch (e) {
      AppLogger.error('Error saving vehicle: $e');
      rethrow;
    }
  }

  Future<void> saveInsurance({
    required String driverId,
    String? insuranceProvider,
    String? policyNumber,
    DateTime? expiryDate,
    String? documentPhotoUrl,
  }) async {
    try {
      final existing = await _supabaseClient
          .from('driver_insurance')
          .select('id')
          .eq('driver_id', driverId)
          .maybeSingle();
      final data = {
        'driver_id': driverId,
        if (insuranceProvider != null) 'insurance_provider': insuranceProvider,
        if (policyNumber != null) 'policy_number': policyNumber,
        if (expiryDate != null) 'expiry_date': expiryDate.toIso8601String().substring(0, 10),
        if (documentPhotoUrl != null) 'document_photo_url': documentPhotoUrl,
        'verification_status': 'pending',
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (existing != null) {
        await _supabaseClient
            .from('driver_insurance')
            .update(data)
            .eq('id', existing['id'] as String);
      } else {
        await _supabaseClient.from('driver_insurance').insert(data);
      }
    } catch (e) {
      AppLogger.error('Error saving insurance: $e');
      rethrow;
    }
  }

  Future<void> recordConsent({
    required String driverId,
    required String consentType,
    String? appVersion,
  }) async {
    try {
      await _supabaseClient.from('driver_consents').upsert({
        'driver_id': driverId,
        'consent_type': consentType,
        'consented': true,
        'consented_at': DateTime.now().toUtc().toIso8601String(),
        if (appVersion != null) 'app_version': appVersion,
      }, onConflict: 'driver_id,consent_type');
    } catch (e) {
      AppLogger.error('Error recording consent: $e');
      rethrow;
    }
  }

  Future<Driver?> submitApplication(String driverId) async {
    try {
      AppLogger.info('Submitting driver application: $driverId');
      final now = DateTime.now().toIso8601String();
      final row = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .update({
            'driver_status': 'pending_review',
            'submitted_at': now,
            'rejection_reason': null,
            'onboarding_step': 8,
            'updated_at': now,
          })
          .eq('id', driverId)
          .select()
          .single();
      AppLogger.info('Driver application submitted successfully');

      // Fire-and-forget: notify edge function for admin FCM notifications
      // (non-fatal — submission already succeeded above)
      _supabaseClient.functions.invoke(
        'submit-driver-application',
        body: {'driver_id': driverId},
      ).ignore();

      return Driver.fromJson(row);
    } catch (e) {
      AppLogger.error('Error submitting driver application: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getVerificationDocuments(String driverId) async {
    try {
      final results = await Future.wait<dynamic>([
        _supabaseClient
            .from('driver_identity_documents')
            .select()
            .eq('driver_id', driverId),
        _supabaseClient
            .from('driver_licenses')
            .select()
            .eq('driver_id', driverId)
            .maybeSingle(),
        _supabaseClient
            .from('driver_vehicles')
            .select()
            .eq('driver_id', driverId)
            .eq('is_primary', true)
            .maybeSingle(),
        _supabaseClient
            .from('driver_insurance')
            .select()
            .eq('driver_id', driverId)
            .maybeSingle(),
        _supabaseClient
            .from('driver_consents')
            .select()
            .eq('driver_id', driverId),
      ]);
      return {
        'identity_documents': results[0],
        'license': results[1],
        'vehicle': results[2],
        'insurance': results[3],
        'consents': results[4],
      };
    } catch (e) {
      AppLogger.error('Error fetching verification documents: $e');
      return {};
    }
  }

  Future<void> updateOnlineStatus(String driverId, bool isOnline) async {
    try {
      await _supabaseClient.functions.invoke(
        'validate-driver-online',
        body: {'driver_id': driverId, 'go_online': isOnline},
      );
    } catch (e) {
      // Fallback to direct DB update
      await _supabaseClient
          .from(AppConstants.tableDrivers)
          .update({'is_online': isOnline, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', driverId);
    }
  }

  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.asin(math.sqrt(a));
  }
}
