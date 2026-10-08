class GroceryCategory {
  final String id;
  final String name;
  final String? icon;
  final String? imageUrl;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;

  GroceryCategory({
    required this.id,
    required this.name,
    this.icon,
    this.imageUrl,
    this.sortOrder = 0,
    this.isActive = true,
    required this.createdAt,
  });

  factory GroceryCategory.fromJson(Map<String, dynamic> json) {
    return GroceryCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      imageUrl: json['image_url'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'image_url': imageUrl,
    'sort_order': sortOrder,
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
  };
}
