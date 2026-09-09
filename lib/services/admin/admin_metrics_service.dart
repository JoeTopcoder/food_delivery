import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/admin_metrics_model.dart';
import '../../utils/app_logger.dart';

/// Data access for the admin operating dashboard.
///
/// RPCs only. There is no direct SELECT across orders, payments or drivers from
/// the client for any of this — the aggregation and the admin check both live
/// in Postgres, and a client-side query would be neither aggregated server-side
/// nor gated by anything an attacker cannot skip.
///
/// Follows the existing AnalyticsService shape so the two read the same way.
class AdminMetricsService {
  AdminMetricsService(this._client);

  final SupabaseClient _client;

  Future<FoodMetrics> food(MetricsPeriod period) async {
    final rows = await _client.rpc('admin_metrics_food', params: period.params);
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) return FoodMetrics.empty;
    return FoodMetrics.fromJson(Map<String, dynamic>.from(list.first as Map));
  }

  Future<GroceryMetrics> grocery(MetricsPeriod period) async {
    final rows = await _client.rpc('admin_metrics_grocery', params: period.params);
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) return GroceryMetrics.empty;
    return GroceryMetrics.fromJson(Map<String, dynamic>.from(list.first as Map));
  }

  Future<CombinedMetrics> combined(MetricsPeriod period) async {
    final rows = await _client.rpc('admin_metrics_combined', params: period.params);
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) return CombinedMetrics.empty;
    return CombinedMetrics.fromJson(Map<String, dynamic>.from(list.first as Map));
  }

  Future<DailyTarget?> dailyTarget(String vertical, {DateTime? date}) async {
    final rows = await _client.rpc(
      'admin_get_daily_target',
      params: {
        'p_vertical': vertical,
        if (date != null)
          'p_target_date': date.toIso8601String().split('T').first,
      },
    );
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) return null;
    return DailyTarget.fromJson(Map<String, dynamic>.from(list.first as Map));
  }

  /// Manual override. Inserts a new row server-side; never updates one, so the
  /// history of what was expected stays readable.
  Future<void> setDailyTarget({
    required DateTime date,
    required String vertical,
    required int targetOrders,
    String? notes,
  }) async {
    try {
      await _client.rpc('admin_set_daily_target', params: {
        'p_target_date': date.toIso8601String().split('T').first,
        'p_vertical': vertical,
        'p_target_orders': targetOrders,
        'p_notes': notes,
      });
    } catch (e) {
      AppLogger.error('setDailyTarget failed: $e');
      rethrow;
    }
  }

  /// Target history for the drill-down. Read through the RPC-owned tables via
  /// a plain select is not possible — daily_targets has RLS and no policy — so
  /// this uses the history RPC.
  Future<List<Map<String, dynamic>>> targetHistory(
    String vertical, {
    int limit = 30,
  }) async {
    final rows = await _client.rpc('admin_target_history', params: {
      'p_vertical': vertical,
      'p_limit': limit,
    });
    return ((rows as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
