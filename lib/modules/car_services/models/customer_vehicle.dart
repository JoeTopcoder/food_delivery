class CustomerVehicle {
  final String id;
  final String customerId;
  final String? nickname;
  final String make;
  final String model;
  final int? year;
  final String? color;
  final String? licensePlate;
  final String vehicleType; // sedan | suv | van | truck | bike
  final String? photoUrl;
  final bool isDefault;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomerVehicle({
    required this.id,
    required this.customerId,
    this.nickname,
    required this.make,
    required this.model,
    this.year,
    this.color,
    this.licensePlate,
    required this.vehicleType,
    this.photoUrl,
    required this.isDefault,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  String get displayName {
    if (nickname != null && nickname!.isNotEmpty) return nickname!;
    final y = year != null ? '$year ' : '';
    return '$y$make $model';
  }

  factory CustomerVehicle.fromMap(Map<String, dynamic> m) => CustomerVehicle(
        id: m['id'] as String,
        customerId: m['customer_id'] as String,
        nickname: m['nickname'] as String?,
        make: m['make'] as String,
        model: m['model'] as String,
        year: m['year'] as int?,
        color: m['color'] as String?,
        licensePlate: m['license_plate'] as String?,
        vehicleType: m['vehicle_type'] as String? ?? 'sedan',
        photoUrl: m['photo_url'] as String?,
        isDefault: m['is_default'] as bool? ?? false,
        isActive: m['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'customer_id': customerId,
        'nickname': nickname,
        'make': make,
        'model': model,
        'year': year,
        'color': color,
        'license_plate': licensePlate,
        'vehicle_type': vehicleType,
        'photo_url': photoUrl,
        'is_default': isDefault,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  CustomerVehicle copyWith({
    String? id,
    String? customerId,
    String? nickname,
    String? make,
    String? model,
    int? year,
    String? color,
    String? licensePlate,
    String? vehicleType,
    String? photoUrl,
    bool? isDefault,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      CustomerVehicle(
        id: id ?? this.id,
        customerId: customerId ?? this.customerId,
        nickname: nickname ?? this.nickname,
        make: make ?? this.make,
        model: model ?? this.model,
        year: year ?? this.year,
        color: color ?? this.color,
        licensePlate: licensePlate ?? this.licensePlate,
        vehicleType: vehicleType ?? this.vehicleType,
        photoUrl: photoUrl ?? this.photoUrl,
        isDefault: isDefault ?? this.isDefault,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toSnapshot() => {
        'id': id,
        'make': make,
        'model': model,
        'year': year,
        'color': color,
        'license_plate': licensePlate,
        'vehicle_type': vehicleType,
        'nickname': nickname,
        'photo_url': photoUrl,
      };
}
