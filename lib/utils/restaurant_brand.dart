import '../models/restaurant_model.dart';

/// Collapses multi-location brands into a single card. Restaurants that share a
/// chain (via [Restaurant.chainId]/[Restaurant.chainName], falling back to the
/// legacy [Restaurant.brand]) — e.g. "KFC" — are represented by ONE entry shown
/// under the chain/brand name; single-location restaurants pass through
/// unchanged. The order is later routed to the closest location server-side
/// (resolve_fulfillment_store).
List<Restaurant> collapseRestaurantsByBrand(List<Restaurant> list) {
  final groups = <String, List<Restaurant>>{};
  final result = <Restaurant>[];
  final order = <String>[]; // preserve first-seen order of brand keys

  for (final r in list) {
    final key = r.brandKey; // chain-preferred grouping key
    if (key != null) {
      if (!groups.containsKey(key)) order.add(key);
      groups.putIfAbsent(key, () => []).add(r);
    } else {
      result.add(r);
    }
  }

  for (final key in order) {
    final locs = groups[key]!;
    // Representative: prefer an open location, then the highest-rated, so the
    // brand card and its menu are stable and available.
    locs.sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      return (b.rating ?? 0).compareTo(a.rating ?? 0);
    });
    // Display under the brand/chain name (menu/id stay the representative's).
    result.add(locs.first.copyWith(name: locs.first.displayBrand));
  }
  return result;
}
