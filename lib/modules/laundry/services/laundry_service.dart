import 'dart:io';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/index.dart';
import '../../../utils/app_logger.dart';
import '../../../services/loyalty_service.dart';

class LaundryInsufficientBalanceException implements Exception {
  final double required;
  final double available;
  const LaundryInsufficientBalanceException(this.required, this.available);
  @override
  String toString() =>
      'Insufficient wallet balance. Required: \$$required, Available: \$$available';
}

class LaundryAuthException implements Exception {
  final String message;
  const LaundryAuthException(this.message);
  @override
  String toString() => message;
}

class LaundryService {
  final SupabaseClient _supabase;

  LaundryService({required SupabaseClient supabase}) : _supabase = supabase;

  String get _uid {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw const LaundryAuthException('Not authenticated');
    return id;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MASTER SERVICE CATALOGUE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<LaundryServiceType>> getServiceCatalogue() async {
    try {
      final rows = await _supabase
          .from('laundry_services')
          .select()
          .eq('is_active', true)
          .order('sort_order');
      return (rows as List)
          .map((r) => LaundryServiceType.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('getServiceCatalogue: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROVIDERS — Customer browsing
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<LaundryProvider>> getActiveProviders({String? query}) async {
    var q = _supabase
        .from('laundry_providers')
        .select(
          '*, laundry_pricing(*), laundry_provider_services(*, laundry_services(*))',
        )
        .eq('is_active', true)
        .eq('status', 'active');

    if (query != null && query.isNotEmpty) {
      q = q.ilike('business_name', '%$query%');
    }

    final rows = await q.order('rating', ascending: false).limit(50);
    return (rows as List)
        .map((r) => LaundryProvider.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<LaundryProvider?> getProviderById(String id) async {
    try {
      final row = await _supabase
          .from('laundry_providers')
          .select('*, laundry_pricing(*), laundry_provider_services(*, laundry_services(*))')
          .eq('id', id)
          .single();
      return LaundryProvider.fromMap(row);
    } catch (e) {
      AppLogger.error('getProviderById: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MY PROVIDER PROFILE (provider role)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<LaundryProvider?> getMyProviderProfile() async {
    try {
      final rows = await _supabase
          .from('laundry_providers')
          .select('*, laundry_pricing(*), laundry_provider_services(*, laundry_services(*))')
          .eq('user_id', _uid)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      return LaundryProvider.fromMap(rows.first);
    } catch (e) {
      AppLogger.error('getMyProviderProfile: $e');
      return null;
    }
  }

  Future<LaundryProvider> createProviderProfile({
    required String businessName,
    String? description,
    String? phone,
    String? email,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    final row = await _supabase
        .from('laundry_providers')
        .insert({
          'user_id':       _uid,
          'business_name': businessName,
          'description':   description,
          'phone':         phone,
          'email':         email,
          'address':       address,
          'latitude':      latitude,
          'longitude':     longitude,
          'status':        'pending',
          'onboarding_step': 1,
        })
        .select()
        .single();
    return LaundryProvider.fromMap(row);
  }

  Future<LaundryProvider> updateProviderProfile(
    String providerId,
    Map<String, dynamic> updates,
  ) async {
    updates['updated_at'] = DateTime.now().toIso8601String();
    final row = await _supabase
        .from('laundry_providers')
        .update(updates)
        .eq('id', providerId)
        .select()
        .single();
    return LaundryProvider.fromMap(row);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROVIDER SERVICES (pricing per service)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<LaundryProviderService>> getProviderServices(String providerId) async {
    final rows = await _supabase
        .from('laundry_provider_services')
        .select('*, laundry_services(*)')
        .eq('provider_id', providerId)
        .order('created_at');
    return (rows as List)
        .map((r) => LaundryProviderService.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> upsertProviderService(
    String providerId,
    String serviceId,
    Map<String, dynamic> pricing,
  ) async {
    await _supabase.from('laundry_provider_services').upsert({
      'provider_id': providerId,
      'service_id':  serviceId,
      ...pricing,
      'updated_at':  DateTime.now().toIso8601String(),
    }, onConflict: 'provider_id,service_id');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMAGE UPLOAD
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> uploadProviderLogo(String providerId, File file) async {
    try {
      final bytes = await file.readAsBytes();
      final ext   = file.path.split('.').last.toLowerCase();
      final path  = '$providerId/logo.$ext';
      await _supabase.storage
          .from('laundry-provider-logos')
          .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
      return _supabase.storage.from('laundry-provider-logos').getPublicUrl(path);
    } catch (e) {
      AppLogger.error('uploadProviderLogo: $e');
      return null;
    }
  }

  Future<String?> uploadOrderPhoto(String bookingId, File file, String photoType) async {
    try {
      final bytes = await file.readAsBytes();
      final ext   = file.path.split('.').last.toLowerCase();
      final ts    = DateTime.now().millisecondsSinceEpoch;
      final path  = '$bookingId/$photoType/$ts.$ext';
      final bucket = photoType == 'before'
          ? 'laundry-before-photos'
          : photoType == 'after'
              ? 'laundry-after-photos'
              : 'laundry-order-photos';
      await _supabase.storage
          .from(bucket)
          .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
      final url = _supabase.storage.from(bucket).getPublicUrl(path);
      // persist to DB
      await _supabase.from('laundry_photos').insert({
        'booking_id':   bookingId,
        'uploader_id':  _uid,
        'photo_type':   photoType,
        'url':          url,
      });
      return url;
    } catch (e) {
      AppLogger.error('uploadOrderPhoto: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOOKINGS — Customer side
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<LaundryBooking>> getMyBookings() async {
    try {
      final rows = await _supabase
          .from('laundry_bookings')
          .select('*, laundry_providers(business_name, logo_url), laundry_booking_items(*)')
          .eq('customer_id', _uid)
          .order('created_at', ascending: false)
          .limit(50);
      return (rows as List)
          .map((r) => LaundryBooking.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('getMyBookings: $e');
      return [];
    }
  }

  Future<LaundryBooking?> getBookingById(String id) async {
    try {
      final row = await _supabase
          .from('laundry_bookings')
          .select('''
            *,
            laundry_providers(business_name, logo_url, phone),
            laundry_booking_items(*),
            laundry_status_history(*),
            laundry_photos(*)
          ''')
          .eq('id', id)
          .single();

      // Sort status history chronologically in Dart (PostgREST doesn't allow
      // ordering inside nested embeds).
      if (row['laundry_status_history'] is List) {
        (row['laundry_status_history'] as List).sort((a, b) =>
            (a['created_at'] as String).compareTo(b['created_at'] as String));
      }

      return LaundryBooking.fromMap(row);
    } catch (e) {
      AppLogger.error('getBookingById: $e');
      return null;
    }
  }

  Future<LaundryBooking> createBooking({
    required String providerId,
    required String pickupAddress,
    double? pickupLat,
    double? pickupLng,
    required String returnAddress,
    double? returnLat,
    double? returnLng,
    required DateTime pickupDate,
    required String pickupTimeSlot,
    double? estimatedWeightKg,
    int estimatedBags = 1,
    String? customerNotes,
    String? specialInstructions,
    double? estimatedTotal,
    double pickupFee = 0,
    double deliveryFee = 0,
    String paymentMethod = 'card',
    required List<Map<String, dynamic>> items,
  }) async {
    // 1. Insert booking
    final bookingNumber = 'LDY-${100000 + Random().nextInt(899999)}';
    final bookingRow = await _supabase
        .from('laundry_bookings')
        .insert({
          'booking_number':      bookingNumber,
          'customer_id':         _uid,
          'provider_id':         providerId,
          'status':              'new_request',
          'pickup_address':      pickupAddress,
          'pickup_latitude':     pickupLat,
          'pickup_longitude':    pickupLng,
          'return_address':      returnAddress,
          'return_latitude':     returnLat,
          'return_longitude':    returnLng,
          'pickup_date':         pickupDate.toIso8601String().split('T').first,
          'pickup_time_slot':    pickupTimeSlot,
          'estimated_weight_kg': estimatedWeightKg,
          'estimated_bags':      estimatedBags,
          'customer_notes':      customerNotes,
          'special_instructions':specialInstructions,
          'estimated_total':     estimatedTotal,
          'pickup_fee':          pickupFee,
          'delivery_fee':        deliveryFee,
          'payment_method':      paymentMethod,
        })
        .select()
        .single();

    final bookingId = bookingRow['id'] as String;

    // 2. Insert line items
    if (items.isNotEmpty) {
      final itemRows = items.map((i) => {...i, 'booking_id': bookingId}).toList();
      await _supabase.from('laundry_booking_items').insert(itemRows);
    }

    return LaundryBooking.fromMap(bookingRow);
  }

  Future<void> cancelBooking(String bookingId, String reason) async {
    // 1. Read booking BEFORE cancelling to capture amounts for refund
    final bookingRow = await _supabase
        .from('laundry_bookings')
        .select('reserved_amount, pickup_fee, customer_id, booking_number')
        .eq('id', bookingId)
        .eq('customer_id', _uid)
        .maybeSingle();

    // 2. Mark booking cancelled — do NOT zero reserved_amount here;
    // the releaseReservation RPC reads it to compute the refund and zeroes it
    // itself after a successful wallet update.
    await _supabase.from('laundry_bookings').update({
      'status':              'cancelled',
      'cancellation_reason': reason,
      'cancelled_by':        'customer',
      'cancelled_at':        DateTime.now().toIso8601String(),
    }).eq('id', bookingId).eq('customer_id', _uid);

    if (bookingRow == null) return;

    final customerId    = (bookingRow['customer_id']    as String?) ?? _uid;
    final reserved      = (bookingRow['reserved_amount'] as num?)?.toDouble() ?? 0.0;
    final pickupFee     = (bookingRow['pickup_fee']      as num?)?.toDouble() ?? 0.0;
    final bookingNumber = (bookingRow['booking_number']  as String?) ?? bookingId;

    // Fetch booked service names for the transaction description
    final itemRows = await _supabase
        .from('laundry_booking_items')
        .select('service_name')
        .eq('booking_id', bookingId);
    final servicesSummary = (itemRows as List).isNotEmpty
        ? (itemRows).map((r) => r['service_name'] as String).join(', ')
        : 'Laundry Service';

    // Refund = reserved_amount if set, otherwise fall back to pickup_fee.
    final refundAmount = reserved > 0 ? reserved : pickupFee;
    if (refundAmount <= 0) return;

    // 3. Try the server-side RPC (atomic)
    bool rpcOk = false;
    try {
      await releaseReservation(bookingId,
          reason: 'customer_cancelled', cancellationFee: 0);
      rpcOk = true;
    } catch (e) {
      AppLogger.error('releaseReservation RPC failed, using direct fallback: $e');
    }

    // 4. Direct fallback — runs if RPC unavailable or fails
    if (!rpcOk) {
      await _directRefundWallet(
        customerId:      customerId,
        bookingNumber:   bookingNumber,
        servicesSummary: servicesSummary,
        refundAmount:    refundAmount,
      );
    }
  }

  /// Credits [refundAmount] back to the user's wallet.
  /// Releases from reserved_balance first; any remainder is added to balance.
  Future<void> _directRefundWallet({
    required String customerId,
    required String bookingNumber,
    required String servicesSummary,
    required double refundAmount,
  }) async {
    try {
      final walletRow = await _supabase
          .from('wallets')
          .select('balance, reserved_balance')
          .eq('user_id', customerId)
          .maybeSingle();

      if (walletRow == null) {
        AppLogger.error('_directRefundWallet: wallet not found for $customerId');
        return;
      }

      final currentBalance  = (walletRow['balance']          as num?)?.toDouble() ?? 0.0;
      final currentReserved = (walletRow['reserved_balance'] as num?)?.toDouble() ?? 0.0;

      final fromReserved = min(currentReserved, refundAmount).clamp(0.0, double.infinity);
      final toBalance    = refundAmount - fromReserved;

      await _supabase.from('wallets').update({
        'reserved_balance': (currentReserved - fromReserved).clamp(0.0, double.infinity),
        'balance':          currentBalance + toBalance,
        'updated_at':       DateTime.now().toIso8601String(),
      }).eq('user_id', customerId);

      // order_id FK references orders, not laundry_bookings — store NULL.
      await _supabase.from('wallet_transactions').insert({
        'user_id':     customerId,
        'amount':      refundAmount,
        'type':        'refund',
        'status':      'completed',
        'description': '$servicesSummary · $bookingNumber — refunded to wallet',
        'order_id':    null,
      });

      AppLogger.info(
          '_directRefundWallet: refunded \$$refundAmount to $customerId '
          '(released_reserved=\$$fromReserved, credited_balance=\$$toBalance)');
    } catch (e) {
      AppLogger.error('_directRefundWallet failed: $e');
    }
  }

  Future<void> approvePrice(String bookingId) async {
    await _supabase.from('laundry_bookings').update({
      'price_approved_by_customer': true,
      'status':                     'price_confirmed',
    }).eq('id', bookingId).eq('customer_id', _uid);
  }

  Future<void> submitReview(LaundryReview review) async {
    await _supabase.from('laundry_reviews').upsert(review.toMap(),
        onConflict: 'booking_id');
    // also update booking rating columns
    await _supabase.from('laundry_bookings').update({
      'customer_rating_provider': review.providerRating,
      'customer_rating_driver':   review.driverRating,
      'customer_review':          review.reviewText,
    }).eq('id', review.bookingId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOOKINGS — Provider side
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<LaundryBooking>> getProviderBookings(
    String providerId, {
    List<String>? statuses,
  }) async {
    try {
      var q = _supabase
          .from('laundry_bookings')
          .select('*, users(name, phone), laundry_booking_items(*)')
          .eq('provider_id', providerId);

      if (statuses != null && statuses.isNotEmpty) {
        q = q.inFilter('status', statuses);
      }

      final rows = await q.order('created_at', ascending: false).limit(100);
      return (rows as List)
          .map((r) => LaundryBooking.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('getProviderBookings: $e');
      return [];
    }
  }

  Future<void> updateBookingStatus(
    String bookingId,
    LaundryBookingStatus status, {
    String? note,
    String? customerId,
  }) async {
    await _supabase.from('laundry_bookings').update({
      'status':     status.dbString,
      'updated_at': DateTime.now().toIso8601String(),
      if (status == LaundryBookingStatus.completed)
        'completed_at': DateTime.now().toIso8601String(),
    }).eq('id', bookingId);

    // Status history is auto-inserted by DB trigger, but we add note manually if given
    if (note != null) {
      await _supabase.from('laundry_status_history').insert({
        'booking_id': bookingId,
        'status':     status.dbString,
        'actor_id':   _uid,
        'actor_role': 'provider',
        'note':       note,
      });
    }

    // Settle financials when booking completes (releases reservation, splits commission)
    if (status == LaundryBookingStatus.completed) {
      try {
        final result = await settleBooking(bookingId);
        // Award loyalty points to the customer based on amount charged
        final charged = (result['charged'] as num?)?.toDouble() ?? 0.0;
        if (charged > 0) {
          final bookingRow = await _supabase
              .from('laundry_bookings')
              .select('customer_id')
              .eq('id', bookingId)
              .maybeSingle();
          final custId = bookingRow?['customer_id'] as String?;
          if (custId != null) {
            await LoyaltyService(_supabase).earnPoints(
              userId:      custId,
              orderId:     bookingId,
              orderTotal:  charged,
              description: 'Earned from laundry service',
            );
          }
        }
      } catch (e) {
        AppLogger.error('settleBooking failed for $bookingId: $e');
      }
    }

    // Push notification to customer
    final notif = _laundryStatusNotification(status);
    if (notif != null && customerId != null) {
      _sendCustomerNotification(
        customerId: customerId,
        title: notif.$1,
        body:  notif.$2,
        type:  'laundry_status',
        bookingId: bookingId,
      );
    }
  }

  /// Returns (title, body) for a status, or null if no notification needed.
  static (String, String)? _laundryStatusNotification(LaundryBookingStatus s) {
    switch (s) {
      case LaundryBookingStatus.accepted:
        return ('Booking Accepted!', 'Your laundry provider has accepted your order. We\'ll be there soon!');
      case LaundryBookingStatus.waitingForPickup:
        return ('Driver On the Way', 'A driver is heading to collect your laundry.');
      case LaundryBookingStatus.pickedUpFromCustomer:
        return ('Laundry Collected', 'Your laundry has been picked up and is on its way to us.');
      case LaundryBookingStatus.receivedAtLaundry:
        return ('Received at Laundry', 'We\'ve got your laundry! Processing will begin shortly.');
      case LaundryBookingStatus.weighed:
        return ('Price Ready — Action Needed', 'We\'ve weighed your laundry. Please review and approve the final price.');
      case LaundryBookingStatus.washingCleaning:
        return ('Washing in Progress', 'Your clothes are in the wash — sit back and relax!');
      case LaundryBookingStatus.qualityCheck:
        return ('Almost Ready', 'Quality check in progress. Your fresh laundry is nearly done!');
      case LaundryBookingStatus.readyForDelivery:
        return ('Ready for Delivery!', 'Your clean laundry is folded and ready. Delivery coming soon!');
      case LaundryBookingStatus.outForDelivery:
        return ('Out for Delivery!', 'Your fresh laundry is on its way back to you.');
      case LaundryBookingStatus.completed:
        return ('Laundry Delivered!', 'Your order is complete. Enjoy your fresh, clean clothes!');
      case LaundryBookingStatus.cancelled:
        return ('Booking Cancelled', 'Your laundry booking has been cancelled and any payment refunded.');
      default:
        return null;
    }
  }

  void _sendCustomerNotification({
    required String customerId,
    required String title,
    required String body,
    required String type,
    required String bookingId,
  }) {
    // Fire-and-forget — never block the status update on notification delivery.
    Future(() async {
      try {
        await _supabase.functions.invoke(
          'send-fcm-notification',
          body: {
            'topic': 'customer_$customerId',
            'title': title,
            'body':  body,
            'data': {
              'type':       type,
              'booking_id': bookingId,
              'user_id':    customerId,
            },
          },
        );
      } catch (e) {
        AppLogger.error('Laundry push notification failed: $e');
      }
    });
  }

  Future<void> recordWeight(
    String bookingId, {
    required double weightKg,
    required double actualTotal,
    String? photoUrl,
    String? notes,
  }) async {
    // 1. Record the weigh-in
    await _supabase.from('laundry_weights').insert({
      'booking_id':   bookingId,
      'weight_kg':    weightKg,
      'recorded_by':  _uid,
      'photo_url':    photoUrl,
      'notes':        notes,
    });
    // 2. Update booking
    await _supabase.from('laundry_bookings').update({
      'actual_weight_kg': weightKg,
      'actual_total':     actualTotal,
      'status':           'weighed',
    }).eq('id', bookingId);
  }

  Future<void> updateActualPrice(String bookingId, double actualTotal) async {
    await _supabase.from('laundry_bookings').update({
      'actual_total': actualTotal,
      'status':       'weighed',
    }).eq('id', bookingId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DRIVER side
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<LaundryBooking>> getDriverAssignedBookings() async {
    try {
      final assignments = await _supabase
          .from('laundry_driver_assignments')
          .select('booking_id')
          .eq('driver_id', _uid)
          .not('status', 'in', '(completed,cancelled)');

      final ids = (assignments as List)
          .map((a) => a['booking_id'] as String)
          .toList();
      if (ids.isEmpty) return [];

      final rows = await _supabase
          .from('laundry_bookings')
          .select('*, laundry_providers(business_name, address, latitude, longitude), users(name, phone)')
          .inFilter('id', ids);

      return (rows as List)
          .map((r) => LaundryBooking.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('getDriverAssignedBookings: $e');
      return [];
    }
  }

  Future<void> updateDriverAssignmentStatus(
    String bookingId,
    LaundryDriverLeg leg,
    String status, {
    String? proofUrl,
  }) async {
    final updates = <String, dynamic>{
      'status':     status,
      if (status == 'accepted')     'accepted_at':  DateTime.now().toIso8601String(),
      if (status == 'completed')    'completed_at': DateTime.now().toIso8601String(),
      if (proofUrl != null && leg == LaundryDriverLeg.pickup)
        'pickup_proof_url': proofUrl,
      if (proofUrl != null && leg == LaundryDriverLeg.returnLeg)
        'dropoff_proof_url': proofUrl,
    };

    await _supabase
        .from('laundry_driver_assignments')
        .update(updates)
        .eq('booking_id', bookingId)
        .eq('driver_id', _uid)
        .eq('leg', leg == LaundryDriverLeg.pickup ? 'pickup' : 'return');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADMIN
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<LaundryProvider>> getAllProviders({LaundryProviderStatus? status}) async {
    var q = _supabase.from('laundry_providers').select('*, laundry_pricing(*)');
    if (status != null) q = q.eq('status', status.dbString);
    final rows = await q.order('created_at', ascending: false);
    return (rows as List)
        .map((r) => LaundryProvider.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> approveProvider(String providerId) async {
    await _supabase.from('laundry_providers').update({
      'status':      'active',
      'is_active':   true,
      'is_verified': true,
      'updated_at':  DateTime.now().toIso8601String(),
    }).eq('id', providerId);
  }

  Future<void> rejectProvider(String providerId, String reason) async {
    await _supabase.from('laundry_providers').update({
      'status':           'rejected',
      'rejection_reason': reason,
      'updated_at':       DateTime.now().toIso8601String(),
    }).eq('id', providerId);
  }

  Future<void> suspendProvider(String providerId) async {
    await _supabase.from('laundry_providers').update({
      'status':    'suspended',
      'is_active': false,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', providerId);
  }

  Future<List<LaundryBooking>> getAllBookings({
    String? status,
    DateTime? from,
    DateTime? to,
  }) async {
    var q = _supabase
        .from('laundry_bookings')
        .select('*, laundry_providers(business_name), users(name)');
    if (status != null) q = q.eq('status', status);
    if (from != null)   q = q.gte('created_at', from.toIso8601String());
    if (to != null)     q = q.lte('created_at', to.toIso8601String());
    final rows = await q.order('created_at', ascending: false).limit(200);
    return (rows as List)
        .map((r) => LaundryBooking.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getAdminAnalytics() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();

    final todayRows = await _supabase
        .from('laundry_bookings')
        .select('id')
        .gte('created_at', todayStart);

    final monthRows = await _supabase
        .from('laundry_bookings')
        .select('actual_total, estimated_total')
        .gte('created_at', monthStart);

    final completedMonth = await _supabase
        .from('laundry_bookings')
        .select('actual_total')
        .eq('status', 'completed')
        .gte('created_at', monthStart);

    double revenue = 0;
    for (final r in (completedMonth as List)) {
      revenue += (r['actual_total'] as num?)?.toDouble() ?? 0;
    }

    return {
      'orders_today':   (todayRows as List).length,
      'orders_month':   (monthRows as List).length,
      'revenue_month':  revenue,
    };
  }

  Future<void> assignDriver(
    String bookingId,
    String driverId,
    LaundryDriverLeg leg,
  ) async {
    await _supabase.from('laundry_driver_assignments').upsert({
      'booking_id':   bookingId,
      'driver_id':    driverId,
      'leg':          leg == LaundryDriverLeg.pickup ? 'pickup' : 'return',
      'status':       leg == LaundryDriverLeg.pickup
          ? 'assigned_pickup'
          : 'assigned_return',
      'assigned_at':  DateTime.now().toIso8601String(),
    }, onConflict: 'booking_id,leg');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAYMENT & COMMISSION  (migration 117)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Reserve wallet funds at booking creation.
  /// Throws [LaundryInsufficientBalanceException] if balance is too low.
  Future<Map<String, dynamic>> reservePayment({
    required String bookingId,
    required double laundryAmount,
    double pickupFee = 0,
    double serviceFee = 0,
  }) async {
    final res = await _supabase.rpc('reserve_laundry_payment', params: {
      'p_booking_id':     bookingId,
      'p_laundry_amount': laundryAmount,
      'p_pickup_fee':     pickupFee,
      'p_service_fee':    serviceFee,
    });
    final data = res as Map<String, dynamic>;
    if (data['success'] != true) {
      throw LaundryInsufficientBalanceException(
        (data['required'] as num?)?.toDouble() ?? 0,
        (data['available'] as num?)?.toDouble() ?? 0,
      );
    }
    return data;
  }

  /// Adjust reservation when provider records actual weight / final price.
  Future<Map<String, dynamic>> adjustReservation({
    required String bookingId,
    required double newLaundryAmount,
  }) async {
    final res = await _supabase.rpc('adjust_laundry_reservation', params: {
      'p_booking_id':      bookingId,
      'p_new_laundry_amt': newLaundryAmount,
    });
    final data = res as Map<String, dynamic>;
    if (data['success'] != true) {
      throw LaundryInsufficientBalanceException(
        (data['extra_needed'] as num?)?.toDouble() ?? 0,
        (data['available'] as num?)?.toDouble() ?? 0,
      );
    }
    return data;
  }

  /// Reserve return delivery fee when booking is ready_for_delivery.
  Future<Map<String, dynamic>> reserveReturnFee({
    required String bookingId,
    required double returnFee,
  }) async {
    final res = await _supabase.rpc('reserve_laundry_return_fee', params: {
      'p_booking_id': bookingId,
      'p_return_fee': returnFee,
    });
    final data = res as Map<String, dynamic>;
    if (data['success'] != true) {
      throw LaundryInsufficientBalanceException(
        (data['required'] as num?)?.toDouble() ?? 0,
        (data['available'] as num?)?.toDouble() ?? 0,
      );
    }
    return data;
  }

  /// Final settlement — splits commission, records payouts. Idempotent.
  Future<Map<String, dynamic>> settleBooking(String bookingId) async {
    final res = await _supabase.rpc('settle_laundry_booking', params: {
      'p_booking_id': bookingId,
    });
    return res as Map<String, dynamic>;
  }

  /// Release reservation on cancellation.
  Future<void> releaseReservation(String bookingId, {
    String reason = 'cancelled',
    double cancellationFee = 0,
  }) async {
    await _supabase.rpc('release_laundry_reservation', params: {
      'p_booking_id':       bookingId,
      'p_reason':           reason,
      'p_cancellation_fee': cancellationFee,
    });
  }

  // ── Driver Jobs (migration 117) ──────────────────────────────────────────

  Future<List<LaundryDriverJob>> getDriverJobsForBooking(String bookingId) async {
    try {
      final rows = await _supabase
          .from('laundry_driver_jobs')
          .select('*, users(name, phone, profile_image_url)')
          .eq('booking_id', bookingId)
          .order('created_at');
      return (rows as List)
          .map((r) => LaundryDriverJob.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('getDriverJobsForBooking: $e');
      return [];
    }
  }

  Future<String> createDriverJob({
    required String bookingId,
    required String jobType,
    required String pickupAddress,
    double? pickupLat,
    double? pickupLng,
    required String dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
    double deliveryFee = 0,
    double driverPayout = 0,
  }) async {
    final res = await _supabase.rpc('create_laundry_driver_job', params: {
      'p_booking_id':      bookingId,
      'p_job_type':        jobType,
      'p_pickup_address':  pickupAddress,
      'p_pickup_lat':      pickupLat,
      'p_pickup_lng':      pickupLng,
      'p_dropoff_address': dropoffAddress,
      'p_dropoff_lat':     dropoffLat,
      'p_dropoff_lng':     dropoffLng,
      'p_delivery_fee':    deliveryFee,
      'p_driver_payout':   driverPayout,
    });
    return res as String;
  }

  Future<Map<String, dynamic>> acceptDriverJob(String jobId) async {
    final res = await _supabase.rpc('accept_laundry_driver_job', params: {
      'p_job_id': jobId,
    });
    return res as Map<String, dynamic>;
  }

  // ── Commission settings (admin) ──────────────────────────────────────────

  Future<Map<String, dynamic>?> getDefaultCommissionSettings() async {
    try {
      final rows = await _supabase
          .from('laundry_commission_settings')
          .select()
          .eq('is_default', true)
          .eq('is_active', true)
          .limit(1);
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (e) {
      AppLogger.error('getDefaultCommissionSettings: $e');
      return null;
    }
  }

  Future<void> upsertCommissionSettings({
    String? providerId,
    required String commissionType,
    required double commissionValue,
    required double customerServiceFee,
    required bool appliesToDeliveryFee,
    bool isDefault = false,
  }) async {
    await _supabase.from('laundry_commission_settings').upsert({
      'provider_id':             providerId,
      'commission_type':         commissionType,
      'commission_value':        commissionValue,
      'customer_service_fee':    customerServiceFee,
      'applies_to_delivery_fee': appliesToDeliveryFee,
      'is_default':              isDefault,
      'is_active':               true,
      'updated_at':              DateTime.now().toIso8601String(),
    });
  }

  // ── Payment splits (admin / provider) ───────────────────────────────────

  Future<LaundryPaymentSplit?> getPaymentSplit(String bookingId) async {
    try {
      final row = await _supabase
          .from('laundry_payment_splits')
          .select()
          .eq('booking_id', bookingId)
          .single();
      return LaundryPaymentSplit.fromMap(row);
    } catch (e) {
      AppLogger.error('getPaymentSplit: $e');
      return null;
    }
  }

  Future<List<LaundryPaymentSplit>> getProviderPaymentSplits(String providerId) async {
    try {
      final rows = await _supabase
          .from('laundry_payment_splits')
          .select()
          .eq('provider_id', providerId)
          .order('created_at', ascending: false)
          .limit(100);
      return (rows as List)
          .map((r) => LaundryPaymentSplit.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('getProviderPaymentSplits: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getAdminCommissionAnalytics() async {
    try {
      final row = await _supabase
          .from('laundry_admin_analytics')
          .select()
          .single();
      return row;
    } catch (e) {
      AppLogger.error('getAdminCommissionAnalytics: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>?> getProviderEarnings(String providerId) async {
    try {
      final rows = await _supabase
          .from('laundry_provider_earnings')
          .select()
          .eq('provider_id', providerId)
          .limit(1);
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (e) {
      AppLogger.error('getProviderEarnings: $e');
      return null;
    }
  }

  // Wallet balance is read via the unified walletBalanceStreamProvider.
}

