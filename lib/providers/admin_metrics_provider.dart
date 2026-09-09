import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/supabase_config.dart';
import '../models/admin_metrics_model.dart';
import '../services/admin/admin_metrics_service.dart';

final adminMetricsServiceProvider = Provider<AdminMetricsService>(
  (ref) => AdminMetricsService(SupabaseConfig.client),
);

/// The period every KPI card is scoped to. Held here rather than in the screen
/// so the cards all move together and none can be left showing a stale range.
final adminPeriodProvider = StateProvider<MetricsPeriod>(
  (ref) => MetricsPeriod.today,
);

/// Bumped by the 60-second poll. The KPI providers watch it, so one timer
/// refreshes all of them instead of each card holding its own.
final adminKpiTickProvider = StateProvider<int>((ref) => 0);

/// Bumped by the 15-second live-ops poll, which is deliberately separate: the
/// operational panel needs to be fresher than the financial cards, and tying
/// them together would refetch aggregates four times as often for no reason.
final adminLiveTickProvider = StateProvider<int>((ref) => 0);

final adminFoodMetricsProvider = FutureProvider.autoDispose<FoodMetrics>((ref) {
  ref.watch(adminKpiTickProvider);
  final period = ref.watch(adminPeriodProvider);
  return ref.watch(adminMetricsServiceProvider).food(period);
});

final adminGroceryMetricsProvider =
    FutureProvider.autoDispose<GroceryMetrics>((ref) {
  ref.watch(adminKpiTickProvider);
  final period = ref.watch(adminPeriodProvider);
  return ref.watch(adminMetricsServiceProvider).grocery(period);
});

final adminCombinedMetricsProvider =
    FutureProvider.autoDispose<CombinedMetrics>((ref) {
  ref.watch(adminKpiTickProvider);
  final period = ref.watch(adminPeriodProvider);
  return ref.watch(adminMetricsServiceProvider).combined(period);
});

/// Today's target for one vertical. Always today, whatever period the KPI cards
/// are showing: a target is a property of a day, and pairing today's actual
/// with a year-to-date figure would be meaningless.
final adminDailyTargetProvider =
    FutureProvider.autoDispose.family<DailyTarget?, String>((ref, vertical) {
  ref.watch(adminLiveTickProvider);
  return ref.watch(adminMetricsServiceProvider).dailyTarget(vertical);
});

final adminTargetHistoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, vertical) {
  return ref.watch(adminMetricsServiceProvider).targetHistory(vertical);
});

/// Live ops is on the 15-second tick — it is the panel someone stares at while
/// an order ages, and stale numbers there are the ones that cost money.
final adminLiveOpsProvider =
    FutureProvider.autoDispose<List<LiveOpsRow>>((ref) {
  ref.watch(adminLiveTickProvider);
  return ref.watch(adminMetricsServiceProvider).liveOps();
});

final adminSlaAttributionProvider =
    FutureProvider.autoDispose<List<SlaAttributionRow>>((ref) {
  ref.watch(adminKpiTickProvider);
  final period = ref.watch(adminPeriodProvider);
  return ref.watch(adminMetricsServiceProvider).slaAttribution(period);
});

/// Which leaderboard the user is looking at. Held outside the widget so it
/// survives the periodic rebuilds.
final adminPartnerKindProvider = StateProvider<PartnerKind>(
  (ref) => PartnerKind.restaurant,
);

final adminTopPartnersProvider =
    FutureProvider.autoDispose<List<PartnerRow>>((ref) {
  ref.watch(adminKpiTickProvider);
  final period = ref.watch(adminPeriodProvider);
  final kind = ref.watch(adminPartnerKindProvider);
  return ref.watch(adminMetricsServiceProvider).topPartners(period, kind);
});
