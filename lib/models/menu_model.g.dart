// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: unused_element

part of 'menu_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OptionChoice _$OptionChoiceFromJson(Map<String, dynamic> json) => OptionChoice(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      isAvailable: json['is_available'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$OptionChoiceToJson(OptionChoice instance) =>
    <String, dynamic>{
      'id': instance.id,
      'group_id': instance.groupId,
      'name': instance.name,
      'price': instance.price,
      'is_available': instance.isAvailable,
      'sort_order': instance.sortOrder,
    };

OptionGroup _$OptionGroupFromJson(Map<String, dynamic> json) => OptionGroup(
      id: json['id'] as String,
      menuItemId: json['menu_item_id'] as String,
      name: json['name'] as String,
      isRequired: json['is_required'] as bool? ?? false,
      maxSelections: (json['max_selections'] as num?)?.toInt() ?? 1,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      choices: (json['choices'] as List<dynamic>?)
              ?.map((e) => OptionChoice.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$OptionGroupToJson(OptionGroup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'menu_item_id': instance.menuItemId,
      'name': instance.name,
      'is_required': instance.isRequired,
      'max_selections': instance.maxSelections,
      'sort_order': instance.sortOrder,
      'choices': instance.choices.map((e) => e.toJson()).toList(),
    };

MenuItemSide _$MenuItemSideFromJson(Map<String, dynamic> json) => MenuItemSide(
      id: json['id'] as String,
      menuItemId: json['menu_item_id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      isAvailable: json['is_available'] as bool? ?? true,
      sideType: json['side_type'] as String? ?? 'side',
      createdAt: DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$MenuItemSideToJson(MenuItemSide instance) =>
    <String, dynamic>{
      'id': instance.id,
      'menu_item_id': instance.menuItemId,
      'name': instance.name,
      'price': instance.price,
      'is_available': instance.isAvailable,
      'side_type': instance.sideType,
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
      unit: json['unit'] as String?,
      brand: json['brand'] as String?,
      weight: json['weight'] as String?,
      inStock: json['in_stock'] as bool? ?? true,
      maxQuantity: (json['max_quantity'] as num?)?.toInt() ?? 99,
      productType: json['product_type'] as String? ?? 'food',
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
      'unit': instance.unit,
      'brand': instance.brand,
      'weight': instance.weight,
      'in_stock': instance.inStock,
      'max_quantity': instance.maxQuantity,
      'product_type': instance.productType,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };
