import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/driver/driver_intelligence_models.dart';
import '../../utils/app_logger.dart';

/// Client service for the `driver-intelligence` edge function.
/// Provides order scoring, hybrid payout, stacking, performance,
/// earnings floor, recommendations, session management, and earnings.
class DriverIntelligenceService {
  final SupabaseClient _client;
  DriverIntelligenceService(this._client);

  // ── Score an order ──────────────────────────────────────────────
  Future<OrderScore?> scoreOrder({
    required String orderId,
    String? driverId,
    double? driverLat,
    double? driverLng,
  }) async {
    final res = await _invoke({
      'action': 'score_order',
      'order_id': orderId,
      if (driverId != null) 'driver_id': driverId,
      if (driverLat != null) 'driver_lat': driverLat,
      if (driverLng != null) 'driver_lng': driverLng,
    });
    return res != null ? OrderScore.fromJson(res) : null;
  }

  // ── Calculate hybrid payout ─────────────────────────────────────
  Future<Map<String, dynamic>?> calculatePayout({
    required double distanceKm,
    required double durationMinutes,
    double waitMinutes = 0,
    double tip = 0,
    double surgeMultiplier = 1.0,
    String driverTier = 'bronze',
  }) async {
    return _invoke({
      'action': 'calculate_payout',
      'distance_km': distanceKm,
      'duration_minutes': durationMinutes,
      'wait_minutes': waitMinutes,
      'tip': tip,
      'surge_multiplier': surgeMultiplier,
      'driver_tier': driverTier,
    });
  }

  // ── Check stacking feasibility ──────────────────────────────────
  Future<StackProposal?> checkStacking({
    required String driverId,
    required List<String> orderIds,
  }) async {
    final res = await _invoke({
      'action': 'check_stacking',
      'driver_id': driverId,
      'order_ids': orderIds,
    });
    return res != null ? StackProposal.fromJson(res) : null;
  }

  // ── Update zone demand (admin / cron trigger) ───────────────────
  Future<Map<String, dynamic>?> updateZoneDemand() async {
    return _invoke({'action': 'update_zone_demand'});
  }

  // ── Update driver performance stats ─────────────────────────────
  Future<Map<String, dynamic>?> updatePerformance(String driverId) async {
    return _invoke({'action': 'update_performance', 'driver_id': driverId});
  }

  // ── Check earnings floor ────────────────────────────────────────
  Future<Map<String, dynamic>?> checkEarningsFloor(String driverId) async {
    return _invoke({'action': 'check_earnings_floor', 'driver_id': driverId});
  }

  // ── Get recommendations ─────────────────────────────────────────
  Future<DriverRecommendations?> getRecommendations({
    required String driverId,
    double? driverLat,
    double? driverLng,
  }) async {
    final res = await _invoke({
      'action': 'get_recommendations',
      'driver_id': driverId,
      if (driverLat != null) 'driver_lat': driverLat,
      if (driverLng != null) 'driver_lng': driverLng,
    });
    return res != null ? DriverRecommendations.fromJson(res) : null;
  }

  // ── Session management ──────────────────────────────────────────
  Future<void> startSession(String driverId) async {
    await _invoke({'action': 'start_session', 'driver_id': driverId});
  }

  Future<Map<String, dynamic>?> endSession(String driverId) async {
    return _invoke({'action': 'end_session', 'driver_id': driverId});
  }

  // ── Earnings dashboard data ─────────────────────────────────────
  Future<EarningsSummary?> getEarnings({
    required String driverId,
    String period = 'today',
  }) async {
    // Query the driver_earnings ledger directly (RLS: "Drivers read own
    // earnings"). This avoids depending on the driver-intelligence edge
    // function for the per-order earnings list.
    try {
      final now = DateTime.now();
      late final DateTime since;
      switch (period) {
        case 'today':
          since = DateTime(now.year, now.month, now.day);
          break;
        case 'week':
          since = now.subtract(const Duration(days: 7));
          break;
        case 'month':
          since = now.subtract(const Duration(days: 30));
          break;
        default:
          since = DateTime.fromMillisecondsSinceEpoch(0);
      }
      final rows = await _client
          .from('driver_earnings')
          .select()
          .eq('driver_id', driverId)
          .gte('earned_at', since.toUtc().toIso8601String())
          .order('earned_at', ascending: false);

      final items = (rows as List)
          .map((e) => EarningsDetail.fromJson(e as Map<String, dynamic>))
          .toList();
      double sum(double Function(EarningsDetail) f) =>
          items.fold<double>(0.0, (s, e) => s + f(e));
      final totalPayout = sum((e) => e.totalPayout);
      final totalMinutes = sum((e) => e.durationMinutes);
      double round2(double v) => (v * 100).roundToDouble() / 100;

      return EarningsSummary(
        period: period,
        deliveryCount: items.length,
        totalPayout: round2(totalPayout),
        basePay: round2(sum((e) => e.basePay)),
        distancePay: round2(sum((e) => e.distancePay)),
        timePay: round2(sum((e) => e.timePay)),
        waitPay: round2(sum((e) => e.waitPay)),
        boostPay: round2(sum((e) => e.boostPay)),
        surgePay: round2(sum((e) => e.surgePay)),
        tips: round2(sum((e) => e.tip)),
        floorTopups: round2(sum((e) => e.floorTopup)),
        totalDistanceKm: round2(sum((e) => e.distanceKm)),
        totalMinutes: totalMinutes.round(),
        avgPerDelivery: items.isNotEmpty ? round2(totalPayout / items.length) : 0,
        avgPerHour: totalMinutes > 0 ? round2(totalPayout / (totalMinutes / 60)) : 0,
        deliveries: items,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Fetch zones from DB directly (fast, no edge function) ───────
  Future<List<DemandZone>> getZones() async {
    try {
      // Fully server-computed from live data: active_orders (unassigned active
      // orders in the zone), available_drivers (online drivers with a fresh
      // location in the zone), and the derived demand_level / surge_multiplier.
      final res = await _client.rpc('get_demand_zones');
      return (res as List)
          .map((e) => DemandZone.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Failed to fetch demand zones: $e');
      return [];
    }
  }

  // ── Fetch driver stats from DB directly ─────────────────────────
  Future<DriverStats?> getDriverStats(String driverId) async {
    try {
      final res = await _client
          .from('driver_stats')
          .select()
          .eq('driver_id', driverId)
          .maybeSingle();
      return res != null ? DriverStats.fromJson(res) : null;
    } catch (e) {
      AppLogger.error('Failed to fetch driver stats: $e');
      return null;
    }
  }

  // ── Private: invoke edge function ───────────────────────────────
  Future<Map<String, dynamic>?> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke(
        'driver-intelligence',
        body: body,
      );
      if (response.status >= 400) {
        AppLogger.error(
          'driver-intelligence error ${response.status}: ${response.data}',
        );
        return null;
      }
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is String) return jsonDecode(data) as Map<String, dynamic>;
      return null;
    } catch (e) {
      AppLogger.error('driver-intelligence invoke failed: $e');
      return null;
    }
  }
}
