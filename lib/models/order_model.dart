import 'package:json_annotation/json_annotation.dart';

part 'order_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class OrderItemSide {
  final String id;
  final String sideName;
  final double sidePrice;

  OrderItemSide({
    required this.id,
    required this.sideName,
    required this.sidePrice,
  });

  factory OrderItemSide.fromJson(Map<String, dynamic> json) =>
      _$OrderItemSideFromJson(json);
  Map<String, dynamic> toJson() => _$OrderItemSideToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class OrderItem {
  final String id;
  final String menuItemId;
  final String itemName;
  final double price;
  final int quantity;
  final String? notes;
  final List<OrderItemSide>? sides;

  OrderItem({
    required this.id,
    required this.menuItemId,
    required this.itemName,
    required this.price,
    required this.quantity,
    this.notes,
    this.sides,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) =>
      _$OrderItemFromJson(json);
  Map<String, dynamic> toJson() => _$OrderItemToJson(this);

  double get sidesTotal =>
      sides?.fold(0.0, (sum, s) => sum! + s.sidePrice) ?? 0.0;

  double get subtotal => (price + sidesTotal) * quantity;
}

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class Order {
  final String id;
  final String userId;
  final String restaurantId;
  final String? driverId;
  final List<OrderItem> items;
  final double subtotal;
  final double? taxAmount;
  final double deliveryFee;
  final double? discount;
  final double totalAmount;
  final String
  status; // pending, confirmed, preparing, ready, out_for_delivery, delivered, cancelled
  final String? deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String? notes;
  final String? paymentMethod;
  final String paymentStatus; // pending, completed, failed
  final DateTime orderedAt;
  final DateTime? confirmedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final double? userRating;
  final String? userReview;
  final int? foodRating;
  final int? deliveryRating;
  final int? packagingRating;
  final String? reviewPhotoUrl;
  final bool contactlessDelivery;
  final String? deliveryPhotoUrl;
  final String? deliveryOtp;
  final bool? deliveryOtpVerified;
  final int? driverRating;
  final double? driverTip;
  final double? commissionAmount;
  final double? commissionRate;
  final DateTime? scheduledFor;
  final bool isScheduled;
  final double? postDeliveryTip;
  final DateTime? tipUpdatedAt;
  final String? receiptNumber;
  final DateTime? receiptGeneratedAt;
  final DateTime? estimatedDeliveryAt;
  final int? estimatedPrepMinutes;

  Order({
    required this.id,
    required this.userId,
    required this.restaurantId,
    this.driverId,
    required this.items,
    required this.subtotal,
    this.taxAmount,
    required this.deliveryFee,
    this.discount,
    required this.totalAmount,
    required this.status,
    this.deliveryAddress,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.notes,
    this.paymentMethod,
    this.paymentStatus = 'pending',
    required this.orderedAt,
    this.confirmedAt,
    this.completedAt,
    this.cancelledAt,
    this.userRating,
    this.userReview,
    this.foodRating,
    this.deliveryRating,
    this.packagingRating,
    this.reviewPhotoUrl,
    this.contactlessDelivery = false,
    this.deliveryPhotoUrl,
    this.deliveryOtp,
    this.deliveryOtpVerified,
    this.driverRating,
    this.driverTip,
    this.commissionAmount,
    this.commissionRate,
    this.scheduledFor,
    this.isScheduled = false,
    this.postDeliveryTip,
    this.tipUpdatedAt,
    this.receiptNumber,
    this.receiptGeneratedAt,
    this.estimatedDeliveryAt,
    this.estimatedPrepMinutes,
  });

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);
  Map<String, dynamic> toJson() => _$OrderToJson(this);

  Order copyWith({
    String? id,
    String? userId,
    String? restaurantId,
    String? driverId,
    List<OrderItem>? items,
    double? subtotal,
    double? taxAmount,
    double? deliveryFee,
    double? discount,
    double? totalAmount,
    String? status,
    String? deliveryAddress,
    double? deliveryLatitude,
    double? deliveryLongitude,
    String? notes,
    String? paymentMethod,
    String? paymentStatus,
    DateTime? orderedAt,
    DateTime? confirmedAt,
    DateTime? completedAt,
    DateTime? cancelledAt,
    double? userRating,
    String? userReview,
    int? foodRating,
    int? deliveryRating,
    int? packagingRating,
    String? reviewPhotoUrl,
    bool? contactlessDelivery,
    String? deliveryPhotoUrl,
    String? deliveryOtp,
    bool? deliveryOtpVerified,
    int? driverRating,
    double? driverTip,
    double? commissionAmount,
    double? commissionRate,
    DateTime? scheduledFor,
    bool? isScheduled,
    double? postDeliveryTip,
    DateTime? tipUpdatedAt,
    String? receiptNumber,
    DateTime? receiptGeneratedAt,
    DateTime? estimatedDeliveryAt,
    int? estimatedPrepMinutes,
  }) {
    return Order(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      restaurantId: restaurantId ?? this.restaurantId,
      driverId: driverId ?? this.driverId,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      discount: discount ?? this.discount,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      deliveryLatitude: deliveryLatitude ?? this.deliveryLatitude,
      deliveryLongitude: deliveryLongitude ?? this.deliveryLongitude,
      notes: notes ?? this.notes,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      orderedAt: orderedAt ?? this.orderedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      completedAt: completedAt ?? this.completedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      userRating: userRating ?? this.userRating,
      userReview: userReview ?? this.userReview,
      foodRating: foodRating ?? this.foodRating,
      deliveryRating: deliveryRating ?? this.deliveryRating,
      packagingRating: packagingRating ?? this.packagingRating,
      reviewPhotoUrl: reviewPhotoUrl ?? this.reviewPhotoUrl,
      contactlessDelivery: contactlessDelivery ?? this.contactlessDelivery,
      deliveryPhotoUrl: deliveryPhotoUrl ?? this.deliveryPhotoUrl,
      deliveryOtp: deliveryOtp ?? this.deliveryOtp,
      deliveryOtpVerified: deliveryOtpVerified ?? this.deliveryOtpVerified,
      driverRating: driverRating ?? this.driverRating,
      driverTip: driverTip ?? this.driverTip,
      commissionAmount: commissionAmount ?? this.commissionAmount,
      commissionRate: commissionRate ?? this.commissionRate,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      isScheduled: isScheduled ?? this.isScheduled,
      postDeliveryTip: postDeliveryTip ?? this.postDeliveryTip,
      tipUpdatedAt: tipUpdatedAt ?? this.tipUpdatedAt,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      receiptGeneratedAt: receiptGeneratedAt ?? this.receiptGeneratedAt,
      estimatedDeliveryAt: estimatedDeliveryAt ?? this.estimatedDeliveryAt,
      estimatedPrepMinutes: estimatedPrepMinutes ?? this.estimatedPrepMinutes,
    );
  }
}
