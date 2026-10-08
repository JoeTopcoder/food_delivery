class UserAddress {
  final String id;
  final String userId;
  final String label; // 'Home', 'Work', 'Other'
  final String address;
  final double? latitude;
  final double? longitude;
  final bool isDefault;
  final DateTime createdAt;

  const UserAddress({
    required this.id,
    required this.userId,
    required this.label,
    required this.address,
    this.latitude,
    this.longitude,
    required this.isDefault,
    required this.createdAt,
  });

  factory UserAddress.fromJson(Map<String, dynamic> json) => UserAddress(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    label: json['label'] as String? ?? 'Home',
    address: json['address'] as String,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    isDefault: json['is_default'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'label': label,
    'address': address,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    'is_default': isDefault,
    'created_at': createdAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAddress &&
          id == other.id &&
          label == other.label &&
          address == other.address &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          isDefault == other.isDefault;

  @override
  int get hashCode =>
      Object.hash(id, label, address, latitude, longitude, isDefault);
}
