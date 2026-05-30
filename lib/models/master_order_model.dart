// Models for the new multi-restaurant order tables:
//   master_orders → MasterOrder
//   restaurant_orders → RestaurantOrder
//   restaurant_order_items → RestaurantOrderItem
//   restaurant_order_item_sides → RestaurantOrderItemSide
//
// Written manually (no build_runner needed) so no .g.dart companion is required.

class RestaurantOrderItemSide {
  final String id;
  final String restaurantOrderItemId;
  final String sideName;
  final double sidePrice;

  const RestaurantOrderItemSide({
    required this.id,
    required this.restaurantOrderItemId,
    required this.sideName,
    required this.sidePrice,
  });

  factory RestaurantOrderItemSide.fromJson(Map<String, dynamic> json) =>
      RestaurantOrderItemSide(
        id:                     json['id'] as String? ?? '',
        restaurantOrderItemId:  json['restaurant_order_item_id'] as String? ?? '',
        sideName:               json['side_name'] as String,
        sidePrice:              (json['side_price'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
    'id':                      id,
    'restaurant_order_item_id': restaurantOrderItemId,
    'side_name':               sideName,
    'side_price':              sidePrice,
  };
}

class RestaurantOrderItem {
  final String id;
  final String restaurantOrderId;
  final String? menuItemId;
  final String itemName;
  final double price;
  final int quantity;
  final String? notes;
  final List<RestaurantOrderItemSide>? sides;

  const RestaurantOrderItem({
    required this.id,
    required this.restaurantOrderId,
    this.menuItemId,
    required this.itemName,
    required this.price,
    required this.quantity,
    this.notes,
    this.sides,
  });

  double get sidesTotal =>
      sides?.fold(0.0, (sum, s) => (sum ?? 0.0) + s.sidePrice) ?? 0.0;
  double get subtotal => (price + sidesTotal) * quantity;

  factory RestaurantOrderItem.fromJson(Map<String, dynamic> json) {
    final sidesRaw = json['restaurant_order_item_sides'] as List?;
    return RestaurantOrderItem(
      id:                  json['id'] as String? ?? '',
      restaurantOrderId:   json['restaurant_order_id'] as String? ?? '',
      menuItemId:          json['menu_item_id'] as String?,
      itemName:            json['item_name'] as String,
      price:               (json['price'] as num).toDouble(),
      quantity:            (json['quantity'] as num).toInt(),
      notes:               json['notes'] as String?,
      sides: sidesRaw
          ?.map((s) => RestaurantOrderItemSide.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RestaurantOrder {
  final String id;
  final String masterOrderId;
  final String restaurantId;
  final String? restaurantName;
  final String? restaurantOrderNumber;
  final String status;
  final double subtotal;
  final double deliveryFee;
  final double? commissionRate;
  final double? commissionAmount;
  final double? distanceKm;
  final int? estimatedPrepMinutes;
  final String? notes;
  final int sequenceInGroup;
  final String? deliveryOtp;
  final String pickupStatus;
  final DateTime? confirmedAt;
  final DateTime? preparingAt;
  final DateTime? readyAt;
  final DateTime? cancelledAt;
  final DateTime? pickedUpAt;
  final DateTime createdAt;
  final List<RestaurantOrderItem>? items;

  // Delivery info from master_orders join (for restaurant dashboard)
  final String? deliveryAddress;
  final bool contactlessDelivery;
  final String? paymentMethod;

  const RestaurantOrder({
    required this.id,
    required this.masterOrderId,
    required this.restaurantId,
    this.restaurantName,
    this.restaurantOrderNumber,
    required this.status,
    required this.subtotal,
    this.deliveryFee = 0,
    this.commissionRate,
    this.commissionAmount,
    this.distanceKm,
    this.estimatedPrepMinutes,
    this.notes,
    this.sequenceInGroup = 1,
    this.deliveryOtp,
    this.pickupStatus = 'pending',
    this.confirmedAt,
    this.preparingAt,
    this.readyAt,
    this.cancelledAt,
    this.pickedUpAt,
    required this.createdAt,
    this.items,
    this.deliveryAddress,
    this.contactlessDelivery = false,
    this.paymentMethod,
  });

  RestaurantOrder copyWith({String? status, String? pickupStatus}) => RestaurantOrder(
    id:                     id,
    masterOrderId:          masterOrderId,
    restaurantId:           restaurantId,
    restaurantName:         restaurantName,
    restaurantOrderNumber:  restaurantOrderNumber,
    status:                 status ?? this.status,
    subtotal:               subtotal,
    deliveryFee:            deliveryFee,
    commissionRate:         commissionRate,
    commissionAmount:       commissionAmount,
    distanceKm:             distanceKm,
    estimatedPrepMinutes:   estimatedPrepMinutes,
    notes:                  notes,
    sequenceInGroup:        sequenceInGroup,
    deliveryOtp:            deliveryOtp,
    pickupStatus:           pickupStatus ?? this.pickupStatus,
    confirmedAt:            confirmedAt,
    preparingAt:            preparingAt,
    readyAt:                readyAt,
    cancelledAt:            cancelledAt,
    pickedUpAt:             pickedUpAt,
    createdAt:              createdAt,
    items:                  items,
    deliveryAddress:        deliveryAddress,
    contactlessDelivery:    contactlessDelivery,
    paymentMethod:          paymentMethod,
  );

  factory RestaurantOrder.fromJson(Map<String, dynamic> json) {
    final itemsRaw       = json['restaurant_order_items'] as List?;
    final restaurantData = json['restaurants'] as Map<String, dynamic>?;
    final masterData     = json['master_orders'] as Map<String, dynamic>?;

    return RestaurantOrder(
      id:                    json['id'] as String,
      masterOrderId:         json['master_order_id'] as String? ?? '',
      restaurantId:          json['restaurant_id'] as String,
      restaurantName:        restaurantData?['name'] as String?,
      restaurantOrderNumber: json['restaurant_order_number'] as String?,
      status:                json['status'] as String? ?? 'pending',
      subtotal:              (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      deliveryFee:           (json['delivery_fee'] as num?)?.toDouble() ?? 0.0,
      commissionRate:        (json['commission_rate'] as num?)?.toDouble(),
      commissionAmount:      (json['commission_amount'] as num?)?.toDouble(),
      distanceKm:            (json['distance_km'] as num?)?.toDouble(),
      estimatedPrepMinutes:  (json['estimated_prep_minutes'] as num?)?.toInt(),
      notes:                 json['notes'] as String?,
      sequenceInGroup:       (json['sequence_in_group'] as num?)?.toInt() ?? 1,
      deliveryOtp:           json['delivery_otp'] as String?,
      pickupStatus:          json['pickup_status'] as String? ?? 'pending',
      confirmedAt:  _parseDate(json['confirmed_at']),
      preparingAt:  _parseDate(json['preparing_at']),
      readyAt:      _parseDate(json['ready_at']),
      cancelledAt:  _parseDate(json['cancelled_at']),
      pickedUpAt:   _parseDate(json['picked_up_at']),
      createdAt:    DateTime.parse(json['created_at'] as String),
      items: itemsRaw
          ?.map((i) => RestaurantOrderItem.fromJson(i as Map<String, dynamic>))
          .toList(),
      deliveryAddress:     masterData?['delivery_address'] as String?,
      contactlessDelivery: masterData?['contactless_delivery'] as bool? ?? false,
      paymentMethod:       masterData?['payment_method'] as String?,
    );
  }

  static DateTime? _parseDate(dynamic val) =>
      val == null ? null : DateTime.parse(val as String);
}

class MasterOrder {
  final String id;
  final String customerId;
  final String? masterOrderNumber;
  final String status;
  final String deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String paymentMethod;
  final String paymentStatus;
  final double subtotal;
  final double deliveryFee;
  final double extraStopFee;
  final double platformFee;
  final double taxAmount;
  final double discount;
  final double totalAmount;
  final String? driverId;
  final String? notes;
  final bool isPickup;
  final bool contactlessDelivery;
  final double? driverTip;
  final double? postDeliveryTip;
  final String? deliveryOtp;
  final bool? deliveryOtpVerified;
  final String? deliveryPhotoUrl;
  final DateTime? estimatedDeliveryAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final List<RestaurantOrder>? restaurantOrders;

  const MasterOrder({
    required this.id,
    required this.customerId,
    this.masterOrderNumber,
    required this.status,
    required this.deliveryAddress,
    this.deliveryLatitude,
    this.deliveryLongitude,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.subtotal,
    required this.deliveryFee,
    this.extraStopFee = 0,
    this.platformFee = 0,
    this.taxAmount = 0,
    this.discount = 0,
    required this.totalAmount,
    this.driverId,
    this.notes,
    this.isPickup = false,
    this.contactlessDelivery = false,
    this.driverTip,
    this.postDeliveryTip,
    this.deliveryOtp,
    this.deliveryOtpVerified,
    this.deliveryPhotoUrl,
    this.estimatedDeliveryAt,
    this.deliveredAt,
    this.cancelledAt,
    required this.createdAt,
    this.restaurantOrders,
  });

  int get restaurantCount => restaurantOrders?.length ?? 0;

  bool get isDelivered  => status == 'delivered';
  bool get isCancelled  => status == 'cancelled' || status == 'partially_cancelled';
  bool get isActive     => !isDelivered && !isCancelled;

  factory MasterOrder.fromJson(Map<String, dynamic> json) {
    final roRaw = json['restaurant_orders'] as List?;
    final orders = roRaw
        ?.map((r) => RestaurantOrder.fromJson(r as Map<String, dynamic>))
        .toList();
    orders?.sort((a, b) => a.sequenceInGroup.compareTo(b.sequenceInGroup));

    return MasterOrder(
      id:                  json['id'] as String,
      customerId:          json['customer_id'] as String,
      masterOrderNumber:   json['master_order_number'] as String?,
      status:              json['status'] as String? ?? 'pending',
      deliveryAddress:     json['delivery_address'] as String? ?? '',
      deliveryLatitude:    (json['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude:   (json['delivery_longitude'] as num?)?.toDouble(),
      paymentMethod:       json['payment_method'] as String? ?? 'stripe',
      paymentStatus:       json['payment_status'] as String? ?? 'pending',
      subtotal:            (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      deliveryFee:         (json['delivery_fee'] as num?)?.toDouble() ?? 0.0,
      extraStopFee:        (json['extra_stop_fee'] as num?)?.toDouble() ?? 0.0,
      platformFee:         (json['platform_fee'] as num?)?.toDouble() ?? 0.0,
      taxAmount:           (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      discount:            (json['discount'] as num?)?.toDouble() ?? 0.0,
      totalAmount:         (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      driverId:            json['driver_id'] as String?,
      notes:               json['notes'] as String?,
      isPickup:            json['is_pickup'] as bool? ?? false,
      contactlessDelivery: json['contactless_delivery'] as bool? ?? false,
      driverTip:           (json['driver_tip'] as num?)?.toDouble(),
      postDeliveryTip:     (json['post_delivery_tip'] as num?)?.toDouble(),
      deliveryOtp:         json['delivery_otp'] as String?,
      deliveryOtpVerified: json['delivery_otp_verified'] as bool?,
      deliveryPhotoUrl:    json['delivery_photo_url'] as String?,
      estimatedDeliveryAt: _parseDate(json['estimated_delivery_at']),
      deliveredAt:         _parseDate(json['delivered_at']),
      cancelledAt:         _parseDate(json['cancelled_at']),
      createdAt:           DateTime.parse(json['created_at'] as String),
      restaurantOrders:    orders,
    );
  }

  static DateTime? _parseDate(dynamic val) =>
      val == null ? null : DateTime.parse(val as String);
}
