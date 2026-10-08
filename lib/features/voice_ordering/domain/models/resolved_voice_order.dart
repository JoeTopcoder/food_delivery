import '../../../../models/catalog/menu_model.dart';
import '../../../../models/catalog/restaurant_model.dart';

/// One real menu item resolved from a [ParsedVoiceOrderItem] — always a
/// real [MenuItem] re-fetched from the database, with real [MenuItemSide]/
/// [OptionChoice] objects for whatever spoken modifiers matched. Price is
/// never taken from the voice layer — it's read directly off [menuItem].
class MatchedVoiceOrderItem {
  const MatchedVoiceOrderItem({
    required this.menuItem,
    required this.quantity,
    this.matchedSides = const [],
    this.matchedOptions = const {},
    this.notes,
  });

  final MenuItem menuItem;
  final int quantity;
  final List<MenuItemSide> matchedSides;

  /// Keyed by [OptionGroup.id].
  final Map<String, List<OptionChoice>> matchedOptions;
  final String? notes;

  double get unitPrice {
    final base = menuItem.discount != null && menuItem.discount! > 0
        ? menuItem.price - (menuItem.price * menuItem.discount! / 100)
        : menuItem.price;
    final sidesTotal = matchedSides.fold<double>(0, (sum, s) => sum + s.price);
    final optionsTotal = matchedOptions.values
        .expand((choices) => choices)
        .fold<double>(0, (sum, c) => sum + c.price);
    return base + sidesTotal + optionsTotal;
  }

  double get lineTotal => unitPrice * quantity;

  List<String> get modifierLabels => [
    for (final s in matchedSides) s.name,
    for (final choices in matchedOptions.values) ...choices.map((c) => c.name),
  ];
}

/// One spoken item that couldn't be confidently matched to anything on the
/// resolved restaurant's real menu — shown to the customer with an "add
/// manually" deep link, never silently dropped or guessed at.
class UnmatchedVoiceOrderItem {
  const UnmatchedVoiceOrderItem({required this.nameAsSaid, this.reason});

  final String nameAsSaid;
  final String? reason;
}

/// The fully resolved result of one voice-order "add" attempt — every id
/// here is real and re-verified against the database. Nothing in this
/// object has touched the cart yet; that only happens when the customer
/// taps Confirm on [VoiceOrderConfirmScreen].
class ResolvedVoiceOrder {
  const ResolvedVoiceOrder({
    required this.restaurant,
    required this.matchedItems,
    required this.unmatchedItems,
  });

  final Restaurant restaurant;
  final List<MatchedVoiceOrderItem> matchedItems;
  final List<UnmatchedVoiceOrderItem> unmatchedItems;

  double get subtotal =>
      matchedItems.fold<double>(0, (sum, i) => sum + i.lineTotal);
}
