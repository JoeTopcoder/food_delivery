import '../../config/supabase_config.dart';

/// Client for restaurant staff management, presence and shift reconciliation.
/// Thin wrapper over the server RPCs / edge functions — all authorization,
/// role rules and money math are enforced server-side.
class StaffService {
  final _c = SupabaseConfig.client;

  // ── Memberships (which restaurants the current user belongs to) ────────────
  Future<List<Map<String, dynamic>>> myMemberships() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return [];
    final r = await _c
        .from('restaurant_staff')
        .select('restaurant_id, role, is_active, restaurants(name)')
        .eq('user_id', uid)
        .eq('is_active', true);
    return (r as List).cast<Map<String, dynamic>>();
  }

  // ── Staff management (owner/manager) ───────────────────────────────────────
  Future<List<Map<String, dynamic>>> listMembers(String restaurantId) async {
    final r = await _c.rpc('staff_list_members', params: {'p_restaurant': restaurantId});
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> pendingInvites(String restaurantId) async {
    final r = await _c
        .from('staff_invitations')
        .select('id, email, role, created_at, expires_at')
        .eq('restaurant_id', restaurantId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<({bool ok, String? reason, bool emailed})> invite(
      String restaurantId, String email, String role) async {
    try {
      final res = await _c.functions.invoke('staff-invite',
          body: {'restaurant_id': restaurantId, 'email': email, 'role': role});
      final d = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      return (ok: d['ok'] == true, reason: d['reason']?.toString(), emailed: d['emailed'] == true);
    } catch (_) {
      return (ok: false, reason: 'request_failed', emailed: false);
    }
  }

  Future<bool> revokeInvite(String invitationId) async =>
      ((await _c.rpc('staff_revoke_invitation', params: {'p_invitation_id': invitationId})) as Map?)?['ok'] == true;

  Future<({bool ok, String? reason})> setActive(String restaurantId, String userId, bool active) async {
    final r = (await _c.rpc('staff_set_active',
        params: {'p_restaurant': restaurantId, 'p_user': userId, 'p_active': active})) as Map?;
    return (ok: r?['ok'] == true, reason: r?['reason']?.toString());
  }

  Future<({bool ok, String? reason})> setRole(String restaurantId, String userId, String role) async {
    final r = (await _c.rpc('staff_set_role',
        params: {'p_restaurant': restaurantId, 'p_user': userId, 'p_role': role})) as Map?;
    return (ok: r?['ok'] == true, reason: r?['reason']?.toString());
  }

  Future<bool> passwordReset(String restaurantId, String userId) async {
    try {
      final res = await _c.functions.invoke('staff-password-reset',
          body: {'restaurant_id': restaurantId, 'user_id': userId});
      return (res.data as Map?)?['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<({bool ok, String? reason, String? restaurantId})> acceptInvite(String token) async {
    final r = (await _c.rpc('staff_accept_invitation', params: {'p_token': token})) as Map?;
    return (ok: r?['ok'] == true, reason: r?['reason']?.toString(), restaurantId: r?['restaurant_id']?.toString());
  }

  // ── Presence ───────────────────────────────────────────────────────────────
  Future<void> heartbeat(String restaurantId, String sessionId) async {
    try {
      await _c.rpc('cashier_heartbeat', params: {'p_restaurant': restaurantId, 'p_session': sessionId});
    } catch (_) {/* transient */}
  }

  Future<void> endPresence(String restaurantId, String sessionId) async {
    try {
      await _c.rpc('cashier_presence_end', params: {'p_restaurant': restaurantId, 'p_session': sessionId});
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> dashboardCounts(String restaurantId) async {
    final r = await _c.rpc('cashier_dashboard_counts', params: {'p_restaurant': restaurantId});
    return (r as Map?)?.cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> presenceList(String restaurantId) async {
    final r = await _c.rpc('cashier_presence_list', params: {'p_restaurant': restaurantId});
    return (r as List).cast<Map<String, dynamic>>();
  }

  // ── Shifts / reconciliation ────────────────────────────────────────────────
  Future<Map<String, dynamic>?> myOpenShift(String restaurantId) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return null;
    final r = await _c
        .from('cashier_shifts')
        .select('*')
        .eq('restaurant_id', restaurantId)
        .eq('cashier_user_id', uid)
        .inFilter('status', ['open', 'submitted'])
        .maybeSingle();
    return r;
  }

  Future<({bool ok, String? reason, String? shiftId})> openShift(String restaurantId, int openingFloatCents) async {
    final r = (await _c.rpc('shift_open',
        params: {'p_restaurant': restaurantId, 'p_opening_float_cents': openingFloatCents})) as Map?;
    return (ok: r?['ok'] == true, reason: r?['reason']?.toString(), shiftId: r?['shift_id']?.toString());
  }

  Future<({bool ok, String? reason, int? expected})> recordCash(
      String shiftId, String kind, int amountCents, {String? orderId, String? note}) async {
    final r = (await _c.rpc('shift_record_cash', params: {
      'p_shift': shiftId, 'p_kind': kind, 'p_amount_cents': amountCents, 'p_order_id': orderId, 'p_note': note,
    })) as Map?;
    return (ok: r?['ok'] == true, reason: r?['reason']?.toString(), expected: (r?['expected_cash_cents'] as num?)?.toInt());
  }

  Future<List<Map<String, dynamic>>> shiftMovements(String shiftId) async {
    final r = await _c.from('shift_cash_movements').select('kind, amount_cents, note, created_at')
        .eq('shift_id', shiftId).order('created_at');
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<({bool ok, String? reason, int? variance})> submitShift(
      String shiftId, int countedCents, String? explanation) async {
    final r = (await _c.rpc('shift_submit', params: {
      'p_shift': shiftId, 'p_counted_cash_cents': countedCents, 'p_explanation': explanation,
    })) as Map?;
    return (ok: r?['ok'] == true, reason: r?['reason']?.toString(), variance: (r?['variance_cents'] as num?)?.toInt());
  }

  Future<List<Map<String, dynamic>>> shiftsByStatus(String restaurantId, List<String> statuses) async {
    final r = await _c.from('cashier_shifts')
        .select('*, users:cashier_user_id(name)')
        .eq('restaurant_id', restaurantId)
        .inFilter('status', statuses)
        .order('opened_at', ascending: false)
        .limit(100);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<({bool ok, String? reason, String? status})> approveShift(
      String shiftId, bool approve, String? reason) async {
    final r = (await _c.rpc('shift_approve',
        params: {'p_shift': shiftId, 'p_approve': approve, 'p_reason': reason})) as Map?;
    return (ok: r?['ok'] == true, reason: r?['reason']?.toString(), status: r?['status']?.toString());
  }
}
