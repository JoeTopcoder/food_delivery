class LedgerEntry {
  final String id;
  final String userId;
  final String role;
  final String? orderId;
  final String? rideId;
  final String? restaurantId;
  final String? driverId;
  final String type;
  final String direction;
  final int amountCents;
  final String currency;
  final String status;
  final DateTime availableAt;
  final String? payoutRequestId;
  final String? description;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const LedgerEntry({
    required this.id,
    required this.userId,
    required this.role,
    this.orderId,
    this.rideId,
    this.restaurantId,
    this.driverId,
    required this.type,
    required this.direction,
    required this.amountCents,
    required this.currency,
    required this.status,
    required this.availableAt,
    this.payoutRequestId,
    this.description,
    required this.metadata,
    required this.createdAt,
  });

  bool get isCredit => direction == 'credit';
  bool get isAvailable => status == 'available';
  bool get isPending => status == 'pending';
  bool get isLocked => status == 'locked';
  bool get isWithdrawn => status == 'withdrawn';
  double get amountDollars => amountCents / 100.0;

  /// Display label for the entry type.
  String get typeLabel {
    switch (type) {
      case 'order_earning':
        return 'Order Earning';
      case 'ride_earning':
        return 'Ride Earning';
      case 'tip':
        return 'Tip';
      case 'bonus':
        return 'Bonus';
      case 'adjustment':
        return 'Adjustment';
      case 'refund':
        return 'Refund';
      case 'chargeback':
        return 'Chargeback';
      case 'platform_reversal':
        return 'Platform Reversal';
      default:
        return type;
    }
  }

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        role: j['role'] as String,
        orderId: j['order_id'] as String?,
        rideId: j['ride_id'] as String?,
        restaurantId: j['restaurant_id'] as String?,
        driverId: j['driver_id'] as String?,
        type: j['type'] as String,
        direction: j['direction'] as String,
        amountCents: j['amount_cents'] as int,
        currency: j['currency'] as String? ?? 'usd',
        status: j['status'] as String,
        availableAt: DateTime.parse(j['available_at'] as String),
        payoutRequestId: j['payout_request_id'] as String?,
        description: j['description'] as String?,
        metadata:
            (j['metadata'] as Map<String, dynamic>?) ?? const {},
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'role': role,
        'order_id': orderId,
        'ride_id': rideId,
        'restaurant_id': restaurantId,
        'driver_id': driverId,
        'type': type,
        'direction': direction,
        'amount_cents': amountCents,
        'currency': currency,
        'status': status,
        'available_at': availableAt.toIso8601String(),
        'payout_request_id': payoutRequestId,
        'description': description,
        'metadata': metadata,
        'created_at': createdAt.toIso8601String(),
      };
}
