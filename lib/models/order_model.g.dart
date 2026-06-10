// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OrderItemSide _$OrderItemSideFromJson(Map<String, dynamic> json) =>
    OrderItemSide(
      id: json['id'] as String,
      sideName: json['side_name'] as String,
      sidePrice: (json['side_price'] as num).toDouble(),
    );

Map<String, dynamic> _$OrderItemSideToJson(OrderItemSide instance) =>
    <String, dynamic>{
      'id': instance.id,
      'side_name': instance.sideName,
      'side_price': instance.sidePrice,
    };

OrderItem _$OrderItemFromJson(Map<String, dynamic> json) => OrderItem(
      id: json['id'] as String,
      menuItemId: json['menu_item_id'] as String,
      itemName: json['item_name'] as String,
      price: (json['price'] as num).toDouble(),
      quantity: (json['quantity'] as num).toInt(),
      notes: json['notes'] as String?,
      sides: (json['sides'] as List<dynamic>?)
          ?.map((e) => OrderItemSide.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$OrderItemToJson(OrderItem instance) => <String, dynamic>{
      'id': instance.id,
      'menu_item_id': instance.menuItemId,
      'item_name': instance.itemName,
      'price': instance.price,
      'quantity': instance.quantity,
      'notes': instance.notes,
      'sides': instance.sides?.map((e) => e.toJson()).toList(),
    };

Order _$OrderFromJson(Map<String, dynamic> json) => Order(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      restaurantId: json['restaurant_id'] as String,
      driverId: json['driver_id'] as String?,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      subtotal: (json['subtotal'] as num).toDouble(),
      taxAmount: (json['tax_amount'] as num?)?.toDouble(),
      deliveryFee: (json['delivery_fee'] as num).toDouble(),
      discount: (json['discount'] as num?)?.toDouble(),
      totalAmount: (json['total_amount'] as num).toDouble(),
      status: json['status'] as String,
      deliveryAddress: json['delivery_address'] as String?,
      deliveryLatitude: (json['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude: (json['delivery_longitude'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      paymentMethod: json['payment_method'] as String?,
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      orderedAt: DateTime.parse(json['ordered_at'] as String),
      confirmedAt: json['confirmed_at'] == null
          ? null
          : DateTime.parse(json['confirmed_at'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      cancelledAt: json['cancelled_at'] == null
          ? null
          : DateTime.parse(json['cancelled_at'] as String),
      userRating: (json['user_rating'] as num?)?.toDouble(),
      userReview: json['user_review'] as String?,
      foodRating: (json['food_rating'] as num?)?.toInt(),
      deliveryRating: (json['delivery_rating'] as num?)?.toInt(),
      packagingRating: (json['packaging_rating'] as num?)?.toInt(),
      reviewPhotoUrl: json['review_photo_url'] as String?,
      contactlessDelivery: json['contactless_delivery'] as bool? ?? false,
      deliveryPhotoUrl: json['delivery_photo_url'] as String?,
      deliveryOtp: json['delivery_otp'] as String?,
      deliveryOtpVerified: json['delivery_otp_verified'] as bool?,
      driverRating: (json['driver_rating'] as num?)?.toInt(),
      driverTip: (json['driver_tip'] as num?)?.toDouble(),
      commissionAmount: (json['commission_amount'] as num?)?.toDouble(),
      commissionRate: (json['commission_rate'] as num?)?.toDouble(),
      scheduledFor: json['scheduled_for'] == null
          ? null
          : DateTime.parse(json['scheduled_for'] as String),
      isScheduled: json['is_scheduled'] as bool? ?? false,
      postDeliveryTip: (json['post_delivery_tip'] as num?)?.toDouble(),
      tipUpdatedAt: json['tip_updated_at'] == null
          ? null
          : DateTime.parse(json['tip_updated_at'] as String),
      receiptNumber: json['receipt_number'] as String?,
      receiptGeneratedAt: json['receipt_generated_at'] == null
          ? null
          : DateTime.parse(json['receipt_generated_at'] as String),
      estimatedDeliveryAt: json['estimated_delivery_at'] == null
          ? null
          : DateTime.parse(json['estimated_delivery_at'] as String),
      estimatedPrepMinutes: (json['estimated_prep_minutes'] as num?)?.toInt(),
      isPickup: json['is_pickup'] as bool? ?? false,
      pickupFee: (json['pickup_fee'] as num?)?.toDouble(),
      pickupCode: json['pickup_code'] as String?,
      fromAd: json['from_ad'] as bool? ?? false,
      adId: json['ad_id'] as String?,
      orderGroupId: json['order_group_id'] as String?,
      isMultiRestaurant: json['is_multi_restaurant'] as bool? ?? false,
      sequenceInGroup: (json['sequence_in_group'] as num?)?.toInt(),
      restaurantOrderNumber: json['restaurant_order_number'] as String?,
      outstandingDebtCharged:
          (json['outstanding_debt_charged'] as num?)?.toDouble() ?? 0,
    );

Map<String, dynamic> _$OrderToJson(Order instance) => <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'restaurant_id': instance.restaurantId,
      'driver_id': instance.driverId,
      'items': instance.items.map((e) => e.toJson()).toList(),
      'subtotal': instance.subtotal,
      'tax_amount': instance.taxAmount,
      'delivery_fee': instance.deliveryFee,
      'discount': instance.discount,
      'total_amount': instance.totalAmount,
      'status': instance.status,
      'delivery_address': instance.deliveryAddress,
      'delivery_latitude': instance.deliveryLatitude,
      'delivery_longitude': instance.deliveryLongitude,
      'notes': instance.notes,
      'payment_method': instance.paymentMethod,
      'payment_status': instance.paymentStatus,
      'ordered_at': instance.orderedAt.toIso8601String(),
      'confirmed_at': instance.confirmedAt?.toIso8601String(),
      'completed_at': instance.completedAt?.toIso8601String(),
      'cancelled_at': instance.cancelledAt?.toIso8601String(),
      'user_rating': instance.userRating,
      'user_review': instance.userReview,
      'food_rating': instance.foodRating,
      'delivery_rating': instance.deliveryRating,
      'packaging_rating': instance.packagingRating,
      'review_photo_url': instance.reviewPhotoUrl,
      'contactless_delivery': instance.contactlessDelivery,
      'delivery_photo_url': instance.deliveryPhotoUrl,
      'delivery_otp': instance.deliveryOtp,
      'delivery_otp_verified': instance.deliveryOtpVerified,
      'driver_rating': instance.driverRating,
      'driver_tip': instance.driverTip,
      'commission_amount': instance.commissionAmount,
      'commission_rate': instance.commissionRate,
      'scheduled_for': instance.scheduledFor?.toIso8601String(),
      'is_scheduled': instance.isScheduled,
      'post_delivery_tip': instance.postDeliveryTip,
      'tip_updated_at': instance.tipUpdatedAt?.toIso8601String(),
      'receipt_number': instance.receiptNumber,
      'receipt_generated_at': instance.receiptGeneratedAt?.toIso8601String(),
      'estimated_delivery_at': instance.estimatedDeliveryAt?.toIso8601String(),
      'estimated_prep_minutes': instance.estimatedPrepMinutes,
      'is_pickup': instance.isPickup,
      'pickup_fee': instance.pickupFee,
      'pickup_code': instance.pickupCode,
      'from_ad': instance.fromAd,
      'ad_id': instance.adId,
      'order_group_id': instance.orderGroupId,
      'is_multi_restaurant': instance.isMultiRestaurant,
      'sequence_in_group': instance.sequenceInGroup,
      'restaurant_order_number': instance.restaurantOrderNumber,
      'outstanding_debt_charged': instance.outstandingDebtCharged,
    };
