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

// ── User Intelligence Profile ──────────────────────────────────

final userIntelligenceProvider =
    FutureProvider.autoDispose<UserIntelligenceProfile?>((ref) async {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) return null;
      return ref.watch(recommendationServiceProvider).getProfile(userId);
    });

// ── Active Coupons ─────────────────────────────────────────────

final activeCouponsProvider = FutureProvider.autoDispose<List<SmartCoupon>>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];
  return ref.watch(recommendationServiceProvider).getActiveCoupons(userId);
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
