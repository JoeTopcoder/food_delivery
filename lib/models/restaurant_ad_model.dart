import 'package:json_annotation/json_annotation.dart';

part 'restaurant_ad_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class RestaurantAd {
  final String id;
  final String restaurantId;
  final String title;
  final String? description;
  final String? imageUrl;
  final bool isActive;
  final DateTime startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Joined restaurant data (optional, populated on fetch)
  final String? restaurantName;
  final String? restaurantImageUrl;
  final String? cuisineType;

  RestaurantAd({
    required this.id,
    required this.restaurantId,
    required this.title,
    this.description,
    this.imageUrl,
    this.isActive = true,
    required this.startsAt,
    this.endsAt,
    required this.createdAt,
    this.updatedAt,
    this.restaurantName,
    this.restaurantImageUrl,
    this.cuisineType,
  });

  factory RestaurantAd.fromJson(Map<String, dynamic> json) {
    // Handle joined restaurant data
    final restaurant = json['restaurants'] as Map<String, dynamic>?;
    if (restaurant != null) {
      json['restaurant_name'] = restaurant['name'];
      json['restaurant_image_url'] = restaurant['image_url'];
      json['cuisine_type'] = restaurant['cuisine_type'];
    }
    return _$RestaurantAdFromJson(json);
  }

  Map<String, dynamic> toJson() => _$RestaurantAdToJson(this);

  bool get isCurrentlyActive {
    if (!isActive) return false;
    final now = DateTime.now();
    if (now.isBefore(startsAt)) return false;
    if (endsAt != null && now.isAfter(endsAt!)) return false;
    return true;
  }
}
