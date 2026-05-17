import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_logger.dart';

class FavoritesService {
  final SupabaseClient _client;
  FavoritesService(this._client);

  Future<List<Map<String, dynamic>>> getFavoriteRestaurants(
    String userId,
  ) async {
    try {
      final res = await _client
          .from('favorites')
          .select('id, created_at, restaurants(*)')
          .eq('user_id', userId)
          .not('restaurant_id', 'is', null)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      AppLogger.error('Error getting favorite restaurants: $e');
      return [];
    }
  }

  Future<bool> isFavorite(String userId, String restaurantId) async {
    try {
      final res = await _client
          .from('favorites')
          .select('id')
          .eq('user_id', userId)
          .eq('restaurant_id', restaurantId)
          .maybeSingle();
      return res != null;
    } catch (e) {
      return false;
    }
  }

  Future<void> toggleFavorite(String userId, String restaurantId) async {
    try {
      final existing = await _client
          .from('favorites')
          .select('id')
          .eq('user_id', userId)
          .eq('restaurant_id', restaurantId)
          .maybeSingle();

      if (existing != null) {
        await _client.from('favorites').delete().eq('id', existing['id']);
      } else {
        await _client.from('favorites').insert({
          'user_id': userId,
          'restaurant_id': restaurantId,
        });
      }
    } catch (e) {
      AppLogger.error('Error toggling favorite: $e');
      rethrow;
    }
  }

  Future<int> getFavoriteCount(String userId) async {
    try {
      final res = await _client
          .from('favorites')
          .select('id')
          .eq('user_id', userId)
          .count();
      return res.count;
    } catch (e) {
      return 0;
    }
  }
}
