import 'dart:async';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/index.dart';
import '../../../utils/app_logger.dart';
import '../../../config/app_constants.dart';

class RideAuthException implements Exception {
  final String message;
  const RideAuthException(this.message);
  @override
  String toString() => message;
}

class RideService {
  final SupabaseClient _supabase;

  RideService({required SupabaseClient supabase}) : _supabase = supabase;

  // ====================================================================
  // FARE CALCULATION
  // ====================================================================

  Future<Map<String, dynamic>> calculateRideFare({
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'calculate-ride-fare',
        body: {
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          'destination_lat': destinationLat,
          'destination_lng': destinationLng,
        },
      );

      AppLogger.info(
        'Fare calculation response: status=${response.status}, data=${response.data}',
      );

      if (response.status != 200) {
        final errorMsg = response.data is Map
            ? (response.data as Map)['error'] ?? response.data.toString()
            : response.data.toString();
        throw Exception(
          'Edge function returned status ${response.status}: $errorMsg',
        );
      }

      return response.data as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error(
        'Error calculating fare from edge function (using local fallback)',
        e,
      );
      return _calculateFareLocally(
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
      );
    }
  }

  Map<String, dynamic> _calculateFareLocally({
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
  }) {
    const double earthRadiusKm = 6371.0;
    final double dLat = _toRad(destinationLat - pickupLat);
    final double dLng = _toRad(destinationLng - pickupLng);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(pickupLat)) *
            math.cos(_toRad(destinationLat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final double distanceKm = earthRadiusKm * c;

    const double avgSpeedKmh = 30.0;
    final int estimatedMinutes = (distanceKm / avgSpeedKmh * 60).round();

    // USD pricing: $3.00 per mile, $8.00 minimum
    const double kmPerMile = 1.60934;
    final double distanceMiles = distanceKm / kmPerMile;
    const double perMileRate = 3.0;
    const double minimumFare = 8.0;
    const double platformFeeRate = 0.20;

    final double rawFare = distanceMiles * perMileRate;
    final double estimatedFare = rawFare < minimumFare ? minimumFare : rawFare;
    final double platformFee = estimatedFare * platformFeeRate;
    final double platformServiceFee = AppConstants.calculateServiceFee(estimatedFare);
    final double stripeFeePortion = AppConstants.calculateStripeFee(estimatedFare);

    return {
      'distance_km': double.parse(distanceKm.toStringAsFixed(2)),
      'distance_miles': double.parse(distanceMiles.toStringAsFixed(2)),
      'estimated_duration_minutes': estimatedMinutes,
      'estimated_fare': double.parse(estimatedFare.toStringAsFixed(2)),
      'platform_fee': double.parse(platformFee.toStringAsFixed(2)),
      'platform_service_fee': platformServiceFee,
      'stripe_fee_amount': stripeFeePortion,
      'per_mile_rate': perMileRate,
      'distance_fare': double.parse((distanceMiles * perMileRate).toStringAsFixed(2)),
      'currency': 'USD',
      'source': 'local',
    };
  }

  double _toRad(double deg) => deg * math.pi / 180.0;

  // ====================================================================
  // RIDE REQUEST MANAGEMENT
  // ====================================================================

  Future<Map<String, dynamic>> createRideRequest({
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String destinationAddress,
    required double destinationLat,
    required double destinationLng,
    required double distanceKm,
    required int estimatedDurationMinutes,
    required double estimatedFare,
    required double platformFee,
    required String paymentMethod,
    String? savedCardId,
    String? stripePaymentIntentId,
    DateTime? scheduledFor,
    bool isAirportPickup = false,
    bool isAirportDropoff = false,
    String? terminalInfo,
    double? airportSurcharge,
    double? platformServiceFee,
    double? stripeFeePortion,
  }) async {
    try {
      final token = await _freshToken();

      final body = <String, dynamic>{
        'pickup_address': pickupAddress,
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'destination_address': destinationAddress,
        'destination_lat': destinationLat,
        'destination_lng': destinationLng,
        'distance_km': distanceKm,
        'estimated_duration_minutes': estimatedDurationMinutes,
        'estimated_fare': estimatedFare,
        'platform_fee': platformFee,
        'payment_method': paymentMethod,
        'saved_card_id': savedCardId,
        if (stripePaymentIntentId != null) 'stripe_payment_intent_id': stripePaymentIntentId,
        if (scheduledFor != null) 'scheduled_for': scheduledFor.toIso8601String(),
        if (isAirportPickup) 'is_airport_pickup': true,
        if (isAirportDropoff) 'is_airport_dropoff': true,
        if (terminalInfo != null && terminalInfo.isNotEmpty) 'terminal_info': terminalInfo,
        if (airportSurcharge != null) 'airport_surcharge': airportSurcharge,
        if (platformServiceFee != null) 'platform_service_fee': platformServiceFee,
        if (stripeFeePortion != null) 'stripe_fee_amount': stripeFeePortion,
      };

      final response = await _supabase.functions.invoke(
        'create-ride-request',
        body: body,
        headers: {'Authorization': 'Bearer $token'},
      );

      await _requireOk(response, expected: 201, label: 'Failed to create ride');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error('Error creating ride request', e);
      rethrow;
    }
  }

  Future<RideRequest> getRideRequest(String rideId) async {
    try {
      final response = await _supabase
          .from('ride_requests')
          .select()
          .eq('id', rideId)
          .single();

      return RideRequest.fromJson(response);
    } catch (e) {
      AppLogger.error('Error fetching ride request', e);
      rethrow;
    }
  }

  Future<List<RideRequest>> getRideHistory({
    required String customerId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _supabase
          .from('ride_requests')
          .select()
          .eq('customer_id', customerId)
          .order('requested_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List<dynamic>)
          .map((r) => RideRequest.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error fetching ride history', e);
      return [];
    }
  }

  Future<List<RideRequest>> getDriverRides({
    required String driverId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _supabase
          .from('ride_requests')
          .select()
          .eq('driver_id', driverId)
          .order('requested_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List<dynamic>)
          .map((r) => RideRequest.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error fetching driver rides', e);
      rethrow;
    }
  }

  Future<List<RideRequest>> getDriverRideHistory(String driverId) async {
    try {
      final response = await _supabase
          .from('ride_requests')
          .select()
          .eq('driver_id', driverId)
          .inFilter('ride_status', ['ride_completed', 'cancelled', 'failed'])
          .order('requested_at', ascending: false)
          .limit(200);

      return (response as List<dynamic>)
          .map((r) => RideRequest.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error fetching driver ride history', e);
      rethrow;
    }
  }

  // ====================================================================
  // DRIVER MATCHING
  // ====================================================================

  Future<List<Map<String, dynamic>>> findNearbyDrivers({
    required double pickupLat,
    required double pickupLng,
    double searchRadiusKm = 15,
    int limit = 5,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'find-nearby-drivers',
        body: {
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          'search_radius_km': searchRadiusKm,
          'limit': limit,
        },
      );

      if (response.status != 200) {
        throw Exception('Failed to find drivers: ${response.data}');
      }

      final data = response.data as Map<String, dynamic>;
      final drivers = data['drivers'] as List<dynamic>;
      return drivers.map((d) => d as Map<String, dynamic>).toList();
    } catch (e) {
      AppLogger.error('Error finding nearby drivers', e);
      rethrow;
    }
  }

  // ====================================================================
  // RIDE STATUS MANAGEMENT
  // ====================================================================

  /// Returns a valid access token, refreshing the session if it is expired
  /// or will expire within the next 60 seconds.
  /// Throws [RideAuthException] if the session is invalid and the user must re-login.
  Future<String> _freshToken() async {
    var session = _supabase.auth.currentSession;
    if (session != null) {
      final expiresAt = session.expiresAt;
      final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (expiresAt == null || expiresAt - nowSecs < 60) {
        try {
          final result = await _supabase.auth.refreshSession();
          session = result.session ?? session;
        } catch (_) {
          // Refresh failed — keep the current session and let the server decide.
          // Never sign the user out here; PostgREST and most operations accept
          // the existing token even if the refresh endpoint rejects it.
        }
      }
    }
    final token = session?.accessToken;
    if (token == null) throw RideAuthException('Not authenticated. Please log in again.');
    return token;
  }

  /// Checks a Supabase Functions response and throws on non-[expected] status.
  Future<void> _requireOk(
    dynamic response, {
    int expected = 200,
    required String label,
  }) async {
    final status = (response as dynamic).status as int;
    if (status != expected) {
      throw Exception('$label: ${response.data}');
    }
  }

  Future<Map<String, dynamic>> updateRideStatus({
    required String rideId,
    required String newStatus,
    double? latitude,
    double? longitude,
    String? pin,
    String? pauseReason,
  }) async {
    try {
      final result = await _supabase.rpc('update_ride_status', params: {
        'p_ride_id': rideId,
        'p_new_status': newStatus,
        if (latitude != null) 'p_latitude': latitude,
        if (longitude != null) 'p_longitude': longitude,
        if (pin != null) 'p_pin': pin,
        if (pauseReason != null) 'p_pause_reason': pauseReason,
      });
      return (result as Map<String, dynamic>?) ?? {'message': 'Ride status updated'};
    } catch (e) {
      AppLogger.error('Error updating ride status', e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> completeRide({
    required String rideId,
    double? finalDistanceKm,
    int? finalDurationMinutes,
  }) async {
    try {
      final token = await _freshToken();
      final body = <String, dynamic>{'ride_id': rideId};
      if (finalDistanceKm != null) body['final_distance_km'] = finalDistanceKm;
      if (finalDurationMinutes != null) body['final_duration_minutes'] = finalDurationMinutes;

      final response = await _supabase.functions.invoke(
        'complete-ride',
        body: body,
        headers: {'Authorization': 'Bearer $token'},
      );

      await _requireOk(response, label: 'Failed to complete ride');
      return (response.data as Map<String, dynamic>?) ?? {'message': 'Ride completed'};
    } catch (e) {
      AppLogger.error('Error completing ride', e);
      rethrow;
    }
  }

  /// Cancels a ride, handling Stripe payment release or cancellation-fee capture
  /// for card payments server-side via the update-ride-status edge function.
  /// Scheduled rides are cancelled directly in the DB because the edge function
  /// does not allow the scheduled→cancelled transition.
  Future<Map<String, dynamic>> cancelRide({required String rideId}) async {
    try {
      // Check current status first — scheduled rides can't go through the edge function.
      final rideRow = await _supabase
          .from('ride_requests')
          .select('ride_status')
          .eq('id', rideId)
          .single();
      final currentStatus = rideRow['ride_status'] as String?;

      if (currentStatus == 'scheduled') {
        // Fetch full ride to check payment method before cancelling
        final fullRide = await _supabase
            .from('ride_requests')
            .select('payment_method, payment_status, estimated_fare, customer_id')
            .eq('id', rideId)
            .single();

        await _supabase.from('ride_requests').update({
          'ride_status': 'cancelled',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', rideId);
        // Release the assigned driver so they are not left with a ghost booking.
        await _supabase.from('ride_driver_requests').update({
          'status': 'cancelled',
          'responded_at': DateTime.now().toIso8601String(),
        }).eq('ride_id', rideId).inFilter('status', ['accepted', 'offered']);

        // Refund wallet if applicable — scheduled rides have no cancellation fee
        if (fullRide['payment_method'] == 'wallet' &&
            fullRide['payment_status'] == 'paid') {
          final fare = (fullRide['estimated_fare'] as num?)?.toDouble() ?? 0.0;
          if (fare > 0) {
            try {
              await _supabase.rpc('wallet_credit', params: {
                'p_user_id':     fullRide['customer_id'],
                'p_amount':      fare,
                'p_description': 'Ride refund — scheduled ride cancelled',
              });
              await _supabase.from('ride_requests').update({
                'payment_status': 'refunded',
              }).eq('id', rideId);
            } catch (e) {
              AppLogger.error('Wallet refund failed for scheduled ride $rideId', e);
            }
          }
        }

        return {'message': 'Scheduled ride cancelled'};
      }

      final token = await _freshToken();
      final response = await _supabase.functions.invoke(
        'update-ride-status',
        body: {'ride_id': rideId, 'new_status': 'cancelled'},
        headers: {'Authorization': 'Bearer $token'},
      );
      await _requireOk(response, label: 'Failed to cancel ride');
      return (response.data as Map<String, dynamic>?) ?? {'message': 'Ride cancelled'};
    } catch (e) {
      AppLogger.error('Error cancelling ride', e);
      rethrow;
    }
  }

  /// Charges the accrued pause fee to the customer immediately (card/wallet/cash).
  /// Clears `waiting_started_at` on the ride so the final fare is not double-charged.
  /// Returns a map with: amount, payment_method, status
  ///   status values: "charged", "cash_pending", "charge_failed", "insufficient_funds", "no_charge"
  Future<Map<String, dynamic>> chargePauseFee({required String rideId}) async {
    try {
      final token = await _freshToken();
      final response = await _supabase.functions.invoke(
        'charge-pause-fee',
        body: {'ride_id': rideId},
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.status != 200) {
        final data = response.data;
        final err = data is Map
            ? data['error'] ?? 'Failed to charge pause fee'
            : 'Failed to charge pause fee';
        throw Exception(err);
      }
      return (response.data as Map<String, dynamic>?) ?? {'amount': 0, 'status': 'no_charge'};
    } catch (e) {
      AppLogger.error('Error charging pause fee', e);
      rethrow;
    }
  }

  Future<double> startWaitingFee({required String rideId}) async {
    try {
      final response = await _supabase.rpc('update_ride_status', params: {
        'p_ride_id': rideId,
        'p_start_waiting': true,
      });
      final data = response as Map<String, dynamic>?;
      return (data?['rate'] as num?)?.toDouble() ?? 75.0;
    } catch (e) {
      AppLogger.error('Error starting waiting fee', e);
      rethrow;
    }
  }

  // ====================================================================
  // RIDE LOCATION TRACKING
  // ====================================================================

  Future<void> updateDriverLocation({
    required String rideId,
    required String driverId,
    required double latitude,
    required double longitude,
    double? heading,
    double? speed,
  }) async {
    try {
      await _supabase.from('ride_locations').insert({
        'ride_id': rideId,
        'driver_id': driverId,
        'lat': latitude,
        'lng': longitude,
        'heading': heading,
        'speed': speed,
      });
    } catch (e) {
      AppLogger.error('Error updating driver location', e);
      rethrow;
    }
  }

  Stream<RideLocation> watchRideLocation(String rideId) {
    return _supabase
        .from('ride_locations')
        .stream(primaryKey: ['id'])
        .eq('ride_id', rideId)
        .map(
          (events) =>
              events.isNotEmpty ? RideLocation.fromJson(events.last) : null,
        )
        .where((event) => event != null)
        .cast<RideLocation>();
  }

  Future<List<RideLocation>> getRideLocations(String rideId) async {
    try {
      final response = await _supabase
          .from('ride_locations')
          .select()
          .eq('ride_id', rideId)
          .order('created_at', ascending: false)
          .limit(100);

      return (response as List<dynamic>)
          .map((r) => RideLocation.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error fetching ride locations', e);
      rethrow;
    }
  }

  // ====================================================================
  // RIDE MESSAGES
  // ====================================================================

  Stream<RideMessage> watchRideMessages(String rideId) {
    return _supabase
        .from('ride_messages')
        .stream(primaryKey: ['id'])
        .eq('ride_id', rideId)
        .map((events) => events.map((e) => RideMessage.fromJson(e)))
        .expand((x) => x);
  }

  Future<List<RideMessage>> getRideMessages(String rideId) async {
    try {
      final response = await _supabase
          .from('ride_messages')
          .select()
          .eq('ride_id', rideId)
          .order('created_at', ascending: true);

      return (response as List<dynamic>)
          .map((r) => RideMessage.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error fetching ride messages', e);
      rethrow;
    }
  }

  Future<RideMessage> sendRideMessage({
    required String rideId,
    required String senderId,
    required String receiverId,
    required String message,
  }) async {
    try {
      final response = await _supabase
          .from('ride_messages')
          .insert({
            'ride_id': rideId,
            'sender_id': senderId,
            'receiver_id': receiverId,
            'message': message,
          })
          .select()
          .single();

      return RideMessage.fromJson(response);
    } catch (e) {
      AppLogger.error('Error sending ride message', e);
      rethrow;
    }
  }

  Future<void> markRideMessagesAsRead({
    required String rideId,
    required String receiverId,
  }) async {
    try {
      await _supabase
          .from('ride_messages')
          .update({'is_read': true})
          .eq('ride_id', rideId)
          .eq('receiver_id', receiverId);
    } catch (e) {
      AppLogger.error('Error marking messages as read', e);
      rethrow;
    }
  }

  // ====================================================================
  // PRICING SETTINGS
  // ====================================================================

  Future<RidePricingSettings> getPricingSettings() async {
    try {
      final response = await _supabase
          .from('ride_pricing_settings')
          .select()
          .eq('active', true)
          .limit(1)
          .single();

      return RidePricingSettings.fromJson(response);
    } catch (e) {
      AppLogger.error('Error fetching pricing settings', e);
      rethrow;
    }
  }

  Future<RidePricingSettings> updatePricingSettings(RidePricingSettings s) async {
    try {
      final response = await _supabase
          .from('ride_pricing_settings')
          .update({
            'base_fare': s.baseFare,
            'per_km_rate': s.perKmRate,
            'per_minute_rate': s.perMinuteRate,
            'minimum_fare': s.minimumFare,
            'platform_commission_percent': s.platformCommissionPercent,
            'surge_multiplier': s.surgeMultiplier,
            'max_search_radius_km': s.maxSearchRadiusKm,
            'driver_request_timeout_seconds': s.driverRequestTimeoutSeconds,
            'waiting_fee_per_min': s.waitingFeePerMin,
            'card_auth_buffer_percent': s.cardAuthBufferPercent,
            'cash_enabled': s.cashEnabled,
            'card_enabled': s.cardEnabled,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', s.id)
          .select()
          .single();
      return RidePricingSettings.fromJson(response);
    } catch (e) {
      AppLogger.error('Error updating pricing settings', e);
      rethrow;
    }
  }

  // ====================================================================
  // RIDE DRIVER REQUESTS
  // ====================================================================

  Future<RideDriverRequest> respondToRideRequest({
    required String requestId,
    required String status, // 'accepted' or 'rejected'
  }) async {
    try {
      final response = await _supabase
          .from('ride_driver_requests')
          .update({
            'status': status,
            'responded_at': DateTime.now().toIso8601String(),
          })
          .eq('id', requestId)
          .select()
          .single();

      return RideDriverRequest.fromJson(response);
    } catch (e) {
      AppLogger.error('Error responding to ride request', e);
      rethrow;
    }
  }

  Future<List<RideDriverRequest>> getDriverRequests(String driverId) async {
    try {
      final response = await _supabase
          .from('ride_driver_requests')
          .select()
          .eq('driver_id', driverId)
          .eq('status', 'pending')
          .order('sent_at', ascending: false);

      return (response as List<dynamic>)
          .map((r) => RideDriverRequest.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error fetching driver requests', e);
      rethrow;
    }
  }

  // ====================================================================
  // NEW: REAL-TIME STREAMS & ADDITIONAL METHODS
  // ====================================================================

  /// Stream real-time status updates for a ride (customer side).
  Stream<RideRequest> streamRideUpdates(String rideId) {
    return _supabase
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('id', rideId)
        .where((events) => events.isNotEmpty)
        .map((events) => RideRequest.fromJson(events.last));
  }

  /// Stream all rides for a customer in real-time, newest first.
  Stream<List<RideRequest>> streamRideHistory(String customerId) {
    return _supabase
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('customer_id', customerId)
        .order('requested_at', ascending: false)
        .map((events) => events
            .map((e) => RideRequest.fromJson(e))
            .toList());
  }

  /// Stream the customer's current active (non-terminal) ride in real-time.
  /// Also expires any stale searching/requested rides on first call.
  Stream<RideRequest?> streamActiveRideForCustomer(String customerId) {
    // Fire-and-forget: mark old unmatched rides as failed before streaming.
    unawaited(_expireStaleRides(customerId));

    return _supabase
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('customer_id', customerId)
        .order('requested_at', ascending: false)
        .map((events) {
          final now = DateTime.now();
          const staleThreshold = Duration(minutes: 15);
          final active = events.map((e) => RideRequest.fromJson(e)).where((r) {
            if (!r.isActive) return false;
            // Scheduled rides are future bookings, not currently running.
            if (r.rideStatus == RideStatus.scheduled) return false;
            // Pre-driver statuses older than 15 min are stuck — hide them.
            final isPreDriver = r.rideStatus == RideStatus.requested ||
                r.rideStatus == RideStatus.searchingDriver;
            if (isPreDriver && now.difference(r.updatedAt) > staleThreshold) {
              return false;
            }
            return true;
          }).toList();
          return active.isEmpty ? null : active.first;
        });
  }

  Future<void> _expireStaleRides(String customerId) async {
    try {
      await _supabase.rpc(
        'auto_expire_stale_rides',
        params: {'p_customer_id': customerId},
      );
    } catch (_) {}
  }

  /// Streams the current list of pending (non-expired) ride_driver_requests
  /// for a driver. Emits the full list on every DB change so the UI is always
  /// consistent — no expand(), no event-dropping by Riverpod.
  Stream<List<RideDriverRequest>> streamIncomingDriverRequests(String driverId) {
    return _supabase
        .from('ride_driver_requests')
        .stream(primaryKey: ['id'])
        .eq('driver_id', driverId)
        .map((events) => events
            .map((e) => RideDriverRequest.fromJson(e))
            .where((r) =>
                r.status == RideDriverRequestStatus.pending ||
                r.status == RideDriverRequestStatus.offered)
            .toList());
  }

  /// Same as [streamIncomingDriverRequests] but enriches each request with the
  /// full [RideRequest] details in a single batch query via asyncMap.
  /// This eliminates the separate per-ride async fetch and its RLS timing issues.
  Stream<List<DriverRideOffer>> streamDriverRideOffers(String driverId) {
    return streamIncomingDriverRequests(driverId).asyncMap((requests) async {
      if (requests.isEmpty) return <DriverRideOffer>[];

      final rideIds = requests.map((r) => r.rideId).toList();
      final rideMap = <String, RideRequest>{};

      try {
        final rows = await _supabase
            .from('ride_requests')
            .select()
            .inFilter('id', rideIds);

        for (final row in rows as List<dynamic>) {
          final ride = RideRequest.fromJson(row as Map<String, dynamic>);
          rideMap[ride.id] = ride;
        }
      } catch (e) {
        AppLogger.error('Failed to batch-fetch ride details for driver offers', e);
      }

      return requests
          .map((req) => DriverRideOffer(request: req, ride: rideMap[req.rideId]))
          .toList();
    });
  }

  /// Respond to a ride request via the respond-to-ride-request edge function.
  Future<Map<String, dynamic>> respondToDriverRideRequest({
    required String rideDriverRequestId,
    required bool accept,
  }) async {
    try {
      final token = await _freshToken();

      final response = await _supabase.functions.invoke(
        'respond-to-ride-request',
        body: {
          'ride_driver_request_id': rideDriverRequestId,
          'action': accept ? 'accept' : 'reject',
        },
        headers: {'Authorization': 'Bearer $token'},
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error('Error responding to driver ride request', e);
      rethrow;
    }
  }

  /// Update driver availability and online status.
  Future<void> updateDriverAvailability({
    required String driverId,
    required bool isOnline,
    required bool isAvailableForRides,
    String? serviceType, // 'food_delivery', 'ride_sharing', 'both'
    double? currentLat,
    double? currentLng,
  }) async {
    try {
      final updates = <String, dynamic>{
        'is_online': isOnline,
        'is_available_for_rides': isAvailableForRides,
        'updated_at': DateTime.now().toIso8601String(),
      };
      // Auto-approve for ride sharing the moment a driver enables ride mode.
      if (isAvailableForRides) updates['is_ride_driver_approved'] = true;
      if (serviceType != null) updates['service_type'] = serviceType;
      if (currentLat != null) updates['current_lat'] = currentLat;
      if (currentLng != null) updates['current_lng'] = currentLng;

      await _supabase.from('drivers').update(updates).eq('id', driverId);
    } catch (e) {
      AppLogger.error('Error updating driver availability', e);
      rethrow;
    }
  }

  /// Rate customer after ride completion (driver rates customer).
  Future<void> rateCustomer({
    required String rideId,
    required int rating,
    String? review,
  }) async {
    try {
      await _supabase
          .from('ride_requests')
          .update({'rating': rating, 'review': review})
          .eq('id', rideId);
    } catch (e) {
      AppLogger.error('Error rating customer', e);
      rethrow;
    }
  }

  /// Get active ride for customer (if any searching or in-progress ride).
  Future<RideRequest?> getActiveRide(String customerId) async {
    try {
      final response = await _supabase
          .from('ride_requests')
          .select()
          .eq('customer_id', customerId)
          .not('ride_status', 'in', '("ride_completed","cancelled","failed")')
          .order('requested_at', ascending: false)
          .limit(1);

      final list = response as List<dynamic>;
      if (list.isEmpty) return null;
      return RideRequest.fromJson(list.first as Map<String, dynamic>);
    } catch (e) {
      AppLogger.error('Error fetching active ride for customer', e);
      rethrow;
    }
  }

  /// Get active ride for driver.
  Future<RideRequest?> getActiveRideForDriver(String driverId) async {
    try {
      final response = await _supabase
          .from('ride_requests')
          .select()
          .eq('driver_id', driverId)
          .not('ride_status', 'in', '("ride_completed","cancelled","failed")')
          .order('requested_at', ascending: false)
          .limit(1);

      final list = response as List<dynamic>;
      if (list.isEmpty) return null;
      return RideRequest.fromJson(list.first as Map<String, dynamic>);
    } catch (e) {
      AppLogger.error('Error fetching active ride for driver', e);
      rethrow;
    }
  }

  /// Streams the driver's accepted scheduled rides, sorted by pickup time.
  Stream<List<RideRequest>> streamDriverScheduledRides(String driverId) {
    return _supabase
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('driver_id', driverId)
        .map((rows) => (rows as List<dynamic>)
            .map((r) => RideRequest.fromJson(r as Map<String, dynamic>))
            .where((r) =>
                r.rideStatus == RideStatus.scheduled &&
                r.scheduledFor != null &&
                r.scheduledFor!.isAfter(DateTime.now()))
            .toList()
          ..sort((a, b) => a.scheduledFor!.compareTo(b.scheduledFor!)));
  }

  /// Driver backs out of an accepted scheduled ride.
  /// Resets the ride so the customer's system can find a replacement driver.
  Future<void> cancelDriverScheduledRide({
    required String rideId,
    required String driverId,
  }) async {
    try {
      await _supabase.from('ride_requests').update({
        'driver_id': null,
        'accepted_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', rideId).eq('driver_id', driverId);

      await _supabase.from('ride_driver_requests').update({
        'status': 'cancelled',
        'responded_at': DateTime.now().toIso8601String(),
      }).eq('ride_id', rideId).eq('driver_id', driverId).eq('status', 'accepted');
    } catch (e) {
      AppLogger.error('Error cancelling driver scheduled ride', e);
      rethrow;
    }
  }

  /// Stream driver offers (status='offered') for a ride, enriched with driver details.
  /// Returns a list of maps, each containing the ride_driver_request fields plus:
  ///   driver_name, driver_rating, vehicle_type, vehicle_make, vehicle_model,
  ///   vehicle_color, plate_number
  Stream<List<Map<String, dynamic>>> streamDriverOffers(String rideId) {
    return _supabase
        .from('ride_driver_requests')
        .stream(primaryKey: ['id'])
        .eq('ride_id', rideId)
        .asyncMap((rows) async {
          if (rows.isEmpty) return <Map<String, dynamic>>[];
          final offeredRows = rows
              .where((r) => r['status'] == 'offered' || r['status'] == 'pending')
              .toList();
          final offeredDriverIds = offeredRows
              .map((r) => r['driver_id'] as String?)
              .where((id) => id != null)
              .cast<String>()
              .toList();
          if (offeredDriverIds.isEmpty) {
            return offeredRows
                .map((r) => Map<String, dynamic>.from(r))
                .toList();
          }
          // Fetch driver + user info for offered drivers
          final driversResp = await _supabase
              .from('drivers')
              .select('id, rating, vehicle_type, vehicle_make, vehicle_model, vehicle_color, plate_number, user_id')
              .inFilter('id', offeredDriverIds);
          final driverList = driversResp as List<dynamic>;
          final userIds = driverList
              .map((d) => d['user_id'] as String?)
              .where((id) => id != null)
              .cast<String>()
              .toList();
          List<dynamic> userList = [];
          if (userIds.isNotEmpty) {
            userList = await _supabase
                .from('users')
                .select('id, name, email')
                .inFilter('id', userIds) as List<dynamic>;
          }
          final driverMap = {
            for (final d in driverList) d['id'] as String: d
          };
          final userMap = {
            for (final u in userList) u['id'] as String: u
          };
          return offeredRows.map((r) {
            final driverId = r['driver_id'] as String;
            final driver = driverMap[driverId];
            final userId = driver?['user_id'] as String?;
            final user = userId != null ? userMap[userId] : null;
            final name = (user?['name'] as String?)?.isNotEmpty == true
                ? user!['name'] as String
                : (user?['email'] as String?)?.split('@').first ?? 'Driver';
            return {
              ...Map<String, dynamic>.from(r),
              'driver_name': name,
              'driver_rating': (driver?['rating'] as num?)?.toDouble() ?? 0.0,
              'vehicle_type': driver?['vehicle_type'] as String? ?? '',
              'vehicle_make': driver?['vehicle_make'] as String? ?? '',
              'vehicle_model': driver?['vehicle_model'] as String? ?? '',
              'vehicle_color': driver?['vehicle_color'] as String? ?? '',
              'plate_number': driver?['plate_number'] as String? ?? '',
            };
          }).toList();
        });
  }

  /// Customer confirms a specific driver offer.
  Future<Map<String, dynamic>> activateScheduledRide(String rideId) async {
    try {
      final token = await _freshToken();
      final response = await _supabase.functions.invoke(
        'activate-scheduled-ride',
        body: {'ride_id': rideId},
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.status != 200) {
        final data = response.data;
        final err = data is Map ? data['error'] ?? 'Failed to activate ride' : 'Failed to activate ride';
        throw Exception(err);
      }
      return response.data as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error('Error activating scheduled ride', e);
      rethrow;
    }
  }

  Future<void> selectDriver({
    required String rideId,
    required String driverRequestId,
  }) async {
    try {
      final token = await _freshToken();
      final response = await _supabase.functions.invoke(
        'select-driver',
        body: {
          'ride_id': rideId,
          'driver_request_id': driverRequestId,
        },
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.status != 200) {
        final data = response.data;
        final err = data is Map ? data['error'] ?? 'Failed to select driver' : 'Failed to select driver';
        throw Exception(err);
      }
    } catch (e) {
      AppLogger.error('Error selecting driver', e);
      rethrow;
    }
  }
}
