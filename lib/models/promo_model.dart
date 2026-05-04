class PromoCode {
  final String id;
  final String code;
  final String discountType; // 'percentage' | 'fixed'
  final double discountValue;
  final double? minOrderAmount;
  final int? maxUses;
  final int usedCount;
  final DateTime? expiresAt;
  final bool isActive;
  final DateTime createdAt;

  const PromoCode({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    this.minOrderAmount,
    this.maxUses,
    required this.usedCount,
    this.expiresAt,
    required this.isActive,
    required this.createdAt,
  });

  factory PromoCode.fromJson(Map<String, dynamic> json) => PromoCode(
    id: json['id'] as String,
    code: json['code'] as String,
    discountType: json['discount_type'] as String,
    discountValue: (json['discount_value'] as num).toDouble(),
    minOrderAmount: (json['min_order_amount'] as num?)?.toDouble(),
    maxUses: json['max_uses'] as int?,
    usedCount: (json['usage_count'] as num? ?? 0).toInt(),
    expiresAt: json['expires_at'] != null
        ? DateTime.parse(json['expires_at'] as String)
        : null,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'discount_type': discountType,
    'discount_value': discountValue,
    if (minOrderAmount != null) 'min_order_amount': minOrderAmount,
    if (maxUses != null) 'max_uses': maxUses,
    'usage_count': usedCount,
    if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
  };

  /// Compute the discount amount for a given subtotal.
  double computeDiscount(double subtotal) {
    if (!isValid(subtotal)) return 0;
    if (discountType == 'percentage') return subtotal * discountValue / 100;
    return discountValue > subtotal ? subtotal : discountValue;
  }

  bool isValid(double subtotal) {
    if (!isActive) return false;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt!)) return false;
    if (maxUses != null && usedCount >= maxUses!) return false;
    if (minOrderAmount != null && subtotal < minOrderAmount!) return false;
    return true;
  }
}
