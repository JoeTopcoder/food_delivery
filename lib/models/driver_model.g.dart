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
  stripeAccountId: json['stripe_account_id'] as String?,
  payoutsEnabled: json['payouts_enabled'] as bool? ?? false,
  stripeDebitCardAdded: json['stripe_debit_card_added'] as bool? ?? false,
  stripeAccountStatus: json['stripe_account_status'] as String?,
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: json['updated_at'] == null
      ? null
      : DateTime.parse(json['updated_at'] as String),
  activeServices: (json['active_services'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  driverStatus: json['driver_status'] as String? ?? 'draft',
  onboardingStep: (json['onboarding_step'] as num?)?.toInt() ?? 0,
  serviceType: json['service_type'] as String? ?? 'food_delivery',
  fullName: json['full_name'] as String?,
  phoneNumber: json['phone_number'] as String?,
  profilePhotoUrl: json['profile_photo_url'] as String?,
  dateOfBirth: json['date_of_birth'] == null
      ? null
      : DateTime.parse(json['date_of_birth'] as String),
  homeAddress: json['home_address'] as String?,
  submittedAt: json['submitted_at'] == null
      ? null
      : DateTime.parse(json['submitted_at'] as String),
  approvedAt: json['approved_at'] == null
      ? null
      : DateTime.parse(json['approved_at'] as String),
  reviewedBy: json['reviewed_by'] as String?,
  reviewedAt: json['reviewed_at'] == null
      ? null
      : DateTime.parse(json['reviewed_at'] as String),
  rejectionReason: json['rejection_reason'] as String?,
  isFoodDriverApproved: json['is_food_driver_approved'] as bool? ?? false,
  isRideDriverApproved: json['is_ride_driver_approved'] as bool? ?? false,
  isAvailableForFood: json['is_available_for_food'] as bool? ?? false,
  isAvailableForRides: json['is_available_for_rides'] as bool? ?? false,
  isOnline: json['is_online'] as bool? ?? false,
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
  'stripe_account_id': instance.stripeAccountId,
  'payouts_enabled': instance.payoutsEnabled,
  'stripe_debit_card_added': instance.stripeDebitCardAdded,
  'stripe_account_status': instance.stripeAccountStatus,
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt?.toIso8601String(),
  'active_services': instance.activeServices,
  'driver_status': instance.driverStatus,
  'onboarding_step': instance.onboardingStep,
  'service_type': instance.serviceType,
  'full_name': instance.fullName,
  'phone_number': instance.phoneNumber,
  'profile_photo_url': instance.profilePhotoUrl,
  'date_of_birth': instance.dateOfBirth?.toIso8601String(),
  'home_address': instance.homeAddress,
  'submitted_at': instance.submittedAt?.toIso8601String(),
  'approved_at': instance.approvedAt?.toIso8601String(),
  'reviewed_by': instance.reviewedBy,
  'reviewed_at': instance.reviewedAt?.toIso8601String(),
  'rejection_reason': instance.rejectionReason,
  'is_food_driver_approved': instance.isFoodDriverApproved,
  'is_ride_driver_approved': instance.isRideDriverApproved,
  'is_available_for_food': instance.isAvailableForFood,
  'is_available_for_rides': instance.isAvailableForRides,
  'is_online': instance.isOnline,
};
