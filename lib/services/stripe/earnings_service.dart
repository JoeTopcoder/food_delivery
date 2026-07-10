import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/stripe/earnings_summary_model.dart';
import '../../models/stripe/ledger_entry_model.dart';

class EarningsService {
  EarningsService(this._client);
  final SupabaseClient _client;

  /// Returns summary, payout settings, connected account status, and recent payouts.
  Future<Map<String, dynamic>> getEarningsSummary({required String role}) async {
    final res = await _client.functions.invoke(
      'get-earnings-summary',
      body: {'role': role},
    );
    _checkError(res);
    return res.data as Map<String, dynamic>;
  }

  /// Fetch ledger entries for the current user from Supabase directly.
  Future<List<LedgerEntry>> getLedgerEntries({
    required String userId,
    required String role,
    int limit = 50,
    String? status,
  }) async {
    var query = _client
        .from('earnings_ledger')
        .select('*')
        .eq('user_id', userId)
        .eq('role', role);

    if (status != null) {
      query = query.eq('status', status);
    }

    final rows = await query
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((r) => LedgerEntry.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Convenience: parse EarningsSummary from getEarningsSummary response.
  Future<EarningsSummary> fetchSummary({required String role}) async {
    final data = await getEarningsSummary(role: role);
    final summaryJson = data['summary'] as Map<String, dynamic>?;
    return summaryJson != null
        ? EarningsSummary.fromJson(summaryJson)
        : EarningsSummary.zero();
  }

  void _checkError(FunctionResponse res) {
    final data = res.data;
    if (data is Map && data.containsKey('error')) {
      throw Exception(data['error']);
    }
  }
}
