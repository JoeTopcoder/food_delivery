import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/driver_intelligence_models.dart';
import '../utils/app_logger.dart';

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
    final res = await _invoke({
      'action': 'get_driver_earnings',
      'driver_id': driverId,
      'period': period,
    });
    return res != null ? EarningsSummary.fromJson(res) : null;
  }

  // ── Fetch zones from DB directly (fast, no edge function) ───────
  Future<List<DemandZone>> getZones() async {
    try {
      final res = await _client
          .from('zones')
          .select()
          .eq('is_active', true)
          .order('surge_multiplier', ascending: false);
      return (res as List).map((e) => DemandZone.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Failed to fetch zones: $e');
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
