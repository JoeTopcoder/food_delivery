import 'package:intl/intl.dart';

enum RideStatus {
  requested,
  searchingDriver,
  scheduled,
  driverAssigned,
  driverArriving,
  driverArrived,
  rideStarted,
  ridePaused,
  rideCompleted,
  cancelled,
  failed;

  static RideStatus fromString(String value) {
    final normalized = value.replaceAll('_', '').toLowerCase();
    return RideStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse: () => RideStatus.failed,
    );
  }

  String toDisplayString() {
    switch (this) {
      case RideStatus.requested:
        return 'Ride Requested';
      case RideStatus.searchingDriver:
        return 'Searching for Driver';
      case RideStatus.scheduled:
        return 'Scheduled';
      case RideStatus.driverAssigned:
        return 'Driver Assigned';
      case RideStatus.driverArriving:
        return 'Driver Arriving';
      case RideStatus.driverArrived:
        return 'Driver Arrived';
      case RideStatus.rideStarted:
        return 'Ride in Progress';
      case RideStatus.ridePaused:
        return 'Ride Paused';
      case RideStatus.rideCompleted:
        return 'Ride Completed';
      case RideStatus.cancelled:
        return 'Cancelled';
      case RideStatus.failed:
        return 'Failed';
    }
  }
}

enum PaymentStatus {
  pending,
  authorized,
  paid,
  cashPending,
  cashCollected,
  failed,
  refunded,
  cancelled;

  static PaymentStatus fromString(String value) {
    return PaymentStatus.values.firstWhere(
      (e) => e.name == value.replaceAll('_', ''),
      orElse: () => PaymentStatus.failed,
    );
  }
}

enum PaymentMethod {
  card,
  cash,
  wallet;

  static PaymentMethod fromString(String value) {
    return PaymentMethod.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => PaymentMethod.card,
    );
  }
}

class RideRequest {
  final String id;
  final String customerId;
  final String? driverId;

  // Pickup location
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;

  // Destination location
  final String destinationAddress;
  final double destinationLat;
  final double destinationLng;

  // Route details
  final double? distanceKm;
  final int? estimatedDurationMinutes;

  // Pricing
  final double? estimatedFare;
  final double? finalFare;
  final double? platformFee;
  final double? driverEarning;

  // Payment
  final PaymentStatus paymentStatus;
  final PaymentMethod? paymentMethod;

  // Status
  final RideStatus rideStatus;

  // Pause
  final String? pauseReason;
  final DateTime? pausedAt;

  // Cancellation
  final String? cancellationReason;
  final String? cancelledBy;

  // Rating & Review
  final int? rating;
  final String? review;

  // Scheduled ride
  final DateTime? scheduledFor;

  // OTP PIN shown to customer; driver must enter to start the ride
  final String? ridePin;

  // Cancellation fee charged when customer cancels after driver is assigned
  final double? cancellationFee;

  // Waiting fee: set by driver after grace period expires
  final DateTime? waitingStartedAt;
  final double? waitingFeePerMin;

  // Timestamps
  final DateTime requestedAt;
  final DateTime? acceptedAt;
  final DateTime? driverArrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  RideRequest({
    required this.id,
    required this.customerId,
    this.driverId,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.destinationAddress,
    required this.destinationLat,
    required this.destinationLng,
    this.distanceKm,
    this.estimatedDurationMinutes,
    this.estimatedFare,
    this.finalFare,
    this.platformFee,
    this.driverEarning,
    required this.paymentStatus,
    this.paymentMethod,
    required this.rideStatus,
    this.pauseReason,
    this.pausedAt,
    this.cancellationReason,
    this.cancelledBy,
    this.rating,
    this.review,
    this.scheduledFor,
    this.ridePin,
    this.cancellationFee,
    this.waitingStartedAt,
    this.waitingFeePerMin,
    required this.requestedAt,
    this.acceptedAt,
    this.driverArrivedAt,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RideRequest.fromJson(Map<String, dynamic> json) {
    return RideRequest(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      driverId: json['driver_id'] as String?,
      pickupAddress: json['pickup_address'] as String,
      pickupLat: (json['pickup_lat'] as num).toDouble(),
      pickupLng: (json['pickup_lng'] as num).toDouble(),
      destinationAddress: json['destination_address'] as String,
      destinationLat: (json['destination_lat'] as num).toDouble(),
      destinationLng: (json['destination_lng'] as num).toDouble(),
      distanceKm: json['distance_km'] != null
          ? (json['distance_km'] as num).toDouble()
          : null,
      estimatedDurationMinutes: json['estimated_duration_minutes'] as int?,
      estimatedFare: json['estimated_fare'] != null
          ? (json['estimated_fare'] as num).toDouble()
          : null,
      finalFare: json['final_fare'] != null
          ? (json['final_fare'] as num).toDouble()
          : null,
      platformFee: json['platform_fee'] != null
          ? (json['platform_fee'] as num).toDouble()
          : null,
      driverEarning: json['driver_earning'] != null
          ? (json['driver_earning'] as num).toDouble()
          : null,
      paymentStatus: PaymentStatus.fromString(
        json['payment_status'] as String? ?? '',
      ),
      paymentMethod: json['payment_method'] != null
          ? PaymentMethod.fromString(json['payment_method'] as String)
          : null,
      rideStatus: RideStatus.fromString(json['ride_status'] as String? ?? ''),
      pauseReason: json['pause_reason'] as String?,
      pausedAt: json['paused_at'] != null
          ? DateTime.parse(json['paused_at'] as String)
          : null,
      cancellationReason: json['cancellation_reason'] as String?,
      cancelledBy: json['cancelled_by'] as String?,
      rating: json['rating'] as int?,
      review: json['review'] as String?,
      scheduledFor: json['scheduled_for'] != null
          ? DateTime.parse(json['scheduled_for'] as String)
          : null,
      ridePin: json['ride_pin'] as String?,
      cancellationFee: json['cancellation_fee'] != null
          ? (json['cancellation_fee'] as num).toDouble()
          : null,
      waitingStartedAt: json['waiting_started_at'] != null
          ? DateTime.parse(json['waiting_started_at'] as String)
          : null,
      waitingFeePerMin: json['waiting_fee_per_min'] != null
          ? (json['waiting_fee_per_min'] as num).toDouble()
          : null,
      requestedAt: DateTime.parse(json['requested_at'] as String),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      driverArrivedAt: json['driver_arrived_at'] != null
          ? DateTime.parse(json['driver_arrived_at'] as String)
          : null,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'customer_id': customerId,
    'driver_id': driverId,
    'pickup_address': pickupAddress,
    'pickup_lat': pickupLat,
    'pickup_lng': pickupLng,
    'destination_address': destinationAddress,
    'destination_lat': destinationLat,
    'destination_lng': destinationLng,
    'distance_km': distanceKm,
    'estimated_duration_minutes': estimatedDurationMinutes,
    'estimated_fare': estimatedFare,
    'final_fare': finalFare,
    'platform_fee': platformFee,
    'driver_earning': driverEarning,
    'payment_status': paymentStatus.name,
    'payment_method': paymentMethod?.name,
    'ride_status': rideStatus.name,
    'pause_reason': pauseReason,
    'paused_at': pausedAt?.toIso8601String(),
    'cancellation_reason': cancellationReason,
    'cancelled_by': cancelledBy,
    'rating': rating,
    'review': review,
    'scheduled_for': scheduledFor?.toIso8601String(),
    'ride_pin': ridePin,
    'cancellation_fee': cancellationFee,
    'waiting_started_at': waitingStartedAt?.toIso8601String(),
    'waiting_fee_per_min': waitingFeePerMin,
    'requested_at': requestedAt.toIso8601String(),
    'accepted_at': acceptedAt?.toIso8601String(),
    'driver_arrived_at': driverArrivedAt?.toIso8601String(),
    'started_at': startedAt?.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  RideRequest copyWith({
    String? id,
    String? customerId,
    String? driverId,
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String? destinationAddress,
    double? destinationLat,
    double? destinationLng,
    double? distanceKm,
    int? estimatedDurationMinutes,
    double? estimatedFare,
    double? finalFare,
    double? platformFee,
    double? driverEarning,
    PaymentStatus? paymentStatus,
    PaymentMethod? paymentMethod,
    RideStatus? rideStatus,
    String? pauseReason,
    DateTime? pausedAt,
    String? cancellationReason,
    String? cancelledBy,
    int? rating,
    String? review,
    DateTime? scheduledFor,
    String? ridePin,
    double? cancellationFee,
    DateTime? waitingStartedAt,
    double? waitingFeePerMin,
    DateTime? requestedAt,
    DateTime? acceptedAt,
    DateTime? driverArrivedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RideRequest(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      driverId: driverId ?? this.driverId,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      destinationLat: destinationLat ?? this.destinationLat,
      destinationLng: destinationLng ?? this.destinationLng,
      distanceKm: distanceKm ?? this.distanceKm,
      estimatedDurationMinutes:
          estimatedDurationMinutes ?? this.estimatedDurationMinutes,
      estimatedFare: estimatedFare ?? this.estimatedFare,
      finalFare: finalFare ?? this.finalFare,
      platformFee: platformFee ?? this.platformFee,
      driverEarning: driverEarning ?? this.driverEarning,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      rideStatus: rideStatus ?? this.rideStatus,
      pauseReason: pauseReason ?? this.pauseReason,
      pausedAt: pausedAt ?? this.pausedAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      rating: rating ?? this.rating,
      review: review ?? this.review,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      ridePin: ridePin ?? this.ridePin,
      cancellationFee: cancellationFee ?? this.cancellationFee,
      waitingStartedAt: waitingStartedAt ?? this.waitingStartedAt,
      waitingFeePerMin: waitingFeePerMin ?? this.waitingFeePerMin,
      requestedAt: requestedAt ?? this.requestedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      driverArrivedAt: driverArrivedAt ?? this.driverArrivedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper getters
  bool get isActive => ![
    RideStatus.rideCompleted,
    RideStatus.cancelled,
    RideStatus.failed,
  ].contains(rideStatus);

  bool get canBeCancelled => ![
    RideStatus.rideCompleted,
    RideStatus.cancelled,
  ].contains(rideStatus);

  String get distanceDisplay => distanceKm != null
      ? '${distanceKm!.toStringAsFixed(1)} km'
      : 'Calculating...';

  String get durationDisplay => estimatedDurationMinutes != null
      ? '$estimatedDurationMinutes mins'
      : 'Calculating...';

  String get fareDisplay => estimatedFare != null
      ? 'J\$${estimatedFare!.toStringAsFixed(0)}'
      : 'Calculating...';

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(requestedAt);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return DateFormat('MMM d, yyyy').format(requestedAt);
    }
  }
}
