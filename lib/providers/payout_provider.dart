import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';
import '../services/payout_service.dart';

final payoutServiceProvider = Provider<PayoutService>((ref) {
  return PayoutService(SupabaseConfig.client);
});

final myPayoutsProvider = FutureProvider.family
    .autoDispose<List<PayoutRequest>, String>((ref, userId) async {
      final service = ref.watch(payoutServiceProvider);
      return service.getMyPayouts(userId);
    });

final allPayoutsProvider = FutureProvider.autoDispose<List<PayoutRequest>>((
  ref,
) async {
  final service = ref.watch(payoutServiceProvider);
  return service.getAllPayouts();
});

final restaurantEarningsProvider = FutureProvider.family
    .autoDispose<double, String>((ref, restaurantId) async {
      final service = ref.watch(payoutServiceProvider);
      return service.getRestaurantEarnings(restaurantId);
    });

final driverTotalPaidOutProvider = FutureProvider.family
    .autoDispose<double, String>((ref, driverId) async {
      final service = ref.watch(payoutServiceProvider);
      return service.getTotalPaidOut(driverId, 'driver');
    });

final restaurantTotalPaidOutProvider = FutureProvider.family
    .autoDispose<double, String>((ref, restaurantId) async {
      final service = ref.watch(payoutServiceProvider);
      return service.getTotalPaidOut(restaurantId, 'restaurant');
    });
