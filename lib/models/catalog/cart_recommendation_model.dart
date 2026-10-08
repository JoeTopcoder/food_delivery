class CartRecommendation {
  final String restaurantId;
  final String restaurantName;
  final String? cuisineType;
  final double? rating;
  final String? imageUrl;
  final int? estimatedDeliveryTime;
  final double? distanceKm;
  final double? deliveryFee;
  final String reason;
  final bool isCoOrder;

  const CartRecommendation({
    required this.restaurantId,
    required this.restaurantName,
    this.cuisineType,
    this.rating,
    this.imageUrl,
    this.estimatedDeliveryTime,
    this.distanceKm,
    this.deliveryFee,
    required this.reason,
    this.isCoOrder = false,
  });

  factory CartRecommendation.fromJson(Map<String, dynamic> j) {
    return CartRecommendation(
      restaurantId:          j['restaurant_id'] as String,
      restaurantName:        j['restaurant_name'] as String,
      cuisineType:           j['cuisine_type'] as String?,
      rating:                (j['rating'] as num?)?.toDouble(),
      imageUrl:              j['image_url'] as String?,
      estimatedDeliveryTime: (j['estimated_delivery_time'] as num?)?.toInt(),
      distanceKm:            (j['distance_km'] as num?)?.toDouble(),
      deliveryFee:           (j['delivery_fee'] as num?)?.toDouble(),
      reason:                j['reason'] as String? ?? '',
      isCoOrder:             j['is_co_order'] as bool? ?? false,
    );
  }
}
