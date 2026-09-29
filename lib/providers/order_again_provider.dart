import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';
import '../models/order_model.dart';
import '../models/restaurant_model.dart';
import '../services/grocery_service.dart';
import 'auth_provider.dart';
import 'user_provider.dart';

/// One "Order Again" entry — a restaurant/store the customer has ordered from
/// before, with their most recent reorderable order and how often they've used
/// it. Derived purely from real completed order history; nothing is inferred.
class OrderAgainEntry {
  final String restaurantId;

  /// The most recent reorderable order from this restaurant — the one a tap
  /// re-orders. Live availability/price is resolved at reorder time.
  final Order order;

  /// How many reorderable orders the customer has from this restaurant. Drives
  /// the "frequently ordered" ranking.
  final int timesOrdered;

  const OrderAgainEntry({
    required this.restaurantId,
    required this.order,
    required this.timesOrdered,
  });

  /// A short summary of the order for the card: the single item's name, or a
  /// count when the order had several distinct items.
  String get summary {
    final distinct =
        order.items.map((i) => i.menuItemId).toSet().length;
    if (order.items.isEmpty) return 'Previous order';
    if (distinct == 1) return order.items.first.itemName;
    final total = order.items.fold<int>(0, (s, i) => s + i.quantity);
    return '$total items';
  }
}

/// Statuses that represent a genuinely completed order and may be re-ordered.
/// Cancelled / failed / in-progress orders are intentionally excluded.
const _reorderableStatuses = {'delivered', 'completed'};

/// The customer's "Order Again" list, derived from their own order history
/// (RLS already scopes [userOrdersProvider] to `user_id = auth.uid()`).
///
/// Ranking: most frequently ordered first, then most recent. One entry per
/// restaurant (its latest reorderable order). Capped so the home screen never
/// walks the customer's entire lifetime history.
final orderAgainProvider =
    Provider.autoDispose<List<OrderAgainEntry>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];

  final ordersAsync = ref.watch(userOrdersProvider(uid));
  final orders = ordersAsync.valueOrNull ?? const <Order>[];

  final reorderable = orders
      .where((o) => _reorderableStatuses.contains(o.status))
      .toList()
    ..sort((a, b) => b.orderedAt.compareTo(a.orderedAt)); // most recent first

  // Group by restaurant: keep the most recent order (first seen) + a count.
  final byRestaurant = <String, ({Order order, int count})>{};
  for (final o in reorderable) {
    final existing = byRestaurant[o.restaurantId];
    if (existing == null) {
      byRestaurant[o.restaurantId] = (order: o, count: 1);
    } else {
      byRestaurant[o.restaurantId] =
          (order: existing.order, count: existing.count + 1);
    }
  }

  final entries = byRestaurant.entries
      .map((e) => OrderAgainEntry(
            restaurantId: e.key,
            order: e.value.order,
            timesOrdered: e.value.count,
          ))
      .toList()
    ..sort((a, b) {
      final byFreq = b.timesOrdered.compareTo(a.timesOrdered);
      if (byFreq != 0) return byFreq;
      return b.order.orderedAt.compareTo(a.order.orderedAt);
    });

  return entries.take(8).toList();
});

/// Resolves a restaurant/store for an Order Again card. Grocery partners are
/// returned masked (customer-facing brand), matching the rest of the app.
/// Cached per id by Riverpod so the rail resolves each store once.
final orderAgainStoreProvider =
    FutureProvider.autoDispose.family<Restaurant?, String>((ref, id) async {
  final row = await SupabaseConfig.client
      .from('restaurants')
      .select()
      .eq('id', id)
      .maybeSingle();
  if (row == null) return null;
  // Mask grocery partners so the customer sees the HotBite grocery brand, not
  // the supplier — consistent with the rest of the app.
  if (row['store_type'] == 'grocery') {
    return GroceryService.maskGroceryStore(row);
  }
  return Restaurant.fromJson(row);
});
