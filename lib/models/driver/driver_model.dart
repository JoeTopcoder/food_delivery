import 'package:json_annotation/json_annotation.dart';

part 'driver_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class Driver {
  final String id;
  final String userId;
  final String? vehicleType; // 'bike', 'car', 'scooter'
  final String? vehicleNumber;
  final String? vehicleBrand;
  final String? vehicleColor;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? plateNumber;
  final String? licensePlate;
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
  final String? stripeAccountId;
  final bool payoutsEnabled;
  final bool stripeDebitCardAdded;
  final String? stripeAccountStatus;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String>? activeServices;

  // ── Verification & onboarding ──────────────────────────────────────────────
  final String driverStatus; // draft | pending_review | under_review | approved | rejected | suspended | expired_documents
  final int onboardingStep;
  final String serviceType; // food_delivery | ride_sharing | both
  final String? fullName;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final DateTime? dateOfBirth;
  final String? homeAddress;
  final DateTime? submittedAt;
  final DateTime? approvedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;

  // ── Per-service approval flags ─────────────────────────────────────────────
  final bool isFoodDriverApproved;
  final bool isRideDriverApproved;

  // ── Live availability per service ─────────────────────────────────────────
  final bool isAvailableForFood;
  final bool isAvailableForRides;
  final bool isOnline;

  Driver({
    required this.id,
    required this.userId,
    this.vehicleType,
    this.vehicleNumber,
    this.vehicleBrand,
    this.vehicleColor,
    this.vehicleMake,
    this.vehicleModel,
    this.plateNumber,
    this.licensePlate,
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
    this.stripeAccountId,
    this.payoutsEnabled = false,
    this.stripeDebitCardAdded = false,
    this.stripeAccountStatus,
    required this.createdAt,
    this.updatedAt,
    this.activeServices,
    this.driverStatus = 'draft',
    this.onboardingStep = 0,
    this.serviceType = 'food_delivery',
    this.fullName,
    this.phoneNumber,
    this.profilePhotoUrl,
    this.dateOfBirth,
    this.homeAddress,
    this.submittedAt,
    this.approvedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
    this.isFoodDriverApproved = false,
    this.isRideDriverApproved = false,
    this.isAvailableForFood = false,
    this.isAvailableForRides = false,
    this.isOnline = false,
  });

  factory Driver.fromJson(Map<String, dynamic> json) => _$DriverFromJson(json);
  Map<String, dynamic> toJson() => _$DriverToJson(this);

  bool get isApproved => driverStatus == 'approved';
  bool get isPendingReview => driverStatus == 'pending_review' || driverStatus == 'under_review';
  bool get isRejected => driverStatus == 'rejected';
  bool get isDraft => driverStatus == 'draft';
  bool get canGoOnline => isApproved && (isFoodDriverApproved || isRideDriverApproved);

  Driver copyWith({
    String? id,
    String? userId,
    String? vehicleType,
    String? vehicleNumber,
    String? vehicleBrand,
    String? vehicleColor,
    String? vehicleMake,
    String? vehicleModel,
    String? plateNumber,
    String? licensePlate,
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
    String? stripeAccountId,
    bool? payoutsEnabled,
    bool? stripeDebitCardAdded,
    String? stripeAccountStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? activeServices,
    String? driverStatus,
    int? onboardingStep,
    String? serviceType,
    String? fullName,
    String? phoneNumber,
    String? profilePhotoUrl,
    DateTime? dateOfBirth,
    String? homeAddress,
    DateTime? submittedAt,
    DateTime? approvedAt,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? rejectionReason,
    bool? isFoodDriverApproved,
    bool? isRideDriverApproved,
    bool? isAvailableForFood,
    bool? isAvailableForRides,
    bool? isOnline,
  }) {
    return Driver(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      vehicleType: vehicleType ?? this.vehicleType,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      vehicleBrand: vehicleBrand ?? this.vehicleBrand,
      vehicleColor: vehicleColor ?? this.vehicleColor,
      vehicleMake: vehicleMake ?? this.vehicleMake,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      plateNumber: plateNumber ?? this.plateNumber,
      licensePlate: licensePlate ?? this.licensePlate,
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
      stripeAccountId: stripeAccountId ?? this.stripeAccountId,
      payoutsEnabled: payoutsEnabled ?? this.payoutsEnabled,
      stripeDebitCardAdded: stripeDebitCardAdded ?? this.stripeDebitCardAdded,
      stripeAccountStatus: stripeAccountStatus ?? this.stripeAccountStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      activeServices: activeServices ?? this.activeServices,
      driverStatus: driverStatus ?? this.driverStatus,
      onboardingStep: onboardingStep ?? this.onboardingStep,
      serviceType: serviceType ?? this.serviceType,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      homeAddress: homeAddress ?? this.homeAddress,
      submittedAt: submittedAt ?? this.submittedAt,
      approvedAt: approvedAt ?? this.approvedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      isFoodDriverApproved: isFoodDriverApproved ?? this.isFoodDriverApproved,
      isRideDriverApproved: isRideDriverApproved ?? this.isRideDriverApproved,
      isAvailableForFood: isAvailableForFood ?? this.isAvailableForFood,
      isAvailableForRides: isAvailableForRides ?? this.isAvailableForRides,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
