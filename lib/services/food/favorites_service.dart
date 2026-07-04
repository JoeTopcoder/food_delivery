import 'package:supabase_flutter/supabase_flutter.dart';

class FavoritesService {
  final SupabaseClient _client;
  FavoritesService(this._client);

  Future<List<Map<String, dynamic>>> getFavoriteRestaurants(
    String userId,
  ) async {
    final res = await _client
        .from('favorites')
        .select('id, created_at, restaurants(*)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<bool> isFavorite(String userId, String restaurantId) async {
    try {
      final rows = await _client
          .from('favorites')
          .select('id')
          .eq('user_id', userId)
          .eq('restaurant_id', restaurantId)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> toggleFavorite(String userId, String restaurantId) async {
    final rows = await _client
        .from('favorites')
        .select('id')
        .eq('user_id', userId)
        .eq('restaurant_id', restaurantId)
        .limit(1);

    if ((rows as List).isNotEmpty) {
      await _client.from('favorites').delete()
          .eq('user_id', userId)
          .eq('restaurant_id', restaurantId);
    } else {
      await _client.from('favorites').insert({
        'user_id': userId,
        'restaurant_id': restaurantId,
        'is_mock_data': false,
      });
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
