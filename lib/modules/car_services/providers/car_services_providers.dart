import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/index.dart';
import '../services/car_services_service.dart';
import '../../../config/supabase_config.dart';

// ── SERVICE ───────────────────────────────────────────────────────────────────

final carServicesServiceProvider = Provider<CarServicesService>((ref) {
  return CarServicesService(supabase: SupabaseConfig.client);
});

// ── CATEGORIES ────────────────────────────────────────────────────────────────

/// All active service categories, ordered by sort_order.
/// keepAlive — categories change rarely; no need to re-fetch on every navigation.
final carServiceCategoriesProvider =
    FutureProvider<List<CarServiceCategory>>((ref) async {
  ref.keepAlive();
  return ref.watch(carServicesServiceProvider).getCategories();
});

// ── PROVIDERS ─────────────────────────────────────────────────────────────────

/// All providers for the admin view — includes inactive and rejected ones.
final allCarServiceProvidersAdminProvider =
    FutureProvider<List<CarServiceProvider>>((ref) async {
  return ref.watch(carServicesServiceProvider).getAllProvidersAdmin();
});

/// All active providers, optionally filtered by categoryId (null = all).
/// keepAlive — keeps the list cached so returning to the screen is instant.
final carServiceProvidersProvider =
    FutureProvider.family<List<CarServiceProvider>, String?>(
        (ref, categoryId) async {
  ref.keepAlive();
  return ref
      .watch(carServicesServiceProvider)
      .getProviders(categoryId: categoryId);
});

/// Full detail for a single provider (with offerings + images).
final carServiceProviderDetailProvider =
    FutureProvider.family<CarServiceProvider?, String>(
        (ref, providerId) async {
  return ref
      .watch(carServicesServiceProvider)
      .getProviderById(providerId);
});

/// The logged-in user's own provider profile (for service_provider role).
final myCarServiceProviderProfileProvider =
    FutureProvider<CarServiceProvider?>((ref) async {
  return ref.watch(carServicesServiceProvider).getMyProviderProfile();
});

// ── OFFERINGS ─────────────────────────────────────────────────────────────────

/// All active offerings for a given provider.
final carServiceOfferingsProvider =
    FutureProvider.family<List<CarServiceOffering>, String>(
        (ref, providerId) async {
  return ref
      .watch(carServicesServiceProvider)
      .getOfferingsByProvider(providerId);
});

// ── BOOKINGS ──────────────────────────────────────────────────────────────────

/// Current customer's bookings, newest first.
final myCarServiceBookingsProvider =
    FutureProvider<List<CarServiceBooking>>((ref) async {
  return ref.watch(carServicesServiceProvider).getMyBookings();
});

/// Single booking detail by ID.
final carServiceBookingDetailProvider =
    FutureProvider.family<CarServiceBooking?, String>(
        (ref, bookingId) async {
  return ref
      .watch(carServicesServiceProvider)
      .getBookingById(bookingId);
});

/// All bookings for a provider (all statuses).
final providerBookingsProvider =
    FutureProvider.family<List<CarServiceBooking>, String>(
        (ref, providerId) async {
  return ref
      .watch(carServicesServiceProvider)
      .getProviderBookings(providerId);
});

// ── REVIEWS ───────────────────────────────────────────────────────────────────

/// Reviews for a given provider, newest first.
final carServiceProviderReviewsProvider =
    FutureProvider.family<List<CarServiceReview>, String>(
        (ref, providerId) async {
  return ref
      .watch(carServicesServiceProvider)
      .getProviderReviews(providerId);
});

// ── AVAILABILITY ──────────────────────────────────────────────────────────────

/// Weekly availability slots for a provider.
final providerAvailabilityProvider =
    FutureProvider.family<List<ProviderAvailability>, String>(
        (ref, providerId) async {
  return ref
      .watch(carServicesServiceProvider)
      .getProviderAvailability(providerId);
});

// ── REAL-TIME STREAMS ─────────────────────────────────────────────────────────

/// Live stream of a single booking (updates in real-time via Supabase Realtime).
final watchCarServiceBookingProvider =
    StreamProvider.family<CarServiceBooking, String>((ref, bookingId) {
  return ref.watch(carServicesServiceProvider).watchBooking(bookingId);
});

/// Live stream of all bookings for a provider.
final watchProviderBookingsProvider =
    StreamProvider.family<List<CarServiceBooking>, String>(
        (ref, providerId) {
  return ref
      .watch(carServicesServiceProvider)
      .watchProviderBookings(providerId);
});

// ── ADMIN ─────────────────────────────────────────────────────────────────────

/// Providers pending admin approval.
final pendingProvidersProvider =
    FutureProvider<List<CarServiceProvider>>((ref) async {
  return ref.watch(carServicesServiceProvider).getPendingProviders();
});

// ── CUSTOMER VEHICLES ─────────────────────────────────────────────────────────

final customerVehicleServiceProvider = Provider<CustomerVehicleService>((ref) {
  return CustomerVehicleService(supabase: SupabaseConfig.client);
});

final myVehiclesProvider = FutureProvider<List<CustomerVehicle>>((ref) async {
  return ref.watch(customerVehicleServiceProvider).getMyVehicles();
});
