import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../models/order_model.dart';
import '../services/driver_service.dart';
import '../utils/app_logger.dart';

class OrderService {
  final SupabaseClient _supabaseClient;

  OrderService(this._supabaseClient);

  // Create order
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
  }) async {
    try {
      AppLogger.info('Creating order for user: $userId');

      // Fetch restaurant commission rate
      final restaurantData = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select('commission_rate')
          .eq('id', restaurantId)
          .single();
      final commissionRate =
          (restaurantData['commission_rate'] ??
                  AppConstants.defaultCommissionRate)
              .toDouble();
      final commissionAmount = totalAmount * commissionRate;

      // Generate 4-digit OTP for delivery verification
      final otp = (1000 + (DateTime.now().millisecondsSinceEpoch % 9000))
          .toString();

      final response = await _supabaseClient
          .from(AppConstants.tableOrders)
          .insert({
            'user_id': userId,
            'restaurant_id': restaurantId,
            'subtotal': subtotal,
            'tax_amount': ?taxAmount,
            'delivery_fee': deliveryFee,
            'total_amount': totalAmount,
            'status': AppConstants.orderPending,
            'delivery_address': deliveryAddress,
            'delivery_latitude': deliveryLatitude,
            'delivery_longitude': deliveryLongitude,
            'notes': ?notes,
            'payment_method': paymentMethod ?? 'cash',
            'payment_status': AppConstants.paymentPending,
            'ordered_at': DateTime.now().toIso8601String(),
            'contactless_delivery': contactlessDelivery,
            'delivery_otp': otp,
            if (discount != null && discount > 0) 'discount': discount,
            if (driverTip != null && driverTip > 0) 'driver_tip': driverTip,
            if (scheduledFor != null)
              'scheduled_for': scheduledFor.toIso8601String(),
            if (scheduledFor != null) 'is_scheduled': true,
            'commission_rate': commissionRate,
            'commission_amount': commissionAmount,
          })
          .select()
          .single();

      final orderId = response['id'];

      // Insert order items and their sides
      for (final item in items) {
        final itemResponse = await _supabaseClient
            .from(AppConstants.tableOrderItems)
            .insert({
              'order_id': orderId,
              'menu_item_id': item.menuItemId,
              'item_name': item.itemName,
              'price': item.price,
              'quantity': item.quantity,
              'subtotal': item.subtotal,
              if (item.notes != null) 'notes': item.notes,
            })
            .select()
            .single();

        if (item.sides != null && item.sides!.isNotEmpty) {
          final sideRows = item.sides!
              .map(
                (s) => {
                  'order_item_id': itemResponse['id'],
                  'side_name': s.sideName,
                  'side_price': s.sidePrice,
                },
              )
              .toList();
          await _supabaseClient
              .from(AppConstants.tableOrderItemSides)
              .insert(sideRows);
        }
      }

      // Fetch complete order
      final completeOrder = await getOrderById(orderId);
      AppLogger.info('Order created successfully');
      return completeOrder;
    } catch (e) {
      AppLogger.error('Error creating order: $e');
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

      // When order is marked ready, notify all available drivers
      if (status == AppConstants.orderReady) {
        await _notifyAvailableDrivers(orderId: orderId);
      }

      // Notify the customer on every status change
      try {
        final order = await _supabaseClient
            .from(AppConstants.tableOrders)
            .select('user_id')
            .eq('id', orderId)
            .single();
        final userId = order['user_id'] as String?;
        if (userId != null) {
          await _notifyCustomer(
            userId: userId,
            orderId: orderId,
            status: status,
          );
        }
      } catch (e) {
        AppLogger.error('Error sending customer notification: $e');
      }

      // Notify admins on every status change
      try {
        await _sendPushNotification(
          topic: AppConstants.fcmTopicAdmins,
          title: 'Order Status Update',
          body:
              'Order #${orderId.substring(0, 8)} → ${status.replaceAll('_', ' ')}',
          data: {
            'type': AppConstants.notificationTypeOrderStatus,
            'order_id': orderId,
            'status': status,
          },
        );
      } catch (e) {
        AppLogger.error('Error sending admin notification: $e');
      }

      AppLogger.info('Order status updated successfully');
    } catch (e) {
      AppLogger.error('Error updating order status: $e');
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
          .select('status, driver_id')
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

      // Note: Notification record can be saved to database if needed
      // await _supabaseClient.from('notifications').insert({...});

      // Notify restaurant
      await _notifyRestaurant(
        restaurantId: restaurantId,
        orderId: orderId,
        status: status,
      );

      // Notify customer
      await _notifyCustomer(userId: userId, orderId: orderId, status: status);

      // Notify driver (if assigned)
      if (driverId != null && driverId.isNotEmpty) {
        await _notifyDriver(
          driverId: driverId,
          orderId: orderId,
          status: status,
        );
      }

      // When order is marked ready, notify all available drivers
      if (status == AppConstants.orderReady) {
        await _notifyAvailableDrivers(orderId: orderId);
      }

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
        body: 'Order #${orderId.substring(0, 8)}',
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
      final body = _getCustomerNotificationBody(status);
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
        body: 'Order #${orderId.substring(0, 8)}',
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

      for (final driver in drivers) {
        final driverId = driver['id'] as String;
        await _sendPushNotification(
          topic: 'driver_$driverId',
          title: 'New Order Ready for Pickup!',
          body: 'Order #${orderId.substring(0, 8)} is ready. Tap to accept.',
          data: {
            'type': AppConstants.notificationTypeDeliveryUpdate,
            'order_id': orderId,
            'status': AppConstants.orderReady,
            'user_id': driverId,
          },
        );
      }

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
  String _getCustomerNotificationBody(String status) {
    switch (status) {
      case 'confirmed':
        return 'Your order has been confirmed by the restaurant';
      case 'preparing':
        return 'Your delicious food is being prepared';
      case 'ready':
        return 'Your order is ready for pickup';
      case 'picked_up':
        return 'Your order has been picked up by the driver';
      case 'on_the_way':
        return 'Your food will arrive in approximately 20 minutes';
      case 'delivered':
        return 'Thank you for ordering! Rate your experience';
      case 'cancelled':
        return 'Your order has been cancelled';
      default:
        return 'Your order has been updated';
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
