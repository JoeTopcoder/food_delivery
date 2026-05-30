class CarServiceProviderImage {
  final String id;
  final String providerId;
  final String imageUrl;
  final bool isPrimary;
  final int sortOrder;

  const CarServiceProviderImage({
    required this.id,
    required this.providerId,
    required this.imageUrl,
    required this.isPrimary,
    required this.sortOrder,
  });

  factory CarServiceProviderImage.fromMap(Map<String, dynamic> map) {
    return CarServiceProviderImage(
      id: map['id'] as String,
      providerId: map['provider_id'] as String,
      imageUrl: map['image_url'] as String,
      isPrimary: map['is_primary'] as bool? ?? false,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'provider_id': providerId,
    'image_url': imageUrl,
    'is_primary': isPrimary,
    'sort_order': sortOrder,
  };
}
