import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/social/referral_service.dart';
import '../services/food/favorites_service.dart';

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

final favoriteLaundryProvidersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, userId) async {
  final rows = await Supabase.instance.client
      .from('user_favorite_laundry_providers')
      .select('provider_id, laundry_providers(id, business_name, rating, address, logo_url, banner_url)')
      .eq('user_id', userId)
      .order('created_at', ascending: false);
  return (rows as List).cast<Map<String, dynamic>>();
});

final favoriteCarProvidersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, userId) async {
  final rows = await Supabase.instance.client
      .from('user_favorite_car_providers')
      .select('provider_id, car_service_providers(id, business_name, rating, base_location_address, profile_image_url)')
      .eq('user_id', userId)
      .order('created_at', ascending: false);
  return (rows as List).cast<Map<String, dynamic>>();
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
