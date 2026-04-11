import 'package:flutter_riverpod/flutter_riverpod.dart';
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

final userSubscriptionsProvider = FutureProvider.family
    .autoDispose<List<UserSubscription>, String>(
      (ref, userId) =>
          ref.watch(subscriptionServiceProvider).getUserSubscriptions(userId),
    );

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

// Surge Zones (admin)
final allSurgeZonesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(surgeServiceProvider).getAllSurgeZones(),
    );
