// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'restaurant_ad_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RestaurantAd _$RestaurantAdFromJson(Map<String, dynamic> json) => RestaurantAd(
  id: json['id'] as String,
  restaurantId: json['restaurant_id'] as String,
  title: json['title'] as String,
  description: json['description'] as String?,
  imageUrl: json['image_url'] as String?,
  isActive: json['is_active'] as bool? ?? true,
  startsAt: DateTime.parse(json['starts_at'] as String),
  endsAt: json['ends_at'] == null
      ? null
      : DateTime.parse(json['ends_at'] as String),
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: json['updated_at'] == null
      ? null
      : DateTime.parse(json['updated_at'] as String),
  restaurantName: json['restaurant_name'] as String?,
  restaurantImageUrl: json['restaurant_image_url'] as String?,
  cuisineType: json['cuisine_type'] as String?,
);

Map<String, dynamic> _$RestaurantAdToJson(RestaurantAd instance) =>
    <String, dynamic>{
      'id': instance.id,
      'restaurant_id': instance.restaurantId,
      'title': instance.title,
      'description': instance.description,
      'image_url': instance.imageUrl,
      'is_active': instance.isActive,
      'starts_at': instance.startsAt.toIso8601String(),
      'ends_at': instance.endsAt?.toIso8601String(),
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
      'restaurant_name': instance.restaurantName,
      'restaurant_image_url': instance.restaurantImageUrl,
      'cuisine_type': instance.cuisineType,
    };
