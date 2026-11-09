/// An admin-configured driver-pay rule for a delivery distance range.
///
/// A range tier ([isDefault] false) pays for deliveries whose distance falls in
/// [minKm]..[maxKm] (inclusive). The single default tier ([isDefault] true) is
/// used when a delivery's distance matches no range. Each tier pays either a
/// FLAT amount (JMD) or a PERCENT (0..100) of the order's delivery fee.
class DriverPayTier {
  final String id;
  final String? label;
  final double? minKm;
  final double? maxKm;
  final String payType; // 'flat' | 'percent'
  final double amount; // flat: JMD ; percent: 0..100
  final bool isDefault;
  final bool isActive;
  final int sortOrder;

  const DriverPayTier({
    required this.id,
    this.label,
    this.minKm,
    this.maxKm,
    required this.payType,
    required this.amount,
    this.isDefault = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  bool get isPercent => payType == 'percent';

  factory DriverPayTier.fromJson(Map<String, dynamic> j) => DriverPayTier(
        id: j['id'] as String,
        label: j['label'] as String?,
        minKm: (j['min_km'] as num?)?.toDouble(),
        maxKm: (j['max_km'] as num?)?.toDouble(),
        payType: j['pay_type'] as String,
        amount: (j['amount'] as num).toDouble(),
        isDefault: j['is_default'] as bool? ?? false,
        isActive: j['is_active'] as bool? ?? true,
        sortOrder: j['sort_order'] as int? ?? 0,
      );

  Map<String, dynamic> toInsert() => {
        if (label != null) 'label': label,
        'min_km': minKm,
        'max_km': maxKm,
        'pay_type': payType,
        'amount': amount,
        'is_default': isDefault,
        'is_active': isActive,
        'sort_order': sortOrder,
      };
}
