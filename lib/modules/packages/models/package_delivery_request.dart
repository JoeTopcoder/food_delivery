class PackageDeliveryRequest {
  final String id;
  final String packageRecordId;
  final String customerId;
  final String? driverId;
  final String shippingCompanyId;
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String destinationAddress;
  final double destinationLat;
  final double destinationLng;
  final double? estimatedDistanceKm;
  final int? estimatedDurationMinutes;
  final double deliveryFee;
  final double platformFee;
  final double driverEarning;
  final String paymentStatus;
  final String paymentMethod;
  final String? savedCardId;
  final String? stripePaymentIntentId;
  final String deliveryStatus;
  final String? cancellationReason;
  final String? cancelledBy;
  // Joined from shipping_companies
  final String? companyName;
  final String? companyLogoUrl;
  final DateTime requestedAt;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  const PackageDeliveryRequest({
    required this.id,
    required this.packageRecordId,
    required this.customerId,
    this.driverId,
    required this.shippingCompanyId,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.destinationAddress,
    required this.destinationLat,
    required this.destinationLng,
    this.estimatedDistanceKm,
    this.estimatedDurationMinutes,
    required this.deliveryFee,
    required this.platformFee,
    required this.driverEarning,
    required this.paymentStatus,
    required this.paymentMethod,
    this.savedCardId,
    this.stripePaymentIntentId,
    required this.deliveryStatus,
    this.cancellationReason,
    this.cancelledBy,
    this.companyName,
    this.companyLogoUrl,
    required this.requestedAt,
    this.acceptedAt,
    this.pickedUpAt,
    this.deliveredAt,
  });

  factory PackageDeliveryRequest.fromJson(Map<String, dynamic> j) =>
      PackageDeliveryRequest(
        id: j['id'] as String,
        packageRecordId: j['package_record_id'] as String,
        customerId: j['customer_id'] as String,
        driverId: j['driver_id'] as String?,
        shippingCompanyId: j['shipping_company_id'] as String,
        pickupAddress: j['pickup_address'] as String,
        pickupLat: (j['pickup_lat'] as num).toDouble(),
        pickupLng: (j['pickup_lng'] as num).toDouble(),
        destinationAddress: j['destination_address'] as String,
        destinationLat: (j['destination_lat'] as num).toDouble(),
        destinationLng: (j['destination_lng'] as num).toDouble(),
        estimatedDistanceKm: (j['estimated_distance_km'] as num?)?.toDouble(),
        estimatedDurationMinutes: j['estimated_duration_minutes'] as int?,
        deliveryFee: (j['delivery_fee'] as num).toDouble(),
        platformFee: (j['platform_fee'] as num).toDouble(),
        driverEarning: (j['driver_earning'] as num).toDouble(),
        paymentStatus: j['payment_status'] as String? ?? 'pending',
        paymentMethod: j['payment_method'] as String? ?? 'card',
        savedCardId: j['saved_card_id'] as String?,
        stripePaymentIntentId: j['stripe_payment_intent_id'] as String?,
        deliveryStatus: j['delivery_status'] as String? ?? 'pending_verification',
        cancellationReason: j['cancellation_reason'] as String?,
        cancelledBy: j['cancelled_by'] as String?,
        companyName: (j['shipping_companies'] as Map<String, dynamic>?)?['name'] as String?,
        companyLogoUrl: (j['shipping_companies'] as Map<String, dynamic>?)?['logo_url'] as String?,
        requestedAt: DateTime.parse(j['requested_at'] as String),
        acceptedAt: j['accepted_at'] != null
            ? DateTime.parse(j['accepted_at'] as String)
            : null,
        pickedUpAt: j['picked_up_at'] != null
            ? DateTime.parse(j['picked_up_at'] as String)
            : null,
        deliveredAt: j['delivered_at'] != null
            ? DateTime.parse(j['delivered_at'] as String)
            : null,
      );

  bool get isActive => !['delivered', 'cancelled', 'failed'].contains(deliveryStatus);

  String get displayFee => '\$${deliveryFee.toStringAsFixed(2)}';

  String get statusLabel {
    switch (deliveryStatus) {
      case 'pending_verification':
        return 'Pending Verification';
      case 'verified':
        return 'Verified';
      case 'awaiting_payment':
        return 'Awaiting Payment';
      case 'searching_driver':
        return 'Searching Driver';
      case 'driver_assigned':
        return 'Driver Assigned';
      case 'driver_arriving_warehouse':
        return 'Driver Heading to Warehouse';
      case 'driver_at_warehouse':
        return 'Driver at Warehouse';
      case 'package_picked_up':
        return 'Package Picked Up';
      case 'in_transit':
        return 'In Transit';
      case 'arriving_destination':
        return 'Almost There';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      case 'failed':
        return 'Failed';
      default:
        return deliveryStatus;
    }
  }
}
