import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/index.dart';
import '../services/laundry_service.dart';
import '../../../config/supabase_config.dart';

// ── SERVICE ───────────────────────────────────────────────────────────────────

final laundryServiceProvider = Provider<LaundryService>((ref) {
  return LaundryService(supabase: SupabaseConfig.client);
});

// ── MASTER CATALOGUE ──────────────────────────────────────────────────────────

final laundryCatalogueProvider =
    FutureProvider.autoDispose<List<LaundryServiceType>>((ref) async {
  ref.keepAlive();
  return ref.read(laundryServiceProvider).getServiceCatalogue();
});

// ── PROVIDERS (customer browsing) ─────────────────────────────────────────────

final laundryProvidersProvider =
    FutureProvider.autoDispose<List<LaundryProvider>>((ref) async {
  ref.keepAlive();
  return ref.read(laundryServiceProvider).getActiveProviders();
});

final laundryProviderSearchProvider =
    FutureProvider.autoDispose.family<List<LaundryProvider>, String>(
        (ref, query) async {
  return ref.read(laundryServiceProvider).getActiveProviders(query: query);
});

final laundryProviderDetailProvider =
    FutureProvider.autoDispose.family<LaundryProvider?, String>(
        (ref, id) async {
  return ref.read(laundryServiceProvider).getProviderById(id);
});

// ── MY PROVIDER PROFILE (laundry_provider role) ───────────────────────────────

final myLaundryProviderProvider =
    FutureProvider.autoDispose<LaundryProvider?>((ref) async {
  return ref.read(laundryServiceProvider).getMyProviderProfile();
});

// ── PROVIDER SERVICES ─────────────────────────────────────────────────────────

final laundryProviderServicesProvider =
    FutureProvider.autoDispose.family<List<LaundryProviderService>, String>(
        (ref, providerId) async {
  return ref.read(laundryServiceProvider).getProviderServices(providerId);
});

// ── CUSTOMER BOOKINGS ─────────────────────────────────────────────────────────

final myLaundryBookingsProvider =
    FutureProvider.autoDispose<List<LaundryBooking>>((ref) async {
  return ref.read(laundryServiceProvider).getMyBookings();
});

final laundryBookingDetailProvider =
    FutureProvider.autoDispose.family<LaundryBooking?, String>(
        (ref, bookingId) async {
  return ref.read(laundryServiceProvider).getBookingById(bookingId);
});

// ── PROVIDER BOOKINGS ─────────────────────────────────────────────────────────

class LaundryProviderBookingParams {
  final String providerId;
  final List<String>? statuses;
  const LaundryProviderBookingParams(this.providerId, {this.statuses});

  @override
  bool operator ==(Object other) =>
      other is LaundryProviderBookingParams &&
      other.providerId == providerId &&
      other.statuses?.join() == statuses?.join();

  @override
  int get hashCode => Object.hash(providerId, statuses?.join());
}

final providerLaundryBookingsProvider = FutureProvider.autoDispose
    .family<List<LaundryBooking>, LaundryProviderBookingParams>(
        (ref, params) async {
  return ref
      .read(laundryServiceProvider)
      .getProviderBookings(params.providerId, statuses: params.statuses);
});

// ── DRIVER BOOKINGS ───────────────────────────────────────────────────────────

final driverLaundryBookingsProvider =
    FutureProvider.autoDispose<List<LaundryBooking>>((ref) async {
  return ref.read(laundryServiceProvider).getDriverAssignedBookings();
});

// ── ADMIN ─────────────────────────────────────────────────────────────────────

final adminLaundryProvidersProvider = FutureProvider.autoDispose
    .family<List<LaundryProvider>, LaundryProviderStatus?>(
        (ref, status) async {
  return ref.read(laundryServiceProvider).getAllProviders(status: status);
});

final adminLaundryBookingsProvider =
    FutureProvider.autoDispose<List<LaundryBooking>>((ref) async {
  return ref.read(laundryServiceProvider).getAllBookings();
});

final adminLaundryAnalyticsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.read(laundryServiceProvider).getAdminAnalytics();
});

// ── PAYMENT & COMMISSION ──────────────────────────────────────────────────────

final laundryDriverJobsProvider =
    FutureProvider.autoDispose.family<List<LaundryDriverJob>, String>(
        (ref, bookingId) async {
  return ref.read(laundryServiceProvider).getDriverJobsForBooking(bookingId);
});

final laundryPaymentSplitProvider =
    FutureProvider.autoDispose.family<LaundryPaymentSplit?, String>(
        (ref, bookingId) async {
  return ref.read(laundryServiceProvider).getPaymentSplit(bookingId);
});

final laundryDefaultCommissionProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  return ref.read(laundryServiceProvider).getDefaultCommissionSettings();
});

final laundryAdminCommissionAnalyticsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.read(laundryServiceProvider).getAdminCommissionAnalytics();
});

final laundryProviderEarningsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>(
        (ref, providerId) async {
  return ref.read(laundryServiceProvider).getProviderEarnings(providerId);
});

final laundryProviderSplitsProvider =
    FutureProvider.autoDispose.family<List<LaundryPaymentSplit>, String>(
        (ref, providerId) async {
  return ref.read(laundryServiceProvider).getProviderPaymentSplits(providerId);
});

// Wallet balance is now served by the unified walletBalanceStreamProvider
// from lib/providers/wallet_provider.dart — use that everywhere.
