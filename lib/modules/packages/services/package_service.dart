import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shipping_company.dart';
import '../models/package_record.dart';
import '../models/package_delivery_request.dart';

class PackageService {
  final SupabaseClient _supabase;

  PackageService(this._supabase);

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  Future<String> _freshToken() async {
    final session = _supabase.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');
    if (session.isExpired) {
      final res = await _supabase.auth.refreshSession();
      return res.session?.accessToken ?? session.accessToken;
    }
    return session.accessToken;
  }

  Future<Map<String, dynamic>> _callFn(
    String fnName,
    Map<String, dynamic> body,
  ) async {
    final token = await _freshToken();
    final res = await _supabase.functions.invoke(
      fnName,
      body: body,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.status == 401) {
      throw PackageAuthException('Session expired. Please log in again.');
    }
    if (res.status != 200 && res.status != 201) {
      final msg = (res.data as Map<String, dynamic>?)?['error'] ?? 'Unknown error';
      throw Exception(msg);
    }
    return res.data as Map<String, dynamic>;
  }

  // ── Shipping Companies ──────────────────────────────────────────────────────

  Future<List<ShippingCompany>> getShippingCompanies() async {
    final data = await _supabase
        .from('shipping_companies')
        .select()
        .eq('active', true)
        .order('name');
    return (data as List).map((j) => ShippingCompany.fromJson(j)).toList();
  }

  // ── Package Verification ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> verifyPackage({
    required String shippingCompanyId,
    required String trackingNumber,
  }) async {
    return _callFn('verify-package', {
      'shipping_company_id': shippingCompanyId,
      'tracking_number': trackingNumber,
    });
  }

  // ── Fee Calculation ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> calculateFee({
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    required String packageType,
    double? packageWeight,
  }) async {
    return _callFn('calculate-package-fee', {
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'destination_lat': destinationLat,
      'destination_lng': destinationLng,
      'package_type': packageType,
      if (packageWeight != null) 'package_weight': packageWeight,
    });
  }

  // ── Create Delivery Request ─────────────────────────────────────────────────

  Future<PackageDeliveryRequest> createDelivery({
    required String packageRecordId,
    required String shippingCompanyId,
    required String paymentMethod,
    required double deliveryFee,
    required double platformFee,
    required double driverEarning,
    String? savedCardId,
    String? stripePaymentIntentId,
  }) async {
    final res = await _callFn('create-package-delivery', {
      'package_record_id': packageRecordId,
      'shipping_company_id': shippingCompanyId,
      'payment_method': paymentMethod,
      'delivery_fee': deliveryFee,
      'platform_fee': platformFee,
      'driver_earning': driverEarning,
      if (savedCardId != null) 'saved_card_id': savedCardId,
      if (stripePaymentIntentId != null)
        'stripe_payment_intent_id': stripePaymentIntentId,
    });
    return PackageDeliveryRequest.fromJson(
        res['delivery_request'] as Map<String, dynamic>);
  }

  // ── Status Updates ──────────────────────────────────────────────────────────

  Future<PackageDeliveryRequest> updateStatus({
    required String deliveryRequestId,
    required String newStatus,
    String? note,
  }) async {
    final res = await _callFn('update-package-status', {
      'delivery_request_id': deliveryRequestId,
      'new_status': newStatus,
      if (note != null) 'note': note,
    });
    return PackageDeliveryRequest.fromJson(
        res['delivery_request'] as Map<String, dynamic>);
  }

  // ── Barcode Scan + Pickup Confirm ───────────────────────────────────────────

  Future<PackageDeliveryRequest> confirmPickup({
    required String deliveryRequestId,
    required String scannedBarcode,
    String? scanImageUrl,
  }) async {
    final res = await _callFn('confirm-package-pickup', {
      'delivery_request_id': deliveryRequestId,
      'scanned_barcode': scannedBarcode,
      if (scanImageUrl != null) 'scan_image_url': scanImageUrl,
    });
    return PackageDeliveryRequest.fromJson(
        res['delivery_request'] as Map<String, dynamic>);
  }

  // ── Complete Delivery ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> completeDelivery({
    required String deliveryRequestId,
    String? scannedBarcode,
    String? scanImageUrl,
  }) async {
    return _callFn('complete-package-delivery', {
      'delivery_request_id': deliveryRequestId,
      if (scannedBarcode != null) 'scanned_barcode': scannedBarcode,
      if (scanImageUrl != null) 'scan_image_url': scanImageUrl,
    });
  }

  // ── Customer: my active delivery ────────────────────────────────────────────

  Future<PackageDeliveryRequest?> getMyActiveDelivery() async {
    final uid = _currentUserId;
    if (uid == null) return null;
    final data = await _supabase
        .from('package_delivery_requests')
        .select()
        .eq('customer_id', uid)
        .not('delivery_status', 'in',
            '("delivered","cancelled","failed")')
        .order('requested_at', ascending: false)
        .limit(1);
    if ((data as List).isEmpty) return null;
    return PackageDeliveryRequest.fromJson(data.first);
  }

  // ── Customer: delivery history ──────────────────────────────────────────────

  Future<List<PackageDeliveryRequest>> getMyDeliveryHistory() async {
    final uid = _currentUserId;
    if (uid == null) return [];
    final data = await _supabase
        .from('package_delivery_requests')
        .select()
        .eq('customer_id', uid)
        .order('requested_at', ascending: false);
    return (data as List)
        .map((j) => PackageDeliveryRequest.fromJson(j))
        .toList();
  }

  // ── Driver: my active package delivery ─────────────────────────────────────

  Future<PackageDeliveryRequest?> getMyActiveDeliveryAsDriver() async {
    final uid = _currentUserId;
    if (uid == null) return null;

    final driverRow = await _supabase
        .from('drivers')
        .select('id')
        .eq('user_id', uid)
        .maybeSingle();
    if (driverRow == null) return null;
    final driverId = driverRow['id'] as String;

    final data = await _supabase
        .from('package_delivery_requests')
        .select('*, shipping_companies(name, logo_url)')
        .eq('driver_id', driverId)
        .not('delivery_status', 'in', '("delivered","cancelled","failed")')
        .order('accepted_at', ascending: false)
        .limit(1);
    if ((data as List).isEmpty) return null;
    return PackageDeliveryRequest.fromJson(data.first);
  }

  // ── Driver: available package requests ─────────────────────────────────────

  Future<List<PackageDeliveryRequest>> getAvailablePackageRequests() async {
    final data = await _supabase
        .from('package_delivery_requests')
        .select('*, shipping_companies(name, logo_url)')
        .eq('delivery_status', 'searching_driver')
        .order('requested_at', ascending: false);
    return (data as List)
        .map((j) => PackageDeliveryRequest.fromJson(j))
        .toList();
  }

  // ── Driver: accept a package request ───────────────────────────────────────

  Future<PackageDeliveryRequest> acceptPackageRequest(
      String deliveryRequestId) async {
    final res = await _callFn('accept-package-delivery', {
      'delivery_request_id': deliveryRequestId,
    });
    return PackageDeliveryRequest.fromJson(
        res['delivery_request'] as Map<String, dynamic>);
  }

  // ── Realtime: stream delivery request ──────────────────────────────────────

  Stream<PackageDeliveryRequest> streamDeliveryRequest(
      String deliveryRequestId) {
    return _supabase
        .from('package_delivery_requests')
        .stream(primaryKey: ['id'])
        .eq('id', deliveryRequestId)
        .map((rows) {
          if (rows.isEmpty) throw Exception('Delivery request not found');
          return PackageDeliveryRequest.fromJson(rows.first);
        });
  }

  // ── Fetch tracking number from shipping company API ─────────────────────────

  /// Calls the `fetch-tracking-number` edge function.
  /// [shippingCompanyId] is always required.
  /// [packageRecordId] is optional — only admins may pass this to target a
  /// specific record; customers leave it null.
  ///
  /// Returns a map with at minimum:
  ///   tracking_number, tracking_status, package (full record map)
  Future<Map<String, dynamic>> fetchTrackingNumber({
    required String shippingCompanyId,
    String? trackingNumber,
    String? packageRecordId,
  }) async {
    return _callFn('fetch-tracking-number', {
      'shipping_company_id': shippingCompanyId,
      if (trackingNumber != null) 'tracking_number': trackingNumber,
      if (packageRecordId != null) 'package_record_id': packageRecordId,
    });
  }

  // ── Package record lookup ───────────────────────────────────────────────────

  Future<PackageRecord?> getPackageRecord(String packageRecordId) async {
    final data = await _supabase
        .from('package_records')
        .select()
        .eq('id', packageRecordId)
        .single();
    return PackageRecord.fromJson(data);
  }
}

class PackageAuthException implements Exception {
  final String message;
  const PackageAuthException(this.message);
  @override
  String toString() => message;
}
