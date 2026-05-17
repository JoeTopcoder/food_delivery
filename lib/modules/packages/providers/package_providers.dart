import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/package_service.dart';
import '../models/shipping_company.dart';
import '../models/package_delivery_request.dart';

// ── Service ─────────────────────────────────────────────────────────────────

final packageServiceProvider = Provider<PackageService>((ref) {
  return PackageService(Supabase.instance.client);
});

// ── Shipping companies list ──────────────────────────────────────────────────

final shippingCompaniesProvider =
    FutureProvider<List<ShippingCompany>>((ref) async {
  return ref.read(packageServiceProvider).getShippingCompanies();
});

// ── Active delivery stream (customer) ───────────────────────────────────────

final activePackageDeliveryStreamProvider =
    StreamProvider.family<PackageDeliveryRequest, String>(
        (ref, deliveryRequestId) {
  return ref
      .read(packageServiceProvider)
      .streamDeliveryRequest(deliveryRequestId);
});

// ── My active delivery (customer — one-shot) ─────────────────────────────────

final myActivePackageDeliveryProvider =
    FutureProvider<PackageDeliveryRequest?>((ref) async {
  return ref.read(packageServiceProvider).getMyActiveDelivery();
});

// ── Delivery history (customer) ──────────────────────────────────────────────

final myPackageDeliveryHistoryProvider =
    FutureProvider<List<PackageDeliveryRequest>>((ref) async {
  return ref.read(packageServiceProvider).getMyDeliveryHistory();
});

// ── Available package requests (driver) ─────────────────────────────────────

final availablePackageRequestsProvider =
    FutureProvider<List<PackageDeliveryRequest>>((ref) async {
  return ref.read(packageServiceProvider).getAvailablePackageRequests();
});

// ── Driver's own active package delivery ─────────────────────────────────────

final myActivePackageDeliveryAsDriverProvider =
    FutureProvider<PackageDeliveryRequest?>((ref) async {
  return ref.read(packageServiceProvider).getMyActiveDeliveryAsDriver();
});
