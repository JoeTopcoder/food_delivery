class Banner {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String restaurantId;
  final bool isActive;
  final int sortOrder;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;

  // Joined restaurant name (optional, for admin list)
  final String? restaurantName;
  final bool? restaurantVerified;

  Banner({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    required this.restaurantId,
    this.isActive = true,
    this.sortOrder = 0,
    this.startsAt,
    this.endsAt,
    required this.createdAt,
    this.restaurantName,
    this.restaurantVerified,
  });

  factory Banner.fromJson(Map<String, dynamic> json) {
    final restaurant = json['restaurants'] as Map<String, dynamic>?;
    return Banner(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      imageUrl: json['image_url'] as String?,
      restaurantId: json['restaurant_id'] as String,
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
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'subtitle': subtitle,
    'image_url': imageUrl,
    'restaurant_id': restaurantId,
    'is_active': isActive,
    'sort_order': sortOrder,
    'starts_at': startsAt?.toIso8601String(),
    'ends_at': endsAt?.toIso8601String(),
  };
}
