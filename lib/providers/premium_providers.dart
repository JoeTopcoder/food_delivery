import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/referral_service.dart';
import '../services/favorites_service.dart';

// ==================== REFERRAL PROVIDERS ====================

final referralServiceProvider = Provider<ReferralService>((ref) {
  return ReferralService(Supabase.instance.client);
});

final referralCodeProvider = FutureProvider.family<String?, String>((
  ref,
  userId,
) async {
  final service = ref.watch(referralServiceProvider);
  return service.getReferralCode(userId);
});

final referralStatsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, userId) async {
      final service = ref.watch(referralServiceProvider);
      return service.getReferralStats(userId);
    });

final referredUsersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      userId,
    ) async {
      final service = ref.watch(referralServiceProvider);
      return service.getReferredUsers(userId);
    });

// ==================== FAVORITES PROVIDERS ====================

final favoritesServiceProvider = Provider<FavoritesService>((ref) {
  return FavoritesService(Supabase.instance.client);
});

final favoriteRestaurantsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      userId,
    ) async {
      final service = ref.watch(favoritesServiceProvider);
      return service.getFavoriteRestaurants(userId);
    });

final isFavoriteProvider =
    FutureProvider.family<bool, (String userId, String restaurantId)>((
      ref,
      params,
    ) async {
      final service = ref.watch(favoritesServiceProvider);
      return service.isFavorite(params.$1, params.$2);
    });

// ==================== DRIVER LEADERBOARD ====================

final driverLeaderboardProvider =
    StreamProvider<({List<Map<String, dynamic>> drivers, int totalDrivers})>((
      ref,
    ) {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;

      Future<({List<Map<String, dynamic>> drivers, int totalDrivers})>
      fetchLeaderboard() async {
        final resFuture = client.from('driver_leaderboard').select().limit(50);
        final countFuture = client
            .from('driver_leaderboard')
            .select()
            .count(CountOption.exact);

        final res = await resFuture;
        final countRes = await countFuture;
        final totalDrivers = countRes.count;

        final drivers = List<Map<String, dynamic>>.from(res as List);

        if (userId != null && !drivers.any((d) => d['user_id'] == userId)) {
          final myRes = await client
              .from('driver_leaderboard')
              .select()
              .eq('user_id', userId)
              .limit(1);
          final myList = List<Map<String, dynamic>>.from(myRes as List);
          if (myList.isNotEmpty) {
            drivers.add(myList.first);
          }
        }

        return (drivers: drivers, totalDrivers: totalDrivers);
      }

      // Listen to changes on the drivers table and re-fetch leaderboard
      final stream = client
          .from('drivers')
          .stream(primaryKey: ['id'])
          .map((_) => fetchLeaderboard());

      return stream.asyncMap((future) => future);
    });
