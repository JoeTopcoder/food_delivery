import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';

/// A restaurant surfaced in a HotBite Picks rail (Most Ordered / Top Rated /
/// curated). Lightweight — the card only needs display fields; tapping resolves
/// the full Restaurant via the existing restaurant service.
class PickRestaurant {
  final String id;
  final String name;
  final String? imageUrl;
  final String? cuisineType;
  final double rating;
  final int reviewCount;
  final int? orderCount;

  const PickRestaurant({
    required this.id,
    required this.name,
    this.imageUrl,
    this.cuisineType,
    required this.rating,
    required this.reviewCount,
    this.orderCount,
  });

  factory PickRestaurant.fromRow(Map<String, dynamic> r) => PickRestaurant(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? 'Restaurant',
        imageUrl: r['image_url'] as String?,
        cuisineType: (r['cuisine_type'] ?? r['subtitle']) as String?,
        rating: ((r['rating'] as num?) ?? 0).toDouble(),
        reviewCount: ((r['review_count'] as num?) ?? 0).toInt(),
        orderCount: (r['order_count'] as num?)?.toInt(),
      );
}

/// A discounted menu item for the Hot Deals rail. All prices come from the DB.
class PickDeal {
  final String id;
  final String restaurantId;
  final String name;
  final String? imageUrl;
  final String? restaurantName;
  final double price;
  final double salePrice;
  final double discount;

  const PickDeal({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.imageUrl,
    this.restaurantName,
    required this.price,
    required this.salePrice,
    required this.discount,
  });

  factory PickDeal.fromRow(Map<String, dynamic> r) => PickDeal(
        id: r['id'] as String,
        restaurantId: r['restaurant_id'] as String,
        name: (r['name'] as String?) ?? 'Item',
        imageUrl: r['image_url'] as String?,
        restaurantName: r['restaurant_name'] as String?,
        price: ((r['price'] as num?) ?? 0).toDouble(),
        salePrice: ((r['sale_price'] as num?) ?? 0).toDouble(),
        discount: ((r['discount'] as num?) ?? 0).toDouble(),
      );
}

Future<List<Map<String, dynamic>>> _rpc(
    String fn, Map<String, dynamic> params) async {
  final res = await SupabaseConfig.client.rpc(fn, params: params);
  return ((res as List?) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

/// Admin-curated featured restaurants (section 'featured'). Availability-guarded
/// server-side. Cached until invalidated (curated data changes rarely).
final curatedPicksProvider =
    FutureProvider.autoDispose<List<PickRestaurant>>((ref) async {
  ref.keepAlive();
  try {
    final rows = await _rpc('get_hotbite_picks', {'p_section': 'featured'});
    return rows
        .where((r) => r['entity_type'] == 'restaurant' ||
            r['entity_type'] == 'grocery_store')
        .map(PickRestaurant.fromRow)
        .toList();
  } catch (_) {
    return const [];
  }
});

/// Most-ordered restaurants from real completed orders (last 30 days).
final mostOrderedProvider =
    FutureProvider.autoDispose<List<PickRestaurant>>((ref) async {
  ref.keepAlive();
  try {
    final rows = await _rpc(
        'get_most_ordered_restaurants', {'p_days': 30, 'p_limit': 10});
    return rows.map(PickRestaurant.fromRow).toList();
  } catch (_) {
    return const [];
  }
});

/// Top-rated restaurants with a minimum-review threshold so a single review
/// can't crown a restaurant.
final topRatedPicksProvider =
    FutureProvider.autoDispose<List<PickRestaurant>>((ref) async {
  ref.keepAlive();
  try {
    final rows = await _rpc(
        'get_top_rated_restaurants', {'p_min_reviews': 3, 'p_limit': 10});
    return rows.map(PickRestaurant.fromRow).toList();
  } catch (_) {
    return const [];
  }
});

/// Real active discounts from the menus table (food).
final hotDealsProvider =
    FutureProvider.autoDispose<List<PickDeal>>((ref) async {
  try {
    final rows =
        await _rpc('get_hot_deals', {'p_limit': 12, 'p_grocery': false});
    return rows.map(PickDeal.fromRow).toList();
  } catch (_) {
    return const [];
  }
});
