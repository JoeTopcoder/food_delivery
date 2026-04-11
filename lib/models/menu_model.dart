import 'package:json_annotation/json_annotation.dart';

part 'menu_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class OptionChoice {
  final String id;
  final String groupId;
  final String name;
  final double price;
  final bool isAvailable;
  final int sortOrder;

  OptionChoice({
    required this.id,
    required this.groupId,
    required this.name,
    this.price = 0,
    this.isAvailable = true,
    this.sortOrder = 0,
  });

  factory OptionChoice.fromJson(Map<String, dynamic> json) =>
      _$OptionChoiceFromJson(json);
  Map<String, dynamic> toJson() => _$OptionChoiceToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class OptionGroup {
  final String id;
  final String menuItemId;
  final String name;
  final bool isRequired;
  final int maxSelections;
  final int sortOrder;
  final List<OptionChoice> choices;

  OptionGroup({
    required this.id,
    required this.menuItemId,
    required this.name,
    this.isRequired = false,
    this.maxSelections = 1,
    this.sortOrder = 0,
    this.choices = const [],
  });

  /// Single-select means the user picks exactly one option (radio-style).
  bool get isSingleSelect => maxSelections == 1;

  factory OptionGroup.fromJson(Map<String, dynamic> json) {
    final choicesJson =
        json['menu_option_choices'] as List? ?? json['choices'] as List? ?? [];
    return OptionGroup(
      id: json['id'] as String,
      menuItemId: json['menu_item_id'] as String,
      name: json['name'] as String,
      isRequired: json['is_required'] as bool? ?? false,
      maxSelections: json['max_selections'] as int? ?? 1,
      sortOrder: json['sort_order'] as int? ?? 0,
      choices:
          choicesJson
              .map((c) => OptionChoice.fromJson(c as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
    );
  }

  Map<String, dynamic> toJson() => _$OptionGroupToJson(this);
}

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
  @JsonKey(includeFromJson: false, includeToJson: false)
  final List<OptionGroup> optionGroups;
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
    this.optionGroups = const [],
    required this.createdAt,
    this.updatedAt,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    final item = _$MenuItemFromJson(json);
    final groupsJson = json['menu_option_groups'] as List? ?? [];
    final groups =
        groupsJson
            .map((g) => OptionGroup.fromJson(g as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return item.copyWith(optionGroups: groups);
  }

  Map<String, dynamic> toJson() => _$MenuItemToJson(this);

  bool get hasOptions => optionGroups.isNotEmpty;

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
    List<OptionGroup>? optionGroups,
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
      optionGroups: optionGroups ?? this.optionGroups,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  double get discountedPrice {
    if (discount == null || discount == 0) return price;
    return price - (price * discount! / 100);
  }
}
