import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/menu_model.dart';
import '../utils/app_logger.dart';

/// One menu item returned by the `menu-by-category` edge function, with a
/// snapshot of its restaurant attached so we can render a meaningful card.
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

  factory MenuItemWithRestaurant.fromJson(Map<String, dynamic> json) {
    final restaurantJson = json['restaurant'] as Map<String, dynamic>? ?? {};
    final cleaned = Map<String, dynamic>.from(json)..remove('restaurant');
    return MenuItemWithRestaurant(
      item: MenuItem.fromJson(cleaned),
      restaurantId: restaurantJson['id'] as String?,
      restaurantName: restaurantJson['name'] as String?,
      restaurantImageUrl: restaurantJson['image_url'] as String?,
      restaurantRating: (restaurantJson['rating'] as num?)?.toDouble(),
      restaurantDeliveryFee: (restaurantJson['delivery_fee'] as num?)
          ?.toDouble(),
      restaurantEstimatedDeliveryTime:
          (restaurantJson['estimated_delivery_time'] as num?)?.toInt(),
      restaurantIsCurrentlyOpen: restaurantJson['is_currently_open'] == true,
    );
  }
}

class MenuCategoryService {
  final SupabaseClient _client;
  MenuCategoryService(this._client);

  /// Calls the `menu-by-category` edge function to fetch every meal across
  /// open restaurants in [category].
  Future<List<MenuItemWithRestaurant>> getMealsByCategory(
    String category, {
    int limit = 100,
  }) async {
    try {
      AppLogger.info('Fetching meals for category=$category via edge function');
      final response = await _client.functions.invoke(
        'menu-by-category',
        body: {'category': category, 'limit': limit},
      );

      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      if (data['error'] != null) {
        throw Exception(data['error']);
      }

      final raw = (data['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      return raw.map(MenuItemWithRestaurant.fromJson).toList();
    } catch (e) {
      AppLogger.error('menu-by-category edge function error: $e');
      rethrow;
    }
  }
}
