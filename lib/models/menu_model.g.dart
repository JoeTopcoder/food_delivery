// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'menu_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MenuItemSide _$MenuItemSideFromJson(Map<String, dynamic> json) => MenuItemSide(
      id: json['id'] as String,
      menuItemId: json['menu_item_id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      isAvailable: json['is_available'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$MenuItemSideToJson(MenuItemSide instance) =>
    <String, dynamic>{
      'id': instance.id,
      'menu_item_id': instance.menuItemId,
      'name': instance.name,
      'price': instance.price,
      'is_available': instance.isAvailable,
      'created_at': instance.createdAt.toIso8601String(),
    };

MenuItem _$MenuItemFromJson(Map<String, dynamic> json) => MenuItem(
      id: json['id'] as String,
      restaurantId: json['restaurant_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: (json['price'] as num).toDouble(),
      imageUrl: json['image_url'] as String?,
      category: json['category'] as String,
      isAvailable: json['is_available'] as bool? ?? true,
      discount: (json['discount'] as num?)?.toDouble(),
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      preparationTime: (json['preparation_time'] as num?)?.toInt(),
      sides: (json['sides'] as List<dynamic>?)
          ?.map((e) => MenuItemSide.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$MenuItemToJson(MenuItem instance) => <String, dynamic>{
      'id': instance.id,
      'restaurant_id': instance.restaurantId,
      'name': instance.name,
      'description': instance.description,
      'price': instance.price,
      'image_url': instance.imageUrl,
      'category': instance.category,
      'is_available': instance.isAvailable,
      'discount': instance.discount,
      'tags': instance.tags,
      'preparation_time': instance.preparationTime,
      'sides': instance.sides?.map((e) => e.toJson()).toList(),
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };
