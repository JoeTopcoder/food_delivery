import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/analytics_service.dart';

// ── Service provider ───────────────────────────────────────────────────────

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService(Supabase.instance.client);
});

// ── Data providers ─────────────────────────────────────────────────────────

final analyticsSummaryProvider = FutureProvider.autoDispose<AnalyticsSummary>((
  ref,
) async {
  return ref.watch(analyticsServiceProvider).getSummary();
});

final dauTrendProvider = FutureProvider.autoDispose
    .family<List<DauDataPoint>, int>((ref, days) async {
      return ref.watch(analyticsServiceProvider).getDauTrend(days: days);
    });

final retentionProvider = FutureProvider.autoDispose
    .family<List<RetentionPoint>, int>((ref, dayN) async {
      return ref.watch(analyticsServiceProvider).getRetention(dayN: dayN);
    });

final topRestaurantsProvider = FutureProvider.autoDispose<List<TopRestaurant>>((
  ref,
) async {
  return ref.watch(analyticsServiceProvider).getTopRestaurants();
});
