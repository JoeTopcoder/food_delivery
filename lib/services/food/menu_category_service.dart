import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/menu_model.dart';
import '../../utils/app_logger.dart';

/// One menu item with a snapshot of its restaurant for rendering a card.
class MenuItemWithRestaurant {
  final MenuItem item;
  final String? restaurantId;
  final String? restaurantName;
  final String? restaurantImageUrl;
  final double? restaurantRating;
  final double? restaurantDeliveryFee;
  final int? restaurantEstimatedDeliveryTime;
  final bool restaurantIsCurrentlyOpen;

  MenuItemWithRestaurant({
    required this.item,
    this.restaurantId,
    this.restaurantName,
    this.restaurantImageUrl,
    this.restaurantRating,
    this.restaurantDeliveryFee,
    this.restaurantEstimatedDeliveryTime,
    this.restaurantIsCurrentlyOpen = false,
  });

  /// Builds from a direct Supabase join row where the restaurant data is
  /// nested under the key "restaurants" (plural, matching the table name).
  factory MenuItemWithRestaurant.fromRow(Map<String, dynamic> row) {
    // Supabase join nests the related table under its name ("restaurants").
    final r = row['restaurants'] as Map<String, dynamic>? ?? {};
    // Strip the nested map before parsing the menu item.
    final itemMap = Map<String, dynamic>.from(row)..remove('restaurants');
    return MenuItemWithRestaurant(
      item: MenuItem.fromJson(itemMap),
      restaurantId: r['id'] as String?,
      restaurantName: r['name'] as String?,
      restaurantImageUrl: r['image_url'] as String?,
      restaurantRating: (r['rating'] as num?)?.toDouble(),
      restaurantDeliveryFee: (r['delivery_fee'] as num?)?.toDouble(),
      restaurantEstimatedDeliveryTime:
          (r['estimated_delivery_time'] as num?)?.toInt(),
      restaurantIsCurrentlyOpen: r['is_open'] == true,
    );
  }
}

class MenuCategoryService {
  final SupabaseClient _client;
  MenuCategoryService(this._client);

  /// Fetches every available menu item in [category] across open restaurants
  /// using a direct DB query with a join — no edge function required.
  Future<List<MenuItemWithRestaurant>> getMealsByCategory(
    String category, {
    int limit = 100,
  }) async {
    try {
      AppLogger.info('Fetching meals for category=$category');
      final rows = await _client
          .from('menus')
          .select(
            '*, restaurants(id, name, image_url, rating, delivery_fee, estimated_delivery_time, is_open)',
          )
          .ilike('category', category)
          .eq('is_available', true)
          .order('rating', ascending: false)
          .limit(limit);

      return (rows as List)
          .map((r) => MenuItemWithRestaurant.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('getMealsByCategory error: $e');
      rethrow;
    }
  }
}
