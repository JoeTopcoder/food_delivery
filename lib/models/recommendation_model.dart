/// An AI-scored restaurant recommendation for a specific user.
class SmartRecommendation {
  final String restaurantId;
  final String restaurantName;
  final String? cuisineType;
  final double rating;
  final String? imageUrl;
  final double deliveryFee;
  final int? estimatedDeliveryTime;
  final bool isOpen;
  final double distanceKm;
  final double finalScore;
  final String section;
  final String reason;

  const SmartRecommendation({
    required this.restaurantId,
    required this.restaurantName,
    this.cuisineType,
    this.rating = 0,
    this.imageUrl,
    this.deliveryFee = 0,
    this.estimatedDeliveryTime,
    this.isOpen = true,
    this.distanceKm = 0,
    this.finalScore = 0,
    required this.section,
    required this.reason,
  });

  factory SmartRecommendation.fromJson(Map<String, dynamic> json) =>
      SmartRecommendation(
        restaurantId: json['restaurant_id'] as String,
        restaurantName: json['restaurant_name'] as String? ?? '',
        cuisineType: json['cuisine_type'] as String?,
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        imageUrl: json['image_url'] as String?,
        deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0,
        estimatedDeliveryTime: json['estimated_delivery_time'] as int?,
        isOpen: json['is_open'] as bool? ?? true,
        distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
        finalScore: (json['final_score'] as num?)?.toDouble() ?? 0,
        section: json['section'] as String? ?? 'for_you',
        reason: json['reason'] as String? ?? 'Recommended for you',
      );
}

/// AI-generated targeted coupon.
class SmartCoupon {
  final String? id;
  final String code;
  final int discountPercent;
  final double minOrder;
  final String reason;
  final int expiresInHours;

  const SmartCoupon({
    this.id,
    required this.code,
    required this.discountPercent,
    this.minOrder = 0,
    required this.reason,
    this.expiresInHours = 72,
  });

  factory SmartCoupon.fromJson(Map<String, dynamic> json) => SmartCoupon(
    id: json['coupon_id'] as String?,
    code: json['code'] as String? ?? '',
    discountPercent: json['discount_percent'] as int? ?? 0,
    minOrder: (json['min_order'] as num?)?.toDouble() ?? 0,
    reason: json['reason'] as String? ?? '',
    expiresInHours: json['expires_in_hours'] as int? ?? 72,
  );
}

/// The complete response from the brain engine for the home screen.
class BrainEngineResponse {
  final List<SmartRecommendation> forYou;
  final List<SmartRecommendation> becauseYouLove;
  final List<SmartRecommendation> dealsForYou;
  final List<SmartRecommendation> quickDelivery;
  final SmartCoupon? activeCoupon;
  final String userSegment;
  final double churnRisk;
  final String? topCuisine;

  const BrainEngineResponse({
    this.forYou = const [],
    this.becauseYouLove = const [],
    this.dealsForYou = const [],
    this.quickDelivery = const [],
    this.activeCoupon,
    this.userSegment = 'new_user',
    this.churnRisk = 0,
    this.topCuisine,
  });

  bool get hasPersonalizedContent =>
      forYou.isNotEmpty ||
      becauseYouLove.isNotEmpty ||
      dealsForYou.isNotEmpty ||
      quickDelivery.isNotEmpty;

  List<SmartRecommendation> get allRecommendations => [
    ...forYou,
    ...becauseYouLove,
    ...dealsForYou,
    ...quickDelivery,
  ];
}
