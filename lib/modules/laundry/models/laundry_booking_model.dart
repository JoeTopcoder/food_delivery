enum LaundryBookingStatus {
  newRequest,
  accepted,
  pickupDriverSearching,
  pickupDriverAssigned,
  waitingForPickup,
  pickedUpFromCustomer,
  receivedAtLaundry,
  weighed,
  priceConfirmed,
  washingCleaning,
  qualityCheck,
  readyForDelivery,
  returnPaymentRequired,
  returnDriverSearching,
  returnDriverAssigned,
  pickedUpForReturn,
  outForDelivery,
  completed,
  cancelled,
  disputed;

  static LaundryBookingStatus fromString(String v) {
    const map = {
      'new_request':              LaundryBookingStatus.newRequest,
      'accepted':                 LaundryBookingStatus.accepted,
      'pickup_driver_searching':  LaundryBookingStatus.pickupDriverSearching,
      'pickup_driver_assigned':   LaundryBookingStatus.pickupDriverAssigned,
      'waiting_for_pickup':       LaundryBookingStatus.waitingForPickup,
      'picked_up_from_customer':  LaundryBookingStatus.pickedUpFromCustomer,
      'received_at_laundry':      LaundryBookingStatus.receivedAtLaundry,
      'weighed':                  LaundryBookingStatus.weighed,
      'price_confirmed':          LaundryBookingStatus.priceConfirmed,
      'washing_cleaning':         LaundryBookingStatus.washingCleaning,
      'quality_check':            LaundryBookingStatus.qualityCheck,
      'ready_for_delivery':       LaundryBookingStatus.readyForDelivery,
      'return_payment_required':  LaundryBookingStatus.returnPaymentRequired,
      'return_driver_searching':  LaundryBookingStatus.returnDriverSearching,
      'return_driver_assigned':   LaundryBookingStatus.returnDriverAssigned,
      'picked_up_for_return':     LaundryBookingStatus.pickedUpForReturn,
      'out_for_delivery':         LaundryBookingStatus.outForDelivery,
      'completed':                LaundryBookingStatus.completed,
      'cancelled':                LaundryBookingStatus.cancelled,
      'disputed':                 LaundryBookingStatus.disputed,
    };
    return map[v] ?? LaundryBookingStatus.newRequest;
  }

  String get dbString {
    const map = {
      LaundryBookingStatus.newRequest:            'new_request',
      LaundryBookingStatus.accepted:              'accepted',
      LaundryBookingStatus.pickupDriverSearching: 'pickup_driver_searching',
      LaundryBookingStatus.pickupDriverAssigned:  'pickup_driver_assigned',
      LaundryBookingStatus.waitingForPickup:      'waiting_for_pickup',
      LaundryBookingStatus.pickedUpFromCustomer:  'picked_up_from_customer',
      LaundryBookingStatus.receivedAtLaundry:     'received_at_laundry',
      LaundryBookingStatus.weighed:               'weighed',
      LaundryBookingStatus.priceConfirmed:        'price_confirmed',
      LaundryBookingStatus.washingCleaning:       'washing_cleaning',
      LaundryBookingStatus.qualityCheck:          'quality_check',
      LaundryBookingStatus.readyForDelivery:      'ready_for_delivery',
      LaundryBookingStatus.returnPaymentRequired: 'return_payment_required',
      LaundryBookingStatus.returnDriverSearching: 'return_driver_searching',
      LaundryBookingStatus.returnDriverAssigned:  'return_driver_assigned',
      LaundryBookingStatus.pickedUpForReturn:     'picked_up_for_return',
      LaundryBookingStatus.outForDelivery:        'out_for_delivery',
      LaundryBookingStatus.completed:             'completed',
      LaundryBookingStatus.cancelled:             'cancelled',
      LaundryBookingStatus.disputed:              'disputed',
    };
    return map[this]!;
  }

  String get displayLabel {
    const map = {
      LaundryBookingStatus.newRequest:            'New Request',
      LaundryBookingStatus.accepted:              'Accepted',
      LaundryBookingStatus.pickupDriverSearching: 'Finding Pickup Driver',
      LaundryBookingStatus.pickupDriverAssigned:  'Pickup Driver Assigned',
      LaundryBookingStatus.waitingForPickup:      'Waiting for Pickup',
      LaundryBookingStatus.pickedUpFromCustomer:  'Laundry Collected',
      LaundryBookingStatus.receivedAtLaundry:     'Received at Laundry',
      LaundryBookingStatus.weighed:               'Weighed — Price Ready',
      LaundryBookingStatus.priceConfirmed:        'Price Confirmed',
      LaundryBookingStatus.washingCleaning:       'Washing / Cleaning',
      LaundryBookingStatus.qualityCheck:          'Quality Check',
      LaundryBookingStatus.readyForDelivery:      'Ready for Delivery',
      LaundryBookingStatus.returnPaymentRequired: 'Top-Up Required',
      LaundryBookingStatus.returnDriverSearching: 'Finding Return Driver',
      LaundryBookingStatus.returnDriverAssigned:  'Return Driver Assigned',
      LaundryBookingStatus.pickedUpForReturn:     'Picked Up for Return',
      LaundryBookingStatus.outForDelivery:        'Out for Delivery',
      LaundryBookingStatus.completed:             'Completed',
      LaundryBookingStatus.cancelled:             'Cancelled',
      LaundryBookingStatus.disputed:              'Disputed',
    };
    return map[this]!;
  }

  bool get isTerminal =>
      this == LaundryBookingStatus.completed ||
      this == LaundryBookingStatus.cancelled;

  bool get isActive =>
      !isTerminal && this != LaundryBookingStatus.disputed;

  bool get needsPaymentAction =>
      this == LaundryBookingStatus.weighed ||
      this == LaundryBookingStatus.returnPaymentRequired;

  /// Returns 0–19 for a linear progress indicator
  int get stepIndex => LaundryBookingStatus.values.indexOf(this);
}

// ─── Booking ──────────────────────────────────────────────────────────────────

class LaundryBooking {
  final String id;
  final String bookingNumber;
  final String customerId;
  final String providerId;
  final LaundryBookingStatus status;

  // Addresses
  final String pickupAddress;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final String returnAddress;
  final double? returnLatitude;
  final double? returnLongitude;

  // Schedule
  final DateTime pickupDate;
  final String pickupTimeSlot;
  final DateTime? returnDate;
  final String? returnTimeSlot;

  // Estimates
  final double? estimatedWeightKg;
  final int estimatedBags;
  final String? customerNotes;
  final String? specialInstructions;

  // Actuals
  final double? actualWeightKg;
  final int? actualBags;
  final String? providerNotes;

  // Pricing
  final double? estimatedTotal;
  final double? actualTotal;
  final double pickupFee;
  final double deliveryFee;
  final double platformFee;
  final double discountAmount;
  final String currency;

  // Payment
  final String paymentMethod;
  final String? stripePaymentIntentId;
  final String paymentStatus;
  final bool priceApprovedByCustomer;

  // Ratings
  final int? customerRatingProvider;
  final int? customerRatingDriver;
  final String? customerReview;

  // Payment extras (from migration 117)
  final double reservedAmount;
  final double returnDeliveryFee;
  final double customerServiceFee;
  final double? finalTotal;
  final Map<String, dynamic>? commissionSnapshot;

  // Timestamps
  final String? cancellationReason;
  final DateTime? cancelledAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Joined data
  final List<LaundryBookingItem>? items;
  final List<LaundryStatusEntry>? statusHistory;
  final List<LaundryPhoto>? photos;
  final String? providerName;
  final String? providerLogoUrl;
  final String? customerName;

  const LaundryBooking({
    required this.id,
    required this.bookingNumber,
    required this.customerId,
    required this.providerId,
    required this.status,
    required this.pickupAddress,
    this.pickupLatitude,
    this.pickupLongitude,
    required this.returnAddress,
    this.returnLatitude,
    this.returnLongitude,
    required this.pickupDate,
    required this.pickupTimeSlot,
    this.returnDate,
    this.returnTimeSlot,
    this.estimatedWeightKg,
    this.estimatedBags = 1,
    this.customerNotes,
    this.specialInstructions,
    this.actualWeightKg,
    this.actualBags,
    this.providerNotes,
    this.estimatedTotal,
    this.actualTotal,
    this.pickupFee = 0,
    this.deliveryFee = 0,
    this.platformFee = 0,
    this.discountAmount = 0,
    this.currency = 'USD',
    this.paymentMethod = 'card',
    this.stripePaymentIntentId,
    this.paymentStatus = 'pending',
    this.priceApprovedByCustomer = false,
    this.customerRatingProvider,
    this.customerRatingDriver,
    this.customerReview,
    this.reservedAmount = 0,
    this.returnDeliveryFee = 0,
    this.customerServiceFee = 0,
    this.finalTotal,
    this.commissionSnapshot,
    this.cancellationReason,
    this.cancelledAt,
    this.completedAt,
    required this.createdAt,
    this.updatedAt,
    this.items,
    this.statusHistory,
    this.photos,
    this.providerName,
    this.providerLogoUrl,
    this.customerName,
  });

  factory LaundryBooking.fromMap(Map<String, dynamic> m) {
    final rawItems   = m['laundry_booking_items'] as List<dynamic>?;
    final rawHistory = m['laundry_status_history'] as List<dynamic>?;
    final rawPhotos  = m['laundry_photos'] as List<dynamic>?;
    final provider   = m['laundry_providers'] as Map<String, dynamic>?;
    final customer   = m['users'] as Map<String, dynamic>?;

    return LaundryBooking(
      id:             m['id'] as String,
      bookingNumber:  m['booking_number'] as String,
      customerId:     m['customer_id'] as String,
      providerId:     m['provider_id'] as String,
      status:         LaundryBookingStatus.fromString(m['status'] as String),
      pickupAddress:  m['pickup_address'] as String? ?? '',
      pickupLatitude: (m['pickup_latitude'] as num?)?.toDouble(),
      pickupLongitude:(m['pickup_longitude'] as num?)?.toDouble(),
      returnAddress:  m['return_address'] as String? ?? '',
      returnLatitude: (m['return_latitude'] as num?)?.toDouble(),
      returnLongitude:(m['return_longitude'] as num?)?.toDouble(),
      pickupDate:     DateTime.parse(m['pickup_date'] as String),
      pickupTimeSlot: m['pickup_time_slot'] as String? ?? '',
      returnDate:     m['return_date'] != null ? DateTime.parse(m['return_date'] as String) : null,
      returnTimeSlot: m['return_time_slot'] as String?,
      estimatedWeightKg: (m['estimated_weight_kg'] as num?)?.toDouble(),
      estimatedBags:  m['estimated_bags'] as int? ?? 1,
      customerNotes:  m['customer_notes'] as String?,
      specialInstructions: m['special_instructions'] as String?,
      actualWeightKg: (m['actual_weight_kg'] as num?)?.toDouble(),
      actualBags:     m['actual_bags'] as int?,
      providerNotes:  m['provider_notes'] as String?,
      estimatedTotal: (m['estimated_total'] as num?)?.toDouble(),
      actualTotal:    (m['actual_total'] as num?)?.toDouble(),
      pickupFee:      (m['pickup_fee'] as num?)?.toDouble() ?? 0,
      deliveryFee:    (m['delivery_fee'] as num?)?.toDouble() ?? 0,
      platformFee:    (m['platform_fee'] as num?)?.toDouble() ?? 0,
      discountAmount: (m['discount_amount'] as num?)?.toDouble() ?? 0,
      currency:       m['currency'] as String? ?? 'USD',
      paymentMethod:  m['payment_method'] as String? ?? 'card',
      stripePaymentIntentId: m['stripe_payment_intent_id'] as String?,
      paymentStatus:  m['payment_status'] as String? ?? 'pending',
      priceApprovedByCustomer: m['price_approved_by_customer'] as bool? ?? false,
      customerRatingProvider: m['customer_rating_provider'] as int?,
      customerRatingDriver:   m['customer_rating_driver'] as int?,
      customerReview:         m['customer_review'] as String?,
      reservedAmount:         (m['reserved_amount'] as num?)?.toDouble() ?? 0,
      returnDeliveryFee:      (m['return_delivery_fee'] as num?)?.toDouble() ?? 0,
      customerServiceFee:     (m['customer_service_fee'] as num?)?.toDouble() ?? 0,
      finalTotal:             (m['final_total'] as num?)?.toDouble(),
      commissionSnapshot:     m['commission_snapshot'] as Map<String, dynamic>?,
      cancellationReason: m['cancellation_reason'] as String?,
      cancelledAt:  m['cancelled_at'] != null ? DateTime.parse(m['cancelled_at'] as String) : null,
      completedAt:  m['completed_at'] != null ? DateTime.parse(m['completed_at'] as String) : null,
      createdAt:    DateTime.parse(m['created_at'] as String),
      updatedAt:    m['updated_at'] != null ? DateTime.parse(m['updated_at'] as String) : null,
      items: rawItems?.map((i) => LaundryBookingItem.fromMap(i as Map<String, dynamic>)).toList(),
      statusHistory: rawHistory?.map((h) => LaundryStatusEntry.fromMap(h as Map<String, dynamic>)).toList(),
      photos: rawPhotos?.map((p) => LaundryPhoto.fromMap(p as Map<String, dynamic>)).toList(),
      providerName:    provider?['business_name'] as String?,
      providerLogoUrl: provider?['logo_url'] as String?,
      customerName:    customer?['name'] as String?,
    );
  }

  /// Displayed price: actual if available, else estimated
  double? get displayTotal => actualTotal ?? estimatedTotal;

  LaundryBooking copyWith({
    LaundryBookingStatus? status,
    double? actualTotal,
    double? actualWeightKg,
    bool? priceApprovedByCustomer,
    double? reservedAmount,
    double? returnDeliveryFee,
    double? finalTotal,
    Map<String, dynamic>? commissionSnapshot,
  }) =>
    LaundryBooking(
      id: id, bookingNumber: bookingNumber, customerId: customerId,
      providerId: providerId, status: status ?? this.status,
      pickupAddress: pickupAddress, returnAddress: returnAddress,
      pickupDate: pickupDate, pickupTimeSlot: pickupTimeSlot,
      estimatedBags: estimatedBags, pickupFee: pickupFee,
      deliveryFee: deliveryFee, platformFee: platformFee,
      discountAmount: discountAmount, currency: currency,
      paymentMethod: paymentMethod, paymentStatus: paymentStatus,
      priceApprovedByCustomer: priceApprovedByCustomer ?? this.priceApprovedByCustomer,
      actualTotal: actualTotal ?? this.actualTotal,
      actualWeightKg: actualWeightKg ?? this.actualWeightKg,
      estimatedTotal: estimatedTotal, createdAt: createdAt,
      reservedAmount: reservedAmount ?? this.reservedAmount,
      returnDeliveryFee: returnDeliveryFee ?? this.returnDeliveryFee,
      customerServiceFee: customerServiceFee,
      finalTotal: finalTotal ?? this.finalTotal,
      commissionSnapshot: commissionSnapshot ?? this.commissionSnapshot,
    );
}

// ─── BookingItem ──────────────────────────────────────────────────────────────

class LaundryBookingItem {
  final String id;
  final String bookingId;
  final String serviceId;
  final String serviceName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String? notes;

  const LaundryBookingItem({
    required this.id,
    required this.bookingId,
    required this.serviceId,
    required this.serviceName,
    this.quantity = 1,
    this.unitPrice = 0,
    this.totalPrice = 0,
    this.notes,
  });

  factory LaundryBookingItem.fromMap(Map<String, dynamic> m) => LaundryBookingItem(
    id:          m['id'] as String,
    bookingId:   m['booking_id'] as String,
    serviceId:   m['service_id'] as String,
    serviceName: m['service_name'] as String,
    quantity:    m['quantity'] as int? ?? 1,
    unitPrice:   (m['unit_price'] as num?)?.toDouble() ?? 0,
    totalPrice:  (m['total_price'] as num?)?.toDouble() ?? 0,
    notes:       m['notes'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'booking_id':   bookingId,
    'service_id':   serviceId,
    'service_name': serviceName,
    'quantity':     quantity,
    'unit_price':   unitPrice,
    'total_price':  totalPrice,
    'notes':        notes,
  };
}

// ─── StatusEntry ──────────────────────────────────────────────────────────────

class LaundryStatusEntry {
  final String id;
  final String bookingId;
  final LaundryBookingStatus status;
  final String? actorId;
  final String? actorRole;
  final String? note;
  final DateTime createdAt;

  const LaundryStatusEntry({
    required this.id,
    required this.bookingId,
    required this.status,
    this.actorId,
    this.actorRole,
    this.note,
    required this.createdAt,
  });

  factory LaundryStatusEntry.fromMap(Map<String, dynamic> m) => LaundryStatusEntry(
    id:        m['id'] as String,
    bookingId: m['booking_id'] as String,
    status:    LaundryBookingStatus.fromString(m['status'] as String),
    actorId:   m['actor_id'] as String?,
    actorRole: m['actor_role'] as String?,
    note:      m['note'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}

// ─── Photo ────────────────────────────────────────────────────────────────────

class LaundryPhoto {
  final String id;
  final String bookingId;
  final String? uploaderId;
  final String photoType; // 'before' | 'after' | 'pickup_proof' | 'dropoff_proof' | 'customer_upload'
  final String url;
  final String? caption;
  final DateTime createdAt;

  const LaundryPhoto({
    required this.id,
    required this.bookingId,
    this.uploaderId,
    required this.photoType,
    required this.url,
    this.caption,
    required this.createdAt,
  });

  factory LaundryPhoto.fromMap(Map<String, dynamic> m) => LaundryPhoto(
    id:         m['id'] as String,
    bookingId:  m['booking_id'] as String,
    uploaderId: m['uploader_id'] as String?,
    photoType:  m['photo_type'] as String,
    url:        m['url'] as String,
    caption:    m['caption'] as String?,
    createdAt:  DateTime.parse(m['created_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'booking_id':  bookingId,
    'uploader_id': uploaderId,
    'photo_type':  photoType,
    'url':         url,
    'caption':     caption,
  };
}

// ─── Review ───────────────────────────────────────────────────────────────────

class LaundryReview {
  final String id;
  final String bookingId;
  final String customerId;
  final String providerId;
  final String? driverId;
  final int? providerRating;
  final int? driverRating;
  final String? reviewText;
  final String? providerResponse;
  final DateTime createdAt;

  const LaundryReview({
    required this.id,
    required this.bookingId,
    required this.customerId,
    required this.providerId,
    this.driverId,
    this.providerRating,
    this.driverRating,
    this.reviewText,
    this.providerResponse,
    required this.createdAt,
  });

  factory LaundryReview.fromMap(Map<String, dynamic> m) => LaundryReview(
    id:               m['id'] as String,
    bookingId:        m['booking_id'] as String,
    customerId:       m['customer_id'] as String,
    providerId:       m['provider_id'] as String,
    driverId:         m['driver_id'] as String?,
    providerRating:   m['provider_rating'] as int?,
    driverRating:     m['driver_rating'] as int?,
    reviewText:       m['review_text'] as String?,
    providerResponse: m['provider_response'] as String?,
    createdAt:        DateTime.parse(m['created_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'booking_id':      bookingId,
    'customer_id':     customerId,
    'provider_id':     providerId,
    'driver_id':       driverId,
    'provider_rating': providerRating,
    'driver_rating':   driverRating,
    'review_text':     reviewText,
  };
}

// ─── DriverAssignment ─────────────────────────────────────────────────────────

enum LaundryDriverLeg { pickup, returnLeg }

class LaundryDriverAssignment {
  final String id;
  final String bookingId;
  final String driverId;
  final LaundryDriverLeg leg;
  final String status;
  final DateTime assignedAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;
  final String? pickupProofUrl;
  final String? dropoffProofUrl;
  final String? driverNotes;

  // Joined
  final String? driverName;
  final String? driverPhone;
  final String? driverAvatarUrl;

  const LaundryDriverAssignment({
    required this.id,
    required this.bookingId,
    required this.driverId,
    required this.leg,
    required this.status,
    required this.assignedAt,
    this.acceptedAt,
    this.completedAt,
    this.pickupProofUrl,
    this.dropoffProofUrl,
    this.driverNotes,
    this.driverName,
    this.driverPhone,
    this.driverAvatarUrl,
  });

  factory LaundryDriverAssignment.fromMap(Map<String, dynamic> m) {
    final driver = m['users'] as Map<String, dynamic>?;
    return LaundryDriverAssignment(
      id:         m['id'] as String,
      bookingId:  m['booking_id'] as String,
      driverId:   m['driver_id'] as String,
      leg:        m['leg'] == 'pickup' ? LaundryDriverLeg.pickup : LaundryDriverLeg.returnLeg,
      status:     m['status'] as String,
      assignedAt: DateTime.parse(m['assigned_at'] as String),
      acceptedAt: m['accepted_at'] != null ? DateTime.parse(m['accepted_at'] as String) : null,
      completedAt: m['completed_at'] != null ? DateTime.parse(m['completed_at'] as String) : null,
      pickupProofUrl:  m['pickup_proof_url'] as String?,
      dropoffProofUrl: m['dropoff_proof_url'] as String?,
      driverNotes: m['driver_notes'] as String?,
      driverName:      driver?['name'] as String?,
      driverPhone:     driver?['phone'] as String?,
      driverAvatarUrl: driver?['profile_image_url'] as String?,
    );
  }
}
