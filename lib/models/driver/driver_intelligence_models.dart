// Models for the driver intelligence system: order scoring, earnings,
// performance stats, zone demand, and order stacking.

// ── Order Score ─────────────────────────────────────────────────────
class OrderScore {
  final int score;
  final String label;
  final String recommendation;
  final String? rejectReason;
  final String? alternativeZone;
  final OrderPayout payout;
  final OrderMetrics metrics;
  final RestaurantInfo? restaurant;
  final bool isPeakHour;

  const OrderScore({
    required this.score,
    required this.label,
    required this.recommendation,
    this.rejectReason,
    this.alternativeZone,
    required this.payout,
    required this.metrics,
    this.restaurant,
    this.isPeakHour = false,
  });

  factory OrderScore.fromJson(Map<String, dynamic> json) => OrderScore(
    score: (json['score'] as num?)?.toInt() ?? 50,
    label: json['label'] as String? ?? 'Good',
    recommendation: json['recommendation'] as String? ?? 'neutral',
    rejectReason: json['reject_reason'] as String?,
    alternativeZone: json['alternative_zone'] as String?,
    payout: OrderPayout.fromJson(json['payout'] as Map<String, dynamic>? ?? {}),
    metrics: OrderMetrics.fromJson(
      json['metrics'] as Map<String, dynamic>? ?? {},
    ),
    restaurant: json['restaurant'] != null
        ? RestaurantInfo.fromJson(json['restaurant'] as Map<String, dynamic>)
        : null,
    isPeakHour: json['is_peak_hour'] as bool? ?? false,
  );

  bool get isHighValue => score >= 80;
  bool get isGood => score >= 60;
  bool get isBad => score < 40;
}

class OrderPayout {
  final double basePay;
  final double distancePay;
  final double timePay;
  final double waitPay;
  final double surgeMultiplier;
  final double tipEstimate;
  final double totalPayout;

  const OrderPayout({
    this.basePay = 0,
    this.distancePay = 0,
    this.timePay = 0,
    this.waitPay = 0,
    this.surgeMultiplier = 1.0,
    this.tipEstimate = 0,
    this.totalPayout = 0,
  });

  factory OrderPayout.fromJson(Map<String, dynamic> json) => OrderPayout(
    basePay: (json['base_pay'] as num?)?.toDouble() ?? 0,
    distancePay: (json['distance_pay'] as num?)?.toDouble() ?? 0,
    timePay: (json['time_pay'] as num?)?.toDouble() ?? 0,
    waitPay: (json['wait_pay'] as num?)?.toDouble() ?? 0,
    surgeMultiplier: (json['surge_multiplier'] as num?)?.toDouble() ?? 1.0,
    tipEstimate: (json['tip_estimate'] as num?)?.toDouble() ?? 0,
    totalPayout: (json['total_payout'] as num?)?.toDouble() ?? 0,
  );
}

class OrderMetrics {
  final double distanceKm;
  final double distanceMiles;
  final int estimatedMinutes;
  final double earningsPerKm;
  final double earningsPerMile;
  final double earningsPerHour;

  const OrderMetrics({
    this.distanceKm = 0,
    this.distanceMiles = 0,
    this.estimatedMinutes = 0,
    this.earningsPerKm = 0,
    this.earningsPerMile = 0,
    this.earningsPerHour = 0,
  });

  factory OrderMetrics.fromJson(Map<String, dynamic> json) => OrderMetrics(
    distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
    distanceMiles: (json['distance_miles'] as num?)?.toDouble() ?? 0,
    estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt() ?? 0,
    earningsPerKm: (json['earnings_per_km'] as num?)?.toDouble() ?? 0,
    earningsPerMile: (json['earnings_per_mile'] as num?)?.toDouble() ?? 0,
    earningsPerHour: (json['earnings_per_hour'] as num?)?.toDouble() ?? 0,
  );
}

class RestaurantInfo {
  final String? name;
  final double avgPrepMinutes;
  final bool isSlow;

  const RestaurantInfo({
    this.name,
    this.avgPrepMinutes = 15,
    this.isSlow = false,
  });

  factory RestaurantInfo.fromJson(Map<String, dynamic> json) => RestaurantInfo(
    name: json['name'] as String?,
    avgPrepMinutes: (json['avg_prep_minutes'] as num?)?.toDouble() ?? 15,
    isSlow: json['is_slow'] as bool? ?? false,
  );
}

// ── Driver Stats / Performance ──────────────────────────────────────
class DriverStats {
  final String driverId;
  final double score;
  final String tier;
  final double acceptanceRate;
  final double completionRate;
  final double onTimeRate;
  final double avgDeliveryMinutes;
  final double avgCustomerRating;
  final double avgTipPercent;
  final double totalTips;
  final double totalDistanceKm;
  final int ordersAccepted;
  final int ordersDeclined;
  final double bonusMultiplier;
  final bool priorityDispatch;
  final double hourlyEarnings;
  final double sessionEarnings;

  const DriverStats({
    required this.driverId,
    this.score = 50,
    this.tier = 'bronze',
    this.acceptanceRate = 0,
    this.completionRate = 0,
    this.onTimeRate = 0,
    this.avgDeliveryMinutes = 0,
    this.avgCustomerRating = 0,
    this.avgTipPercent = 0,
    this.totalTips = 0,
    this.totalDistanceKm = 0,
    this.ordersAccepted = 0,
    this.ordersDeclined = 0,
    this.bonusMultiplier = 1.0,
    this.priorityDispatch = false,
    this.hourlyEarnings = 0,
    this.sessionEarnings = 0,
  });

  factory DriverStats.fromJson(Map<String, dynamic> json) => DriverStats(
    driverId: json['driver_id'] as String? ?? '',
    score: (json['driver_score'] ?? json['score'] as num?)?.toDouble() ?? 50,
    tier: json['tier'] as String? ?? 'bronze',
    acceptanceRate: (json['acceptance_rate'] as num?)?.toDouble() ?? 0,
    completionRate: (json['completion_rate'] as num?)?.toDouble() ?? 0,
    onTimeRate: (json['on_time_rate'] as num?)?.toDouble() ?? 0,
    avgDeliveryMinutes: (json['avg_delivery_minutes'] as num?)?.toDouble() ?? 0,
    avgCustomerRating: (json['avg_customer_rating'] as num?)?.toDouble() ?? 0,
    avgTipPercent: (json['avg_tip_percent'] as num?)?.toDouble() ?? 0,
    totalTips: (json['total_tips'] as num?)?.toDouble() ?? 0,
    totalDistanceKm: (json['total_distance_km'] as num?)?.toDouble() ?? 0,
    ordersAccepted: (json['orders_accepted'] as num?)?.toInt() ?? 0,
    ordersDeclined: (json['orders_declined'] as num?)?.toInt() ?? 0,
    bonusMultiplier: (json['bonus_multiplier'] as num?)?.toDouble() ?? 1.0,
    priorityDispatch: json['priority_dispatch'] as bool? ?? false,
    hourlyEarnings: (json['hourly_earnings_current'] as num?)?.toDouble() ?? 0,
    sessionEarnings: (json['session_earnings'] as num?)?.toDouble() ?? 0,
  );

  String get tierEmoji {
    switch (tier) {
      case 'elite':
        return '💎';
      case 'gold':
        return '🥇';
      case 'silver':
        return '🥈';
      default:
        return '🥉';
    }
  }

  String get tierLabel => '${tier[0].toUpperCase()}${tier.substring(1)}';

  int get scoreToNextTier {
    if (tier == 'elite') return 0;
    if (tier == 'gold') return (90 - score).ceil();
    if (tier == 'silver') return (75 - score).ceil();
    return (60 - score).ceil();
  }
}

// ── Zone / Surge ────────────────────────────────────────────────────
class DemandZone {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final int activeOrders;
  final int availableDrivers;
  final String demandLevel;
  final double surgeMultiplier;
  final double? distanceFromDriver;

  const DemandZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusKm = 3.0,
    this.activeOrders = 0,
    this.availableDrivers = 0,
    this.demandLevel = 'normal',
    this.surgeMultiplier = 1.0,
    this.distanceFromDriver,
  });

  factory DemandZone.fromJson(Map<String, dynamic> json) => DemandZone(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    radiusKm: (json['radius_km'] as num?)?.toDouble() ?? 3.0,
    activeOrders: (json['active_orders'] as num?)?.toInt() ?? 0,
    availableDrivers: (json['available_drivers'] as num?)?.toInt() ?? 0,
    demandLevel: json['demand_level'] as String? ?? 'normal',
    surgeMultiplier: (json['surge_multiplier'] as num?)?.toDouble() ?? 1.0,
    distanceFromDriver: (json['distance_km'] as num?)?.toDouble(),
  );

  bool get hasSurge => surgeMultiplier > 1.0;
}

// ── Earnings Detail ─────────────────────────────────────────────────
class EarningsDetail {
  final String id;
  final String? orderId;
  final double totalPayout;
  final double basePay;
  final double distancePay;
  final double timePay;
  final double waitPay;
  final double boostPay;
  final double surgePay;
  final double tip;
  final double floorTopup;
  final double distanceKm;
  final double durationMinutes;
  final double earningsPerHour;
  final bool isStacked;
  final DateTime earnedAt;

  const EarningsDetail({
    required this.id,
    this.orderId,
    this.totalPayout = 0,
    this.basePay = 0,
    this.distancePay = 0,
    this.timePay = 0,
    this.waitPay = 0,
    this.boostPay = 0,
    this.surgePay = 0,
    this.tip = 0,
    this.floorTopup = 0,
    this.distanceKm = 0,
    this.durationMinutes = 0,
    this.earningsPerHour = 0,
    this.isStacked = false,
    required this.earnedAt,
  });

  factory EarningsDetail.fromJson(Map<String, dynamic> json) => EarningsDetail(
    id: json['id'] as String? ?? '',
    orderId: json['order_id'] as String?,
    totalPayout: (json['total_payout'] as num?)?.toDouble() ?? 0,
    basePay: (json['base_pay'] as num?)?.toDouble() ?? 0,
    distancePay: (json['distance_pay'] as num?)?.toDouble() ?? 0,
    timePay: (json['time_pay'] as num?)?.toDouble() ?? 0,
    waitPay: (json['wait_pay'] as num?)?.toDouble() ?? 0,
    boostPay: (json['boost_pay'] as num?)?.toDouble() ?? 0,
    surgePay: (json['surge_pay'] as num?)?.toDouble() ?? 0,
    tip: (json['tip'] as num?)?.toDouble() ?? 0,
    floorTopup: (json['floor_topup'] as num?)?.toDouble() ?? 0,
    distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
    durationMinutes: (json['duration_minutes'] as num?)?.toDouble() ?? 0,
    earningsPerHour: (json['earnings_per_hour'] as num?)?.toDouble() ?? 0,
    isStacked: json['is_stacked'] as bool? ?? false,
    earnedAt:
        DateTime.tryParse(json['earned_at'] as String? ?? '') ?? DateTime.now(),
  );
}

class EarningsSummary {
  final String period;
  final int deliveryCount;
  final double totalPayout;
  final double basePay;
  final double distancePay;
  final double timePay;
  final double waitPay;
  final double boostPay;
  final double surgePay;
  final double tips;
  final double floorTopups;
  final double totalDistanceKm;
  final int totalMinutes;
  final double avgPerDelivery;
  final double avgPerHour;
  final List<EarningsDetail> deliveries;

  const EarningsSummary({
    this.period = 'today',
    this.deliveryCount = 0,
    this.totalPayout = 0,
    this.basePay = 0,
    this.distancePay = 0,
    this.timePay = 0,
    this.waitPay = 0,
    this.boostPay = 0,
    this.surgePay = 0,
    this.tips = 0,
    this.floorTopups = 0,
    this.totalDistanceKm = 0,
    this.totalMinutes = 0,
    this.avgPerDelivery = 0,
    this.avgPerHour = 0,
    this.deliveries = const [],
  });

  factory EarningsSummary.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>? ?? {};
    final deliveriesList =
        (json['deliveries'] as List?)
            ?.map((e) => EarningsDetail.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return EarningsSummary(
      period: json['period'] as String? ?? 'today',
      deliveryCount: (json['delivery_count'] as num?)?.toInt() ?? 0,
      totalPayout: (summary['total_payout'] as num?)?.toDouble() ?? 0,
      basePay: (summary['base_pay'] as num?)?.toDouble() ?? 0,
      distancePay: (summary['distance_pay'] as num?)?.toDouble() ?? 0,
      timePay: (summary['time_pay'] as num?)?.toDouble() ?? 0,
      waitPay: (summary['wait_pay'] as num?)?.toDouble() ?? 0,
      boostPay: (summary['boost_pay'] as num?)?.toDouble() ?? 0,
      surgePay: (summary['surge_pay'] as num?)?.toDouble() ?? 0,
      tips: (summary['tips'] as num?)?.toDouble() ?? 0,
      floorTopups: (summary['floor_topups'] as num?)?.toDouble() ?? 0,
      totalDistanceKm: (summary['total_distance_km'] as num?)?.toDouble() ?? 0,
      totalMinutes: (summary['total_minutes'] as num?)?.toInt() ?? 0,
      avgPerDelivery: (summary['avg_per_delivery'] as num?)?.toDouble() ?? 0,
      avgPerHour: (summary['avg_per_hour'] as num?)?.toDouble() ?? 0,
      deliveries: deliveriesList,
    );
  }
}

// ── Stack / Batch ───────────────────────────────────────────────────
class StackProposal {
  final bool canStack;
  final int orderCount;
  final double individualTotal;
  final double stackedTotal;
  final double payoutIncreasePct;
  final double optimizedDistanceKm;
  final int estimatedMinutes;
  final int delayPerCustomerMinutes;
  final String? stackId;
  final List<StackRouteStop> route;
  final List<String>? rejectReasons;

  const StackProposal({
    this.canStack = false,
    this.orderCount = 0,
    this.individualTotal = 0,
    this.stackedTotal = 0,
    this.payoutIncreasePct = 0,
    this.optimizedDistanceKm = 0,
    this.estimatedMinutes = 0,
    this.delayPerCustomerMinutes = 0,
    this.stackId,
    this.route = const [],
    this.rejectReasons,
  });

  factory StackProposal.fromJson(Map<String, dynamic> json) {
    final routeList =
        (json['route'] as List?)
            ?.map((e) => StackRouteStop.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return StackProposal(
      canStack: json['can_stack'] as bool? ?? false,
      orderCount: (json['order_count'] as num?)?.toInt() ?? 0,
      individualTotal: (json['individual_total'] as num?)?.toDouble() ?? 0,
      stackedTotal: (json['stacked_total'] as num?)?.toDouble() ?? 0,
      payoutIncreasePct: (json['payout_increase_pct'] as num?)?.toDouble() ?? 0,
      optimizedDistanceKm:
          (json['optimized_distance_km'] as num?)?.toDouble() ?? 0,
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt() ?? 0,
      delayPerCustomerMinutes:
          (json['delay_per_customer_minutes'] as num?)?.toInt() ?? 0,
      stackId: json['stack_id'] as String?,
      route: routeList,
      rejectReasons: (json['reject_reasons'] as List?)?.cast<String>(),
    );
  }
}

class StackRouteStop {
  final int position;
  final String orderId;
  final String restaurant;

  const StackRouteStop({
    this.position = 1,
    this.orderId = '',
    this.restaurant = '',
  });

  factory StackRouteStop.fromJson(Map<String, dynamic> json) => StackRouteStop(
    position: (json['position'] as num?)?.toInt() ?? 1,
    orderId: json['order_id'] as String? ?? '',
    restaurant: json['restaurant'] as String? ?? '',
  );
}

// ── Recommendations ─────────────────────────────────────────────────
class DriverRecommendations {
  final List<String> tips;
  final List<DemandZone> surgeZones;
  final bool isPeakHour;

  const DriverRecommendations({
    this.tips = const [],
    this.surgeZones = const [],
    this.isPeakHour = false,
  });

  factory DriverRecommendations.fromJson(Map<String, dynamic> json) {
    final zones =
        (json['surge_zones'] as List?)
            ?.map((e) => DemandZone.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return DriverRecommendations(
      tips: (json['tips'] as List?)?.cast<String>() ?? [],
      surgeZones: zones,
      isPeakHour: json['is_peak_hour'] as bool? ?? false,
    );
  }
}
