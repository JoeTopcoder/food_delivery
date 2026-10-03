import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin client for the HotBite Member Referral Rewards RPCs. All reward math is
/// on the server; this only reads/relays. See migrations 20260925*_member_referral_*.
class MemberReferralService {
  MemberReferralService(this._client);
  final SupabaseClient _client;

  /// Programme summary for the current user (rates, counts, progress, balances).
  Future<Map<String, dynamic>> mySummary() async {
    final res = await _client.rpc('referral_my_summary');
    return (res is Map) ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  /// Two-level tree. [parent] null → my direct referrals (level 1); a direct
  /// referral's id → that account's referrals (level 2). Deeper is refused.
  Future<List<Map<String, dynamic>>> myTree({
    String? parent,
    String filter = 'all',
    int limit = 25,
    int offset = 0,
  }) async {
    final res = await _client.rpc('referral_my_tree', params: {
      'p_parent': parent,
      'p_filter': filter,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (res is List)
        ? res.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
  }

  /// The two-level tree as a graph (nodes + parent linkage) for the visual
  /// pyramid diagram. [l1Limit] caps how many direct branches are drawn.
  Future<List<Map<String, dynamic>>> treeGraph({int l1Limit = 12}) async {
    final res = await _client.rpc('referral_tree_graph', params: {'p_l1_limit': l1Limit});
    return (res is List)
        ? res.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
  }

  /// Itemized reward history for the current user.
  Future<List<Map<String, dynamic>>> myRewards({int limit = 50, int offset = 0}) async {
    final res = await _client.rpc('referral_my_rewards',
        params: {'p_limit': limit, 'p_offset': offset});
    return (res is List)
        ? res.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
  }

  /// Set the current user's referrer by code (affects FUTURE orders only).
  Future<Map<String, dynamic>> setReferrer(String code) async {
    final res = await _client.rpc('referral_set_referrer', params: {'p_code': code});
    return (res is Map) ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  // ── Admin ──
  Future<Map<String, dynamic>> adminOverview(DateTime from, DateTime to) async {
    final res = await _client.rpc('admin_referral_overview', params: {
      'p_from': from.toUtc().toIso8601String(),
      'p_to': to.toUtc().toIso8601String(),
    });
    return (res is Map) ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> adminAdjust(String earnerId, int amountCents, String reason) async {
    final res = await _client.rpc('admin_referral_adjust', params: {
      'p_earner': earnerId,
      'p_amount_cents': amountCents,
      'p_reason': reason,
    });
    return (res is Map) ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }
}
