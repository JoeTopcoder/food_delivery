import 'car_service_provider.dart';
import 'car_service_offering.dart';
import 'service_booking_item.dart';
import 'numeric_utils.dart';

enum CarServiceBookingStatus {
  pending,
  confirmed,
  providerEnRoute,
  arrived,
  inProgress,
  completed,
  cancelled,
  noShow;

  static CarServiceBookingStatus fromString(String value) {
    // Normalize snake_case → camelCase for matching
    final normalized = value
        .split('_')
        .asMap()
        .entries
        .map((e) => e.key == 0
            ? e.value.toLowerCase()
            : e.value[0].toUpperCase() + e.value.substring(1).toLowerCase())
        .join();
    return CarServiceBookingStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized.toLowerCase(),
      orElse: () => CarServiceBookingStatus.pending,
    );
  }

  String toDbString() {
    // Convert camelCase enum name to snake_case for DB
    return name.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (m) => '_${m.group(0)!.toLowerCase()}',
    );
  }

  String toDisplayString() {
    switch (this) {
      case CarServiceBookingStatus.pending:
        return 'Pending';
      case CarServiceBookingStatus.confirmed:
        return 'Confirmed';
      case CarServiceBookingStatus.providerEnRoute:
        return 'Provider En Route';
      case CarServiceBookingStatus.arrived:
        return 'Provider Arrived';
      case CarServiceBookingStatus.inProgress:
        return 'In Progress';
      case CarServiceBookingStatus.completed:
        return 'Completed';
      case CarServiceBookingStatus.cancelled:
        return 'Cancelled';
      case CarServiceBookingStatus.noShow:
        return 'No Show';
    }
  }
}

enum CarServicePaymentStatus {
  pending,
  authorized,
  paid,
  failed,
  refunded;

  static CarServicePaymentStatus fromString(String value) {
    return CarServicePaymentStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => CarServicePaymentStatus.pending,
    );
  }
}

enum CarServicePaymentMethod {
  card,
  cash,
  wallet;

  static CarServicePaymentMethod fromString(String value) {
    return CarServicePaymentMethod.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => CarServicePaymentMethod.card,
    );
  }
}

class CarServiceBooking {
  final String id;
  final String bookingNumber;
  final String customerId;
  final String providerId;
  final String offeringId;
  final CarServiceBookingStatus status;
  final DateTime scheduledAt;
  final String serviceAddress;
  final double? serviceLat;
  final double? serviceLng;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? vehiclePlate;
  final double subtotal;
  final double platformFee;
  final double serviceFee;
  final double totalAmount;
  final CarServicePaymentMethod paymentMethod;
  final CarServicePaymentStatus paymentStatus;
  final String? stripePaymentIntentId;
  final String? providerNotes;
  final String? customerNotes;
  final String? cancellationReason;
  final double? providerLat;
  final double? providerLng;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Multi-vehicle / multi-service fields (new)
  final String? selectedAddressId;
  final int vehicleCount;
  final int serviceCount;
  final double itemsSubtotal;
  final double mobileFee;
  final double discountAmount;

  // Joined fields
  final CarServiceProvider? provider;
  final CarServiceOffering? offering;
  final List<ServiceBookingItem>? bookingItems;

  const CarServiceBooking({
    required this.id,
    required this.bookingNumber,
    required this.customerId,
    required this.providerId,
    required this.offeringId,
    required this.status,
    required this.scheduledAt,
    required this.serviceAddress,
    this.serviceLat,
    this.serviceLng,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleColor,
    this.vehiclePlate,
    required this.subtotal,
    required this.platformFee,
    required this.serviceFee,
    required this.totalAmount,
    required this.paymentMethod,
    required this.paymentStatus,
    this.stripePaymentIntentId,
    this.providerNotes,
    this.customerNotes,
    this.cancellationReason,
    this.providerLat,
    this.providerLng,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.selectedAddressId,
    this.vehicleCount = 1,
    this.serviceCount = 1,
    this.itemsSubtotal = 0.0,
    this.mobileFee = 0.0,
    this.discountAmount = 0.0,
    this.provider,
    this.offering,
    this.bookingItems,
  });

  factory CarServiceBooking.fromMap(Map<String, dynamic> map) {
    return CarServiceBooking(
      id: map['id'] as String,
      bookingNumber: map['booking_number'] as String,
      customerId: map['customer_id'] as String,
      providerId: map['provider_id'] as String,
      offeringId: map['offering_id'] as String,
      status: CarServiceBookingStatus.fromString(
        map['status'] as String? ?? 'pending',
      ),
      scheduledAt: DateTime.parse(map['scheduled_at'] as String),
      serviceAddress: map['service_address'] as String,
      serviceLat: parseDouble(map['service_lat']),
      serviceLng: parseDouble(map['service_lng']),
      vehicleMake: map['vehicle_make'] as String?,
      vehicleModel: map['vehicle_model'] as String?,
      vehicleColor: map['vehicle_color'] as String?,
      vehiclePlate: map['vehicle_plate'] as String?,
      subtotal: parseDoubleRequired(map['subtotal']),
      platformFee: parseDoubleRequired(map['platform_fee']),
      serviceFee: parseDoubleRequired(map['service_fee']),
      totalAmount: parseDoubleRequired(map['total_amount']),
      paymentMethod: CarServicePaymentMethod.fromString(
        map['payment_method'] as String? ?? 'card',
      ),
      paymentStatus: CarServicePaymentStatus.fromString(
        map['payment_status'] as String? ?? 'pending',
      ),
      stripePaymentIntentId: map['stripe_payment_intent_id'] as String?,
      providerNotes: map['provider_notes'] as String?,
      customerNotes: map['customer_notes'] as String?,
      cancellationReason: map['cancellation_reason'] as String?,
      providerLat: parseDouble(map['provider_lat']),
      providerLng: parseDouble(map['provider_lng']),
      startedAt: map['started_at'] != null
          ? DateTime.parse(map['started_at'] as String)
          : null,
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      selectedAddressId: map['selected_address_id'] as String?,
      vehicleCount: (map['vehicle_count'] as int?) ?? 1,
      serviceCount: (map['service_count'] as int?) ?? 1,
      itemsSubtotal: parseDoubleRequired(map['items_subtotal']),
      mobileFee: parseDoubleRequired(map['mobile_fee']),
      discountAmount: parseDoubleRequired(map['discount_amount']),
      provider: map['provider'] != null
          ? CarServiceProvider.fromMap(map['provider'] as Map<String, dynamic>)
          : null,
      offering: map['offering'] != null
          ? CarServiceOffering.fromMap(map['offering'] as Map<String, dynamic>)
          : null,
      bookingItems: map['booking_items'] != null
          ? (map['booking_items'] as List<dynamic>)
              .map((i) => ServiceBookingItem.fromMap(i as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'booking_number': bookingNumber,
    'customer_id': customerId,
    'provider_id': providerId,
    'offering_id': offeringId,
    'status': status.toDbString(),
    'scheduled_at': scheduledAt.toIso8601String(),
    'service_address': serviceAddress,
    'service_lat': serviceLat,
    'service_lng': serviceLng,
    'vehicle_make': vehicleMake,
    'vehicle_model': vehicleModel,
    'vehicle_color': vehicleColor,
    'vehicle_plate': vehiclePlate,
    'subtotal': subtotal,
    'platform_fee': platformFee,
    'service_fee': serviceFee,
    'total_amount': totalAmount,
    'payment_method': paymentMethod.name,
    'payment_status': paymentStatus.name,
    'stripe_payment_intent_id': stripePaymentIntentId,
    'provider_notes': providerNotes,
    'customer_notes': customerNotes,
    'cancellation_reason': cancellationReason,
    'provider_lat': providerLat,
    'provider_lng': providerLng,
    'started_at': startedAt?.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  CarServiceBooking copyWith({
    String? id,
    String? bookingNumber,
    String? customerId,
    String? providerId,
    String? offeringId,
    CarServiceBookingStatus? status,
    DateTime? scheduledAt,
    String? serviceAddress,
    double? serviceLat,
    double? serviceLng,
    String? vehicleMake,
    String? vehicleModel,
    String? vehicleColor,
    String? vehiclePlate,
    double? subtotal,
    double? platformFee,
    double? serviceFee,
    double? totalAmount,
    CarServicePaymentMethod? paymentMethod,
    CarServicePaymentStatus? paymentStatus,
    String? stripePaymentIntentId,
    String? providerNotes,
    String? customerNotes,
    String? cancellationReason,
    double? providerLat,
    double? providerLng,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? selectedAddressId,
    int? vehicleCount,
    int? serviceCount,
    double? itemsSubtotal,
    double? mobileFee,
    double? discountAmount,
    CarServiceProvider? provider,
    CarServiceOffering? offering,
    List<ServiceBookingItem>? bookingItems,
  }) {
    return CarServiceBooking(
      id: id ?? this.id,
      bookingNumber: bookingNumber ?? this.bookingNumber,
      customerId: customerId ?? this.customerId,
      providerId: providerId ?? this.providerId,
      offeringId: offeringId ?? this.offeringId,
      status: status ?? this.status,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      serviceAddress: serviceAddress ?? this.serviceAddress,
      serviceLat: serviceLat ?? this.serviceLat,
      serviceLng: serviceLng ?? this.serviceLng,
      vehicleMake: vehicleMake ?? this.vehicleMake,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleColor: vehicleColor ?? this.vehicleColor,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      subtotal: subtotal ?? this.subtotal,
      platformFee: platformFee ?? this.platformFee,
      serviceFee: serviceFee ?? this.serviceFee,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      stripePaymentIntentId: stripePaymentIntentId ?? this.stripePaymentIntentId,
      providerNotes: providerNotes ?? this.providerNotes,
      customerNotes: customerNotes ?? this.customerNotes,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      providerLat: providerLat ?? this.providerLat,
      providerLng: providerLng ?? this.providerLng,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      selectedAddressId: selectedAddressId ?? this.selectedAddressId,
      vehicleCount: vehicleCount ?? this.vehicleCount,
      serviceCount: serviceCount ?? this.serviceCount,
      itemsSubtotal: itemsSubtotal ?? this.itemsSubtotal,
      mobileFee: mobileFee ?? this.mobileFee,
      discountAmount: discountAmount ?? this.discountAmount,
      provider: provider ?? this.provider,
      offering: offering ?? this.offering,
      bookingItems: bookingItems ?? this.bookingItems,
    );
  }

  bool get isActive => ![
    CarServiceBookingStatus.completed,
    CarServiceBookingStatus.cancelled,
    CarServiceBookingStatus.noShow,
  ].contains(status);

  bool get canBeCancelled => [
    CarServiceBookingStatus.pending,
    CarServiceBookingStatus.confirmed,
  ].contains(status);
}
