import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

/// Result from the full-text search_menu_items RPC
class MenuSearchResult {
  final String itemId;
  final String itemName;
  final String? itemDescription;
  final double itemPrice;
  final String? itemImageUrl;
  final String? itemCategory;
  final double? itemDiscount;
  final String restaurantId;
  final String restaurantName;
  final String? restaurantImage;
  final double? restaurantRating;
  final String? restaurantCuisine;
  final double rank;

  MenuSearchResult({
    required this.itemId,
    required this.itemName,
    this.itemDescription,
    required this.itemPrice,
    this.itemImageUrl,
    this.itemCategory,
    this.itemDiscount,
    required this.restaurantId,
    required this.restaurantName,
    this.restaurantImage,
    this.restaurantRating,
    this.restaurantCuisine,
    this.rank = 0,
  });

  double get discountedPrice {
    if (itemDiscount != null && itemDiscount! > 0) {
      return itemPrice * (1 - itemDiscount! / 100);
    }
    return itemPrice;
  }

  factory MenuSearchResult.fromJson(Map<String, dynamic> json) {
    return MenuSearchResult(
      itemId: json['item_id'] as String,
      itemName: json['item_name'] as String,
      itemDescription: json['item_description'] as String?,
      itemPrice: (json['item_price'] as num).toDouble(),
      itemImageUrl: json['item_image_url'] as String?,
      itemCategory: json['item_category'] as String?,
      itemDiscount: (json['item_discount'] as num?)?.toDouble(),
      restaurantId: json['restaurant_id'] as String,
      restaurantName: json['restaurant_name'] as String,
      restaurantImage: json['restaurant_image'] as String?,
      restaurantRating: (json['restaurant_rating'] as num?)?.toDouble(),
      restaurantCuisine: json['restaurant_cuisine'] as String?,
      rank: (json['rank'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Recommendation result
class RecommendationResult {
  final String itemId;
  final String itemName;
  final double itemPrice;
  final String? itemImageUrl;
  final String restaurantId;
  final String restaurantName;
  final String? restaurantImage;

  RecommendationResult({
    required this.itemId,
    required this.itemName,
    required this.itemPrice,
    this.itemImageUrl,
    required this.restaurantId,
    required this.restaurantName,
    this.restaurantImage,
  });

  factory RecommendationResult.fromJson(Map<String, dynamic> json) {
    return RecommendationResult(
      itemId: json['item_id'] as String,
      itemName: json['item_name'] as String,
      itemPrice: (json['item_price'] as num).toDouble(),
      itemImageUrl: json['item_image_url'] as String?,
      restaurantId: json['restaurant_id'] as String,
      restaurantName: json['restaurant_name'] as String,
      restaurantImage: json['restaurant_image'] as String?,
    );
  }
}

class SearchService {
  final SupabaseClient _client;
  SearchService(this._client);

  /// Full-text search on menu items using the DB RPC
  Future<List<MenuSearchResult>> searchMenuItems({
    String? query,
    String? cuisine,
    double? maxPrice,
    double? minRating,
    int limit = 50,
  }) async {
    try {
      final params = <String, dynamic>{'p_limit': limit};
      if (query != null && query.trim().isNotEmpty) {
        params['p_query'] = query.trim();
      }
      if (cuisine != null && cuisine.isNotEmpty) {
        params['p_cuisine'] = cuisine;
      }
      if (maxPrice != null) params['p_max_price'] = maxPrice;
      if (minRating != null && minRating > 0) {
        params['p_min_rating'] = minRating;
      }

      final result = await _client.rpc('search_menu_items', params: params);
      return (result as List)
          .map((e) => MenuSearchResult.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error searching menu items: $e');
      return [];
    }
  }

  /// Get personalized recommendations
  Future<List<RecommendationResult>> getRecommendations(
    String userId, {
    int limit = 20,
  }) async {
    try {
      final result = await _client.rpc(
        'get_recommendations',
        params: {'p_user_id': userId, 'p_limit': limit},
      );
      return (result as List)
          .map((e) => RecommendationResult.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error getting recommendations: $e');
      return [];
    }
  }
}
