import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';

part 'restaurant_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class Restaurant {
  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String? imageUrl;
  final String? phone;
  final String? email;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? cuisineType;
  final double? rating;
  final int? reviewCount;
  final double? deliveryFee;
  final int? estimatedDeliveryTime; // in minutes
  final bool isOpen;
  final String? openingTime;
  final String? closingTime;
  final List<String>? tags;
  final bool isVerified;
  final String? bankName;
  final String? bankBranch;
  final String? bankAccountNumber;
  final String? bankAccountHolder;
  final String? bankAccountType;
  final double? commissionRate;
  final Map<String, dynamic>? operatingHours;
  final double? totalEarnings;
  final double? totalPaidOut;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Restaurant({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    this.imageUrl,
    this.phone,
    this.email,
    this.address,
    this.latitude,
    this.longitude,
    this.cuisineType,
    this.rating,
    this.reviewCount,
    this.deliveryFee,
    this.estimatedDeliveryTime,
    this.isOpen = true,
    this.openingTime,
    this.closingTime,
    this.tags,
    this.isVerified = false,
    this.bankName,
    this.bankBranch,
    this.bankAccountNumber,
    this.bankAccountHolder,
    this.bankAccountType,
    this.commissionRate,
    this.operatingHours,
    this.totalEarnings,
    this.totalPaidOut,
    required this.createdAt,
    this.updatedAt,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) =>
      _$RestaurantFromJson(json);
  Map<String, dynamic> toJson() => _$RestaurantToJson(this);

  Restaurant copyWith({
    String? id,
    String? ownerId,
    String? name,
    String? description,
    String? imageUrl,
    String? phone,
    String? email,
    String? address,
    double? latitude,
    double? longitude,
    String? cuisineType,
    double? rating,
    int? reviewCount,
    double? deliveryFee,
    int? estimatedDeliveryTime,
    bool? isOpen,
    String? openingTime,
    String? closingTime,
    List<String>? tags,
    bool? isVerified,
    String? bankName,
    String? bankBranch,
    String? bankAccountNumber,
    String? bankAccountHolder,
    String? bankAccountType,
    double? commissionRate,
    Map<String, dynamic>? operatingHours,
    double? totalEarnings,
    double? totalPaidOut,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Restaurant(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      cuisineType: cuisineType ?? this.cuisineType,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      estimatedDeliveryTime:
          estimatedDeliveryTime ?? this.estimatedDeliveryTime,
      isOpen: isOpen ?? this.isOpen,
      openingTime: openingTime ?? this.openingTime,
      closingTime: closingTime ?? this.closingTime,
      tags: tags ?? this.tags,
      isVerified: isVerified ?? this.isVerified,
      bankName: bankName ?? this.bankName,
      bankBranch: bankBranch ?? this.bankBranch,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankAccountHolder: bankAccountHolder ?? this.bankAccountHolder,
      bankAccountType: bankAccountType ?? this.bankAccountType,
      commissionRate: commissionRate ?? this.commissionRate,
      operatingHours: operatingHours ?? this.operatingHours,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      totalPaidOut: totalPaidOut ?? this.totalPaidOut,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Whether the restaurant is open right now based on its operating hours.
  /// Falls back to the manual [isOpen] flag when no schedule is set.
  bool get isCurrentlyOpen {
    if (!isOpen) return false; // manual override always wins

    if (operatingHours == null || operatingHours!.isEmpty) {
      // No schedule — use legacy openingTime / closingTime if available
      if (openingTime != null && closingTime != null) {
        return _isWithinTimeRange(openingTime!, closingTime!);
      }
      return isOpen;
    }

    // Day-of-week key (lowercase english)
    final now = DateTime.now();
    final dayName = DateFormat('EEEE').format(now).toLowerCase();
    final dayData = operatingHours![dayName];
    if (dayData is! Map) return isOpen;

    final dayIsOpen = dayData['is_open'] ?? true;
    if (dayIsOpen != true) return false;

    final open = dayData['open'] as String?;
    final close = dayData['close'] as String?;
    if (open == null || close == null) return true;

    return _isWithinTimeRange(open, close);
  }

  bool _isWithinTimeRange(String openStr, String closeStr) {
    final now = DateTime.now();
    final parts1 = openStr.split(':');
    final parts2 = closeStr.split(':');
    if (parts1.length < 2 || parts2.length < 2) return true;

    final openMin = int.parse(parts1[0]) * 60 + int.parse(parts1[1]);
    final closeMin = int.parse(parts2[0]) * 60 + int.parse(parts2[1]);
    final nowMin = now.hour * 60 + now.minute;

    if (closeMin > openMin) {
      return nowMin >= openMin && nowMin < closeMin;
    } else {
      // Wraps past midnight (e.g. 18:00 – 02:00)
      return nowMin >= openMin || nowMin < closeMin;
    }
  }
}
