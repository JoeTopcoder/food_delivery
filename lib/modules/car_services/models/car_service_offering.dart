import 'car_service_category.dart';
import 'numeric_utils.dart';

class CarServiceOffering {
  final String id;
  final String providerId;
  final String categoryId;
  final String name;
  final String? description;
  final int durationMinutes;
  final double basePrice;
  final double? sedanPrice;
  final double? suvPrice;
  final double? vanPrice;
  final double? truckPrice;
  final double? bikePrice;
  final bool mobileSupported;
  final bool isActive;

  // Optional joined field
  final CarServiceCategory? category;

  const CarServiceOffering({
    required this.id,
    required this.providerId,
    required this.categoryId,
    required this.name,
    this.description,
    required this.durationMinutes,
    required this.basePrice,
    this.sedanPrice,
    this.suvPrice,
    this.vanPrice,
    this.truckPrice,
    this.bikePrice,
    this.mobileSupported = false,
    required this.isActive,
    this.category,
  });

  factory CarServiceOffering.fromMap(Map<String, dynamic> map) {
    return CarServiceOffering(
      id: map['id'] as String,
      providerId: map['provider_id'] as String? ?? '',
      categoryId: map['category_id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown',
      description: map['description'] as String?,
      durationMinutes: map['duration_minutes'] as int? ?? 60,
      basePrice: parseDoubleRequired(map['base_price']),
      sedanPrice: parseDouble(map['sedan_price']),
      suvPrice: parseDouble(map['suv_price']),
      vanPrice: parseDouble(map['van_price']),
      truckPrice: parseDouble(map['truck_price']),
      bikePrice: parseDouble(map['bike_price']),
      mobileSupported: map['mobile_supported'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
      category: map['category'] != null
          ? CarServiceCategory.fromMap(map['category'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'provider_id': providerId,
        'category_id': categoryId,
        'name': name,
        'description': description,
        'duration_minutes': durationMinutes,
        'base_price': basePrice,
        if (sedanPrice != null) 'sedan_price': sedanPrice,
        if (suvPrice != null) 'suv_price': suvPrice,
        if (vanPrice != null) 'van_price': vanPrice,
        if (truckPrice != null) 'truck_price': truckPrice,
        if (bikePrice != null) 'bike_price': bikePrice,
        'mobile_supported': mobileSupported,
        'is_active': isActive,
      };

  /// Returns the price for a given vehicle type, or basePrice as fallback.
  double priceForVehicle(String? vehicleType) {
    switch (vehicleType?.toLowerCase()) {
      case 'sedan':
        return sedanPrice ?? basePrice;
      case 'suv':
        return suvPrice ?? basePrice;
      case 'van':
        return vanPrice ?? basePrice;
      case 'truck':
        return truckPrice ?? basePrice;
      case 'bike':
        return bikePrice ?? basePrice;
      default:
        return basePrice;
    }
  }

  CarServiceOffering copyWith({
    String? id,
    String? providerId,
    String? categoryId,
    String? name,
    String? description,
    int? durationMinutes,
    double? basePrice,
    double? sedanPrice,
    double? suvPrice,
    double? vanPrice,
    double? truckPrice,
    double? bikePrice,
    bool? mobileSupported,
    bool? isActive,
    CarServiceCategory? category,
  }) {
    return CarServiceOffering(
      id: id ?? this.id,
      providerId: providerId ?? this.providerId,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      basePrice: basePrice ?? this.basePrice,
      sedanPrice: sedanPrice ?? this.sedanPrice,
      suvPrice: suvPrice ?? this.suvPrice,
      vanPrice: vanPrice ?? this.vanPrice,
      truckPrice: truckPrice ?? this.truckPrice,
      bikePrice: bikePrice ?? this.bikePrice,
      mobileSupported: mobileSupported ?? this.mobileSupported,
      isActive: isActive ?? this.isActive,
      category: category ?? this.category,
    );
  }
}
