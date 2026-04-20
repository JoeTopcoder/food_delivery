import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/driver_intelligence_models.dart';
import '../services/driver_intelligence_service.dart';

// ── Service singleton ────────────────────────────────────────────────
final driverIntelligenceServiceProvider = Provider<DriverIntelligenceService>((
  ref,
) {
  return DriverIntelligenceService(SupabaseConfig.client);
});

// ── Order score for a specific order ─────────────────────────────────
final orderScoreProvider = FutureProvider.autoDispose
    .family<
      OrderScore?,
      ({String orderId, String? driverId, double? driverLat, double? driverLng})
    >((ref, params) async {
      final svc = ref.watch(driverIntelligenceServiceProvider);
      return svc.scoreOrder(
        orderId: params.orderId,
        driverId: params.driverId,
        driverLat: params.driverLat,
        driverLng: params.driverLng,
      );
    });

// ── Driver stats ─────────────────────────────────────────────────────
final driverStatsProvider = FutureProvider.autoDispose
    .family<DriverStats?, String>((ref, driverId) async {
      final svc = ref.watch(driverIntelligenceServiceProvider);
      return svc.getDriverStats(driverId);
    });

// ── Demand zones ─────────────────────────────────────────────────────
final demandZonesProvider = FutureProvider.autoDispose<List<DemandZone>>((
  ref,
) async {
  final svc = ref.watch(driverIntelligenceServiceProvider);
  return svc.getZones();
});

// ── Earnings summary by period ───────────────────────────────────────
final earningsSummaryProvider = FutureProvider.autoDispose
    .family<EarningsSummary?, ({String driverId, String period})>((
      ref,
      params,
    ) async {
      final svc = ref.watch(driverIntelligenceServiceProvider);
      return svc.getEarnings(driverId: params.driverId, period: params.period);
    });

// ── Recommendations ──────────────────────────────────────────────────
final driverRecommendationsProvider = FutureProvider.autoDispose
    .family<
      DriverRecommendations?,
      ({String driverId, double? lat, double? lng})
    >((ref, params) async {
      final svc = ref.watch(driverIntelligenceServiceProvider);
      return svc.getRecommendations(
        driverId: params.driverId,
        driverLat: params.lat,
        driverLng: params.lng,
      );
    });

// ── Stacking proposal ────────────────────────────────────────────────
final stackProposalProvider = FutureProvider.autoDispose
    .family<StackProposal?, ({String driverId, List<String> orderIds})>((
      ref,
      params,
    ) async {
      final svc = ref.watch(driverIntelligenceServiceProvider);
      return svc.checkStacking(
        driverId: params.driverId,
        orderIds: params.orderIds,
      );
    });

// ── Zone demand realtime refresh ─────────────────────────────────────
final zoneRealtimeProvider = Provider.autoDispose<void>((ref) {
  final channel = SupabaseConfig.client
      .channel('zone_demand_updates')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'zones',
        callback: (_) => ref.invalidate(demandZonesProvider),
      )
      .subscribe();
  ref.onDispose(() => SupabaseConfig.client.removeChannel(channel));
});
