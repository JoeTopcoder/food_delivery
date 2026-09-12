/// Models for the admin operating dashboard.
///
/// Every money field is MINOR UNITS (cents) as an int, because that is what the
/// RPCs return. The database columns are double precision and converting them
/// is a separate, breaking job; the RPCs cast to NUMERIC before any arithmetic
/// and hand back BIGINT, so no float ever carries a money value across the
/// wire or through this file.
library;

/// Formats minor units for display. The symbol comes from config, never a
/// literal — this platform has already been redenominated once.
String formatMinor(int minorUnits, String symbol) {
  final major = minorUnits / 100;
  final s = major.abs().toStringAsFixed(2);
  final parts = s.split('.');
  final withSeparators = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '${minorUnits < 0 ? '-' : ''}$symbol$withSeparators.${parts[1]}';
}

class FoodMetrics {
  const FoodMetrics({
    required this.ordersCount,
    required this.gmv,
    required this.restaurantCommissionTotal,
    required this.deliveryFeeTotal,
    required this.riderPayoutTotal,
    required this.contributionTotal,
    required this.avgOrderValue,
    required this.breakevenOrdersRequired,
    required this.breakevenProgressPct,
  });

  final int ordersCount;
  final int gmv;
  final int restaurantCommissionTotal;
  final int deliveryFeeTotal;
  final int riderPayoutTotal;
  final int contributionTotal;
  final int avgOrderValue;
  final int breakevenOrdersRequired;
  final double breakevenProgressPct;

  /// True when monthly_ops_cost has never been set. The dashboard says so
  /// rather than drawing a 0% bar, which would read as "failing" instead of
  /// "not configured".
  bool get breakevenUnconfigured => breakevenOrdersRequired == 0;

  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

  factory FoodMetrics.fromJson(Map<String, dynamic> j) => FoodMetrics(
    ordersCount: _i(j['orders_count']),
    gmv: _i(j['gmv']),
    restaurantCommissionTotal: _i(j['restaurant_commission_total']),
    deliveryFeeTotal: _i(j['delivery_fee_total']),
    riderPayoutTotal: _i(j['rider_payout_total']),
    contributionTotal: _i(j['contribution_total']),
    avgOrderValue: _i(j['avg_order_value']),
    breakevenOrdersRequired: _i(j['breakeven_orders_required']),
    breakevenProgressPct: _d(j['breakeven_progress_pct']),
  );

  static const empty = FoodMetrics(
    ordersCount: 0, gmv: 0, restaurantCommissionTotal: 0, deliveryFeeTotal: 0,
    riderPayoutTotal: 0, contributionTotal: 0, avgOrderValue: 0,
    breakevenOrdersRequired: 0, breakevenProgressPct: 0,
  );
}

class GroceryMetrics {
  const GroceryMetrics({
    required this.ordersCount,
    required this.gmv,
    required this.serviceFeeTotal,
    required this.supermarketCommissionTotal,
    required this.deliveryFeeTotal,
    required this.riderPayoutTotal,
    required this.deliveryMarginTotal,
    required this.contributionTotal,
    required this.avgOrderValue,
  });

  final int ordersCount;
  final int gmv;
  final int serviceFeeTotal;
  final int supermarketCommissionTotal;
  final int deliveryFeeTotal;
  final int riderPayoutTotal;
  final int deliveryMarginTotal;
  final int contributionTotal;
  final int avgOrderValue;

  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  factory GroceryMetrics.fromJson(Map<String, dynamic> j) => GroceryMetrics(
    ordersCount: _i(j['orders_count']),
    gmv: _i(j['gmv']),
    serviceFeeTotal: _i(j['service_fee_total']),
    supermarketCommissionTotal: _i(j['supermarket_commission_total']),
    deliveryFeeTotal: _i(j['delivery_fee_total']),
    riderPayoutTotal: _i(j['rider_payout_total']),
    deliveryMarginTotal: _i(j['delivery_margin_total']),
    contributionTotal: _i(j['contribution_total']),
    avgOrderValue: _i(j['avg_order_value']),
  );

  static const empty = GroceryMetrics(
    ordersCount: 0, gmv: 0, serviceFeeTotal: 0, supermarketCommissionTotal: 0,
    deliveryFeeTotal: 0, riderPayoutTotal: 0, deliveryMarginTotal: 0,
    contributionTotal: 0, avgOrderValue: 0,
  );
}

class CombinedMetrics {
  const CombinedMetrics({
    required this.totalContribution,
    required this.opsCostProrated,
    required this.operatingProfit,
  });

  final int totalContribution;
  final int opsCostProrated;
  final int operatingProfit;

  bool get opsCostUnconfigured => opsCostProrated == 0;

  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  factory CombinedMetrics.fromJson(Map<String, dynamic> j) => CombinedMetrics(
    totalContribution: _i(j['total_contribution']),
    opsCostProrated: _i(j['ops_cost_prorated']),
    operatingProfit: _i(j['operating_profit']),
  );

  static const empty = CombinedMetrics(
    totalContribution: 0, opsCostProrated: 0, operatingProfit: 0,
  );
}

enum PaceStatus { ahead, onTrack, behind, noTarget }

class DailyTarget {
  const DailyTarget({
    required this.targetId,
    required this.targetDate,
    required this.vertical,
    required this.targetOrders,
    required this.source,
    required this.actualOrders,
    required this.progressPct,
    required this.projectedEodOrders,
    required this.pace,
    required this.aov,
    required this.grossRevenuePerOrder,
    required this.netContributionPerOrder,
    required this.aovDelta7d,
    required this.grossPerOrderDelta7d,
    required this.netPerOrderDelta7d,
    this.notes,
  });

  final int? targetId;
  final DateTime targetDate;
  final String vertical;
  final int targetOrders;
  final String source;
  final String? notes;
  final int actualOrders;
  final double progressPct;
  final int projectedEodOrders;
  final PaceStatus pace;
  final int aov;
  final int grossRevenuePerOrder;
  final int netContributionPerOrder;
  final int aovDelta7d;
  final int grossPerOrderDelta7d;
  final int netPerOrderDelta7d;

  bool get hasTarget => targetOrders > 0;
  bool get isOverride => source == 'manual_override';

  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

  factory DailyTarget.fromJson(Map<String, dynamic> j) => DailyTarget(
    targetId: (j['target_id'] as num?)?.toInt(),
    targetDate: DateTime.parse(j['target_date'] as String),
    vertical: (j['vertical'] ?? 'food').toString(),
    targetOrders: _i(j['target_orders']),
    source: (j['source'] ?? 'none').toString(),
    notes: j['notes'] as String?,
    actualOrders: _i(j['actual_orders']),
    progressPct: _d(j['progress_pct']),
    projectedEodOrders: _i(j['projected_eod_orders']),
    pace: switch ((j['pace_status'] ?? '').toString()) {
      'ahead' => PaceStatus.ahead,
      'on_track' => PaceStatus.onTrack,
      'behind' => PaceStatus.behind,
      _ => PaceStatus.noTarget,
    },
    aov: _i(j['aov']),
    grossRevenuePerOrder: _i(j['gross_revenue_per_order']),
    netContributionPerOrder: _i(j['net_contribution_per_order']),
    aovDelta7d: _i(j['aov_delta_7d']),
    grossPerOrderDelta7d: _i(j['gross_per_order_delta_7d']),
    netPerOrderDelta7d: _i(j['net_per_order_delta_7d']),
  );
}

/// A period the dashboard can be viewed over. `custom` carries its own bounds.
class MetricsPeriod {
  const MetricsPeriod(this.key, this.label, {this.from, this.to});

  final String key;
  final String label;
  final DateTime? from;
  final DateTime? to;

  static const today = MetricsPeriod('today', 'Today');
  static const mtd = MetricsPeriod('mtd', 'Month to date');
  static const ytd = MetricsPeriod('ytd', 'Year to date');

  static const presets = [today, mtd, ytd];

  Map<String, dynamic> get params => {
    'p_period': key,
    if (from != null) 'p_from': from!.toUtc().toIso8601String(),
    if (to != null) 'p_to': to!.toUtc().toIso8601String(),
  };
}

/// One status queue in the live-ops panel.
///
/// The bucket edges are configurable server-side, so the labels travel with
/// the counts instead of being written into this file — a dashboard that says
/// "30-35" while the SLA has been retuned to 25 is worse than one that says
/// nothing.
class LiveOpsRow {
  const LiveOpsRow({
    required this.status,
    required this.ordersCount,
    required this.bucketLabels,
    required this.bucketCounts,
    required this.breachCount,
    required this.oldestMinutes,
  });

  final String status;
  final int ordersCount;
  final List<String> bucketLabels;
  final List<int> bucketCounts;
  final int breachCount;
  final double oldestMinutes;

  /// Title-cased from the raw status, which is snake_case in the database
  /// ('on_the_way', not 'out_for_delivery' — that value does not exist here).
  String get label => status
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  factory LiveOpsRow.fromJson(Map<String, dynamic> j) => LiveOpsRow(
    status: (j['status'] ?? '').toString(),
    ordersCount: (j['orders_count'] as num?)?.toInt() ?? 0,
    bucketLabels:
        ((j['bucket_labels'] as List?) ?? const []).map((e) => '$e').toList(),
    bucketCounts: ((j['bucket_counts'] as List?) ?? const [])
        .map((e) => (e as num?)?.toInt() ?? 0)
        .toList(),
    breachCount: (j['breach_count'] as num?)?.toInt() ?? 0,
    oldestMinutes: (j['oldest_minutes'] as num?)?.toDouble() ?? 0,
  );
}

/// Average time an order spends waiting on one actor.
class SlaAttributionRow {
  const SlaAttributionRow({
    required this.actorType,
    required this.avgMinutes,
    required this.medianMinutes,
    required this.p90Minutes,
    required this.maxMinutes,
    required this.sampleSize,
    required this.shareOfTimePct,
  });

  final String actorType;
  final double avgMinutes;
  final double medianMinutes;
  final double p90Minutes;
  final double maxMinutes;

  /// How many closed stages this row averages. Shown in the UI, because
  /// order_status_events only started recording on 2026-09-09 and an average
  /// of two stages should not be read as a trend.
  final int sampleSize;
  final double shareOfTimePct;

  String get label => switch (actorType) {
    'customer' => 'Waiting for the store to accept',
    'store' => 'Store preparing',
    'rider' => 'Rider collecting and delivering',
    'dispatch' => 'Dispatch assigning',
    'system' => 'System',
    _ => actorType,
  };

  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

  factory SlaAttributionRow.fromJson(Map<String, dynamic> j) =>
      SlaAttributionRow(
        actorType: (j['actor_type'] ?? '').toString(),
        avgMinutes: _d(j['avg_minutes']),
        medianMinutes: _d(j['median_minutes']),
        p90Minutes: _d(j['p90_minutes']),
        maxMinutes: _d(j['max_minutes']),
        sampleSize: (j['sample_size'] as num?)?.toInt() ?? 0,
        shareOfTimePct: _d(j['share_of_time_pct']),
      );
}

/// One row of a partner leaderboard. Money is minor units, as everywhere else.
class PartnerRow {
  const PartnerRow({
    required this.partnerId,
    required this.partnerName,
    required this.ordersCount,
    required this.gmv,
    required this.contribution,
    required this.deliveredCount,
    required this.onTimePct,
  });

  final String partnerId;
  final String partnerName;
  final int ordersCount;
  final int gmv;
  final int contribution;

  /// Orders with a delivered_at to measure against. On-time is a share of
  /// these, not of every order, so this is shown next to the percentage.
  final int deliveredCount;

  /// Null when nothing in the period has been delivered — which is not the
  /// same as 0%, and must not render as it.
  final double? onTimePct;

  factory PartnerRow.fromJson(Map<String, dynamic> j) => PartnerRow(
    partnerId: (j['partner_id'] ?? '').toString(),
    partnerName: (j['partner_name'] ?? 'Unknown').toString(),
    ordersCount: (j['orders_count'] as num?)?.toInt() ?? 0,
    gmv: (j['gmv'] as num?)?.toInt() ?? 0,
    contribution: (j['contribution'] as num?)?.toInt() ?? 0,
    deliveredCount: (j['delivered_count'] as num?)?.toInt() ?? 0,
    onTimePct: (j['on_time_pct'] as num?)?.toDouble(),
  );
}

/// Which leaderboard the UI is asking for.
enum PartnerKind {
  restaurant('restaurant', 'Restaurants'),
  supermarket('supermarket', 'Supermarkets'),
  rider('rider', 'Riders');

  const PartnerKind(this.key, this.label);
  final String key;
  final String label;
}
