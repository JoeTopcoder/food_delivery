import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/supabase_config.dart';

/// A company that sponsors employee orders.
class Company {
  final String id;
  final String name;
  final String? adminUserId;
  final String? contactEmail;
  final String? contactPhone;
  final String deliveryAddress;
  final double? latitude;
  final double? longitude;
  final int radiusKm;
  final bool isActive;
  const Company({
    required this.id,
    required this.name,
    this.adminUserId,
    this.contactEmail,
    this.contactPhone,
    required this.deliveryAddress,
    this.latitude,
    this.longitude,
    this.radiusKm = 3,
    this.isActive = true,
  });
  factory Company.fromMap(Map<String, dynamic> m) => Company(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        adminUserId: m['admin_user_id'] as String?,
        contactEmail: m['contact_email'] as String?,
        contactPhone: m['contact_phone'] as String?,
        deliveryAddress: (m['delivery_address'] ?? '') as String,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        radiusKm: (m['radius_km'] as num?)?.toInt() ?? 3,
        isActive: (m['is_active'] as bool?) ?? true,
      );
}

/// An employee's membership in a company.
class CompanyMembership {
  final String id;
  final String companyId;
  final String userId;
  final String status; // pending | approved | rejected | suspended
  final String? companyName;
  final String? userName;
  final String? userEmail;
  const CompanyMembership({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.status,
    this.companyName,
    this.userName,
    this.userEmail,
  });
  factory CompanyMembership.fromMap(Map<String, dynamic> m) => CompanyMembership(
        id: m['id'] as String,
        companyId: m['company_id'] as String,
        userId: m['user_id'] as String,
        status: (m['status'] ?? 'pending') as String,
        companyName: (m['companies'] is Map)
            ? (m['companies']['name'] as String?)
            : m['company_name'] as String?,
        userName: (m['users'] is Map) ? (m['users']['name'] as String?) : m['user_name'] as String?,
        userEmail: (m['users'] is Map) ? (m['users']['email'] as String?) : m['user_email'] as String?,
      );
}

/// Server wrapper for Company-Sponsored Ordering. All money/eligibility is
/// decided by the SECURITY DEFINER RPCs — this is a thin, honest client.
class CompanyService {
  final _c = SupabaseConfig.client;

  // ── Employee: discovery & membership ────────────────────────────────────
  Future<List<Company>> searchCompanies(String query) async {
    var q = _c.from('companies').select().eq('is_active', true);
    if (query.trim().isNotEmpty) q = q.ilike('name', '%${query.trim()}%');
    final rows = await q.order('name').limit(30);
    return (rows as List).map((e) => Company.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> apply(String companyId) async {
    await _c.rpc('company_apply', params: {'p_company_id': companyId});
  }

  Future<List<CompanyMembership>> myMemberships() async {
    final rows = await _c
        .from('company_members')
        .select('*, companies(name)')
        .order('applied_at', ascending: false);
    return (rows as List)
        .map((e) => CompanyMembership.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ── Checkout eligibility ────────────────────────────────────────────────
  /// Companies the employee can use for a sponsored order right now
  /// (approved + active + not already used today).
  Future<List<Company>> eligibleForCheckout() async {
    final rows = await _c.rpc('company_eligible_for_checkout');
    return (rows as List)
        .map((e) => Company.fromMap({
              'id': e['company_id'],
              'name': e['name'],
              'delivery_address': e['delivery_address'],
              'latitude': e['latitude'],
              'longitude': e['longitude'],
              'radius_km': e['radius_km'],
            }))
        .toList();
  }

  Future<Map<String, dynamic>> checkRestaurant(String companyId, String restaurantId) async {
    final r = await _c.rpc('company_check_restaurant',
        params: {'p_company_id': companyId, 'p_restaurant_id': restaurantId});
    return Map<String, dynamic>.from(r as Map);
  }

  /// Reserve the day's sponsorship slot. Returns the server result (ok,
  /// reservation_id, estimated_delivery_cents, address, …) or {ok:false, reason}.
  Future<Map<String, dynamic>> reserve(String companyId, String restaurantId) async {
    final r = await _c.rpc('company_reserve_sponsorship',
        params: {'p_company_id': companyId, 'p_restaurant_id': restaurantId});
    return Map<String, dynamic>.from(r as Map);
  }

  Future<void> release(String reservationId) async {
    await _c.rpc('company_release_sponsorship', params: {'p_reservation_id': reservationId});
  }

  // ── Eligible restaurants (within a company's radius) ─────────────────────
  /// Filters restaurants to those within the company's radius, using the same
  /// server distance calc. Returns restaurant rows + distance_km.
  Future<List<Map<String, dynamic>>> eligibleRestaurants(Company company) async {
    final rows = await _c
        .from('restaurants')
        .select('id, name, image_url, cuisine_type, rating, latitude, longitude, address')
        .not('latitude', 'is', null)
        .not('longitude', 'is', null);
    final out = <Map<String, dynamic>>[];
    for (final e in (rows as List)) {
      final m = Map<String, dynamic>.from(e);
      final lat = (m['latitude'] as num?)?.toDouble();
      final lon = (m['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null || company.latitude == null || company.longitude == null) {
        continue;
      }
      final d = _haversineKm(lat, lon, company.latitude!, company.longitude!);
      if (d <= company.radiusKm) {
        m['distance_km'] = double.parse(d.toStringAsFixed(2));
        out.add(m);
      }
    }
    out.sort((a, b) => (a['distance_km'] as double).compareTo(b['distance_km'] as double));
    return out;
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
    final a = (1 - math.cos(dLat)) / 2 +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * (1 - math.cos(dLon)) / 2;
    return r * 2 * math.asin(math.sqrt(a));
  }

  // ── Company admin: profile ──────────────────────────────────────────────
  Future<Company?> myCompany() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return null;
    final rows = await _c.from('companies').select().eq('admin_user_id', uid).limit(1);
    if ((rows as List).isEmpty) return null;
    return Company.fromMap(Map<String, dynamic>.from(rows.first));
  }

  Future<Company> createCompany({
    required String name,
    required String deliveryAddress,
    double? latitude,
    double? longitude,
    int radiusKm = 3,
    String? contactEmail,
    String? contactPhone,
  }) async {
    final uid = _c.auth.currentUser!.id;
    final row = await _c
        .from('companies')
        .insert({
          'name': name,
          'admin_user_id': uid,
          'delivery_address': deliveryAddress,
          'latitude': latitude,
          'longitude': longitude,
          'radius_km': radiusKm.clamp(2, 4),
          'contact_email': contactEmail,
          'contact_phone': contactPhone,
        })
        .select()
        .single();
    return Company.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> updateCompany(String id, Map<String, dynamic> changes) async {
    if (changes.containsKey('radius_km')) {
      changes['radius_km'] = (changes['radius_km'] as int).clamp(2, 4);
    }
    changes['updated_at'] = DateTime.now().toIso8601String();
    await _c.from('companies').update(changes).eq('id', id);
  }

  // ── Company admin: members ──────────────────────────────────────────────
  Future<List<CompanyMembership>> companyMembers(String companyId) async {
    final rows = await _c
        .from('company_members')
        .select('*, users(name, email)')
        .eq('company_id', companyId)
        .order('applied_at', ascending: false);
    return (rows as List)
        .map((e) => CompanyMembership.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> decideMember(String memberId, String status) async {
    await _c.rpc('company_decide_member',
        params: {'p_member_id': memberId, 'p_status': status});
  }

  // ── Company admin: dashboard ────────────────────────────────────────────
  Future<Map<String, dynamic>> dailyEstimate(String companyId, {DateTime? date}) async {
    final r = await _c.rpc('company_daily_estimate', params: {
      'p_company_id': companyId,
      if (date != null) 'p_date': _ymd(date),
    });
    return Map<String, dynamic>.from(r as Map);
  }

  Future<List<Map<String, dynamic>>> companyOrders(String companyId, {DateTime? date}) async {
    final rows = await _c.rpc('company_orders', params: {
      'p_company_id': companyId,
      if (date != null) 'p_date': _ymd(date),
    });
    return (rows as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Immediate account summary (flat fees): today's counts + all-time ledger
  /// totals, paid and outstanding (cents).
  Future<Map<String, dynamic>> accountSummary(String companyId, {DateTime? date}) async {
    final r = await _c.rpc('company_account_summary', params: {
      'p_company_id': companyId,
      if (date != null) 'p_date': _ymd(date),
    });
    return Map<String, dynamic>.from(r as Map);
  }

  /// HotBite admin records a company payment against the outstanding balance.
  Future<void> recordPayment(String companyId, int amountCents,
      {String? reference, String? note}) async {
    await _c.rpc('company_record_payment', params: {
      'p_company_id': companyId,
      'p_amount_cents': amountCents,
      'p_reference': reference,
      'p_note': note,
    });
  }

  Future<List<Map<String, dynamic>>> statements(String companyId) async {
    final rows = await _c
        .from('company_daily_statements')
        .select()
        .eq('company_id', companyId)
        .order('statement_date', ascending: false)
        .limit(60);
    return (rows as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final companyServiceProvider = Provider<CompanyService>((ref) => CompanyService());
