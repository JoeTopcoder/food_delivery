// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'restaurant_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Restaurant _$RestaurantFromJson(Map<String, dynamic> json) => Restaurant(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      cuisineType: json['cuisine_type'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: (json['review_count'] as num?)?.toInt(),
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble(),
      estimatedDeliveryTime: (json['estimated_delivery_time'] as num?)?.toInt(),
      isOpen: json['is_open'] as bool? ?? true,
      openingTime: json['opening_time'] as String?,
      closingTime: json['closing_time'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      isVerified: json['is_verified'] as bool? ?? false,
      bankName: json['bank_name'] as String?,
      bankBranch: json['bank_branch'] as String?,
      bankAccountNumber: json['bank_account_number'] as String?,
      bankAccountHolder: json['bank_account_holder'] as String?,
      bankAccountType: json['bank_account_type'] as String?,
      commissionRate: (json['commission_rate'] as num?)?.toDouble(),
      serviceFee: (json['service_fee'] as num?)?.toDouble(),
      operatingHours: json['operating_hours'] as Map<String, dynamic>?,
      totalEarnings: (json['total_earnings'] as num?)?.toDouble(),
      totalPaidOut: (json['total_paid_out'] as num?)?.toDouble(),
      storeType: json['store_type'] as String? ?? 'food',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$RestaurantToJson(Restaurant instance) =>
    <String, dynamic>{
      'id': instance.id,
      'owner_id': instance.ownerId,
      'name': instance.name,
      'description': instance.description,
      'image_url': instance.imageUrl,
      'phone': instance.phone,
      'email': instance.email,
      'address': instance.address,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'cuisine_type': instance.cuisineType,
      'rating': instance.rating,
      'review_count': instance.reviewCount,
      'delivery_fee': instance.deliveryFee,
      'estimated_delivery_time': instance.estimatedDeliveryTime,
      'is_open': instance.isOpen,
      'opening_time': instance.openingTime,
      'closing_time': instance.closingTime,
      'tags': instance.tags,
      'is_verified': instance.isVerified,
      'bank_name': instance.bankName,
      'bank_branch': instance.bankBranch,
      'bank_account_number': instance.bankAccountNumber,
      'bank_account_holder': instance.bankAccountHolder,
      'bank_account_type': instance.bankAccountType,
      'commission_rate': instance.commissionRate,
      'service_fee': instance.serviceFee,
      'operating_hours': instance.operatingHours,
      'total_earnings': instance.totalEarnings,
      'total_paid_out': instance.totalPaidOut,
      'store_type': instance.storeType,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };
