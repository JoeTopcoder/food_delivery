import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/supabase_config.dart';
import '../../models/ordering/order_model.dart';
import '../../models/catalog/restaurant_model.dart';
import '../../services/grocery/grocery_service.dart';
import '../auth_user/auth_provider.dart';
import '../auth_user/user_provider.dart';

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
/// One authoritative "Order Again" row from the server: which order to re-order,
/// its store, and how often ordered. Sourced from the `get_order_again` RPC,
/// which enforces the rules in the database — caller-scoped, completed-only, and
/// **grocery stores excluded** — so grocery can never appear on the food home
/// regardless of the client.
typedef _OrderAgainRow = ({
  String orderId,
  String restaurantId,
  int times,
  DateTime at,
});

final _orderAgainRpcProvider =
    FutureProvider.autoDispose<List<_OrderAgainRow>>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];
  // Re-run whenever the customer's orders change (new delivery completes).
  ref.watch(userOrdersProvider(uid));
  final rows = await SupabaseConfig.client
      .rpc('get_order_again', params: {'p_limit': 8});
  return (rows as List).map((r) {
    final m = Map<String, dynamic>.from(r as Map);
    return (
      orderId: m['order_id'] as String,
      restaurantId: m['restaurant_id'] as String,
      times: (m['times_ordered'] as num).toInt(),
      at: DateTime.parse(m['last_ordered_at'] as String),
    );
  }).toList();
});

final orderAgainProvider =
    Provider.autoDispose<List<OrderAgainEntry>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];

  // The server decides which entries belong (grocery already excluded there).
  final rows = ref.watch(_orderAgainRpcProvider).valueOrNull ?? const [];
  if (rows.isEmpty) return const [];

  // Resolve each allowed order's full detail from the loaded history so the card
  // can show its items and re-order it. Orders not in the loaded page are
  // skipped rather than guessed.
  final orders = ref.watch(userOrdersProvider(uid)).valueOrNull ?? const <Order>[];
  final byId = {for (final o in orders) o.id: o};

  final entries = <OrderAgainEntry>[];
  for (final row in rows) {
    final order = byId[row.orderId];
    if (order == null || !_reorderableStatuses.contains(order.status)) continue;
    entries.add(OrderAgainEntry(
      restaurantId: row.restaurantId,
      order: order,
      timesOrdered: row.times,
    ));
  }
  return entries;
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
