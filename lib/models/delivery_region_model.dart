class DeliveryRegion {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const DeliveryRegion({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
  });

  factory DeliveryRegion.fromJson(Map<String, dynamic> json) => DeliveryRegion(
    id: json['id'] as String,
    name: json['name'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    radiusKm: (json['radius_km'] as num?)?.toDouble() ?? 10.0,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: json['updated_at'] != null
        ? DateTime.parse(json['updated_at'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'radius_km': radiusKm,
    'is_active': isActive,
  };
}
