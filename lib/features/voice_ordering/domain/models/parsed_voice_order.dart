/// What kind of voice command this was — extracted by the parser, never
/// executed by it. Only [addToCart] resolves against the menu; the cart
/// -editing intents map straight onto the existing CartNotifier methods.
enum VoiceOrderIntent {
  addToCart,
  removeFromCart,
  updateQuantity,
  clearCart,
  viewCart,
  checkout,
  unknown;

  static VoiceOrderIntent fromString(String? s) {
    switch (s) {
      case 'add_to_cart':
        return VoiceOrderIntent.addToCart;
      case 'remove_from_cart':
        return VoiceOrderIntent.removeFromCart;
      case 'update_quantity':
        return VoiceOrderIntent.updateQuantity;
      case 'clear_cart':
        return VoiceOrderIntent.clearCart;
      case 'view_cart':
        return VoiceOrderIntent.viewCart;
      case 'checkout':
        return VoiceOrderIntent.checkout;
      default:
        return VoiceOrderIntent.unknown;
    }
  }
}

/// One food item as extracted from the customer's speech — a query to
/// resolve against the real menu, never a real id/price. The LLM that
/// produces this never sees or returns prices.
class ParsedVoiceOrderItem {
  const ParsedVoiceOrderItem({
    required this.nameQuery,
    this.quantity = 1,
    this.modifiers = const [],
    this.notes,
  });

  final String nameQuery;
  final int quantity;
  final List<String> modifiers;
  final String? notes;

  factory ParsedVoiceOrderItem.fromJson(Map<String, dynamic> j) =>
      ParsedVoiceOrderItem(
        nameQuery: (j['name_query'] as String?)?.trim() ?? '',
        quantity: ((j['quantity'] as num?)?.toInt() ?? 1).clamp(1, 50),
        modifiers:
            (j['modifiers'] as List?)?.map((m) => m.toString()).toList() ??
            const [],
        notes: (j['notes'] as String?)?.trim().isNotEmpty == true
            ? (j['notes'] as String).trim()
            : null,
      );
}

/// The structured result of parsing one spoken utterance. Nothing here is
/// trusted as a real restaurant/item id or as authoritative for cart
/// mutation — [VoiceOrderRepository] resolves against the real database
/// (for [VoiceOrderIntent.addToCart]) or maps straight onto the existing
/// cart methods (for the other intents), never this object directly.
class ParsedVoiceOrder {
  const ParsedVoiceOrder({
    required this.intent,
    required this.restaurantQuery,
    required this.items,
    required this.confidence,
    this.itemReference,
    this.newQuantity,
  });

  final VoiceOrderIntent intent;
  final String? restaurantQuery;
  final List<ParsedVoiceOrderItem> items;

  /// For [VoiceOrderIntent.removeFromCart]/[updateQuantity] — the cart item
  /// as named by the customer ("the Ting"), resolved against what's
  /// actually in the cart, never invented.
  final String? itemReference;

  /// For [VoiceOrderIntent.updateQuantity] ("make that two").
  final int? newQuantity;

  /// 0.0-1.0 — the parser's own confidence in this extraction. Below the
  /// repository's threshold, the utterance is treated as unparseable
  /// rather than acted on.
  final double confidence;

  factory ParsedVoiceOrder.fromJson(Map<String, dynamic> j) =>
      ParsedVoiceOrder(
        intent: VoiceOrderIntent.fromString(j['intent'] as String?),
        restaurantQuery: (j['restaurant_query'] as String?)?.trim().isNotEmpty == true
            ? (j['restaurant_query'] as String).trim()
            : null,
        items: (j['items'] as List?)
                ?.whereType<Map>()
                .map((i) => ParsedVoiceOrderItem.fromJson(Map<String, dynamic>.from(i)))
                .where((i) => i.nameQuery.isNotEmpty)
                .toList() ??
            const [],
        itemReference: (j['item_reference'] as String?)?.trim().isNotEmpty == true
            ? (j['item_reference'] as String).trim()
            : null,
        newQuantity: (j['new_quantity'] as num?)?.toInt(),
        confidence: ((j['confidence'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
      );
}
