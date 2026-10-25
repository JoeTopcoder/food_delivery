import '../../config/supabase_config.dart';
import '../../utils/app_logger.dart';

/// Customer-side Host Rewards: claim a property referral from a scanned QR code
/// and save that property as a delivery address. All attribution is validated
/// server-side by the `host_claim_referral` RPC (pinned to auth.uid()).
class HostReferralService {
  final _client = SupabaseConfig.client;

  /// Extracts a referral code from a scanned value — a full URL
  /// (https://thehotbite.com/host/HBHOST-XXXX) or a bare code.
  static String? parseCode(String raw) {
    final v = raw.trim();
    final m = RegExp(r'(HBHOST-[A-Za-z0-9]+)', caseSensitive: false).firstMatch(v);
    return m?.group(1)?.toUpperCase();
  }

  /// Claims the referral. Returns the result map: {ok, property:{...}} or
  /// {ok:false, error:'already_referred'|'invalid_or_inactive_property'|...}.
  Future<Map<String, dynamic>> claim(String code) async {
    try {
      final res = await _client.rpc('host_claim_referral', params: {'p_code': code});
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      AppLogger.error('host_claim_referral failed: $e');
      return {'ok': false, 'error': 'network'};
    }
  }

  /// Saves a claimed property as a delivery address linked to the property, so
  /// checkout can attribute an order delivered there. Idempotent-ish: skips if an
  /// address for this property already exists.
  Future<void> saveClaimedProperty(Map<String, dynamic> property) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    final propertyId = property['id'] as String?;
    if (propertyId == null) return;

    final existing = await _client
        .from('user_addresses')
        .select('id')
        .eq('user_id', uid)
        .eq('host_property_id', propertyId)
        .maybeSingle();
    if (existing != null) return;

    await _client.from('user_addresses').insert({
      'user_id': uid,
      'label': property['name'] ?? 'Host stay',
      'address': property['address'] ?? '',
      if (property['latitude'] != null) 'latitude': property['latitude'],
      if (property['longitude'] != null) 'longitude': property['longitude'],
      'is_default': false,
      'host_property_id': propertyId,
    });
  }
}
