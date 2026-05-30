enum LaundryJobType { pickup, returnDelivery }

extension LaundryJobTypeX on LaundryJobType {
  String get dbString => this == LaundryJobType.pickup ? 'pickup' : 'return_delivery';
  String get displayLabel => this == LaundryJobType.pickup ? 'Pickup' : 'Return Delivery';
  static LaundryJobType fromString(String v) =>
      v == 'return_delivery' ? LaundryJobType.returnDelivery : LaundryJobType.pickup;
}

enum LaundryJobStatus {
  pending, searching, assigned, accepted,
  pickedUp, droppedOff, completed, cancelled;

  static LaundryJobStatus fromString(String v) {
    const map = {
      'pending':    LaundryJobStatus.pending,
      'searching':  LaundryJobStatus.searching,
      'assigned':   LaundryJobStatus.assigned,
      'accepted':   LaundryJobStatus.accepted,
      'picked_up':  LaundryJobStatus.pickedUp,
      'dropped_off':LaundryJobStatus.droppedOff,
      'completed':  LaundryJobStatus.completed,
      'cancelled':  LaundryJobStatus.cancelled,
    };
    return map[v] ?? LaundryJobStatus.pending;
  }

  String get dbString {
    const map = {
      LaundryJobStatus.pending:    'pending',
      LaundryJobStatus.searching:  'searching',
      LaundryJobStatus.assigned:   'assigned',
      LaundryJobStatus.accepted:   'accepted',
      LaundryJobStatus.pickedUp:   'picked_up',
      LaundryJobStatus.droppedOff: 'dropped_off',
      LaundryJobStatus.completed:  'completed',
      LaundryJobStatus.cancelled:  'cancelled',
    };
    return map[this]!;
  }

  String get displayLabel {
    const map = {
      LaundryJobStatus.pending:    'Pending',
      LaundryJobStatus.searching:  'Searching for Driver',
      LaundryJobStatus.assigned:   'Driver Assigned',
      LaundryJobStatus.accepted:   'Driver Accepted',
      LaundryJobStatus.pickedUp:   'Picked Up',
      LaundryJobStatus.droppedOff: 'Dropped Off',
      LaundryJobStatus.completed:  'Completed',
      LaundryJobStatus.cancelled:  'Cancelled',
    };
    return map[this]!;
  }

  bool get isActive =>
      this != LaundryJobStatus.completed && this != LaundryJobStatus.cancelled;
}

class LaundryDriverJob {
  final String id;
  final String bookingId;
  final LaundryJobType jobType;
  final String? driverId;
  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final String dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;
  final double? distanceKm;
  final int? estimatedMinutes;
  final double deliveryFee;
  final double driverPayout;
  final double platformMargin;
  final LaundryJobStatus status;
  final DateTime? broadcastAt;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? droppedOffAt;
  final DateTime? completedAt;
  final String? proofUrl;
  final String? driverNotes;
  final DateTime createdAt;

  // Joined
  final String? driverName;
  final String? driverPhone;
  final String? driverAvatar;

  const LaundryDriverJob({
    required this.id,
    required this.bookingId,
    required this.jobType,
    this.driverId,
    required this.pickupAddress,
    this.pickupLat,
    this.pickupLng,
    required this.dropoffAddress,
    this.dropoffLat,
    this.dropoffLng,
    this.distanceKm,
    this.estimatedMinutes,
    this.deliveryFee = 0,
    this.driverPayout = 0,
    this.platformMargin = 0,
    required this.status,
    this.broadcastAt,
    this.acceptedAt,
    this.pickedUpAt,
    this.droppedOffAt,
    this.completedAt,
    this.proofUrl,
    this.driverNotes,
    required this.createdAt,
    this.driverName,
    this.driverPhone,
    this.driverAvatar,
  });

  factory LaundryDriverJob.fromMap(Map<String, dynamic> m) {
    final driver = m['users'] as Map<String, dynamic>?;
    return LaundryDriverJob(
      id:               m['id'] as String,
      bookingId:        m['booking_id'] as String,
      jobType:          LaundryJobTypeX.fromString(m['job_type'] as String),
      driverId:         m['driver_id'] as String?,
      pickupAddress:    m['pickup_address'] as String,
      pickupLat:        (m['pickup_lat'] as num?)?.toDouble(),
      pickupLng:        (m['pickup_lng'] as num?)?.toDouble(),
      dropoffAddress:   m['dropoff_address'] as String,
      dropoffLat:       (m['dropoff_lat'] as num?)?.toDouble(),
      dropoffLng:       (m['dropoff_lng'] as num?)?.toDouble(),
      distanceKm:       (m['distance_km'] as num?)?.toDouble(),
      estimatedMinutes: m['estimated_minutes'] as int?,
      deliveryFee:      (m['delivery_fee'] as num?)?.toDouble() ?? 0,
      driverPayout:     (m['driver_payout'] as num?)?.toDouble() ?? 0,
      platformMargin:   (m['platform_margin'] as num?)?.toDouble() ?? 0,
      status:           LaundryJobStatus.fromString(m['status'] as String),
      broadcastAt:      m['broadcast_at'] != null ? DateTime.parse(m['broadcast_at'] as String) : null,
      acceptedAt:       m['accepted_at'] != null ? DateTime.parse(m['accepted_at'] as String) : null,
      pickedUpAt:       m['picked_up_at'] != null ? DateTime.parse(m['picked_up_at'] as String) : null,
      droppedOffAt:     m['dropped_off_at'] != null ? DateTime.parse(m['dropped_off_at'] as String) : null,
      completedAt:      m['completed_at'] != null ? DateTime.parse(m['completed_at'] as String) : null,
      proofUrl:         m['proof_url'] as String?,
      driverNotes:      m['driver_notes'] as String?,
      createdAt:        DateTime.parse(m['created_at'] as String),
      driverName:       driver?['name'] as String?,
      driverPhone:      driver?['phone'] as String?,
      driverAvatar:     driver?['profile_image_url'] as String?,
    );
  }
}

// ─── Payment split snapshot ────────────────────────────────────────────────
class LaundryPaymentSplit {
  final String id;
  final String bookingId;
  final double finalLaundryAmount;
  final double pickupDeliveryFee;
  final double returnDeliveryFee;
  final double customerServiceFee;
  final double finalTotal;
  final double commissionableAmount;
  final double commissionRate;
  final String commissionType;
  final double platformCommission;
  final double providerGrossAmount;
  final double providerNetEarning;
  final double pickupDriverEarning;
  final double returnDriverEarning;
  final double platformTotalEarning;
  final String currency;
  final String status;
  final DateTime? settledAt;
  final DateTime createdAt;

  const LaundryPaymentSplit({
    required this.id,
    required this.bookingId,
    this.finalLaundryAmount = 0,
    this.pickupDeliveryFee = 0,
    this.returnDeliveryFee = 0,
    this.customerServiceFee = 0,
    this.finalTotal = 0,
    this.commissionableAmount = 0,
    this.commissionRate = 0,
    this.commissionType = 'percentage',
    this.platformCommission = 0,
    this.providerGrossAmount = 0,
    this.providerNetEarning = 0,
    this.pickupDriverEarning = 0,
    this.returnDriverEarning = 0,
    this.platformTotalEarning = 0,
    this.currency = 'USD',
    this.status = 'pending',
    this.settledAt,
    required this.createdAt,
  });

  factory LaundryPaymentSplit.fromMap(Map<String, dynamic> m) => LaundryPaymentSplit(
    id:                   m['id'] as String,
    bookingId:            m['booking_id'] as String,
    finalLaundryAmount:   (m['final_laundry_amount'] as num?)?.toDouble() ?? 0,
    pickupDeliveryFee:    (m['pickup_delivery_fee'] as num?)?.toDouble() ?? 0,
    returnDeliveryFee:    (m['return_delivery_fee'] as num?)?.toDouble() ?? 0,
    customerServiceFee:   (m['customer_service_fee'] as num?)?.toDouble() ?? 0,
    finalTotal:           (m['final_total'] as num?)?.toDouble() ?? 0,
    commissionableAmount: (m['commissionable_amount'] as num?)?.toDouble() ?? 0,
    commissionRate:       (m['commission_rate'] as num?)?.toDouble() ?? 0,
    commissionType:       m['commission_type'] as String? ?? 'percentage',
    platformCommission:   (m['platform_commission'] as num?)?.toDouble() ?? 0,
    providerGrossAmount:  (m['provider_gross_amount'] as num?)?.toDouble() ?? 0,
    providerNetEarning:   (m['provider_net_earning'] as num?)?.toDouble() ?? 0,
    pickupDriverEarning:  (m['pickup_driver_earning'] as num?)?.toDouble() ?? 0,
    returnDriverEarning:  (m['return_driver_earning'] as num?)?.toDouble() ?? 0,
    platformTotalEarning: (m['platform_total_earning'] as num?)?.toDouble() ?? 0,
    currency:             m['currency'] as String? ?? 'USD',
    status:               m['status'] as String? ?? 'pending',
    settledAt:            m['settled_at'] != null ? DateTime.parse(m['settled_at'] as String) : null,
    createdAt:            DateTime.parse(m['created_at'] as String),
  );
}

// ─── Wallet reservation component ─────────────────────────────────────────
class LaundryWalletReservation {
  final String id;
  final String bookingId;
  final String component;
  final double reservedAmount;
  final String status;
  final DateTime createdAt;

  const LaundryWalletReservation({
    required this.id,
    required this.bookingId,
    required this.component,
    required this.reservedAmount,
    required this.status,
    required this.createdAt,
  });

  factory LaundryWalletReservation.fromMap(Map<String, dynamic> m) =>
      LaundryWalletReservation(
        id:             m['id'] as String,
        bookingId:      m['booking_id'] as String,
        component:      m['component'] as String,
        reservedAmount: (m['reserved_amount'] as num?)?.toDouble() ?? 0,
        status:         m['status'] as String,
        createdAt:      DateTime.parse(m['created_at'] as String),
      );
}
