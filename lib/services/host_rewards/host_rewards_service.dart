import '../../config/supabase_config.dart';

/// Admin-facing data layer for Host Rewards. All reads are RLS-scoped to admins;
/// all mutations go through the `is_admin()`-gated SECURITY DEFINER RPCs, so the
/// client never computes commissions or balances. Money is stored in integer
/// cents — convert with [centsToJmd] for display.
class HostRewardsService {
  final _client = SupabaseConfig.client;

  static const String referralBaseUrl = 'https://thehotbite.com/host';
  String referralUrl(String code) => '$referralBaseUrl/$code';
  static String centsToJmd(int? cents) =>
      'J\$${((cents ?? 0) / 100).toStringAsFixed(2)}';

  // ── Overview ───────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> overview() async {
    Future<int> count(String table, [Map<String, Object> eq = const {}]) async {
      var q = _client.from(table).select('id');
      eq.forEach((k, v) => q = q.eq(k, v));
      final rows = await q;
      return (rows as List).length;
    }

    int sumCents(List rows) =>
        rows.fold<int>(0, (s, r) => s + ((r['amount_cents'] as num?)?.toInt() ?? 0));

    final pending = await _client
        .from('host_commissions')
        .select('amount_cents')
        .eq('status', 'pending');
    final payable = await _client
        .from('host_commissions')
        .select('amount_cents')
        .eq('status', 'payable');
    final paid = await _client
        .from('host_commissions')
        .select('amount_cents')
        .eq('status', 'paid');

    return {
      'hosts_active': await count('hosts', {'status': 'active'}),
      'properties_active': await count('host_properties', {'status': 'active'}),
      'referrals_active': await count('host_referrals', {'status': 'active'}),
      'pending_cents': sumCents(pending as List),
      'payable_cents': sumCents(payable as List),
      'paid_cents': sumCents(paid as List),
    };
  }

  // ── Hosts ────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> hosts() async {
    final rows = await _client
        .from('hosts')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<String> createHost({
    required String fullName,
    String? email,
    String? phone,
    String? businessName,
    String status = 'active',
    String? notes,
  }) async {
    final id = await _client.rpc('host_admin_create_host', params: {
      'p_full_name': fullName,
      'p_email': email,
      'p_phone': phone,
      'p_business_name': businessName,
      'p_status': status,
      'p_notes': notes,
    });
    return id as String;
  }

  Future<void> setHostStatus(String hostId, String status) async {
    await _client.from('hosts').update({'status': status}).eq('id', hostId);
  }

  /// Links a host record to an existing login (by email) + grants the host role,
  /// so they can sign in to the host portal.
  Future<Map<String, dynamic>> linkHostLogin(String hostId, String email) async {
    final res = await _client.rpc('host_admin_link_user',
        params: {'p_host_id': hostId, 'p_email': email});
    return Map<String, dynamic>.from(res as Map);
  }

  // ── Properties ─────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> properties({String? hostId}) async {
    var q = _client.from('host_properties').select();
    if (hostId != null) q = q.eq('host_id', hostId);
    final rows = await q.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, dynamic>> createProperty({
    required String hostId,
    required String name,
    required String address,
    String? parish,
    String? area,
    double? latitude,
    double? longitude,
    String? instructions,
    int? commissionValueCents,
  }) async {
    final res = await _client.rpc('host_admin_create_property', params: {
      'p_host_id': hostId,
      'p_name': name,
      'p_address': address,
      'p_parish': parish,
      'p_area': area,
      'p_lat': latitude,
      'p_lng': longitude,
      'p_instructions': instructions,
      'p_commission_type': null,
      'p_commission_value_cents': commissionValueCents,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<String> rotateCode(String propertyId) async {
    final code = await _client
        .rpc('host_admin_rotate_code', params: {'p_property_id': propertyId});
    return code as String;
  }

  Future<void> setPropertyStatus(String propertyId, String status) async {
    await _client
        .from('host_properties')
        .update({'status': status}).eq('id', propertyId);
  }

  // ── Commissions ────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> commissions({String? status}) async {
    var q = _client.from('host_commissions').select();
    if (status != null) q = q.eq('status', status);
    final rows = await q.order('created_at', ascending: false).limit(200);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  // ── Payouts ──────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> payouts() async {
    final rows = await _client
        .from('host_payouts')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, dynamic>> approvePayout(String hostId) async {
    final res =
        await _client.rpc('host_admin_approve_payout', params: {'p_host_id': hostId});
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> markPayoutPaid(String payoutId, String reference) async {
    await _client.rpc('host_admin_mark_payout_paid',
        params: {'p_payout_id': payoutId, 'p_reference': reference});
  }

  // ── Settings ───────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> config() async {
    final row = await _client
        .from('host_rewards_config')
        .select()
        .eq('id', 1)
        .maybeSingle();
    final flag = await _client
        .from('app_config')
        .select('value')
        .eq('key', 'host_rewards_enabled')
        .maybeSingle();
    return {
      ...?row,
      'enabled': (flag?['value'] as String?) == 'true',
    };
  }

  Future<void> updateConfig({
    int? defaultCommissionCents,
    int? referralDays,
    int? holdPeriodDays,
    bool? enabled,
  }) async {
    final updates = <String, dynamic>{'updated_at': DateTime.now().toUtc().toIso8601String()};
    if (defaultCommissionCents != null) {
      updates['default_commission_cents'] = defaultCommissionCents;
    }
    if (referralDays != null) updates['referral_days'] = referralDays;
    if (holdPeriodDays != null) updates['hold_period_days'] = holdPeriodDays;
    if (updates.length > 1) {
      await _client.from('host_rewards_config').update(updates).eq('id', 1);
    }
    if (enabled != null) {
      await _client
          .from('app_config')
          .update({'value': enabled ? 'true' : 'false'}).eq('key', 'host_rewards_enabled');
    }
  }
}
