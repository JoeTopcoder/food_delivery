import 'package:riverpod/riverpod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/index.dart';
import '../services/ride_service.dart';
import '../../../config/supabase_config.dart';

// ── SERVICE ──────────────────────────────────────────────────────────────────

final rideServiceProvider = Provider<RideService>((ref) {
  return RideService(supabase: SupabaseConfig.client);
});

// ── PRICING ───────────────────────────────────────────────────────────────────

final ridePricingSettingsProvider = FutureProvider<RidePricingSettings>((ref) async {
  return ref.watch(rideServiceProvider).getPricingSettings();
});

// ── FARE CALCULATION ─────────────────────────────────────────────────────────

typedef FareParams = ({double pickupLat, double pickupLng, double destLat, double destLng});

final fareCalculationProvider = FutureProvider.family<Map<String, dynamic>, FareParams>((ref, params) async {
  return ref.watch(rideServiceProvider).calculateRideFare(
    pickupLat: params.pickupLat,
    pickupLng: params.pickupLng,
    destinationLat: params.destLat,
    destinationLng: params.destLng,
  );
});

// ── CREATE RIDE ───────────────────────────────────────────────────────────────

final createRideRequestProvider = FutureProvider.family<Map<String, dynamic>, CreateRideParams>((ref, params) async {
  return ref.watch(rideServiceProvider).createRideRequest(
    pickupAddress: params.pickupAddress,
    pickupLat: params.pickupLat,
    pickupLng: params.pickupLng,
    destinationAddress: params.destinationAddress,
    destinationLat: params.destinationLat,
    destinationLng: params.destinationLng,
    distanceKm: params.distanceKm,
    estimatedDurationMinutes: params.estimatedDurationMinutes,
    estimatedFare: params.estimatedFare,
    platformFee: params.platformFee,
    paymentMethod: params.paymentMethod,
    savedCardId: params.savedCardId,
    scheduledFor: params.scheduledFor,
  );
});

class CreateRideParams {
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String destinationAddress;
  final double destinationLat;
  final double destinationLng;
  final double distanceKm;
  final int estimatedDurationMinutes;
  final double estimatedFare;
  final double platformFee;
  final String paymentMethod;
  final String? savedCardId;
  final DateTime? scheduledFor;

  const CreateRideParams({
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.destinationAddress,
    required this.destinationLat,
    required this.destinationLng,
    required this.distanceKm,
    required this.estimatedDurationMinutes,
    required this.estimatedFare,
    required this.platformFee,
    required this.paymentMethod,
    this.savedCardId,
    this.scheduledFor,
  });
}

// ── ACTIVE RIDE (Customer) ────────────────────────────────────────────────────

final activeRideProvider = StateNotifierProvider<ActiveRideNotifier, AsyncValue<RideRequest?>>((ref) {
  return ActiveRideNotifier(rideService: ref.watch(rideServiceProvider));
});

class ActiveRideNotifier extends StateNotifier<AsyncValue<RideRequest?>> {
  final RideService _rideService;

  ActiveRideNotifier({required RideService rideService})
      : _rideService = rideService,
        super(const AsyncValue.loading());

  Future<void> fetchActiveRide(String rideId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _rideService.getRideRequest(rideId));
  }

  Future<void> updateRideStatus({
    required String rideId,
    required String newStatus,
    double? latitude,
    double? longitude,
  }) async {
    await _rideService.updateRideStatus(
      rideId: rideId,
      newStatus: newStatus,
      latitude: latitude,
      longitude: longitude,
    );
    await fetchActiveRide(rideId);
  }

  Future<void> completeRide({
    required String rideId,
    double? finalDistanceKm,
    int? finalDurationMinutes,
  }) async {
    await _rideService.completeRide(
      rideId: rideId,
      finalDistanceKm: finalDistanceKm,
      finalDurationMinutes: finalDurationMinutes,
    );
    state = const AsyncValue.data(null);
  }

  void clearActiveRide() {
    state = const AsyncValue.data(null);
  }
}

// ── REAL-TIME RIDE STATUS STREAM (Customer) ───────────────────────────────────

/// Streams live ride_request updates for a given rideId.
/// Use this in SearchingDriverScreen and ActiveRideScreen.
final rideStatusStreamProvider = StreamProvider.family<RideRequest, String>((ref, rideId) {
  return ref.watch(rideServiceProvider).streamRideUpdates(rideId);
});

/// Streams live driver offers (status='offered') for a ride, enriched with
/// driver name, rating and vehicle info. Used by SearchingDriverScreen.
final rideDriverOffersProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, rideId) {
  return ref.watch(rideServiceProvider).streamDriverOffers(rideId);
});

// ── RIDE HISTORY ──────────────────────────────────────────────────────────────

/// One-shot fetch — kept for compatibility; prefer rideHistoryStreamProvider.
final rideHistoryProvider = FutureProvider.family<List<RideRequest>, String>((ref, customerId) async {
  return ref.watch(rideServiceProvider).getRideHistory(customerId: customerId);
});

/// Real-time stream of all rides for a customer, newest first.
final rideHistoryStreamProvider = StreamProvider.family<List<RideRequest>, String>((ref, customerId) {
  return ref.watch(rideServiceProvider).streamRideHistory(customerId);
});

/// One-shot fetch — kept for compatibility; prefer activeCustomerRideStreamProvider.
final activeCustomerRideProvider = FutureProvider.family<RideRequest?, String>((ref, customerId) async {
  return ref.watch(rideServiceProvider).getActiveRide(customerId);
});

/// Real-time stream of the customer's active ride (null when none).
final activeCustomerRideStreamProvider = StreamProvider.family<RideRequest?, String>((ref, customerId) {
  return ref.watch(rideServiceProvider).streamActiveRideForCustomer(customerId);
});

final driverRidesProvider = FutureProvider.family<List<RideRequest>, String>((ref, driverId) async {
  return ref.watch(rideServiceProvider).getDriverRides(driverId: driverId);
});

// ── LOCATION STREAM ───────────────────────────────────────────────────────────

final rideLocationStreamProvider = StreamProvider.family<RideLocation, String>((ref, rideId) {
  return ref.watch(rideServiceProvider).watchRideLocation(rideId);
});

// ── MESSAGES ──────────────────────────────────────────────────────────────────

final rideMessagesProvider = StreamProvider.family<RideMessage, String>((ref, rideId) {
  return ref.watch(rideServiceProvider).watchRideMessages(rideId);
});

final rideMessageHistoryProvider = FutureProvider.family<List<RideMessage>, String>((ref, rideId) async {
  return ref.watch(rideServiceProvider).getRideMessages(rideId);
});

// ── NEARBY DRIVERS ────────────────────────────────────────────────────────────

typedef NearbyDriverParams = ({double pickupLat, double pickupLng, double searchRadiusKm});

final nearbyDriversProvider = FutureProvider.family<List<Map<String, dynamic>>, NearbyDriverParams>((ref, params) async {
  return ref.watch(rideServiceProvider).findNearbyDrivers(
    pickupLat: params.pickupLat,
    pickupLng: params.pickupLng,
    searchRadiusKm: params.searchRadiusKm,
  );
});

// ── DRIVER INCOMING REQUESTS (real-time) ─────────────────────────────────────

/// Streams the live list of pending ride_driver_requests for a driver.
final driverIncomingRequestsStreamProvider = StreamProvider.family<List<RideDriverRequest>, String>((ref, driverId) {
  return ref.watch(rideServiceProvider).streamIncomingDriverRequests(driverId);
});

/// Same stream but each request includes the full RideRequest details,
/// loaded atomically via asyncMap — no separate async fetch needed.
final driverRideOffersStreamProvider = StreamProvider.family<List<DriverRideOffer>, String>((ref, driverId) {
  return ref.watch(rideServiceProvider).streamDriverRideOffers(driverId);
});

/// Fetches list of pending driver requests (one-time, for initial load).
final driverRideRequestsProvider = FutureProvider.family<List<RideDriverRequest>, String>((ref, driverId) async {
  return ref.watch(rideServiceProvider).getDriverRequests(driverId);
});

// ── DRIVER AVAILABILITY ───────────────────────────────────────────────────────

/// Tracks what mode the current driver is in. Persisted to DB on change.
final driverOnlineModeProvider = StateNotifierProvider<DriverOnlineModeNotifier, DriverOnlineMode>((ref) {
  return DriverOnlineModeNotifier(ref.watch(rideServiceProvider));
});

enum DriverOnlineMode { foodDelivery, rideSharing, both, offline }

class DriverOnlineModeNotifier extends StateNotifier<DriverOnlineMode> {
  final RideService _rideService;

  DriverOnlineModeNotifier(this._rideService) : super(DriverOnlineMode.offline);

  Future<void> setMode(DriverOnlineMode mode, String driverId, {double? lat, double? lng}) async {
    state = mode;
    final isOnline = mode != DriverOnlineMode.offline;
    final isAvailableForRides = mode == DriverOnlineMode.rideSharing || mode == DriverOnlineMode.both;
    final serviceType = switch (mode) {
      DriverOnlineMode.foodDelivery => 'food_delivery',
      DriverOnlineMode.rideSharing  => 'ride_sharing',
      DriverOnlineMode.both         => 'both',
      DriverOnlineMode.offline      => 'food_delivery',
    };
    await _rideService.updateDriverAvailability(
      driverId: driverId,
      isOnline: isOnline,
      isAvailableForRides: isAvailableForRides,
      serviceType: serviceType,
      currentLat: lat,
      currentLng: lng,
    );
  }
}
