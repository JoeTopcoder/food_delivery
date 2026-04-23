import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../models/order_model.dart';
import '../services/driver_service.dart';
import '../services/earning_service.dart';
import '../utils/app_logger.dart';

class OrderService {
  final SupabaseClient _supabaseClient;

  OrderService(this._supabaseClient);

  // Create order via Edge Function (single round-trip)
  Future<Order?> createOrder({
    required String userId,
    required String restaurantId,
    required List<OrderItem> items,
    required double subtotal,
    required double deliveryFee,
    double? taxAmount,
    double? discount,
    required double totalAmount,
    required String deliveryAddress,
    required double deliveryLatitude,
    required double deliveryLongitude,
    String? notes,
    String? paymentMethod,
    bool contactlessDelivery = false,
    double? driverTip,
    DateTime? scheduledFor,
    bool isPickup = false,
    double? pickupFee,
    bool fromAd = false,
    String? adId,
  }) async {
    try {
      AppLogger.info('Creating order via Edge Function for user: $userId');

      final itemsPayload = items
          .map(
            (item) => <String, dynamic>{
              'menu_item_id': item.menuItemId,
              'item_name': item.itemName,
              'price': item.price,
              'quantity': item.quantity,
              'subtotal': item.subtotal,
              if (item.notes != null) 'notes': item.notes,
              if (item.sides != null && item.sides!.isNotEmpty)
                'sides': item.sides!
                    .map(
                      (s) => {
                        'side_name': s.sideName,
                        'side_price': s.sidePrice,
                      },
                    )
                    .toList(),
            },
          )
          .toList();

      final body = <String, dynamic>{
        'user_id': userId,
        'restaurant_id': restaurantId,
        'items': itemsPayload,
        'subtotal': subtotal,
        'delivery_fee': deliveryFee,
        'total_amount': totalAmount,
        'delivery_address': deliveryAddress,
        'delivery_latitude': deliveryLatitude,
        'delivery_longitude': deliveryLongitude,
        'payment_method': paymentMethod ?? 'cash',
        'contactless_delivery': contactlessDelivery,
        'is_pickup': isPickup,
      };

      if (taxAmount != null) body['tax_amount'] = taxAmount;
      if (discount != null && discount > 0) body['discount'] = discount;
      if (notes != null && notes.isNotEmpty) body['notes'] = notes;
      if (driverTip != null && driverTip > 0) body['driver_tip'] = driverTip;
      if (scheduledFor != null) {
        body['scheduled_for'] = scheduledFor.toIso8601String();
      }
      if (isPickup && pickupFee != null) body['pickup_fee'] = pickupFee;
      if (fromAd) body['from_ad'] = true;
      if (adId != null) body['ad_id'] = adId;

      var response = await _supabaseClient.functions.invoke(
        'place-order',
        body: body,
      );

      // If we get an ES256 JWT error, refresh the session and retry once.
      if (response.status == 401 || response.status == 403) {
        final errStr = response.data?.toString() ?? '';
        if (errStr.contains('ES256') ||
            errStr.contains('UNSUPPORTED_TOKEN') ||
            errStr.contains('LEGACY_JWT') ||
            errStr.contains('Invalid JWT') ||
            errStr.contains('JWT')) {
          await _supabaseClient.auth.refreshSession();
          response = await _supabaseClient.functions.invoke(
            'place-order',
            body: body,
          );
        }
      }

      if (response.status != 200) {
        final errorData = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : (response.data as Map?)?.cast<String, dynamic>() ?? {};
        final errMsg =
            errorData['error'] as String? ??
            'Failed to place order (${response.status})';
        final details = errorData['details'] as String?;
        throw Exception(details != null ? '$errMsg — $details' : errMsg);
      }

      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Order placement failed');
      }

      final orderId = data['order']?['id'] as String?;
      if (orderId == null) {
        throw Exception('No order ID returned from edge function');
      }

      // Fetch complete order with items for the Flutter model
      final completeOrder = await getOrderById(orderId);
      AppLogger.info('Order created successfully via Edge Function');
      return completeOrder;
    } catch (e) {
      AppLogger.error('Error creating order via Edge Function: $e');
      rethrow;
    }
  }

  // Get order by ID
  Future<Order?> getOrderById(String orderId) async {
    try {
      AppLogger.info('Fetching order: $orderId');

      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select()
          .eq('id', orderId)
          .single();

      // Fetch order items
      final itemsResponse = await _supabaseClient
          .from(AppConstants.tableOrderItems)
          .select()
          .eq('order_id', orderId);

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

      final order = Order.fromJson({
        ...response,
        'items': items.map((item) => item.toJson()).toList(),
      });

      AppLogger.info('Order fetched successfully');
      return order;
    } catch (e) {
      AppLogger.error('Error fetching order: $e');
      return null;
    }
  }

  // Get user's orders
  Future<List<Order>> getUserOrders(String userId) async {
    try {
      AppLogger.info('Fetching orders for user: $userId');

      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select()
          .eq('user_id', userId)
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

      AppLogger.info('Fetched ${orders.length} orders');
      return orders;
    } catch (e) {
      AppLogger.error('Error fetching user orders: $e');
      rethrow;
    }
  }

  // Update order status
  Future<void> updateOrderStatus(String orderId, String status) async {
    try {
      AppLogger.info('Updating order status: $orderId -> $status');

      final updateData = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (status == AppConstants.orderConfirmed) {
        updateData['confirmed_at'] = DateTime.now().toIso8601String();
      } else if (status == AppConstants.orderDelivered) {
        updateData['completed_at'] = DateTime.now().toIso8601String();
      } else if (status == AppConstants.orderCancelled) {
        updateData['cancelled_at'] = DateTime.now().toIso8601String();
      }

      await _supabaseClient
          .from(AppConstants.tableOrders)
          .update(updateData)
          .eq('id', orderId);

      // Fire-and-forget: send notifications in the background so the UI
      // updates immediately instead of waiting for every push to complete.

      // When order is marked ready, notify all available drivers (skip pickup orders)
      if (status == AppConstants.orderReady) {
        _supabaseClient
            .from(AppConstants.tableOrders)
            .select('is_pickup')
            .eq('id', orderId)
            .single()
            .then((row) {
              final isPickup = row['is_pickup'] as bool? ?? false;
              if (!isPickup) {
                _notifyAvailableDrivers(orderId: orderId);
              }
            })
            .catchError((e) {
              AppLogger.error('Error checking pickup status: $e');
            });
      }

      // Notify the customer on every status change
      _supabaseClient
          .from(AppConstants.tableOrders)
          .select('user_id')
          .eq('id', orderId)
          .single()
          .then((order) {
            final userId = order['user_id'] as String?;
            if (userId != null) {
              _notifyCustomer(userId: userId, orderId: orderId, status: status);
            }
          })
          .catchError((e) {
            AppLogger.error('Error sending customer notification: $e');
          });

      // Notify admins on every status change
      _sendPushNotification(
        topic: AppConstants.fcmTopicAdmins,
        title: 'Order Status Update',
        body:
            'Order #${orderId.substring(0, 8).toUpperCase()} → ${status.replaceAll('_', ' ')}',
        data: {
          'type': AppConstants.notificationTypeOrderStatus,
          'order_id': orderId,
          'status': status,
        },
      ).catchError((e) {
        AppLogger.error('Error sending admin notification: $e');
        return; // satisfy catchError return type
      });

      // Fire-and-forget: process referral earnings when order is delivered
      if (status == AppConstants.orderDelivered) {
        _supabaseClient
            .from(AppConstants.tableOrders)
            .select('user_id')
            .eq('id', orderId)
            .single()
            .then((row) async {
              final customerId = row['user_id'] as String?;
              if (customerId == null) return;
              final earningService = EarningService(_supabaseClient);
              // Process per-order referral earnings (direct + indirect)
              await earningService.processOrderEarnings(
                orderId: orderId,
                customerId: customerId,
              );
              // Check & award signup bonus if this is the user's first delivered order
              final delivered = await _supabaseClient
                  .from(AppConstants.tableOrders)
                  .select('id')
                  .eq('user_id', customerId)
                  .eq('status', AppConstants.orderDelivered)
                  .limit(2);
              if ((delivered as List).length == 1) {
                await earningService.processSignupBonus(customerId);
              }
            })
            .catchError((e) {
              AppLogger.error('Error processing referral earnings: $e');
            });
      }

      AppLogger.info('Order status updated successfully');
    } catch (e) {
      AppLogger.error('Error updating order status: $e');
      rethrow;
    }
  }

  // Set pickup code for a pickup order (restaurant sets this)
  Future<void> setPickupCode(String orderId, String pickupCode) async {
    try {
      AppLogger.info('Setting pickup code for order: $orderId');
      await _supabaseClient
          .from(AppConstants.tableOrders)
          .update({
            'pickup_code': pickupCode,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);
      AppLogger.info('Pickup code set successfully');
    } catch (e) {
      AppLogger.error('Error setting pickup code: $e');
      rethrow;
    }
  }

  // Verify pickup code and complete the order
  Future<bool> verifyPickupCode(String orderId, String code) async {
    try {
      AppLogger.info('Verifying pickup code for order: $orderId');
      final row = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('pickup_code')
          .eq('id', orderId)
          .single();
      final storedCode = row['pickup_code'] as String?;
      if (storedCode != null && storedCode == code) {
        await updateOrderStatus(orderId, AppConstants.orderDelivered);
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.error('Error verifying pickup code: $e');
      rethrow;
    }
  }

  // Assign driver to order
  Future<void> assignDriverToOrder(String orderId, String driverId) async {
    try {
      AppLogger.info('Assigning driver $driverId to order $orderId');

      await _supabaseClient
          .from(AppConstants.tableOrders)
          .update({'driver_id': driverId})
          .eq('id', orderId);

      AppLogger.info('Driver assigned successfully');
    } catch (e) {
      AppLogger.error('Error assigning driver: $e');
      rethrow;
    }
  }

  // Add review and rating (multi-dimension)
  Future<void> addReview({
    required String orderId,
    required double rating,
    String? review,
    int? foodRating,
    int? deliveryRating,
    int? packagingRating,
    String? photoUrl,
  }) async {
    try {
      AppLogger.info('Adding review for order: $orderId');

      await _supabaseClient
          .from(AppConstants.tableOrders)
          .update({
            'user_rating': rating,
            'user_review': ?review,
            'food_rating': ?foodRating,
            'delivery_rating': ?deliveryRating,
            'packaging_rating': ?packagingRating,
            'review_photo_url': ?photoUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);

      AppLogger.info('Review added successfully');
    } catch (e) {
      AppLogger.error('Error adding review: $e');
      rethrow;
    }
  }

  // Rate the driver (1-5 stars)
  Future<void> rateDriver({
    required String orderId,
    required int rating,
  }) async {
    try {
      AppLogger.info('Rating driver for order: $orderId with $rating stars');
      await _supabaseClient
          .from(AppConstants.tableOrders)
          .update({
            'driver_rating': rating,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);

      // Refresh driver_stats avg rating and recalculate score/tier
      final order = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('driver_id')
          .eq('id', orderId)
          .maybeSingle();
      if (order != null && order['driver_id'] != null) {
        final driverId = order['driver_id'] as String;

        // Recalculate avg rating from all rated orders (last 30 days)
        final thirtyDaysAgo = DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String();
        final ratedOrders = await _supabaseClient
            .from(AppConstants.tableOrders)
            .select('driver_rating')
            .eq('driver_id', driverId)
            .eq('status', 'delivered')
            .not('driver_rating', 'is', null)
            .gte('ordered_at', thirtyDaysAgo);

        if (ratedOrders.isNotEmpty) {
          final sum = ratedOrders.fold<double>(
            0.0,
            (s, o) => s + (o['driver_rating'] as num).toDouble(),
          );
          final avg = double.parse(
            (sum / ratedOrders.length).toStringAsFixed(2),
          );

          await _supabaseClient
              .from('driver_stats')
              .update({
                'avg_customer_rating': avg,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('driver_id', driverId);

          // Also update drivers.rating
          await _supabaseClient
              .from('drivers')
              .update({
                'rating': avg,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', driverId);
        }

        // Recalculate score/tier
        await _supabaseClient.rpc(
          'calculate_driver_score',
          params: {'p_driver_id': driverId},
        );
      }

      AppLogger.info('Driver rated successfully');
    } catch (e) {
      AppLogger.error('Error rating driver: $e');
      rethrow;
    }
  }

  // Tip the driver
  Future<void> tipDriver({
    required String orderId,
    required double tipAmount,
  }) async {
    try {
      AppLogger.info('Tipping driver for order: $orderId amount: \$$tipAmount');
      await _supabaseClient
          .from(AppConstants.tableOrders)
          .update({
            'driver_tip': tipAmount,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);
      AppLogger.info('Driver tipped successfully');
    } catch (e) {
      AppLogger.error('Error tipping driver: $e');
      rethrow;
    }
  }

  // Get orders for multiple restaurants (for multi-restaurant owners)
  Future<List<Order>> getOrdersForRestaurants(
    List<String> restaurantIds,
  ) async {
    try {
      if (restaurantIds.isEmpty) return [];
      AppLogger.info('Fetching orders for ${restaurantIds.length} restaurants');

      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select()
          .inFilter('restaurant_id', restaurantIds)
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

      AppLogger.info('Fetched ${orders.length} orders across restaurants');
      return orders;
    } catch (e) {
      AppLogger.error('Error fetching orders for restaurants: $e');
      rethrow;
    }
  }

  // Get restaurant's orders
  Future<List<Order>> getRestaurantOrders(String restaurantId) async {
    try {
      AppLogger.info('Fetching orders for restaurant: $restaurantId');

      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select()
          .eq('restaurant_id', restaurantId)
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

      AppLogger.info('Fetched ${orders.length} restaurant orders');
      return orders;
    } catch (e) {
      AppLogger.error('Error fetching restaurant orders: $e');
      rethrow;
    }
  }

  // Cancel order
  Future<void> cancelOrder(String orderId) async {
    try {
      AppLogger.info('Cancelling order: $orderId');

      // Guard: prevent cancelling delivered/completed orders
      final order = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('status, driver_id, payment_method, payment_status')
          .eq('id', orderId)
          .single();
      final currentStatus = order['status'] as String?;
      if (currentStatus == AppConstants.orderDelivered ||
          currentStatus == 'completed' ||
          currentStatus == AppConstants.orderCancelled) {
        throw Exception(
          'Cannot cancel an order that is already $currentStatus',
        );
      }

      await _supabaseClient
          .from(AppConstants.tableOrders)
          .update({
            'status': AppConstants.orderCancelled,
            'cancelled_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);

      // Auto-refund card payments
      final paymentMethod = order['payment_method'] as String?;
      final paymentStatus = order['payment_status'] as String?;
      if (paymentMethod == 'card' && paymentStatus == 'completed') {
        try {
          await _supabaseClient.functions.invoke(
            AppConstants.stripePaymentFunction,
            body: {'action': 'refund', 'orderId': orderId},
          );
          AppLogger.info('Refund processed for cancelled order: $orderId');
        } catch (e) {
          AppLogger.error('Refund failed for order $orderId: $e');
        }
      }

      // Notify the customer about cancellation
      try {
        final custOrder = await _supabaseClient
            .from(AppConstants.tableOrders)
            .select('user_id')
            .eq('id', orderId)
            .single();
        final userId = custOrder['user_id'] as String?;
        if (userId != null) {
          _notifyCustomer(
            userId: userId,
            orderId: orderId,
            status: AppConstants.orderCancelled,
          );
        }
      } catch (e) {
        AppLogger.error('Error sending cancel notification: $e');
      }

      // If the order had an assigned driver, recalculate all their stats
      final driverId = order['driver_id'] as String?;
      if (driverId != null) {
        try {
          final driverService = DriverService(_supabaseClient);
          await driverService.updateDriverStats(driverId);
        } catch (e) {
          AppLogger.error('Error updating driver stats after cancel: $e');
        }
      }

      AppLogger.info('Order cancelled successfully');
    } catch (e) {
      AppLogger.error('Error cancelling order: $e');
      rethrow;
    }
  }

  // Broadcast order status update to all stakeholders
  Future<void> broadcastOrderStatusUpdate({
    required String orderId,
    required String status,
    required String restaurantId,
    required String userId,
    String? driverId,
  }) async {
    try {
      AppLogger.info('Broadcasting order status update: $orderId -> $status');

      // Send all notifications in parallel for speed
      final futures = <Future>[];

      futures.add(
        _notifyRestaurant(
          restaurantId: restaurantId,
          orderId: orderId,
          status: status,
        ),
      );

      futures.add(
        _notifyCustomer(userId: userId, orderId: orderId, status: status),
      );

      if (driverId != null && driverId.isNotEmpty) {
        futures.add(
          _notifyDriver(driverId: driverId, orderId: orderId, status: status),
        );
      }

      if (status == AppConstants.orderReady) {
        futures.add(_notifyAvailableDrivers(orderId: orderId));
      }

      await Future.wait(futures);

      AppLogger.info('Broadcast notifications sent');
    } catch (e) {
      AppLogger.error('Error broadcasting order status: $e');
    }
  }

  /// Send a push notification via the Supabase Edge Function
  Future<void> _sendPushNotification({
    String? token,
    String? topic,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      await _supabaseClient.functions.invoke(
        'send-fcm-notification',
        body: {
          'token': ?token,
          'topic': ?topic,
          'title': title,
          'body': body,
          'data': ?data,
        },
      );
    } catch (e) {
      AppLogger.error('Error sending push notification: $e');
    }
  }

  // Notify restaurant about new order or status update
  Future<void> _notifyRestaurant({
    required String restaurantId,
    required String orderId,
    required String status,
  }) async {
    try {
      AppLogger.info('Sending restaurant notification for order: $orderId');
      final title = _getRestaurantNotificationTitle(status);
      await _sendPushNotification(
        topic: 'restaurant_$restaurantId',
        title: title,
        body: 'Order #${orderId.substring(0, 8).toUpperCase()}',
        data: {
          'type': AppConstants.notificationTypeNewOrder,
          'order_id': orderId,
          'status': status,
          'user_id': restaurantId,
        },
      );
    } catch (e) {
      AppLogger.error('Error notifying restaurant: $e');
    }
  }

  // Notify customer about order status
  Future<void> _notifyCustomer({
    required String userId,
    required String orderId,
    required String status,
  }) async {
    try {
      AppLogger.info('Sending customer notification for order: $orderId');
      final title = _getCustomerNotificationTitle(status);
      final body = _getCustomerNotificationBody(status, orderId: orderId);

      // Look up the customer's FCM device token for direct delivery
      final userRow = await _supabaseClient
          .from('users')
          .select('fcm_token')
          .eq('id', userId)
          .maybeSingle();
      final fcmToken = userRow?['fcm_token'] as String?;

      if (fcmToken != null && fcmToken.isNotEmpty) {
        // Send directly to device token (most reliable)
        await _sendPushNotification(
          token: fcmToken,
          title: title,
          body: body,
          data: {
            'type': AppConstants.notificationTypeOrderStatus,
            'order_id': orderId,
            'status': status,
            'user_id': userId,
          },
        );
      } else {
        // Fallback: send to topic
        await _sendPushNotification(
          topic: 'customer_$userId',
          title: title,
          body: body,
          data: {
            'type': AppConstants.notificationTypeOrderStatus,
            'order_id': orderId,
            'status': status,
            'user_id': userId,
          },
        );
      }
    } catch (e) {
      AppLogger.error('Error notifying customer: $e');
    }
  }

  // Notify driver about order assignment or status
  Future<void> _notifyDriver({
    required String driverId,
    required String orderId,
    required String status,
  }) async {
    try {
      AppLogger.info('Sending driver notification for order: $orderId');
      final title = _getDriverNotificationTitle(status);
      await _sendPushNotification(
        topic: 'driver_$driverId',
        title: title,
        body: 'Order #${orderId.substring(0, 8).toUpperCase()}',
        data: {
          'type': AppConstants.notificationTypeDeliveryUpdate,
          'order_id': orderId,
          'status': status,
          'user_id': driverId,
        },
      );
    } catch (e) {
      AppLogger.error('Error notifying driver: $e');
    }
  }

  // Notify all available/online drivers that an order is ready for pickup
  Future<void> _notifyAvailableDrivers({required String orderId}) async {
    try {
      AppLogger.info('Notifying available drivers about ready order: $orderId');

      // Get all online drivers
      final drivers = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .select('id')
          .eq('is_available', true);

      // Send all driver notifications in parallel
      await Future.wait(
        (drivers as List).map((driver) {
          final driverId = driver['id'] as String;
          return _sendPushNotification(
            topic: 'driver_$driverId',
            title: 'New Order Ready for Pickup!',
            body:
                'Order #${orderId.substring(0, 8).toUpperCase()} is ready. Tap to accept.',
            data: {
              'type': AppConstants.notificationTypeDeliveryUpdate,
              'order_id': orderId,
              'status': AppConstants.orderReady,
              'user_id': driverId,
            },
          ).catchError((e) {
            AppLogger.error('Error notifying driver $driverId: $e');
          });
        }),
      );

      AppLogger.info('Notified ${drivers.length} available drivers');
    } catch (e) {
      AppLogger.error('Error notifying available drivers: $e');
    }
  }

  // Get restaurant-specific notification title
  String _getRestaurantNotificationTitle(String status) {
    switch (status) {
      case 'pending':
        return 'New Order Received';
      case 'confirmed':
        return 'Order Confirmed';
      case 'ready':
        return 'Order Ready';
      case 'picked_up':
        return 'Order Picked Up';
      case 'delivered':
        return 'Order Delivered';
      case 'cancelled':
        return 'Order Cancelled';
      default:
        return 'Order Update';
    }
  }

  // Get customer-specific notification title
  String _getCustomerNotificationTitle(String status) {
    switch (status) {
      case 'confirmed':
        return 'Order Confirmed!';
      case 'preparing':
        return 'Preparing Your Order';
      case 'ready':
        return 'Ready for Pickup!';
      case 'picked_up':
        return 'Out for Delivery';
      case 'on_the_way':
        return 'Your Food is On the Way';
      case 'delivered':
        return 'Order Delivered!';
      case 'cancelled':
        return 'Order Cancelled';
      default:
        return 'Order Status Update';
    }
  }

  // Get customer-specific notification body
  String _getCustomerNotificationBody(String status, {String? orderId}) {
    final tag = orderId != null
        ? ' #${orderId.substring(0, 8).toUpperCase()}'
        : '';
    switch (status) {
      case 'confirmed':
        return 'Order$tag has been confirmed by the restaurant';
      case 'preparing':
        return 'Order$tag is being prepared now';
      case 'ready':
        return 'Order$tag is ready for pickup';
      case 'picked_up':
        return 'Order$tag has been picked up by the driver';
      case 'on_the_way':
        return 'Order$tag is on the way!';
      case 'delivered':
        return 'Order$tag delivered! Rate your experience';
      case 'cancelled':
        return 'Order$tag has been cancelled';
      default:
        return 'Order$tag has been updated';
    }
  }

  // Get driver-specific notification title
  String _getDriverNotificationTitle(String status) {
    switch (status) {
      case 'ready':
        return 'Order Ready for Pickup';
      case 'picked_up':
        return 'Order Picked Up';
      case 'on_the_way':
        return 'Delivery in Progress';
      case 'delivered':
        return 'Delivery Completed';
      default:
        return 'Order Update';
    }
  }
}
