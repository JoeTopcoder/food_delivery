import 'laundry_service_model.dart';

enum LaundryProviderStatus { pending, active, suspended, rejected }

extension LaundryProviderStatusX on LaundryProviderStatus {
  String get dbString => name;

  static LaundryProviderStatus fromString(String v) =>
      LaundryProviderStatus.values.firstWhere(
        (e) => e.name == v,
        orElse: () => LaundryProviderStatus.pending,
      );

  String get displayLabel {
    switch (this) {
      case LaundryProviderStatus.pending:    return 'Pending Review';
      case LaundryProviderStatus.active:     return 'Active';
      case LaundryProviderStatus.suspended:  return 'Suspended';
      case LaundryProviderStatus.rejected:   return 'Rejected';
    }
  }
}

class LaundryProvider {
  final String id;
  final String userId;
  final String businessName;
  final String? description;
  final String? logoUrl;
  final String? bannerUrl;
  final String? phone;
  final String? email;
  final String? address;
  final double? latitude;
  final double? longitude;
  final double pickupRadiusKm;
  final LaundryProviderStatus status;
  final bool isActive;
  final bool isVerified;
  final double rating;
  final int reviewCount;
  final Map<String, dynamic>? operatingHours;
  final double commissionRate;
  final int onboardingStep;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Joined data
  final List<LaundryProviderService>? services;
  final LaundryPricing? pricing;

  const LaundryProvider({
    required this.id,
    required this.userId,
    required this.businessName,
    this.description,
    this.logoUrl,
    this.bannerUrl,
    this.phone,
    this.email,
    this.address,
    this.latitude,
    this.longitude,
    this.pickupRadiusKm = 10,
    this.status = LaundryProviderStatus.pending,
    this.isActive = false,
    this.isVerified = false,
    this.rating = 0,
    this.reviewCount = 0,
    this.operatingHours,
    this.commissionRate = 0.15,
    this.onboardingStep = 0,
    this.rejectionReason,
    required this.createdAt,
    this.updatedAt,
    this.services,
    this.pricing,
  });

  factory LaundryProvider.fromMap(Map<String, dynamic> m) {
    // Supabase returns joined rows under the foreign table name.
    // laundry_pricing is a one-to-many (unique per provider) → comes back as a
    // list; take the first element. Fall back to a plain 'pricing' key for any
    // manually-constructed maps.
    final rawServicesList =
        (m['laundry_provider_services'] ?? m['services']) as List<dynamic>?;

    final rawPricingRaw = m['laundry_pricing'] ?? m['pricing'];
    final Map<String, dynamic>? rawPricing;
    if (rawPricingRaw is List) {
      rawPricing = rawPricingRaw.isNotEmpty
          ? rawPricingRaw.first as Map<String, dynamic>
          : null;
    } else {
      rawPricing = rawPricingRaw as Map<String, dynamic>?;
    }

    return LaundryProvider(
      id:              m['id'] as String,
      userId:          m['user_id'] as String,
      businessName:    m['business_name'] as String,
      description:     m['description'] as String?,
      logoUrl:         m['logo_url'] as String?,
      bannerUrl:       m['banner_url'] as String?,
      phone:           m['phone'] as String?,
      email:           m['email'] as String?,
      address:         m['address'] as String?,
      latitude:        (m['latitude'] as num?)?.toDouble(),
      longitude:       (m['longitude'] as num?)?.toDouble(),
      pickupRadiusKm:  (m['pickup_radius_km'] as num?)?.toDouble() ?? 10,
      status:          LaundryProviderStatusX.fromString(m['status'] as String? ?? 'pending'),
      isActive:        m['is_active'] as bool? ?? false,
      isVerified:      m['is_verified'] as bool? ?? false,
      rating:          (m['rating'] as num?)?.toDouble() ?? 0,
      reviewCount:     m['review_count'] as int? ?? 0,
      operatingHours:  m['operating_hours'] as Map<String, dynamic>?,
      commissionRate:  (m['commission_rate'] as num?)?.toDouble() ?? 0.15,
      onboardingStep:  m['onboarding_step'] as int? ?? 0,
      rejectionReason: m['rejection_reason'] as String?,
      createdAt:       DateTime.parse(m['created_at'] as String),
      updatedAt:       m['updated_at'] != null ? DateTime.parse(m['updated_at'] as String) : null,
      services: rawServicesList
          ?.map((s) => LaundryProviderService.fromMap(s as Map<String, dynamic>))
          .toList(),
      pricing: rawPricing != null ? LaundryPricing.fromMap(rawPricing) : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'id':               id,
    'user_id':          userId,
    'business_name':    businessName,
    'description':      description,
    'logo_url':         logoUrl,
    'banner_url':       bannerUrl,
    'phone':            phone,
    'email':            email,
    'address':          address,
    'latitude':         latitude,
    'longitude':        longitude,
    'pickup_radius_km': pickupRadiusKm,
    'status':           status.dbString,
    'is_active':        isActive,
    'is_verified':      isVerified,
    'operating_hours':  operatingHours,
    'commission_rate':  commissionRate,
    'onboarding_step':  onboardingStep,
  };

  LaundryProvider copyWith({
    String? businessName,
    String? description,
    String? logoUrl,
    String? bannerUrl,
    String? phone,
    String? email,
    String? address,
    double? latitude,
    double? longitude,
    double? pickupRadiusKm,
    LaundryProviderStatus? status,
    bool? isActive,
    bool? isVerified,
    double? rating,
    int? reviewCount,
    Map<String, dynamic>? operatingHours,
    int? onboardingStep,
    List<LaundryProviderService>? services,
    LaundryPricing? pricing,
  }) => LaundryProvider(
    id:              id,
    userId:          userId,
    businessName:    businessName ?? this.businessName,
    description:     description  ?? this.description,
    logoUrl:         logoUrl      ?? this.logoUrl,
    bannerUrl:       bannerUrl    ?? this.bannerUrl,
    phone:           phone        ?? this.phone,
    email:           email        ?? this.email,
    address:         address      ?? this.address,
    latitude:        latitude     ?? this.latitude,
    longitude:       longitude    ?? this.longitude,
    pickupRadiusKm:  pickupRadiusKm ?? this.pickupRadiusKm,
    status:          status       ?? this.status,
    isActive:        isActive     ?? this.isActive,
    isVerified:      isVerified   ?? this.isVerified,
    rating:          rating       ?? this.rating,
    reviewCount:     reviewCount  ?? this.reviewCount,
    operatingHours:  operatingHours ?? this.operatingHours,
    commissionRate:  commissionRate,
    onboardingStep:  onboardingStep ?? this.onboardingStep,
    rejectionReason: rejectionReason,
    createdAt:       createdAt,
    updatedAt:       DateTime.now(),
    services:        services ?? this.services,
    pricing:         pricing  ?? this.pricing,
  );
}

// ─── LaundryPricing ───────────────────────────────────────────────────────────

class LaundryPricing {
  final String id;
  final String providerId;
  final double pickupFee;
  final double deliveryFee;
  final double minOrderFee;
  final String currency;

  const LaundryPricing({
    required this.id,
    required this.providerId,
    this.pickupFee = 0,
    this.deliveryFee = 0,
    this.minOrderFee = 5,
    this.currency = 'USD',
  });

  factory LaundryPricing.fromMap(Map<String, dynamic> m) => LaundryPricing(
    id:           m['id'] as String,
    providerId:   m['provider_id'] as String,
    pickupFee:    (m['pickup_fee']   as num?)?.toDouble() ?? 0,
    deliveryFee:  (m['delivery_fee'] as num?)?.toDouble() ?? 0,
    minOrderFee:  (m['min_order_fee'] as num?)?.toDouble() ?? 5,
    currency:     m['currency'] as String? ?? 'USD',
  );

  Map<String, dynamic> toMap() => {
    'provider_id':   providerId,
    'pickup_fee':    pickupFee,
    'delivery_fee':  deliveryFee,
    'min_order_fee': minOrderFee,
    'currency':      currency,
  };
}
