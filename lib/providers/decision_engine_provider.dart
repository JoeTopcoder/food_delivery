import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/ai/decision_engine_service.dart';

// ── Service ────────────────────────────────────────────────────────────────

final decisionEngineServiceProvider = Provider<DecisionEngineService>((ref) {
  return DecisionEngineService(Supabase.instance.client);
});

// ── Per-user AI promo (customer-facing) ───────────────────────────────────
// family by userId so it's scoped and cache-invalidatable.

final userPromoProvider = FutureProvider.autoDispose.family<UserPromo?, String>(
  (ref, userId) async {
    return ref.watch(decisionEngineServiceProvider).getUserPromo(userId);
  },
);

// ── Admin panel data ───────────────────────────────────────────────────────

final segmentDistributionProvider =
    FutureProvider.autoDispose<List<SegmentRow>>((ref) async {
      return ref.watch(decisionEngineServiceProvider).getSegmentDistribution();
    });

final promotionStatsProvider = FutureProvider.autoDispose<List<PromoStat>>((
  ref,
) async {
  return ref.watch(decisionEngineServiceProvider).getPromotionStats();
});

final promotionConfigsProvider =
    FutureProvider.autoDispose<List<PromotionConfig>>((ref) async {
      return ref.watch(decisionEngineServiceProvider).getPromotionConfigs();
    });
