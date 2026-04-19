import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/refund_model.dart';
import '../models/group_order_model.dart';
import '../models/subscription_model.dart';
import '../models/feedback_model.dart';
import '../services/refund_service.dart';
import '../services/group_order_service.dart';
import '../services/subscription_service.dart';
import '../services/feedback_service.dart';
import '../services/surge_service.dart';
import '../services/eta_service.dart';
import '../services/cuisine_service.dart';
import '../services/delivery_fee_service.dart';
import '../services/app_config_service.dart';
import '../config/app_constants.dart';
import '../utils/app_logger.dart';
import './user_provider.dart';
import './address_provider.dart';
import './auth_provider.dart';

// ── Realtime config version ─────────────────────────────────
/// Incremented whenever `app_config` changes via Supabase Realtime.
/// Any provider that watches this will automatically recalculate.
final configVersionProvider = StateProvider<int>((ref) => 0);

/// Call `ref.read(appConfigRealtimeProvider)` once at startup to begin
/// listening for admin pricing changes in real time.
final appConfigRealtimeProvider = Provider<void>((ref) {
  final client = SupabaseConfig.client;
  final channel = client
      .channel('app_config_realtime')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'app_config',
        callback: (payload) async {
          // Reload all config from DB into AppConstants
          await AppConfigService(client).load();
          // Clear cached delivery fees so new prices take effect
          ref.read(deliveryFeeServiceProvider).clearCache();
          // Bump version so watching providers recalculate
          ref.read(configVersionProvider.notifier).state++;
        },
      )
      .subscribe();
  ref.onDispose(() => client.removeChannel(channel));
});

// ── Service Providers ───────────────────────────────────────
final refundServiceProvider = Provider<RefundService>(
  (ref) => RefundService(SupabaseConfig.client),
);

final groupOrderServiceProvider = Provider<GroupOrderService>(
  (ref) => GroupOrderService(SupabaseConfig.client),
);

final subscriptionServiceProvider = Provider<SubscriptionService>(
  (ref) => SubscriptionService(SupabaseConfig.client),
);

final feedbackServiceProvider = Provider<FeedbackService>(
  (ref) => FeedbackService(SupabaseConfig.client),
);

final surgeServiceProvider = Provider<SurgeService>(
  (ref) => SurgeService(SupabaseConfig.client),
);

final etaServiceProvider = Provider<EtaService>(
  (ref) => EtaService(SupabaseConfig.client),
);

final cuisineServiceProvider = Provider<CuisineService>(
  (ref) => CuisineService(SupabaseConfig.client),
);

final deliveryFeeServiceProvider = Provider<DeliveryFeeService>(
  (ref) => DeliveryFeeService(SupabaseConfig.client),
);

/// Delivery fee for a restaurant → delivery location pair.
/// Family key: `'$restaurantId|$deliveryLat|$deliveryLng|$restLat|$restLng|$restFee'`.
final deliveryFeeProvider = FutureProvider.autoDispose
    .family<DeliveryFeeResult?, String>((ref, key) async {
      // Keep alive for 30s so rapid key rebuilds don't restart from scratch
      final link = ref.keepAlive();
      Future.delayed(const Duration(seconds: 30), () => link.close());

      // Re-run whenever admin pricing changes in real time
      ref.watch(configVersionProvider);
      final parts = key.split('|');
      if (parts.length < 3) return null;
      final restaurantId = parts[0];
      var lat = double.tryParse(parts[1]);
      var lng = double.tryParse(parts[2]);
      var restLat = parts.length > 3 ? double.tryParse(parts[3]) : null;
      var restLng = parts.length > 4 ? double.tryParse(parts[4]) : null;
      var restFee = parts.length > 5 ? double.tryParse(parts[5]) : null;

      // If restaurant coords not in key, await from DB (not valueOrNull)
      if (restLat == null || restLng == null) {
        try {
          final rest = await ref.watch(
            restaurantByIdProvider(restaurantId).future,
          );
          if (rest != null) {
            restLat ??= rest.latitude;
            restLng ??= rest.longitude;
            restFee ??= rest.deliveryFee;
          }
        } catch (_) {
          // DB fetch failed — continue with what we have
        }
      }

      // If delivery coords missing, await user's default address from DB
      if (lat == null || lng == null) {
        final userId = ref.watch(currentUserIdProvider);
        if (userId != null) {
          try {
            final addr = await ref.watch(defaultAddressProvider(userId).future);
            lat ??= addr?.latitude;
            lng ??= addr?.longitude;
          } catch (_) {
            // address fetch failed — continue
          }
        }
      }

      // Need at least delivery coords to calculate
      if (lat == null || lng == null) return null;

      AppLogger.info(
        'deliveryFeeProvider: restLat=$restLat, restLng=$restLng, '
        'baseFee=${AppConstants.deliveryBaseFee}, perKm=${AppConstants.deliveryPerKmFee}, '
        'defaultFee=${AppConstants.defaultDeliveryFee}',
      );
      final result = await ref
          .watch(deliveryFeeServiceProvider)
          .calculate(
            restaurantId: restaurantId,
            deliveryLatitude: lat,
            deliveryLongitude: lng,
            restaurantLatitude: restLat,
            restaurantLongitude: restLng,
            restaurantDeliveryFee: restFee,
          );
      AppLogger.info(
        'deliveryFeeProvider: fee=${result?.deliveryFee}, '
        'dist=${result?.distanceKm}, calc=${result?.calculation}',
      );
      return result;
    });

// ── Data Providers ──────────────────────────────────────────

// Refunds
final userRefundsProvider = FutureProvider.family
    .autoDispose<List<Refund>, String>(
      (ref, userId) => ref.watch(refundServiceProvider).getUserRefunds(userId),
    );

final allRefundsProvider = FutureProvider.autoDispose<List<Refund>>(
  (ref) => ref.watch(refundServiceProvider).getAllRefunds(),
);

// Disputes
final userDisputesProvider = FutureProvider.family
    .autoDispose<List<Dispute>, String>(
      (ref, userId) => ref.watch(refundServiceProvider).getUserDisputes(userId),
    );

final allDisputesProvider = FutureProvider.autoDispose<List<Dispute>>(
  (ref) => ref.watch(refundServiceProvider).getAllDisputes(),
);

// Group Orders
final userGroupOrdersProvider = FutureProvider.family
    .autoDispose<List<GroupOrder>, String>(
      (ref, userId) =>
          ref.watch(groupOrderServiceProvider).getUserGroupOrders(userId),
    );

// Subscriptions
final availablePlansProvider = FutureProvider.autoDispose<List<MealPlan>>(
  (ref) => ref.watch(subscriptionServiceProvider).getAvailablePlans(),
);

/// All meal plans (admin) — real-time via Supabase Realtime.
final allMealPlansProvider = FutureProvider.autoDispose<List<MealPlan>>((ref) {
  final channel = Supabase.instance.client.realtime.channel(
    'meal_plans_all_${DateTime.now().microsecondsSinceEpoch}',
  );
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'meal_plans',
        callback: (_) {
          ref.invalidateSelf();
          // Also refresh the customer-facing plans so they see changes instantly
          ref.invalidate(availablePlansProvider);
        },
      )
      .subscribe();
  ref.onDispose(() => Supabase.instance.client.realtime.removeChannel(channel));
  return ref.watch(subscriptionServiceProvider).getAllPlans();
});

final userSubscriptionsProvider = FutureProvider.family
    .autoDispose<List<UserSubscription>, String>(
      (ref, userId) =>
          ref.watch(subscriptionServiceProvider).getUserSubscriptions(userId),
    );

/// Active delivery subscription (Uber One-style) for the current user.
final activeSubscriptionProvider =
    FutureProvider.autoDispose<UserSubscription?>((ref) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) return Future.value(null);
      return ref
          .watch(subscriptionServiceProvider)
          .getActiveDeliverySubscription(userId);
    });

// Feedback
final userFeedbackProvider = FutureProvider.family
    .autoDispose<List<AppFeedback>, String>(
      (ref, userId) =>
          ref.watch(feedbackServiceProvider).getUserFeedback(userId),
    );

final allFeedbackProvider = FutureProvider.autoDispose<List<AppFeedback>>(
  (ref) => ref.watch(feedbackServiceProvider).getAllFeedback(),
);

// Cuisine Categories
final cuisineCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(cuisineServiceProvider).getCategories(),
    );

// Surge Zones (admin) — real-time
final allSurgeZonesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      final channel = Supabase.instance.client.realtime.channel(
        'surge_zones_all_${DateTime.now().microsecondsSinceEpoch}',
      );
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'surge_zones',
            callback: (_) => ref.invalidateSelf(),
          )
          .subscribe();
      ref.onDispose(
        () => Supabase.instance.client.realtime.removeChannel(channel),
      );
      return ref.watch(surgeServiceProvider).getAllSurgeZones();
    });

/// Surge multiplier for a delivery location. Pass `'$lat,$lng'` as the family key.
/// Refreshes in real-time when surge_zones table changes.
final surgeMultiplierProvider = FutureProvider.autoDispose.family<double, String>((
  ref,
  latLng,
) async {
  final parts = latLng.split(',');
  if (parts.length != 2) return 1.0;
  final lat = double.tryParse(parts[0]);
  final lng = double.tryParse(parts[1]);
  if (lat == null || lng == null || (lat == 0 && lng == 0)) return 1.0;

  // Real-time: re-fetch when any surge zone is created/updated/deleted
  try {
    final channel = Supabase.instance.client.realtime.channel(
      'surge_mult_${latLng.hashCode.abs()}_${DateTime.now().microsecondsSinceEpoch}',
    );
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'surge_zones',
          callback: (_) => ref.invalidateSelf(),
        )
        .subscribe();
    ref.onDispose(
      () => Supabase.instance.client.realtime.removeChannel(channel),
    );
  } catch (_) {
    // Realtime subscription failed — still proceed with the DB query.
  }

  return ref
      .watch(surgeServiceProvider)
      .getSurgeMultiplier(latitude: lat, longitude: lng);
});
