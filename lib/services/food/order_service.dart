import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../models/order_model.dart';
import '../driver/driver_service.dart';
import '../earning_service.dart';
import '../../utils/app_logger.dart';

class OrderService {
  final SupabaseClient _supabaseClient;

  OrderService(this._supabaseClient);

  /// Returns an Authorization header with a fresh access token.
  /// Only calls refreshSession() if the current JWT expires within 60 seconds
  /// to avoid an unnecessary round-trip on every order creation.
  Future<Map<String, String>> _freshAuthHeader() async {
    String? token = _supabaseClient.auth.currentSession?.accessToken;
    final expiresAt = _supabaseClient.auth.currentSession?.expiresAt;

    final needsRefresh = expiresAt == null ||
        DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
                .difference(DateTime.now())
                .inSeconds <
            60;

    if (needsRefresh) {
      try {
        final res = await _supabaseClient.auth.refreshSession();
        token = res.session?.accessToken ?? token;
      } catch (_) {}
    }

    return (token != null && token.isNotEmpty)
        ? {'Authorization': 'Bearer $token'}
        : {};
  }

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
    String? promoCode,
    // Payment gate: pass one of these for card payments so the edge function
    // charges/verifies Stripe BEFORE inserting the order.
    String? savedCardPaymentMethodId,
    String? paymentIntentId,
  }) async {
    try {
      AppLogger.info('Creating order via Edge Function for user: $userId');
      AppLogger.info(
        'Order params: restaurantId=$restaurantId, items=${items.length}, subtotal=$subtotal, deliveryFee=$deliveryFee, totalAmount=$totalAmount, isPickup=$isPickup, paymentMethod=$paymentMethod',
      );

      final itemsPayload = items.map((item) {
        // Calculate subtotal: price per unit * quantity + sides total
        final sidesTotal =
            item.sides?.fold<double>(
              0.0,
              (sum, side) => sum + side.sidePrice,
            ) ??
            0.0;
        final itemSubtotal = (item.price + sidesTotal) * item.quantity;

        return <String, dynamic>{
          'menu_item_id': item.menuItemId,
          'item_name': item.itemName,
          'price': item.price,
          'quantity': item.quantity,
          'subtotal': itemSubtotal,
          if (item.notes != null) 'notes': item.notes,
          if (item.sides != null && item.sides!.isNotEmpty)
            'sides': item.sides!
                .map(
                  (s) => {'side_name': s.sideName, 'side_price': s.sidePrice},
                )
                .toList(),
        };
      }).toList();

      AppLogger.info('Items payload: $itemsPayload');

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
      if (promoCode != null && promoCode.trim().isNotEmpty) {
        body['promo_code'] = promoCode.trim().toUpperCase();
      }
      if (savedCardPaymentMethodId != null && savedCardPaymentMethodId.isNotEmpty) {
        body['saved_card_payment_method_id'] = savedCardPaymentMethodId;
      }
      if (paymentIntentId != null && paymentIntentId.isNotEmpty) {
        body['payment_intent_id'] = paymentIntentId;
      }

      AppLogger.info('Sending request to place-order: ${body.keys.join(", ")}');

      // Proactively refresh the JWT before invoking the edge function.
      // Build a fresh Authorization header (refreshes session + reads new token).
      // Explicitly passing the header avoids UNAUTHORIZED_LEGACY_JWT from a
      // stale in-memory token even when the refresh token is valid.
      final authHeader = await _freshAuthHeader();

      late FunctionResponse response;
      try {
        response = await _supabaseClient.functions.invoke(
          'place-order',
          body: body,
          headers: authHeader,
        );
      } on FunctionException catch (fe) {
        final raw = fe.details?.toString() ?? '';
        AppLogger.error(
          'place-order FunctionException: status=${fe.status}, reason=${fe.reasonPhrase}, details=$raw',
        );
        final isJwtError =
            fe.status == 401 ||
            fe.status == 403 ||
            raw.contains('LEGACY_JWT') ||
            raw.contains('ES256') ||
            raw.contains('JWT');
        if (isJwtError) {
          AppLogger.info('Detected JWT error, retrying with fresh header...');
          // Build a second fresh header and retry once.
          final retryHeader = await _freshAuthHeader();
          try {
            response = await _supabaseClient.functions.invoke(
              'place-order',
              body: body,
              headers: retryHeader,
            );
            AppLogger.info('Retry succeeded');
          } on FunctionException catch (fe2) {
            AppLogger.error(
              'Retry also failed: status=${fe2.status}, reason=${fe2.reasonPhrase}, details=${fe2.details}',
            );
            throw Exception('Something went wrong. Please try again.');
          }
        } else {
          AppLogger.error('Not a JWT error, rethrowing: $fe');
          rethrow;
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
        AppLogger.error(
          'place-order failed (${response.status}): $errMsg${details != null ? ' — $details' : ''} | Response: ${response.data}',
        );
        throw Exception(details != null ? '$errMsg — $details' : errMsg);
      }

      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      if (data['success'] != true) {
        AppLogger.error(
          'place-order returned success=false: ${data['error'] ?? 'unknown error'} | Full response: $data',
        );
        throw Exception(data['error'] ?? 'Order placement failed');
      }

      final orderId = data['order']?['id'] as String?;
      if (orderId == null) {
        AppLogger.error('place-order did not return order ID: $data');
        throw Exception('No order ID returned from edge function');
      }

      AppLogger.info(
        'Order $orderId created successfully, fetching full details...',
      );

      // Fetch complete order with items for the Flutter model
      final completeOrder = await getOrderById(orderId);
      AppLogger.info('Order created successfully via Edge Function');
      return completeOrder;
    } catch (e) {
      AppLogger.error('Error creating order via Edge Function: $e');
      rethrow;
    }
  }

  // Get order by ID — single nested query (no N+1)
  Future<Order?> getOrderById(String orderId) async {
    try {
      AppLogger.info('Fetching order: $orderId');

      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select(
            '*, ${AppConstants.tableOrderItems}(*, ${AppConstants.tableOrderItemSides}(*))',
          )
          .eq('id', orderId)
          .single();

      final rawItems = (response[AppConstants.tableOrderItems] as List? ?? []);
      final items = rawItems.map((itemJson) {
        final sides =
            (itemJson[AppConstants.tableOrderItemSides] as List? ?? [])
                .map((s) => OrderItemSide.fromJson(s as Map<String, dynamic>))
                .toList();
        return OrderItem.fromJson({
          ...itemJson as Map<String, dynamic>,
          'sides': sides.map((s) => s.toJson()).toList(),
        });
      }).toList();

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

  // Get user's orders — single nested query with pagination (no N+1)
  Future<List<Order>> getUserOrders(
    String userId, {
    int offset = 0,
    int limit = 20,
  }) async {
    try {
      AppLogger.info(
        'Fetching orders for user: $userId (offset=$offset, limit=$limit)',
      );

      // Fetch only single-restaurant orders.
      // Multi-restaurant sub-orders (is_multi_restaurant = true) are excluded here
      // because they are shown as master orders via customerMasterOrdersProvider.
      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select(
            '*, ${AppConstants.tableOrderItems}(*, ${AppConstants.tableOrderItemSides}(*))',
          )
          .eq('user_id', userId)
          .or('is_multi_restaurant.is.null,is_multi_restaurant.eq.false')
          .order('ordered_at', ascending: false);

      final combined = (response as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      combined.sort((a, b) {
        final aDate =
            DateTime.tryParse(a['ordered_at'] as String? ?? '') ?? DateTime(0);
        final bDate =
            DateTime.tryParse(b['ordered_at'] as String? ?? '') ?? DateTime(0);
        return bDate.compareTo(aDate);
      });

      final page = combined.skip(offset).take(limit).toList();

      final orders = page.map((orderData) {
        final rawItems =
            (orderData[AppConstants.tableOrderItems] as List? ?? []);
        final items = rawItems.map((itemJson) {
          final sides =
              (itemJson[AppConstants.tableOrderItemSides] as List? ?? [])
                  .map((s) => OrderItemSide.fromJson(s as Map<String, dynamic>))
                  .toList();
          return OrderItem.fromJson({
            ...itemJson as Map<String, dynamic>,
            'sides': sides.map((s) => s.toJson()).toList(),
          });
        }).toList();
        return Order.fromJson({
          ...orderData,
          'items': items.map((item) => item.toJson()).toList(),
        });
      }).toList();

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

      // When order is marked ready, notify available drivers.
      // For multi-restaurant sub-orders, wait until ALL siblings are ready
      // before updating order_groups and notifying drivers.
      if (status == AppConstants.orderReady) {
        _supabaseClient
            .from(AppConstants.tableOrders)
            .select('is_pickup, is_multi_restaurant, order_group_id')
            .eq('id', orderId)
            .single()
            .then((row) async {
              final isPickup = row['is_pickup'] as bool? ?? false;
              final isMulti = row['is_multi_restaurant'] as bool? ?? false;
              final groupId = row['order_group_id'] as String?;

              if (isMulti && groupId != null) {
                final siblings = await _supabaseClient
                    .from(AppConstants.tableOrders)
                    .select('status')
                    .eq('order_group_id', groupId);
                final allReady = (siblings as List)
                    .every((o) => o['status'] == AppConstants.orderReady);
                if (allReady) {
                  await _supabaseClient
                      .from('order_groups')
                      .update({
                        'status': AppConstants.orderReady,
                        'updated_at': DateTime.now().toIso8601String(),
                      })
                      .eq('id', groupId);
                  _notifyAvailableDriversForGroup(orderGroupId: groupId);
                }
              } else if (!isPickup) {
                _notifyAvailableDrivers(orderId: orderId);
              }
            })
            .catchError((e) {
              AppLogger.error('Error checking order group ready status: $e');
            });
      }

      // Notify the customer. _notifyCustomer omits user_id from data so the
      // edge function does NOT insert into notifications — preventing
      // trg_notification_push_fcm from firing a second push.
      _supabaseClient
          .from(AppConstants.tableOrders)
          .select('user_id, is_multi_restaurant')
          .eq('id', orderId)
          .single()
          .then((order) {
            final userId = order['user_id'] as String?;
            final isMulti = order['is_multi_restaurant'] as bool? ?? false;
            if (userId != null && !isMulti) {
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

      // 1) Mirror onto the order row (legacy/in-app display).
      final Map<String, dynamic> orderUpdate = {
        'user_rating': rating,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (review != null) orderUpdate['user_review'] = review;
      if (foodRating != null) orderUpdate['food_rating'] = foodRating;
      if (deliveryRating != null)
        orderUpdate['delivery_rating'] = deliveryRating;
      if (packagingRating != null)
        orderUpdate['packaging_rating'] = packagingRating;
      if (photoUrl != null) orderUpdate['review_photo_url'] = photoUrl;

      await _supabaseClient
          .from(AppConstants.tableOrders)
          .update(orderUpdate)
          .eq('id', orderId);

      // 2) Canonical insert into `reviews` so analytics, restaurant
      //    rating aggregates, and the apology-coupon brain trigger fire.
      try {
        final order = await _supabaseClient
            .from(AppConstants.tableOrders)
            .select('user_id, restaurant_id, driver_id')
            .eq('id', orderId)
            .maybeSingle();

        if (order != null &&
            order['user_id'] != null &&
            order['restaurant_id'] != null) {
          await _supabaseClient.from(AppConstants.tableReviews).upsert({
            'order_id': orderId,
            'user_id': order['user_id'],
            'restaurant_id': order['restaurant_id'],
            'driver_id': order['driver_id'],
            'rating': rating,
            if (foodRating != null) 'food_quality': foodRating,
            if (deliveryRating != null) 'delivery_speed': deliveryRating,
            'review_text': review,
            'photo_url': photoUrl,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'order_id');
        }
      } catch (e) {
        // Non-fatal: order row already saved with the rating.
        AppLogger.warning('Failed to mirror review into reviews table: $e');
      }

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

  // Get orders for multiple restaurants (for multi-restaurant owners).
  // Single nested query — avoids N+1 round-trips for items/sides.
  Future<List<Order>> getOrdersForRestaurants(
    List<String> restaurantIds, {
    int? limit,
  }) async {
    try {
      if (restaurantIds.isEmpty) return [];
      AppLogger.info('Fetching orders for ${restaurantIds.length} restaurants');

      final query = _supabaseClient
          .from(AppConstants.tableOrders)
          .select(
            '*, items:${AppConstants.tableOrderItems}'
            '(*, sides:${AppConstants.tableOrderItemSides}(*))',
          )
          .inFilter('restaurant_id', restaurantIds);

      final response = limit != null
          ? await query.order('ordered_at', ascending: false).limit(limit)
          : await query.order('ordered_at', ascending: false);

      final orders = (response as List)
          .map((row) => Order.fromJson(row as Map<String, dynamic>))
          .toList();

      AppLogger.info('Fetched ${orders.length} orders across restaurants');
      return orders;
    } catch (e) {
      AppLogger.error('Error fetching orders for restaurants: $e');
      rethrow;
    }
  }

  // Get restaurant's orders — single nested query, no N+1
  Future<List<Order>> getRestaurantOrders(String restaurantId) async {
    try {
      AppLogger.info('Fetching orders for restaurant: $restaurantId');

      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select(
            '*, ${AppConstants.tableOrderItems}(*, ${AppConstants.tableOrderItemSides}(*))',
          )
          .eq('restaurant_id', restaurantId)
          .order('ordered_at', ascending: false);

      final orders = (response as List).map((orderData) {
        final rawItems =
            (orderData[AppConstants.tableOrderItems] as List? ?? []);
        final items = rawItems.map((itemJson) {
          final sides =
              (itemJson[AppConstants.tableOrderItemSides] as List? ?? [])
                  .map((s) => OrderItemSide.fromJson(s as Map<String, dynamic>))
                  .toList();
          return OrderItem.fromJson({
            ...itemJson as Map<String, dynamic>,
            'sides': sides.map((s) => s.toJson()).toList(),
          });
        }).toList();
        return Order.fromJson({
          ...orderData as Map<String, dynamic>,
          'items': items.map((item) => item.toJson()).toList(),
        });
      }).toList();

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

  /// Cancel every restaurant sub-order and the master order itself.
  /// Uses .select() on every UPDATE so a zero-row result (RLS block or missing
  /// row) is immediately surfaced as an exception rather than silent no-op.
  Future<void> cancelMasterOrder(String masterOrderId) async {
    AppLogger.info('[cancelMasterOrder] START id=$masterOrderId');
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      // ── New schema: master_orders + restaurant_orders ─────────────────────
      final masterRow = await _supabaseClient
          .from(AppConstants.tableMasterOrders)
          .select('status, customer_id, payment_method, payment_status, driver_id')
          .eq('id', masterOrderId)
          .maybeSingle();

      AppLogger.info('[cancelMasterOrder] master_orders fetch: $masterRow');

      if (masterRow != null) {
        final currentStatus = masterRow['status'] as String?;
        if (currentStatus == AppConstants.orderDelivered ||
            currentStatus == AppConstants.orderCancelled) {
          throw Exception('Order is already $currentStatus');
        }

        // ── Update master_orders FIRST ────────────────────────────────────────
        // This fires trg_master_order_cancel_notify (migration 114) exactly
        // once → inserts one notifications row → trg_notification_push_fcm
        // sends one FCM push.
        // Updating restaurant_orders afterward is safe because
        // fn_recalculate_master_status has a guard that skips rows where
        // master_orders.status is already 'cancelled', so no second
        // notification fires from the sub-order trigger chain.
        final masterResult = await _supabaseClient
            .from(AppConstants.tableMasterOrders)
            .update({'status': AppConstants.orderCancelled, 'cancelled_at': now})
            .eq('id', masterOrderId)
            .select('id, status');
        AppLogger.info('[cancelMasterOrder] master_orders updated: $masterResult');

        if ((masterResult as List).isEmpty) {
          throw Exception(
            'master_orders UPDATE returned 0 rows for id=$masterOrderId. '
            'Check the Row Level Security UPDATE policy on master_orders '
            '(migration 111 must be applied).',
          );
        }

        // ── Cancel sub-orders AFTER master is already cancelled ───────────────
        final subResult = await _supabaseClient
            .from(AppConstants.tableRestaurantOrders)
            .update({'status': AppConstants.orderCancelled, 'cancelled_at': now})
            .eq('master_order_id', masterOrderId)
            .neq('status', AppConstants.orderCancelled)
            .select('id');
        AppLogger.info('[cancelMasterOrder] restaurant_orders updated: ${(subResult as List).length} rows');

        final paymentMethod = masterRow['payment_method'] as String?;
        final paymentStatus = masterRow['payment_status'] as String?;
        if ((paymentMethod == 'card' || paymentMethod == 'stripe') &&
            paymentStatus == AppConstants.paymentCompleted) {
          try {
            await _supabaseClient.functions.invoke(
              AppConstants.stripePaymentFunction,
              body: {'action': 'refund', 'masterOrderId': masterOrderId},
            );
          } catch (e) {
            AppLogger.error('[cancelMasterOrder] Refund failed: $e');
          }
        }

        // Notify the customer directly via FCM.
        // _notifyCustomer omits user_id from data so the edge function does NOT
        // insert into notifications → trg_notification_push_fcm (migration 099)
        // does NOT fire a second push. If migration 114 DB trigger is also
        // applied, the client dedup suppresses the duplicate device push.
        final customerId = masterRow['customer_id'] as String?;
        if (customerId != null) {
          unawaited(_notifyCustomer(
            userId: customerId,
            orderId: masterOrderId,
            status: AppConstants.orderCancelled,
          ));
        }

        final driverId = masterRow['driver_id'] as String?;
        if (driverId != null) {
          try {
            await DriverService(_supabaseClient).updateDriverStats(driverId);
          } catch (e) {
            AppLogger.error('[cancelMasterOrder] Driver stats update failed: $e');
          }
        }

        AppLogger.info('[cancelMasterOrder] SUCCESS (new schema)');
        return;
      }

      // ── Legacy schema: order_groups + orders ───────────────────────────────
      AppLogger.info('[cancelMasterOrder] not in master_orders, trying order_groups');

      final groupRow = await _supabaseClient
          .from('order_groups')
          .select('status, customer_id, payment_method, payment_status')
          .eq('id', masterOrderId)
          .maybeSingle();

      AppLogger.info('[cancelMasterOrder] order_groups fetch: $groupRow');

      if (groupRow == null) {
        throw Exception(
          'Order $masterOrderId not found in master_orders or order_groups.',
        );
      }

      final currentStatus = groupRow['status'] as String?;
      if (currentStatus == AppConstants.orderDelivered ||
          currentStatus == AppConstants.orderCancelled) {
        throw Exception('Order is already $currentStatus');
      }

      final legacySubResult = await _supabaseClient
          .from(AppConstants.tableOrders)
          .update({'status': AppConstants.orderCancelled, 'cancelled_at': now, 'updated_at': now})
          .eq('order_group_id', masterOrderId)
          .neq('status', AppConstants.orderCancelled)
          .select('id');
      AppLogger.info('[cancelMasterOrder] orders (legacy) updated: ${(legacySubResult as List).length} rows');

      final legacyGroupResult = await _supabaseClient
          .from('order_groups')
          .update({'status': AppConstants.orderCancelled, 'updated_at': now})
          .eq('id', masterOrderId)
          .select('id, status');
      AppLogger.info('[cancelMasterOrder] order_groups updated: $legacyGroupResult');

      if ((legacyGroupResult as List).isEmpty) {
        throw Exception(
          'order_groups UPDATE returned 0 rows for id=$masterOrderId. '
          'Check RLS UPDATE policy on order_groups.',
        );
      }

      final legacyCustomerId = groupRow['customer_id'] as String?;
      if (legacyCustomerId != null) {
        unawaited(_notifyCustomer(
          userId: legacyCustomerId,
          orderId: masterOrderId,
          status: AppConstants.orderCancelled,
        ));
      }

      AppLogger.info('[cancelMasterOrder] SUCCESS (legacy schema)');
    } catch (e) {
      AppLogger.error('[cancelMasterOrder] FAILED: $e');
      rethrow;
    }
  }

  /// Cancel a single restaurant sub-order within a master order.
  /// Uses .select() on every UPDATE to detect zero-row silent RLS failures.
  Future<void> cancelRestaurantSubOrder({
    required String restaurantOrderId,
    required String masterOrderId,
  }) async {
    AppLogger.info('[cancelSubOrder] START sub=$restaurantOrderId master=$masterOrderId');
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      // ── New schema ──────────────────────────────────────────────────────────
      final roRow = await _supabaseClient
          .from(AppConstants.tableRestaurantOrders)
          .select('status, restaurant_id')
          .eq('id', restaurantOrderId)
          .maybeSingle();

      AppLogger.info('[cancelSubOrder] restaurant_orders fetch: $roRow');

      if (roRow != null) {
        final currentStatus = roRow['status'] as String?;
        if (currentStatus == AppConstants.orderCancelled ||
            currentStatus == AppConstants.orderPickedUp) {
          throw Exception('Cannot cancel sub-order with status: $currentStatus');
        }

        final subResult = await _supabaseClient
            .from(AppConstants.tableRestaurantOrders)
            .update({'status': AppConstants.orderCancelled, 'cancelled_at': now})
            .eq('id', restaurantOrderId)
            .select('id, status');
        AppLogger.info('[cancelSubOrder] restaurant_orders updated: $subResult');

        if ((subResult as List).isEmpty) {
          throw Exception(
            'restaurant_orders UPDATE returned 0 rows for id=$restaurantOrderId. '
            'Ensure the authenticated customer has an RLS UPDATE policy on restaurant_orders.',
          );
        }

        // The DB trigger fn_recalculate_master_status (SECURITY DEFINER) fires
        // automatically after restaurant_orders.status changes and recalculates
        // master_orders.status + stamps cancelled_at — no manual UPDATE needed.

        final siblings = await _supabaseClient
            .from(AppConstants.tableRestaurantOrders)
            .select('status')
            .eq('master_order_id', masterOrderId);

        final allCancelled = (siblings as List)
            .every((r) => (r as Map)['status'] == AppConstants.orderCancelled);

        AppLogger.info('[cancelSubOrder] all siblings cancelled: $allCancelled');

        final restaurantId = roRow['restaurant_id'] as String?;
        if (restaurantId != null) {
          unawaited(_notifyRestaurant(
            restaurantId: restaurantId,
            orderId: restaurantOrderId,
            status: AppConstants.orderCancelled,
          ));
        }

        // Notify customer — user_id omitted from data so edge function skips
        // the notifications insert and trg_notification_push_fcm doesn't re-fire.
        // If migration 114 DB trigger also fires, client dedup handles duplicate.
        final masterInfo = await _supabaseClient
            .from(AppConstants.tableMasterOrders)
            .select('customer_id, payment_method, payment_status, driver_id')
            .eq('id', masterOrderId)
            .maybeSingle();

        final customerId = masterInfo?['customer_id'] as String?;
        if (customerId != null) {
          unawaited(_notifyCustomer(
            userId: customerId,
            orderId: masterOrderId,
            status: AppConstants.orderCancelled,
          ));
        }

        if (allCancelled) {
          final paymentMethod = masterInfo?['payment_method'] as String?;
          final paymentStatus = masterInfo?['payment_status'] as String?;
          if ((paymentMethod == 'card' || paymentMethod == 'stripe') &&
              paymentStatus == AppConstants.paymentCompleted) {
            try {
              await _supabaseClient.functions.invoke(
                AppConstants.stripePaymentFunction,
                body: {'action': 'refund', 'masterOrderId': masterOrderId},
              );
            } catch (e) {
              AppLogger.error('[cancelSubOrder] Refund failed: $e');
            }
          }
        }

        AppLogger.info('[cancelSubOrder] SUCCESS (new schema), allCancelled=$allCancelled');
        return;
      }

      // ── Legacy schema (orders + order_groups) ──────────────────────────────
      AppLogger.info('[cancelSubOrder] not in restaurant_orders, trying orders table');

      final legacyRow = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('status, restaurant_id, order_group_id')
          .eq('id', restaurantOrderId)
          .maybeSingle();

      AppLogger.info('[cancelSubOrder] orders (legacy) fetch: $legacyRow');

      if (legacyRow == null) {
        throw Exception('Sub-order $restaurantOrderId not found in restaurant_orders or orders.');
      }

      final currentStatus = legacyRow['status'] as String?;
      if (currentStatus == AppConstants.orderCancelled ||
          currentStatus == AppConstants.orderPickedUp) {
        throw Exception('Cannot cancel sub-order with status: $currentStatus');
      }

      final legacySubResult = await _supabaseClient
          .from(AppConstants.tableOrders)
          .update({'status': AppConstants.orderCancelled, 'cancelled_at': now, 'updated_at': now})
          .eq('id', restaurantOrderId)
          .select('id, status');
      AppLogger.info('[cancelSubOrder] orders (legacy) updated: $legacySubResult');

      if ((legacySubResult as List).isEmpty) {
        throw Exception('orders UPDATE returned 0 rows for id=$restaurantOrderId. Check RLS.');
      }

      final groupId = legacyRow['order_group_id'] as String? ?? masterOrderId;
      final legacySiblings = await _supabaseClient
          .from(AppConstants.tableOrders)
          .select('status')
          .eq('order_group_id', groupId);

      final allCancelled = (legacySiblings as List)
          .every((r) => (r as Map)['status'] == AppConstants.orderCancelled);

      final groupResult = await _supabaseClient
          .from('order_groups')
          .update({
            'status': allCancelled ? AppConstants.orderCancelled : AppConstants.orderPartiallyCancelled,
            'updated_at': now,
          })
          .eq('id', groupId)
          .select('id, status');
      AppLogger.info('[cancelSubOrder] order_groups updated: $groupResult');

      AppLogger.info('[cancelSubOrder] SUCCESS (legacy schema)');
    } catch (e) {
      AppLogger.error('[cancelSubOrder] FAILED: $e');
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
      final Map<String, dynamic> payload = {'title': title, 'body': body};
      if (token != null) payload['token'] = token;
      if (topic != null) payload['topic'] = topic;
      if (data != null) payload['data'] = data;

      await _supabaseClient.functions.invoke(
        'send-fcm-notification',
        body: payload,
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

      // IMPORTANT: do NOT include user_id in the data payload.
      // The send-fcm-notification edge function inserts into the notifications
      // table only when data.user_id is present. That insert fires
      // trg_notification_push_fcm (migration 099) which calls the edge function
      // again — causing a duplicate push. Omitting user_id stops that loop.
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _sendPushNotification(
          token: fcmToken,
          title: title,
          body: body,
          data: {
            'type': AppConstants.notificationTypeOrderStatus,
            'order_id': orderId,
            'status': status,
          },
        );
      } else {
        await _sendPushNotification(
          topic: 'customer_$userId',
          title: title,
          body: body,
          data: {
            'type': AppConstants.notificationTypeOrderStatus,
            'order_id': orderId,
            'status': status,
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

  // Notify all available drivers that all stops of a multi-restaurant group are ready
  Future<void> _notifyAvailableDriversForGroup({
    required String orderGroupId,
  }) async {
    try {
      AppLogger.info(
        'Notifying available drivers about ready group: $orderGroupId',
      );

      final drivers = await _supabaseClient
          .from(AppConstants.tableDrivers)
          .select('id')
          .eq('is_available', true);

      await Future.wait(
        (drivers as List).map((driver) {
          final driverId = driver['id'] as String;
          return _sendPushNotification(
            topic: 'driver_$driverId',
            title: 'Multi-Stop Order Ready!',
            body: 'A multi-restaurant order is ready for all pickups. Tap to accept.',
            data: {
              'type': AppConstants.notificationTypeDeliveryUpdate,
              'order_group_id': orderGroupId,
              'status': AppConstants.orderReady,
              'user_id': driverId,
            },
          ).catchError((e) {
            AppLogger.error('Error notifying driver $driverId for group: $e');
          });
        }),
      );

      AppLogger.info(
        'Notified ${(drivers as List).length} drivers about group $orderGroupId',
      );
    } catch (e) {
      AppLogger.error('Error notifying drivers for group: $e');
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
