class Banner {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String restaurantId;

  /// 'food' (default) or 'grocery'
  final String section;
  final bool isActive;
  final int sortOrder;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;

  // Joined restaurant name (optional, for admin list)
  final String? restaurantName;
  final bool? restaurantVerified;

  /// 'percentage' | 'fixed' | null (no discount attached to this banner)
  final String? discountType;
  final double? discountValue;
  /// What the discount is computed against: 'subtotal' (meal/food items),
  /// 'delivery_fee', or 'total'. Null when discountType is null.
  final String? appliesTo;
  /// The real promo_codes.code backing this banner's discount, if any —
  /// tapping the banner auto-applies this code for the customer.
  final String? promoCode;

  Banner({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    required this.restaurantId,
    this.section = 'food',
    this.isActive = true,
    this.sortOrder = 0,
    this.startsAt,
    this.endsAt,
    required this.createdAt,
    this.restaurantName,
    this.restaurantVerified,
    this.discountType,
    this.discountValue,
    this.appliesTo,
    this.promoCode,
  });

  factory Banner.fromJson(Map<String, dynamic> json) {
    final restaurant = json['restaurants'] as Map<String, dynamic>?;
    return Banner(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      imageUrl: json['image_url'] as String?,
      restaurantId: json['restaurant_id'] as String,
      section: json['section'] as String? ?? 'food',
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
      startsAt: json['starts_at'] != null
          ? DateTime.parse(json['starts_at'] as String)
          : null,
      endsAt: json['ends_at'] != null
          ? DateTime.parse(json['ends_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      restaurantName: restaurant?['name'] as String?,
      restaurantVerified: restaurant?['is_verified'] as bool?,
      discountType: json['discount_type'] as String?,
      discountValue: (json['discount_value'] as num?)?.toDouble(),
      appliesTo: json['applies_to'] as String?,
      promoCode: json['promo_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'subtitle': subtitle,
    'image_url': imageUrl,
    'restaurant_id': restaurantId,
    'section': section,
    'is_active': isActive,
    'sort_order': sortOrder,
    'starts_at': startsAt?.toIso8601String(),
    'ends_at': endsAt?.toIso8601String(),
    'discount_type': discountType,
    'discount_value': discountValue,
    'applies_to': appliesTo,
    'promo_code': promoCode,
  };
}
