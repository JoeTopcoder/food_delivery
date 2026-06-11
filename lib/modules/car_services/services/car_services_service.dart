import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/app_constants.dart';
import '../models/index.dart';
import '../../../services/loyalty_service.dart';
import '../../../utils/app_logger.dart';

// Re-export so screens only need one service import
export 'customer_vehicle_service.dart';

class CarServicesAuthException implements Exception {
  final String message;
  const CarServicesAuthException(this.message);
  @override
  String toString() => message;
}

class CarServicesService {
  final SupabaseClient _supabase;

  CarServicesService({required SupabaseClient supabase}) : _supabase = supabase;

  // =========================================================================
  // CATEGORIES
  // =========================================================================

  Future<List<CarServiceCategory>> getCategories() async {
    try {
      final response = await _supabase
          .from('car_service_categories')
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      return (response as List<dynamic>)
          .map((row) => CarServiceCategory.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  // =========================================================================
  // PROVIDERS
  // =========================================================================

  Future<List<CarServiceProvider>> getProviders({
    String? categoryId,
    double? lat,
    double? lng,
  }) async {
    try {
      // Lightweight query for the list view — only fields needed for the card.
      // No nested category join on offerings, no images. Detail screen loads those.
      final response = await _supabase
          .from('car_service_providers')
          .select(
            'id, user_id, business_name, bio, profile_image_url,'
            ' rating, total_reviews, total_bookings, is_active, is_verified,'
            ' service_area_radius_km, base_location_lat, base_location_lng,'
            ' base_location_address, stripe_payouts_enabled,'
            ' created_at, updated_at,'
            // Minimal offering fields needed for card display and category filter
            ' offerings:car_service_offerings(id, provider_id, category_id, name, duration_minutes, base_price, is_active)',
          )
          .eq('is_active', true)
          .order('rating', ascending: false)
          .limit(30);

      var providers = (response as List<dynamic>)
          .map((row) => CarServiceProvider.fromMap(row as Map<String, dynamic>))
          .toList();

      // Client-side category filter (offerings already loaded, no extra round-trip)
      if (categoryId != null) {
        providers = providers
            .where((p) =>
                p.offerings?.any((o) => o.categoryId == categoryId) ?? false)
            .toList();
      }

      return providers;
    } catch (e) {
      rethrow;
    }
  }

  Future<CarServiceProvider?> getProviderById(String providerId) async {
    try {
      final response = await _supabase
          .from('car_service_providers')
          .select(
            '*, '
            'offerings:car_service_offerings(*, category:car_service_categories(*)), '
            'images:car_service_provider_images(*)',
          )
          .eq('id', providerId)
          .maybeSingle();

      if (response == null) return null;
      return CarServiceProvider.fromMap(response);
    } catch (e) {
      rethrow;
    }
  }

  Future<CarServiceProvider?> getMyProviderProfile() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw const CarServicesAuthException('User not authenticated');
      }

      final response = await _supabase
          .from('car_service_providers')
          .select(
            '*, '
            'offerings:car_service_offerings(*, category:car_service_categories(*)), '
            'images:car_service_provider_images(*)',
          )
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;
      return CarServiceProvider.fromMap(response);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateProviderProfile(
    String providerId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _supabase
          .from('car_service_providers')
          .update(data)
          .eq('id', providerId);
    } catch (e) {
      rethrow;
    }
  }

  /// Creates or updates the current user's provider profile.
  Future<CarServiceProvider> createOrUpdateProviderProfile(
    Map<String, dynamic> data,
  ) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw const CarServicesAuthException('User not authenticated');

    final existing = await _supabase
        .from('car_service_providers')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();

    final now = DateTime.now().toIso8601String();
    Map<String, dynamic> row;
    if (existing != null) {
      row = await _supabase
          .from('car_service_providers')
          .update({...data, 'updated_at': now})
          .eq('user_id', userId)
          .select('*')
          .single();
    } else {
      row = await _supabase
          .from('car_service_providers')
          .insert({
            'user_id': userId,
            'rating': 0.0,
            'total_reviews': 0,
            'total_bookings': 0,
            'is_active': false,
            'is_verified': false,
            'is_approved': false,
            'is_suspended': false,
            'approval_status': 'pending',
            'stripe_payouts_enabled': false,
            'service_area_radius_km': 10.0,
            ...data,
            'created_at': now,
            'updated_at': now,
          })
          .select('*')
          .single();
    }

    return CarServiceProvider.fromMap(row);
  }

  /// All providers pending admin approval.
  Future<List<CarServiceProvider>> getPendingProviders() async {
    final response = await _supabase
        .from('car_service_providers')
        .select('*')
        .eq('approval_status', 'pending')
        .order('created_at', ascending: true);

    return (response as List<dynamic>)
        .map((row) => CarServiceProvider.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// All providers for admin view (including inactive/rejected).
  Future<List<CarServiceProvider>> getAllProvidersAdmin() async {
    final response = await _supabase
        .from('car_service_providers')
        .select(
          '*, offerings:car_service_offerings(id, name, base_price, is_active)',
        )
        .order('created_at', ascending: false);

    return (response as List<dynamic>)
        .map((row) => CarServiceProvider.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> approveProvider(String providerId) async {
    await _supabase.from('car_service_providers').update({
      'approval_status': 'approved',
      'is_approved': true,
      'is_active': true,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', providerId);
  }

  Future<void> rejectProvider(String providerId, String reason) async {
    await _supabase.from('car_service_providers').update({
      'approval_status': 'rejected',
      'is_approved': false,
      'is_active': false,
      'rejection_reason': reason,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', providerId);
  }

  Future<void> suspendProvider(String providerId) async {
    await _supabase.from('car_service_providers').update({
      'is_suspended': true,
      'is_active': false,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', providerId);
  }

  Future<void> reactivateProvider(String providerId) async {
    await _supabase.from('car_service_providers').update({
      'is_suspended': false,
      'is_active': true,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', providerId);
  }

  // =========================================================================
  // OFFERINGS
  // =========================================================================

  Future<List<CarServiceOffering>> getOfferingsByProvider(
    String providerId,
  ) async {
    try {
      final response = await _supabase
          .from('car_service_offerings')
          .select('*, category:car_service_categories(*)')
          .eq('provider_id', providerId)
          .eq('is_active', true)
          .order('base_price', ascending: true);

      return (response as List<dynamic>)
          .map((row) => CarServiceOffering.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<CarServiceOffering> createOffering(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _supabase
          .from('car_service_offerings')
          .insert(data)
          .select('*, category:car_service_categories(*)')
          .single();

      return CarServiceOffering.fromMap(response);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateOffering(
    String offeringId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _supabase
          .from('car_service_offerings')
          .update(data)
          .eq('id', offeringId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteOffering(String offeringId) async {
    try {
      await _supabase
          .from('car_service_offerings')
          .delete()
          .eq('id', offeringId);
    } catch (e) {
      rethrow;
    }
  }

  // =========================================================================
  // BOOKINGS
  // =========================================================================

  Future<CarServiceBooking> createBooking({
    required String providerId,
    required String offeringId,
    required DateTime scheduledAt,
    required String serviceAddress,
    double? serviceLat,
    double? serviceLng,
    String? vehicleMake,
    String? vehicleModel,
    String? vehicleColor,
    String? vehiclePlate,
    String paymentMethod = 'card',
    String? stripePaymentIntentId,
    String? customerNotes,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw const CarServicesAuthException('User not authenticated');
      }

      // Fetch offering to get base_price for fee calculation
      final offeringRow = await _supabase
          .from('car_service_offerings')
          .select('base_price')
          .eq('id', offeringId)
          .single();

      final subtotal = (offeringRow['base_price'] as num).toDouble();
      final platformFee = double.parse(
        (subtotal * AppConstants.carServicePlatformFeePct).toStringAsFixed(2),
      );
      final serviceFee = AppConstants.calculateServiceFee(subtotal);
      final totalAmount = subtotal + platformFee + serviceFee;

      final payload = <String, dynamic>{
        'customer_id': userId,
        'provider_id': providerId,
        'offering_id': offeringId,
        'status': 'pending',
        'scheduled_at': scheduledAt.toIso8601String(),
        'service_address': serviceAddress,
        if (serviceLat != null) 'service_lat': serviceLat,
        if (serviceLng != null) 'service_lng': serviceLng,
        if (vehicleMake != null) 'vehicle_make': vehicleMake,
        if (vehicleModel != null) 'vehicle_model': vehicleModel,
        if (vehicleColor != null) 'vehicle_color': vehicleColor,
        if (vehiclePlate != null) 'vehicle_plate': vehiclePlate,
        'subtotal': subtotal,
        'platform_fee': platformFee,
        'service_fee': serviceFee,
        'total_amount': totalAmount,
        'payment_method': paymentMethod,
        'payment_status': 'pending',
        if (stripePaymentIntentId != null)
          'stripe_payment_intent_id': stripePaymentIntentId,
        if (customerNotes != null) 'customer_notes': customerNotes,
      };

      final response = await _supabase
          .from('car_service_bookings')
          .insert(payload)
          .select(
            '*, '
            'provider:car_service_providers(*), '
            'offering:car_service_offerings(*, category:car_service_categories(*))',
          )
          .single();

      return CarServiceBooking.fromMap(response);
    } catch (e) {
      rethrow;
    }
  }

  Future<List<CarServiceBooking>> getMyBookings() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw const CarServicesAuthException('User not authenticated');
      }

      final response = await _supabase
          .from('car_service_bookings')
          .select(
            '*, '
            'provider:car_service_providers(*), '
            'offering:car_service_offerings(*, category:car_service_categories(*))',
          )
          .eq('customer_id', userId)
          .order('scheduled_at', ascending: false);

      return (response as List<dynamic>)
          .map((row) => CarServiceBooking.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<CarServiceBooking>> getProviderBookings(
    String providerId, {
    String? status,
  }) async {
    try {
      var query = _supabase
          .from('car_service_bookings')
          .select(
            '*, '
            'provider:car_service_providers(*), '
            'offering:car_service_offerings(*, category:car_service_categories(*))',
          )
          .eq('provider_id', providerId);

      if (status != null) {
        query = query.eq('status', status);
      }

      final response = await query.order('scheduled_at', ascending: true);

      return (response as List<dynamic>)
          .map((row) => CarServiceBooking.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<CarServiceBooking?> getBookingById(String bookingId) async {
    try {
      final response = await _supabase
          .from('car_service_bookings')
          .select(
            '*, '
            'provider:car_service_providers(*), '
            'offering:car_service_offerings(*, category:car_service_categories(*))',
          )
          .eq('id', bookingId)
          .maybeSingle();

      if (response == null) return null;
      return CarServiceBooking.fromMap(response);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateBookingStatus(
    String bookingId,
    String status, {
    String? notes,
  }) async {
    try {
      final data = <String, dynamic>{'status': status};
      if (notes != null) data['provider_notes'] = notes;
      if (status == 'in_progress') {
        data['started_at'] = DateTime.now().toIso8601String();
      } else if (status == 'completed') {
        data['completed_at'] = DateTime.now().toIso8601String();
      }

      await _supabase
          .from('car_service_bookings')
          .update(data)
          .eq('id', bookingId);

      // Award loyalty points when booking is completed
      if (status == 'completed') {
        try {
          final row = await _supabase
              .from('car_service_bookings')
              .select('customer_id, total_price')
              .eq('id', bookingId)
              .maybeSingle();
          final custId = row?['customer_id'] as String?;
          final total  = (row?['total_price'] as num?)?.toDouble() ?? 0.0;
          if (custId != null && total > 0) {
            await LoyaltyService(_supabase).earnPoints(
              userId:      custId,
              orderId:     bookingId,
              orderTotal:  total,
              description: 'Earned from car service',
            );
          }
        } catch (e) {
          AppLogger.error('Car service loyalty points failed: $e');
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateBookingPayment(
    String bookingId, {
    required String paymentStatus,
    String? stripePaymentIntentId,
  }) async {
    try {
      final data = <String, dynamic>{'payment_status': paymentStatus};
      if (stripePaymentIntentId != null) {
        data['stripe_payment_intent_id'] = stripePaymentIntentId;
      }
      await _supabase
          .from('car_service_bookings')
          .update(data)
          .eq('id', bookingId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateProviderLocation(
    String bookingId,
    double lat,
    double lng,
  ) async {
    try {
      await _supabase.from('car_service_bookings').update({
        'provider_lat': lat,
        'provider_lng': lng,
      }).eq('id', bookingId);
    } catch (e) {
      rethrow;
    }
  }

  // =========================================================================
  // REVIEWS
  // =========================================================================

  Future<void> submitReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw const CarServicesAuthException('User not authenticated');
      }

      // Fetch booking to get provider_id
      final bookingRow = await _supabase
          .from('car_service_bookings')
          .select('provider_id')
          .eq('id', bookingId)
          .single();

      await _supabase.from('car_service_reviews').insert({
        'booking_id': bookingId,
        'customer_id': userId,
        'provider_id': bookingRow['provider_id'],
        'rating': rating,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<List<CarServiceReview>> getProviderReviews(
    String providerId,
  ) async {
    try {
      final response = await _supabase
          .from('car_service_reviews')
          .select()
          .eq('provider_id', providerId)
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((row) => CarServiceReview.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  // =========================================================================
  // AVAILABILITY
  // =========================================================================

  Future<List<ProviderAvailability>> getProviderAvailability(
    String providerId,
  ) async {
    try {
      final response = await _supabase
          .from('car_service_provider_availability')
          .select()
          .eq('provider_id', providerId)
          .order('day_of_week', ascending: true);

      return (response as List<dynamic>)
          .map((row) =>
              ProviderAvailability.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> upsertAvailability(List<ProviderAvailability> slots) async {
    try {
      final data = slots.map((s) => s.toMap()).toList();
      await _supabase
          .from('car_service_provider_availability')
          .upsert(data, onConflict: 'provider_id,day_of_week');
    } catch (e) {
      rethrow;
    }
  }

  // =========================================================================
  // REAL-TIME STREAMS
  // =========================================================================

  Stream<CarServiceBooking> watchBooking(String bookingId) {
    return _supabase
        .from('car_service_bookings')
        .stream(primaryKey: ['id'])
        .eq('id', bookingId)
        .map((rows) {
          if (rows.isEmpty) {
            throw Exception('Booking $bookingId not found in stream');
          }
          return CarServiceBooking.fromMap(rows.first);
        });
  }

  Stream<List<CarServiceBooking>> watchProviderBookings(String providerId) {
    return _supabase
        .from('car_service_bookings')
        .stream(primaryKey: ['id'])
        .eq('provider_id', providerId)
        .order('scheduled_at', ascending: true)
        .map((rows) =>
            rows.map((row) => CarServiceBooking.fromMap(row)).toList());
  }

  // =========================================================================
  // MULTI-VEHICLE / MULTI-SERVICE BOOKING
  // =========================================================================

  /// Creates one parent booking and N service_booking_items rows.
  /// [groups] maps each vehicle to the list of offerings selected for it.
  /// Returns the created booking with bookingItems populated.
  Future<CarServiceBooking> createMultiBooking({
    required String providerId,
    required List<VehicleServiceGroup> groups,
    required DateTime scheduledAt,
    required String serviceAddress,
    double? serviceLat,
    double? serviceLng,
    String? selectedAddressId,
    double mobileFee = 0.0,
    String paymentMethod = 'card',
    String? customerNotes,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw const CarServicesAuthException('Not authenticated');

    // Validate all services belong to provider
    final allOfferingIds = groups.expand((g) => g.services.map((s) => s.id)).toList();
    if (allOfferingIds.isEmpty) throw Exception('No services selected');

    // Server-side price recalculation
    final offeringRows = await _supabase
        .from('car_service_offerings')
        .select('id, base_price, is_active')
        .eq('provider_id', providerId)
        .inFilter('id', allOfferingIds);
    final priceMap = <String, double>{
      for (final r in offeringRows as List)
        r['id'] as String: (r['base_price'] as num).toDouble(),
    };

    double itemsSubtotal = 0;
    int serviceCount = 0;
    for (final g in groups) {
      for (final s in g.services) {
        itemsSubtotal += priceMap[s.id] ?? s.basePrice;
        serviceCount++;
      }
    }
    itemsSubtotal += mobileFee;

    final platformFee = double.parse((itemsSubtotal * AppConstants.carServicePlatformFeePct).toStringAsFixed(2));
    final svcFee = AppConstants.carServiceServiceFee;
    final totalAmount = itemsSubtotal + platformFee + svcFee;

    // First selected offering for backwards compat
    final firstOffering = groups.first.services.first;

    // Insert parent booking
    final payload = <String, dynamic>{
      'customer_id': userId,
      'provider_id': providerId,
      'offering_id': firstOffering.id,
      'status': 'pending',
      'scheduled_at': scheduledAt.toIso8601String(),
      'service_address': serviceAddress,
      if (serviceLat != null) 'service_lat': serviceLat,
      if (serviceLng != null) 'service_lng': serviceLng,
      // Backwards-compat: first vehicle info
      'vehicle_make': groups.first.vehicle.make,
      'vehicle_model': groups.first.vehicle.model,
      'vehicle_color': groups.first.vehicle.color,
      'vehicle_plate': groups.first.vehicle.licensePlate,
      'subtotal': itemsSubtotal,
      'items_subtotal': itemsSubtotal,
      'mobile_fee': mobileFee,
      'platform_fee': platformFee,
      'service_fee': svcFee,
      'total_amount': totalAmount,
      'vehicle_count': groups.length,
      'service_count': serviceCount,
      'payment_method': paymentMethod,
      'payment_status': 'pending',
      if (selectedAddressId != null) 'selected_address_id': selectedAddressId,
      if (customerNotes != null) 'customer_notes': customerNotes,
    };

    final bookingRow = await _supabase
        .from('car_service_bookings')
        .insert(payload)
        .select('*, provider:car_service_providers(*), offering:car_service_offerings(*, category:car_service_categories(*))')
        .single();

    final booking = CarServiceBooking.fromMap(bookingRow);

    // Insert booking items
    final itemPayloads = <Map<String, dynamic>>[];
    for (final g in groups) {
      for (final svc in g.services) {
        final serverPrice = priceMap[svc.id] ?? svc.basePrice;
        itemPayloads.add({
          'booking_id': booking.id,
          'service_id': svc.id,
          'vehicle_id': g.vehicle.id,
          'service_name_snapshot': svc.name,
          'vehicle_snapshot': g.vehicle.toSnapshot(),
          'base_price': serverPrice,
          'vehicle_price': 0,
          'add_on_price': 0,
          'quantity': 1,
          'line_total': serverPrice,
        });
      }
    }

    final itemRows = await _supabase
        .from('service_booking_items')
        .insert(itemPayloads)
        .select();

    final items = (itemRows as List)
        .map((r) => ServiceBookingItem.fromMap(r as Map<String, dynamic>))
        .toList();

    return booking.copyWith(bookingItems: items);
  }

  Future<List<ServiceBookingItem>> getBookingItems(String bookingId) async {
    final rows = await _supabase
        .from('service_booking_items')
        .select()
        .eq('booking_id', bookingId)
        .order('created_at', ascending: true);
    return (rows as List).map((r) => ServiceBookingItem.fromMap(r as Map<String, dynamic>)).toList();
  }

  // =========================================================================
  // PROVIDER IMAGES
  // =========================================================================

  static const _bucket = 'car-service-images';

  /// Uploads a file to Supabase Storage and returns the public URL.
  Future<String> _uploadToStorage(File file, String path) async {
    final bytes = await file.readAsBytes();
    final ext = file.path.split('.').last.toLowerCase();
    final storagePath = '$path.${ext.isEmpty ? "jpg" : ext}';
    await _supabase.storage
        .from(_bucket)
        .uploadBinary(storagePath, bytes, fileOptions: const FileOptions(upsert: true));
    return _supabase.storage.from(_bucket).getPublicUrl(storagePath);
  }

  /// Uploads and sets the provider's profile image. Returns the new URL.
  Future<String> uploadProviderProfileImage(String providerId, File file) async {
    final userId = _supabase.auth.currentUser?.id ?? 'unknown';
    final url = await _uploadToStorage(file, '$userId/$providerId/profile');
    await _supabase.from('car_service_providers').update({
      'profile_image_url': url,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', providerId);
    return url;
  }

  /// Uploads and sets the provider's banner image. Returns the new URL.
  Future<String> uploadProviderBannerImage(String providerId, File file) async {
    final userId = _supabase.auth.currentUser?.id ?? 'unknown';
    final url = await _uploadToStorage(file, '$userId/$providerId/banner');
    await _supabase.from('car_service_providers').update({
      'banner_image_url': url,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', providerId);
    return url;
  }

  /// Uploads a gallery image and inserts a row in car_service_provider_images.
  Future<CarServiceProviderImage> uploadProviderGalleryImage(
    String providerId,
    File file, {
    bool isPrimary = false,
  }) async {
    final userId = _supabase.auth.currentUser?.id ?? 'unknown';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final url = await _uploadToStorage(file, '$userId/$providerId/gallery/$ts');

    final row = await _supabase
        .from('car_service_provider_images')
        .insert({
          'provider_id': providerId,
          'image_url': url,
          'is_primary': isPrimary,
          'sort_order': ts,
        })
        .select()
        .single();

    return CarServiceProviderImage.fromMap(row);
  }

  /// Deletes a gallery image row (storage object is left; public bucket, low cost).
  Future<void> deleteProviderGalleryImage(String imageId) async {
    await _supabase.from('car_service_provider_images').delete().eq('id', imageId);
  }

  /// Sets one gallery image as the primary and clears others.
  Future<void> setPrimaryGalleryImage(String providerId, String imageId) async {
    await _supabase
        .from('car_service_provider_images')
        .update({'is_primary': false})
        .eq('provider_id', providerId);
    await _supabase
        .from('car_service_provider_images')
        .update({'is_primary': true})
        .eq('id', imageId);
  }
}
