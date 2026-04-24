import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

/// Analytics data models

class AnalyticsSummary {
  final int dau;
  final int newUsers;
  final int ordersToday;
  final double revenueToday;
  final double aovToday;
  final int ordersWeek;
  final double revenueWeek;
  final int ordersMonth;
  final double revenueMonth;
  final double completionRate;

  const AnalyticsSummary({
    required this.dau,
    required this.newUsers,
    required this.ordersToday,
    required this.revenueToday,
    required this.aovToday,
    required this.ordersWeek,
    required this.revenueWeek,
    required this.ordersMonth,
    required this.revenueMonth,
    required this.completionRate,
  });

  factory AnalyticsSummary.fromJson(Map<String, dynamic> j) => AnalyticsSummary(
    dau: _i(j['dau']),
    newUsers: _i(j['new_users']),
    ordersToday: _i(j['orders_today']),
    revenueToday: _d(j['revenue_today']),
    aovToday: _d(j['aov_today']),
    ordersWeek: _i(j['orders_week']),
    revenueWeek: _d(j['revenue_week']),
    ordersMonth: _i(j['orders_month']),
    revenueMonth: _d(j['revenue_month']),
    completionRate: _d(j['completion_rate']),
  );

  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

  /// AI decision hook: simple rule-based recommendation.
  String get recommendation {
    if (ordersToday < 10) return 'Orders are low — consider running a promo.';
    if (dau > 50 && ordersToday < dau ~/ 3) {
      return 'High traffic but low conversion — check UX or promos.';
    }
    if (completionRate < 80) {
      return 'Completion rate below 80% — investigate cancellations.';
    }
    return 'Performance looks healthy — consider scaling campaigns.';
  }
}

class DauDataPoint {
  final DateTime date;
  final int dau;
  final int orders;
  final double revenue;

  const DauDataPoint({
    required this.date,
    required this.dau,
    required this.orders,
    required this.revenue,
  });

  factory DauDataPoint.fromJson(Map<String, dynamic> j) => DauDataPoint(
    date: DateTime.parse(j['trend_date'] as String),
    dau: (j['dau'] as num?)?.toInt() ?? 0,
    orders: (j['orders'] as num?)?.toInt() ?? 0,
    revenue: (j['revenue'] as num?)?.toDouble() ?? 0.0,
  );
}

class RetentionPoint {
  final DateTime cohortDate;
  final int cohortSize;
  final int retained;
  final double rate;

  const RetentionPoint({
    required this.cohortDate,
    required this.cohortSize,
    required this.retained,
    required this.rate,
  });

  factory RetentionPoint.fromJson(Map<String, dynamic> j) => RetentionPoint(
    cohortDate: DateTime.parse(j['cohort_date'] as String),
    cohortSize: (j['cohort_size'] as num?)?.toInt() ?? 0,
    retained: (j['retained'] as num?)?.toInt() ?? 0,
    rate: (j['rate'] as num?)?.toDouble() ?? 0.0,
  );
}

class TopRestaurant {
  final String id;
  final String name;
  final int orderCount;
  final double revenue;

  const TopRestaurant({
    required this.id,
    required this.name,
    required this.orderCount,
    required this.revenue,
  });

  factory TopRestaurant.fromJson(Map<String, dynamic> j) => TopRestaurant(
    id: j['restaurant_id'] as String? ?? '',
    name: j['restaurant_name'] as String? ?? 'Unknown',
    orderCount: (j['order_count'] as num?)?.toInt() ?? 0,
    revenue: (j['revenue'] as num?)?.toDouble() ?? 0.0,
  );
}

/// Service class — thin wrapper over Supabase RPC calls.
class AnalyticsService {
  final SupabaseClient _client;
  AnalyticsService(this._client);

  /// Live summary for today + rolling windows.
  Future<AnalyticsSummary> getSummary() async {
    try {
      final data = await _client.rpc('get_analytics_summary');
      final json = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data as Map);
      return AnalyticsSummary.fromJson(json);
    } catch (e) {
      AppLogger.error('[Analytics] getSummary error: $e');
      rethrow;
    }
  }

  /// DAU/orders/revenue trend for the last [days] days.
  Future<List<DauDataPoint>> getDauTrend({int days = 30}) async {
    try {
      final data =
          await _client.rpc('get_dau_trend', params: {'days_back': days})
              as List;
      return data
          .map(
            (e) => DauDataPoint.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (e) {
      AppLogger.error('[Analytics] getDauTrend error: $e');
      rethrow;
    }
  }

  /// Retention for [dayN] (1, 7, or 30).
  Future<List<RetentionPoint>> getRetention({int dayN = 7}) async {
    try {
      final data =
          await _client.rpc('get_retention', params: {'day_n': dayN}) as List;
      return data
          .map(
            (e) => RetentionPoint.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (e) {
      AppLogger.error('[Analytics] getRetention error: $e');
      rethrow;
    }
  }

  /// Top [limit] restaurants by revenue in last [days] days.
  Future<List<TopRestaurant>> getTopRestaurants({
    int days = 30,
    int limit = 10,
  }) async {
    try {
      final data =
          await _client.rpc(
                'get_top_restaurants',
                params: {'days_back': days, 'row_limit': limit},
              )
              as List;
      return data
          .map(
            (e) => TopRestaurant.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (e) {
      AppLogger.error('[Analytics] getTopRestaurants error: $e');
      rethrow;
    }
  }

  /// Manually trigger a metrics refresh for [date].
  Future<void> refreshMetrics([DateTime? date]) async {
    try {
      final d = (date ?? DateTime.now());
      final iso =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      await _client.rpc('refresh_daily_metrics', params: {'target_date': iso});
    } catch (e) {
      AppLogger.error('[Analytics] refreshMetrics error: $e');
      rethrow;
    }
  }

  /// Record a session (call once per app open for logged-in users).
  Future<void> recordSession(String userId) async {
    try {
      await _client.from('sessions').insert({'user_id': userId});
    } catch (e) {
      // Non-fatal — don't surface to user
      AppLogger.error('[Analytics] recordSession error: $e');
    }
  }
}
