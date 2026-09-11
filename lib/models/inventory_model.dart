/// Lightweight inventory view of a grocery product.
///
/// These fields live on the `menus` row (added by the grocery-inventory
/// migration) but are deliberately NOT on the [MenuItem] model — regenerating
/// `menu_model.g.dart` touches shared code, so inventory is read with a
/// targeted query instead and joined to products by id in the UI.
class ProductInventory {
  final String productId;
  final bool trackInventory;
  final int stockQuantity;
  final int lowStockThreshold;
  final bool inStock;

  const ProductInventory({
    required this.productId,
    required this.trackInventory,
    required this.stockQuantity,
    required this.lowStockThreshold,
    required this.inStock,
  });

  factory ProductInventory.fromJson(Map<String, dynamic> json) =>
      ProductInventory(
        productId: json['id'] as String,
        trackInventory: json['track_inventory'] as bool? ?? false,
        stockQuantity: (json['stock_quantity'] as num?)?.toInt() ?? 0,
        lowStockThreshold: (json['low_stock_threshold'] as num?)?.toInt() ?? 5,
        inStock: json['in_stock'] as bool? ?? true,
      );

  /// Tracked and at/below the reorder threshold (includes fully out of stock).
  bool get isLow => trackInventory && stockQuantity <= lowStockThreshold;

  /// Tracked and nothing left on hand.
  bool get isOut => trackInventory && stockQuantity <= 0;
}

/// One row of the append-only `inventory_movements` ledger.
class InventoryMovement {
  final int id;
  final int change; // signed: +restock/+restore, -sale/-waste, ± adjust
  final int balanceAfter;
  final String reason; // restock | sale | adjustment | waste | stocktake | order_restored
  final String? note;
  final DateTime createdAt;

  const InventoryMovement({
    required this.id,
    required this.change,
    required this.balanceAfter,
    required this.reason,
    required this.note,
    required this.createdAt,
  });

  factory InventoryMovement.fromJson(Map<String, dynamic> json) =>
      InventoryMovement(
        id: (json['id'] as num).toInt(),
        change: (json['change'] as num).toInt(),
        balanceAfter: (json['balance_after'] as num).toInt(),
        reason: json['reason'] as String,
        note: json['note'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// Human label for the movement reason.
  String get reasonLabel => switch (reason) {
    'restock' => 'Restock',
    'sale' => 'Sale',
    'adjustment' => 'Adjustment',
    'waste' => 'Waste / loss',
    'stocktake' => 'Stock count',
    'order_restored' => 'Order cancelled',
    _ => reason,
  };
}
