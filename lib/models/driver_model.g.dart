// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'driver_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Driver _$DriverFromJson(Map<String, dynamic> json) => Driver(
  id: json['id'] as String,
  userId: json['user_id'] as String,
  vehicleType: json['vehicle_type'] as String?,
  vehicleNumber: json['vehicle_number'] as String?,
  licenseNumber: json['license_number'] as String?,
  rating: (json['rating'] as num?)?.toDouble(),
  completedDeliveries: (json['completed_deliveries'] as num?)?.toInt(),
  cancelledDeliveries: (json['cancelled_deliveries'] as num?)?.toInt(),
  totalEarnings: (json['total_earnings'] as num?)?.toDouble(),
  isAvailable: json['is_available'] as bool? ?? true,
  currentLatitude: (json['current_latitude'] as num?)?.toDouble(),
  currentLongitude: (json['current_longitude'] as num?)?.toDouble(),
  isVerified: json['is_verified'] as bool?,
  documentsStatus: json['documents_status'] as String?,
  bankName: json['bank_name'] as String?,
  bankBranch: json['bank_branch'] as String?,
  bankAccountNumber: json['bank_account_number'] as String?,
  bankAccountHolder: json['bank_account_holder'] as String?,
  bankAccountType: json['bank_account_type'] as String?,
  totalPaidOut: (json['total_paid_out'] as num?)?.toDouble(),
  cashFloat: (json['cash_float'] as num?)?.toDouble(),
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: json['updated_at'] == null
      ? null
      : DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$DriverToJson(Driver instance) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'vehicle_type': instance.vehicleType,
  'vehicle_number': instance.vehicleNumber,
  'license_number': instance.licenseNumber,
  'rating': instance.rating,
  'completed_deliveries': instance.completedDeliveries,
  'cancelled_deliveries': instance.cancelledDeliveries,
  'total_earnings': instance.totalEarnings,
  'is_available': instance.isAvailable,
  'current_latitude': instance.currentLatitude,
  'current_longitude': instance.currentLongitude,
  'is_verified': instance.isVerified,
  'documents_status': instance.documentsStatus,
  'bank_name': instance.bankName,
  'bank_branch': instance.bankBranch,
  'bank_account_number': instance.bankAccountNumber,
  'bank_account_holder': instance.bankAccountHolder,
  'bank_account_type': instance.bankAccountType,
  'total_paid_out': instance.totalPaidOut,
  'cash_float': instance.cashFloat,
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt?.toIso8601String(),
};
