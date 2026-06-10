import 'car_service_offering.dart';
import 'car_service_provider_image.dart';
import 'numeric_utils.dart';

class CarServiceProvider {
  final String id;
  final String userId;
  final String businessName;
  final String? ownerName;
  final String? bio;
  final String? profileImageUrl;
  final String? bannerImageUrl;
  final String? coverImageUrl;
  final double rating;
  final int totalReviews;
  final int totalBookings;
  final bool isActive;
  final bool isVerified;
  final bool isApproved;
  final bool isSuspended;
  final String approvalStatus; // 'pending' | 'approved' | 'rejected'
  final String? rejectionReason;
  final String? businessPhone;
  final String? businessEmail;
  final String? businessType;
  final bool mobileServiceAvailable;
  final bool pickupDropoffAvailable;
  final double serviceAreaRadiusKm;
  final double? baseLocationLat;
  final double? baseLocationLng;
  final String? baseLocationAddress;
  final bool stripePayoutsEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Optional joined fields
  final List<CarServiceOffering>? offerings;
  final List<CarServiceProviderImage>? images;

  const CarServiceProvider({
    required this.id,
    required this.userId,
    required this.businessName,
    this.ownerName,
    this.bio,
    this.profileImageUrl,
    this.bannerImageUrl,
    this.coverImageUrl,
    required this.rating,
    required this.totalReviews,
    required this.totalBookings,
    required this.isActive,
    required this.isVerified,
    this.isApproved = false,
    this.isSuspended = false,
    this.approvalStatus = 'pending',
    this.rejectionReason,
    this.businessPhone,
    this.businessEmail,
    this.businessType,
    this.mobileServiceAvailable = false,
    this.pickupDropoffAvailable = false,
    required this.serviceAreaRadiusKm,
    this.baseLocationLat,
    this.baseLocationLng,
    this.baseLocationAddress,
    required this.stripePayoutsEnabled,
    required this.createdAt,
    required this.updatedAt,
    this.offerings,
    this.images,
  });

  factory CarServiceProvider.fromMap(Map<String, dynamic> map) {
    List<CarServiceOffering>? offerings;
    if (map['offerings'] != null) {
      offerings = (map['offerings'] as List<dynamic>)
          .map((o) => CarServiceOffering.fromMap(o as Map<String, dynamic>))
          .toList();
    }

    List<CarServiceProviderImage>? images;
    if (map['images'] != null) {
      images = (map['images'] as List<dynamic>)
          .map((i) => CarServiceProviderImage.fromMap(i as Map<String, dynamic>))
          .toList();
    }

    return CarServiceProvider(
      id: map['id'] as String,
      userId: map['user_id'] as String? ?? '',
      businessName: map['business_name'] as String? ?? 'Unknown',
      ownerName: map['owner_name'] as String?,
      bio: map['bio'] as String?,
      profileImageUrl: map['profile_image_url'] as String?,
      bannerImageUrl: map['banner_image_url'] as String?,
      coverImageUrl: map['cover_image_url'] as String?,
      rating: parseDoubleRequired(map['rating']),
      totalReviews: map['total_reviews'] as int? ?? 0,
      totalBookings: map['total_bookings'] as int? ?? 0,
      isActive: map['is_active'] as bool? ?? false,
      isVerified: map['is_verified'] as bool? ?? false,
      isApproved: map['is_approved'] as bool? ?? false,
      isSuspended: map['is_suspended'] as bool? ?? false,
      approvalStatus: map['approval_status'] as String? ?? 'pending',
      rejectionReason: map['rejection_reason'] as String?,
      businessPhone: map['business_phone'] as String?,
      businessEmail: map['business_email'] as String?,
      businessType: map['business_type'] as String?,
      mobileServiceAvailable: map['mobile_service_available'] as bool? ?? false,
      pickupDropoffAvailable: map['pickup_dropoff_available'] as bool? ?? false,
      serviceAreaRadiusKm: parseDoubleRequired(map['service_area_radius_km'], fallback: 10.0),
      baseLocationLat: parseDouble(map['base_location_lat']),
      baseLocationLng: parseDouble(map['base_location_lng']),
      baseLocationAddress: map['base_location_address'] as String?,
      stripePayoutsEnabled: map['stripe_payouts_enabled'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
      offerings: offerings,
      images: images,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'business_name': businessName,
        'owner_name': ownerName,
        'bio': bio,
        'profile_image_url': profileImageUrl,
        'banner_image_url': bannerImageUrl,
        'cover_image_url': coverImageUrl,
        'rating': rating,
        'total_reviews': totalReviews,
        'total_bookings': totalBookings,
        'is_active': isActive,
        'is_verified': isVerified,
        'is_approved': isApproved,
        'is_suspended': isSuspended,
        'approval_status': approvalStatus,
        'rejection_reason': rejectionReason,
        'business_phone': businessPhone,
        'business_email': businessEmail,
        'business_type': businessType,
        'mobile_service_available': mobileServiceAvailable,
        'pickup_dropoff_available': pickupDropoffAvailable,
        'service_area_radius_km': serviceAreaRadiusKm,
        'base_location_lat': baseLocationLat,
        'base_location_lng': baseLocationLng,
        'base_location_address': baseLocationAddress,
        'stripe_payouts_enabled': stripePayoutsEnabled,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  CarServiceProvider copyWith({
    String? id,
    String? userId,
    String? businessName,
    String? ownerName,
    String? bio,
    String? profileImageUrl,
    String? bannerImageUrl,
    String? coverImageUrl,
    double? rating,
    int? totalReviews,
    int? totalBookings,
    bool? isActive,
    bool? isVerified,
    bool? isApproved,
    bool? isSuspended,
    String? approvalStatus,
    String? rejectionReason,
    String? businessPhone,
    String? businessEmail,
    String? businessType,
    bool? mobileServiceAvailable,
    bool? pickupDropoffAvailable,
    double? serviceAreaRadiusKm,
    double? baseLocationLat,
    double? baseLocationLng,
    String? baseLocationAddress,
    bool? stripePayoutsEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<CarServiceOffering>? offerings,
    List<CarServiceProviderImage>? images,
  }) {
    return CarServiceProvider(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      businessName: businessName ?? this.businessName,
      ownerName: ownerName ?? this.ownerName,
      bio: bio ?? this.bio,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      bannerImageUrl: bannerImageUrl ?? this.bannerImageUrl,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      rating: rating ?? this.rating,
      totalReviews: totalReviews ?? this.totalReviews,
      totalBookings: totalBookings ?? this.totalBookings,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      isApproved: isApproved ?? this.isApproved,
      isSuspended: isSuspended ?? this.isSuspended,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      businessPhone: businessPhone ?? this.businessPhone,
      businessEmail: businessEmail ?? this.businessEmail,
      businessType: businessType ?? this.businessType,
      mobileServiceAvailable:
          mobileServiceAvailable ?? this.mobileServiceAvailable,
      pickupDropoffAvailable:
          pickupDropoffAvailable ?? this.pickupDropoffAvailable,
      serviceAreaRadiusKm: serviceAreaRadiusKm ?? this.serviceAreaRadiusKm,
      baseLocationLat: baseLocationLat ?? this.baseLocationLat,
      baseLocationLng: baseLocationLng ?? this.baseLocationLng,
      baseLocationAddress: baseLocationAddress ?? this.baseLocationAddress,
      stripePayoutsEnabled: stripePayoutsEnabled ?? this.stripePayoutsEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      offerings: offerings ?? this.offerings,
      images: images ?? this.images,
    );
  }
}
