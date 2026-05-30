// Master catalogue of laundry service types + per-provider service config

class LaundryServiceType {
  final String id;
  final String name;
  final String? description;
  final String? icon;
  final int sortOrder;
  final bool isActive;

  const LaundryServiceType({
    required this.id,
    required this.name,
    this.description,
    this.icon,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory LaundryServiceType.fromMap(Map<String, dynamic> m) => LaundryServiceType(
        id:          m['id'] as String,
        name:        m['name'] as String,
        description: m['description'] as String?,
        icon:        m['icon'] as String?,
        sortOrder:   m['sort_order'] as int? ?? 0,
        isActive:    m['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'id':          id,
        'name':        name,
        'description': description,
        'icon':        icon,
        'sort_order':  sortOrder,
        'is_active':   isActive,
      };
}

// Per-provider pricing for a given service
class LaundryProviderService {
  final String id;
  final String providerId;
  final String serviceId;
  final String? serviceName;       // joined from laundry_services
  final String? serviceIcon;
  final bool isAvailable;
  final double? pricePerPound;
  final double? pricePerKg;
  final double minimumOrderFee;
  final double expressFee;
  final double ironingFee;
  final double dryCleaningFee;
  final int estimatedHours;
  final String? notes;

  const LaundryProviderService({
    required this.id,
    required this.providerId,
    required this.serviceId,
    this.serviceName,
    this.serviceIcon,
    this.isAvailable = true,
    this.pricePerPound,
    this.pricePerKg,
    this.minimumOrderFee = 0,
    this.expressFee = 0,
    this.ironingFee = 0,
    this.dryCleaningFee = 0,
    this.estimatedHours = 24,
    this.notes,
  });

  factory LaundryProviderService.fromMap(Map<String, dynamic> m) {
    final svc = m['laundry_services'] as Map<String, dynamic>?;
    return LaundryProviderService(
      id:              m['id'] as String,
      providerId:      m['provider_id'] as String,
      serviceId:       m['service_id'] as String,
      serviceName:     svc?['name'] as String? ?? m['service_name'] as String?,
      serviceIcon:     svc?['icon'] as String? ?? m['service_icon'] as String?,
      isAvailable:     m['is_available'] as bool? ?? true,
      pricePerPound:   (m['price_per_pound'] as num?)?.toDouble(),
      pricePerKg:      (m['price_per_kg'] as num?)?.toDouble(),
      minimumOrderFee: (m['minimum_order_fee'] as num?)?.toDouble() ?? 0,
      expressFee:      (m['express_fee'] as num?)?.toDouble() ?? 0,
      ironingFee:      (m['ironing_fee'] as num?)?.toDouble() ?? 0,
      dryCleaningFee:  (m['dry_cleaning_fee'] as num?)?.toDouble() ?? 0,
      estimatedHours:  m['estimated_hours'] as int? ?? 24,
      notes:           m['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'provider_id':        providerId,
        'service_id':         serviceId,
        'is_available':       isAvailable,
        'price_per_pound':    pricePerPound,
        'price_per_kg':       pricePerKg,
        'minimum_order_fee':  minimumOrderFee,
        'express_fee':        expressFee,
        'ironing_fee':        ironingFee,
        'dry_cleaning_fee':   dryCleaningFee,
        'estimated_hours':    estimatedHours,
        'notes':              notes,
      };

  /// Effective price per kg (converts from per-pound if needed)
  double? get effectivePricePerKg =>
      pricePerKg ?? (pricePerPound != null ? pricePerPound! * 2.20462 : null);
}
