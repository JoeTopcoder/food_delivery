class CarServiceCategory {
  final String id;
  final String name;
  final String? iconName;
  final String? description;
  final bool isActive;
  final int sortOrder;

  const CarServiceCategory({
    required this.id,
    required this.name,
    this.iconName,
    this.description,
    required this.isActive,
    required this.sortOrder,
  });

  factory CarServiceCategory.fromMap(Map<String, dynamic> map) {
    return CarServiceCategory(
      id: map['id'] as String,
      name: map['name'] as String,
      iconName: map['icon_name'] as String?,
      description: map['description'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'icon_name': iconName,
    'description': description,
    'is_active': isActive,
    'sort_order': sortOrder,
  };
}
