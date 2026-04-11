import 'package:json_annotation/json_annotation.dart';

part 'menu_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class MenuItemSide {
  final String id;
  final String menuItemId;
  final String name;
  final double price;
  final bool isAvailable;
  final DateTime createdAt;

  MenuItemSide({
    required this.id,
    required this.menuItemId,
    required this.name,
    required this.price,
    this.isAvailable = true,
    required this.createdAt,
  });

  factory MenuItemSide.fromJson(Map<String, dynamic> json) =>
      _$MenuItemSideFromJson(json);
  Map<String, dynamic> toJson() => _$MenuItemSideToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class MenuItem {
  final String id;
  final String restaurantId;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final String category;
  final bool isAvailable;
  final double? discount;
  final List<String>? tags;
  final int? preparationTime;
  final List<MenuItemSide>? sides;
  final DateTime createdAt;
  final DateTime? updatedAt;

  MenuItem({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    required this.category,
    this.isAvailable = true,
    this.discount,
    this.tags,
    this.preparationTime,
    this.sides,
    required this.createdAt,
    this.updatedAt,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) =>
      _$MenuItemFromJson(json);
  Map<String, dynamic> toJson() => _$MenuItemToJson(this);

  MenuItem copyWith({
    String? id,
    String? restaurantId,
    String? name,
    String? description,
    double? price,
    String? imageUrl,
    String? category,
    bool? isAvailable,
    double? discount,
    List<String>? tags,
    int? preparationTime,
    List<MenuItemSide>? sides,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MenuItem(
      id: id ?? this.id,
      restaurantId: restaurantId ?? this.restaurantId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      isAvailable: isAvailable ?? this.isAvailable,
      discount: discount ?? this.discount,
      tags: tags ?? this.tags,
      preparationTime: preparationTime ?? this.preparationTime,
      sides: sides ?? this.sides,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  double get discountedPrice {
    if (discount == null || discount == 0) return price;
    return price - (price * discount! / 100);
  }
}
