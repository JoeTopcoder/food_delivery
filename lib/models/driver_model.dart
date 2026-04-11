import 'package:json_annotation/json_annotation.dart';

part 'driver_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class Driver {
  final String id;
  final String userId;
  final String? vehicleType; // 'bike', 'car', 'scooter'
  final String? vehicleNumber;
  final String? licenseNumber;
  final double? rating;
  final int? completedDeliveries;
  final int? cancelledDeliveries;
  final double? totalEarnings;
  final bool isAvailable;
  final double? currentLatitude;
  final double? currentLongitude;
  final bool? isVerified;
  final String? documentsStatus; // 'pending', 'approved', 'rejected'
  final String? bankName;
  final String? bankBranch;
  final String? bankAccountNumber;
  final String? bankAccountHolder;
  final String? bankAccountType;
  final double? totalPaidOut;
  final double? cashFloat;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Driver({
    required this.id,
    required this.userId,
    this.vehicleType,
    this.vehicleNumber,
    this.licenseNumber,
    this.rating,
    this.completedDeliveries,
    this.cancelledDeliveries,
    this.totalEarnings,
    this.isAvailable = true,
    this.currentLatitude,
    this.currentLongitude,
    this.isVerified,
    this.documentsStatus,
    this.bankName,
    this.bankBranch,
    this.bankAccountNumber,
    this.bankAccountHolder,
    this.bankAccountType,
    this.totalPaidOut,
    this.cashFloat,
    required this.createdAt,
    this.updatedAt,
  });

  factory Driver.fromJson(Map<String, dynamic> json) => _$DriverFromJson(json);
  Map<String, dynamic> toJson() => _$DriverToJson(this);

  Driver copyWith({
    String? id,
    String? userId,
    String? vehicleType,
    String? vehicleNumber,
    String? licenseNumber,
    double? rating,
    int? completedDeliveries,
    int? cancelledDeliveries,
    double? totalEarnings,
    bool? isAvailable,
    double? currentLatitude,
    double? currentLongitude,
    bool? isVerified,
    String? documentsStatus,
    String? bankName,
    String? bankBranch,
    String? bankAccountNumber,
    String? bankAccountHolder,
    String? bankAccountType,
    double? totalPaidOut,
    double? cashFloat,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Driver(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      vehicleType: vehicleType ?? this.vehicleType,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      rating: rating ?? this.rating,
      completedDeliveries: completedDeliveries ?? this.completedDeliveries,
      cancelledDeliveries: cancelledDeliveries ?? this.cancelledDeliveries,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      isAvailable: isAvailable ?? this.isAvailable,
      currentLatitude: currentLatitude ?? this.currentLatitude,
      currentLongitude: currentLongitude ?? this.currentLongitude,
      isVerified: isVerified ?? this.isVerified,
      documentsStatus: documentsStatus ?? this.documentsStatus,
      bankName: bankName ?? this.bankName,
      bankBranch: bankBranch ?? this.bankBranch,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankAccountHolder: bankAccountHolder ?? this.bankAccountHolder,
      bankAccountType: bankAccountType ?? this.bankAccountType,
      totalPaidOut: totalPaidOut ?? this.totalPaidOut,
      cashFloat: cashFloat ?? this.cashFloat,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
