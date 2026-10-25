import '../../config/supabase_config.dart';

/// Host-facing data layer. Every read is RLS-scoped to the logged-in host's own
/// records (self-read policies), and the dashboard summary comes from the
/// `host_my_dashboard` RPC (pinned to auth.uid()). Hosts never see other hosts'
/// data, customer details, or run payouts.
class HostPortalService {
  final _client = SupabaseConfig.client;

  static const String referralBaseUrl = 'https://thehotbite.com/host';
  String referralUrl(String code) => '$referralBaseUrl/$code';
  static String centsToJmd(int? cents) =>
      'J\$${((cents ?? 0) / 100).toStringAsFixed(2)}';

  Future<Map<String, dynamic>> dashboard() async {
    final res = await _client.rpc('host_my_dashboard');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> myProperties() async {
    final rows = await _client
        .from('host_properties')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> myCommissions() async {
    final rows = await _client
        .from('host_commissions')
        .select()
        .order('created_at', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> myPayouts() async {
    final rows = await _client
        .from('host_payouts')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }
}
