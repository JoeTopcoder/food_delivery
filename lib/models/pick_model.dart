/// Compact picking progress for an order (for the order-list card badge).
class PickProgress {
  final int pickedLines;
  final int totalLines;
  final int pickedUnits;
  final int totalUnits;

  const PickProgress({
    required this.pickedLines,
    required this.totalLines,
    required this.pickedUnits,
    required this.totalUnits,
  });

  bool get hasItems => totalLines > 0;
  bool get started => pickedUnits > 0;
  bool get allPicked => totalLines > 0 && pickedLines == totalLines;
}

/// One line of a grocery order as seen by the in-store picker.
///
/// Read with a targeted query (order_items + the product's barcode/image) so the
/// shared `OrderItem` model and its generated code stay untouched.
class PickLine {
  final String orderItemId;
  final String menuItemId;
  final String name;
  final int quantity;
  final int pickedQuantity;
  final String? barcode; // scan code linked to the product, if any
  final String? imageUrl;

  const PickLine({
    required this.orderItemId,
    required this.menuItemId,
    required this.name,
    required this.quantity,
    required this.pickedQuantity,
    required this.barcode,
    required this.imageUrl,
  });

  bool get done => pickedQuantity >= quantity;
  bool get hasBarcode => barcode != null && barcode!.isNotEmpty;

  PickLine copyWith({int? pickedQuantity, String? barcode}) => PickLine(
    orderItemId: orderItemId,
    menuItemId: menuItemId,
    name: name,
    quantity: quantity,
    pickedQuantity: pickedQuantity ?? this.pickedQuantity,
    barcode: barcode ?? this.barcode,
    imageUrl: imageUrl,
  );
}
