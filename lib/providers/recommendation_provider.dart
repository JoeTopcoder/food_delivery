import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';
import '../models/recommendation_model.dart';
import '../models/user_intelligence_model.dart';
import '../services/behavior_tracking_service.dart';
import '../services/recommendation_service.dart';
import 'auth_provider.dart';

// ── Service Providers ──────────────────────────────────────────

final behaviorTrackingProvider = Provider<BehaviorTrackingService>((ref) {
  return BehaviorTrackingService(SupabaseConfig.client);
});

final recommendationServiceProvider = Provider<RecommendationService>((ref) {
  return RecommendationService(SupabaseConfig.client);
});

// ── Brain Engine Response (main data for smart home screen) ────

final brainEngineProvider = FutureProvider.autoDispose<BrainEngineResponse>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const BrainEngineResponse();

  final service = ref.watch(recommendationServiceProvider);
  // Track app open event
  ref.read(behaviorTrackingProvider).trackAppOpen(userId);

  return service.runBrainEngine(userId: userId);
});

/// Overload that accepts explicit coordinates (from location provider).
final brainEngineWithLocationProvider = FutureProvider.autoDispose
    .family<BrainEngineResponse, ({double? lat, double? lng})>((
      ref,
      coords,
    ) async {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) return const BrainEngineResponse();

      final service = ref.watch(recommendationServiceProvider);
      return service.runBrainEngine(
        userId: userId,
        latitude: coords.lat,
        longitude: coords.lng,
      );
    });

// ── Grocery Brain Engine ───────────────────────────────────────

final groceryBrainEngineProvider =
    FutureProvider.autoDispose<BrainEngineResponse>((ref) async {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) return const BrainEngineResponse();

      final service = ref.watch(recommendationServiceProvider);
      ref.read(behaviorTrackingProvider).trackAppOpen(userId);

      return service.runGroceryBrainEngine(userId: userId);
    });

// ── User Intelligence Profile ──────────────────────────────────

final userIntelligenceProvider =
    FutureProvider.autoDispose<UserIntelligenceProfile?>((ref) async {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) return null;
      return ref.watch(recommendationServiceProvider).getProfile(userId);
    });

// ── Active Coupons (real-time) ─────────────────────────────────
//
// Subscribes to `user_coupons` for the current user via Supabase realtime
// so banners (apology, AI offers) update instantly when a coupon is issued
// or marked is_used by the order trigger.

final activeCouponsProvider = StreamProvider.autoDispose<List<SmartCoupon>>((
  ref,
) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(<SmartCoupon>[]);

  final client = SupabaseConfig.client;
  return client
      .from('user_coupons')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .map((rows) {
        final now = DateTime.now().toUtc();
        return rows
            .where((r) {
              if (r['is_used'] == true) return false;
              final exp = r['expires_at'];
              if (exp is String) {
                final dt = DateTime.tryParse(exp);
                if (dt != null && dt.toUtc().isBefore(now)) return false;
              }
              return true;
            })
            .map(
              (r) => SmartCoupon(
                id: r['id'] as String?,
                code: r['code'] as String? ?? '',
                discountPercent: (r['discount_percent'] as num?)?.toInt() ?? 0,
                minOrder: (r['min_order'] as num?)?.toDouble() ?? 0,
                reason: r['reason'] as String? ?? '',
              ),
            )
            .toList();
      });
});

// ── Real-Time Adaptation State ─────────────────────────────────

/// Local state that tracks recent user interactions within the current session
/// and boosts certain categories/cuisines in real-time.
class RealtimeBoostNotifier extends StateNotifier<Map<String, int>> {
  RealtimeBoostNotifier() : super({});

  /// Record a cuisine/category tap — the more taps, the higher the boost.
  void recordInteraction(String key) {
    final current = state[key] ?? 0;
    state = {...state, key: current + 1};
  }

  /// Get boost multiplier for a key (e.g., "Pizza").
  /// Returns 1.0 (no boost) to 1.5 (max boost after 5+ taps).
  double boostFor(String key) {
    final taps = state[key] ?? 0;
    if (taps == 0) return 1.0;
    if (taps >= 5) return 1.5;
    return 1.0 + (taps * 0.1);
  }

  void reset() => state = {};
}

final realtimeBoostProvider =
    StateNotifierProvider<RealtimeBoostNotifier, Map<String, int>>((ref) {
      return RealtimeBoostNotifier();
    });
