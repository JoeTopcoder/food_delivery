class RidePricingSettings {
  final String id;
  final double baseFare;
  final double perKmRate;
  final double perMinuteRate;
  final double minimumFare;
  final double platformCommissionPercent;
  final double surgeMultiplier;
  final double maxSearchRadiusKm;
  final int driverRequestTimeoutSeconds;
  final double waitingFeePerMin;
  final double cardAuthBufferPercent;
  final bool cashEnabled;
  final bool cardEnabled;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  RidePricingSettings({
    required this.id,
    required this.baseFare,
    required this.perKmRate,
    required this.perMinuteRate,
    required this.minimumFare,
    required this.platformCommissionPercent,
    required this.surgeMultiplier,
    required this.maxSearchRadiusKm,
    required this.driverRequestTimeoutSeconds,
    required this.waitingFeePerMin,
    required this.cardAuthBufferPercent,
    required this.cashEnabled,
    required this.cardEnabled,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RidePricingSettings.fromJson(Map<String, dynamic> json) {
    return RidePricingSettings(
      id: json['id'] as String,
      baseFare: (json['base_fare'] as num).toDouble(),
      perKmRate: (json['per_km_rate'] as num).toDouble(),
      perMinuteRate: (json['per_minute_rate'] as num).toDouble(),
      minimumFare: (json['minimum_fare'] as num).toDouble(),
      platformCommissionPercent: (json['platform_commission_percent'] as num)
          .toDouble(),
      surgeMultiplier: (json['surge_multiplier'] as num).toDouble(),
      maxSearchRadiusKm: (json['max_search_radius_km'] as num).toDouble(),
      driverRequestTimeoutSeconds:
          json['driver_request_timeout_seconds'] as int,
      waitingFeePerMin: (json['waiting_fee_per_min'] as num?)?.toDouble() ?? 75.0,
      cardAuthBufferPercent: (json['card_auth_buffer_percent'] as num?)?.toDouble() ?? 50.0,
      cashEnabled: json['cash_enabled'] as bool? ?? true,
      cardEnabled: json['card_enabled'] as bool? ?? true,
      active: json['active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'base_fare': baseFare,
    'per_km_rate': perKmRate,
    'per_minute_rate': perMinuteRate,
    'minimum_fare': minimumFare,
    'platform_commission_percent': platformCommissionPercent,
    'surge_multiplier': surgeMultiplier,
    'max_search_radius_km': maxSearchRadiusKm,
    'driver_request_timeout_seconds': driverRequestTimeoutSeconds,
    'waiting_fee_per_min': waitingFeePerMin,
    'card_auth_buffer_percent': cardAuthBufferPercent,
    'cash_enabled': cashEnabled,
    'card_enabled': cardEnabled,
    'active': active,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  RidePricingSettings copyWith({
    String? id,
    double? baseFare,
    double? perKmRate,
    double? perMinuteRate,
    double? minimumFare,
    double? platformCommissionPercent,
    double? surgeMultiplier,
    double? maxSearchRadiusKm,
    int? driverRequestTimeoutSeconds,
    double? waitingFeePerMin,
    double? cardAuthBufferPercent,
    bool? cashEnabled,
    bool? cardEnabled,
    bool? active,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RidePricingSettings(
      id: id ?? this.id,
      baseFare: baseFare ?? this.baseFare,
      perKmRate: perKmRate ?? this.perKmRate,
      perMinuteRate: perMinuteRate ?? this.perMinuteRate,
      minimumFare: minimumFare ?? this.minimumFare,
      platformCommissionPercent:
          platformCommissionPercent ?? this.platformCommissionPercent,
      surgeMultiplier: surgeMultiplier ?? this.surgeMultiplier,
      maxSearchRadiusKm: maxSearchRadiusKm ?? this.maxSearchRadiusKm,
      driverRequestTimeoutSeconds:
          driverRequestTimeoutSeconds ?? this.driverRequestTimeoutSeconds,
      waitingFeePerMin: waitingFeePerMin ?? this.waitingFeePerMin,
      cardAuthBufferPercent: cardAuthBufferPercent ?? this.cardAuthBufferPercent,
      cashEnabled: cashEnabled ?? this.cashEnabled,
      cardEnabled: cardEnabled ?? this.cardEnabled,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
