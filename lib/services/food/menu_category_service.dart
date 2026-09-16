import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_constants.dart';
import '../../models/menu_model.dart';
import '../../utils/app_logger.dart';
import '../driver/delivery_fee_service.dart';

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
  final double? restaurantLatitude;
  final double? restaurantLongitude;

  MenuItemWithRestaurant({
    required this.item,
    this.restaurantId,
    this.restaurantName,
    this.restaurantImageUrl,
    this.restaurantRating,
    this.restaurantDeliveryFee,
    this.restaurantEstimatedDeliveryTime,
    this.restaurantIsCurrentlyOpen = false,
    this.restaurantLatitude,
    this.restaurantLongitude,
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
      restaurantLatitude: (r['latitude'] as num?)?.toDouble(),
      restaurantLongitude: (r['longitude'] as num?)?.toDouble(),
    );
  }
}

class MenuCategoryService {
  final SupabaseClient _client;

  /// Customer origin used to hide items from restaurants outside the delivery
  /// zone. Null when the customer's location is unknown.
  final double? originLat;
  final double? originLng;

  MenuCategoryService(this._client, {this.originLat, this.originLng});

  /// Fetches every available menu item in [category] across open restaurants
  /// using a direct DB query with a join — no edge function required.
  ///
  /// Items from restaurants outside the customer's delivery zone
  /// ([AppConstants.browseMaxKm] from their address) are dropped, so browse-by-
  /// category never shows food that can't actually be delivered. A restaurant
  /// with no coordinates cannot be measured and is kept (mirrors the store
  /// listing's behaviour rather than silently hiding an un-geocoded store).
  Future<List<MenuItemWithRestaurant>> getMealsByCategory(
    String category, {
    int limit = 100,
  }) async {
    try {
      AppLogger.info('Fetching meals for category=$category');
      final rows = await _client
          .from('menus')
          .select(
            '*, restaurants(id, name, image_url, rating, delivery_fee, '
            'estimated_delivery_time, is_open, latitude, longitude)',
          )
          .ilike('category', category)
          .eq('is_available', true)
          .order('rating', ascending: false)
          .limit(limit);

      final meals = (rows as List)
          .map((r) => MenuItemWithRestaurant.fromRow(r as Map<String, dynamic>))
          .toList();
      return _inDeliveryZone(meals);
    } catch (e) {
      AppLogger.error('getMealsByCategory error: $e');
      rethrow;
    }
  }

  /// Keep only meals whose restaurant is within the browse radius of the
  /// customer's location. When we don't know where the customer is, measure
  /// from the default origin rather than showing the whole (multi-region)
  /// catalogue — same rule the restaurant listing uses.
  List<MenuItemWithRestaurant> _inDeliveryZone(
    List<MenuItemWithRestaurant> meals,
  ) {
    final maxKm = AppConstants.browseMaxKm;
    if (maxKm <= 0) return meals;
    final lat = originLat ?? AppConstants.defaultOriginLat;
    final lng = originLng ?? AppConstants.defaultOriginLng;

    final near = meals.where((m) {
      final rLat = m.restaurantLatitude;
      final rLng = m.restaurantLongitude;
      if (rLat == null || rLng == null) {
        AppLogger.warning(
          'Restaurant "${m.restaurantName}" has no coordinates — cannot be '
          'distance-filtered in browse-by-category, showing it anyway',
        );
        return true;
      }
      return DeliveryFeeService.haversineKm(lat, lng, rLat, rLng) <= maxKm;
    }).toList();

    if (near.length != meals.length) {
      AppLogger.info(
        'browse-by-category: hid ${meals.length - near.length} of '
        '${meals.length} item(s) beyond ${maxKm.toStringAsFixed(0)}km',
      );
    }
    return near;
  }
}
