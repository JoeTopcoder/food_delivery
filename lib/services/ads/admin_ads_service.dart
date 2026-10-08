import '../../config/supabase_config.dart';
import '../../models/catalog/ad_model.dart';

/// Admin client for the advertising console. All writes go through the
/// SECURITY DEFINER lifecycle RPCs (which re-check is_admin server-side).
class AdminAdsService {
  final _c = SupabaseConfig.client;

  Future<Map<String, dynamic>> settings() async {
    final r = await _c.from('ad_settings').select().eq('id', 1).single();
    return Map<String, dynamic>.from(r);
  }

  Future<void> updateSettings(Map<String, dynamic> patch) async {
    await _c.from('ad_settings').update(patch).eq('id', 1);
  }

  Future<List<AdRequest>> allRequests() async {
    final rows = await _c
        .from('ad_requests')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => AdRequest.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AdCreative>> creatives(String requestId) async {
    final rows = await _c.from('ad_creatives').select().eq('request_id', requestId)
        .order('version', ascending: false);
    return (rows as List).map((e) => AdCreative.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<AdQuote>> quotes(String requestId) async {
    final rows = await _c.from('ad_quotes').select('*, ad_quote_items(*)')
        .eq('request_id', requestId).order('version', ascending: false);
    return (rows as List).map((e) => AdQuote.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<AdCampaign>> campaignsForRequest(String requestId) async {
    final rows = await _c.from('ad_campaigns').select().eq('request_id', requestId)
        .order('created_at', ascending: false);
    return (rows as List).map((e) => AdCampaign.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Map<String, dynamic>?> campaignMetrics(String campaignId) async {
    await _c.rpc('ad_rebuild_daily_metrics', params: {'p_campaign_id': campaignId});
    final rows = await _c.from('ad_daily_metrics').select().eq('campaign_id', campaignId);
    int imp = 0, vs = 0, vc = 0, clk = 0, ord = 0, spend = 0;
    for (final r in (rows as List)) {
      imp += (r['impressions'] as num?)?.toInt() ?? 0;
      vs += (r['video_starts'] as num?)?.toInt() ?? 0;
      vc += (r['video_completions'] as num?)?.toInt() ?? 0;
      clk += (r['cta_clicks'] as num?)?.toInt() ?? 0;
      ord += (r['attributed_orders'] as num?)?.toInt() ?? 0;
      spend += (r['spend_cents'] as num?)?.toInt() ?? 0;
    }
    return {'impressions': imp, 'video_starts': vs, 'video_completions': vc,
            'cta_clicks': clk, 'attributed_orders': ord, 'spend_cents': spend};
  }

  Future<void> reviewRequest(String id, String decision, {String? reason}) =>
      _c.rpc('ad_review_request', params: {'p_request_id': id, 'p_decision': decision, 'p_reason': reason});

  Future<void> issueQuote(String requestId, {int productionCents = 0, int placementCents = 0}) {
    final items = <Map<String, dynamic>>[];
    if (productionCents > 0) items.add({'kind': 'production', 'description': 'Content production', 'amount_cents': productionCents});
    if (placementCents > 0) items.add({'kind': 'placement', 'description': 'Placement', 'amount_cents': placementCents});
    return _c.rpc('ad_issue_quote', params: {'p_request_id': requestId, 'p_items': items});
  }

  Future<void> markCreativeReady(String creativeId, String playbackUrl,
          {String? thumbnailUrl, int? duration}) =>
      _c.rpc('ad_mark_creative_ready', params: {
        'p_creative_id': creativeId, 'p_playback_url': playbackUrl,
        'p_thumbnail_url': thumbnailUrl, 'p_duration': duration,
      });

  Future<void> decideCreative(String creativeId, bool approve, {String? notes}) =>
      _c.rpc('ad_decide_creative', params: {'p_creative_id': creativeId, 'p_approve': approve, 'p_notes': notes});

  Future<String> createCampaign(String requestId, String creativeId,
          {String? quoteId, String destinationType = 'menu'}) async =>
      await _c.rpc('ad_create_campaign', params: {
        'p_request_id': requestId, 'p_creative_id': creativeId,
        'p_quote_id': quoteId, 'p_destination_type': destinationType,
      }) as String;

  Future<void> reserveBooking(String campaignId, int slot, DateTime starts, DateTime ends) =>
      _c.rpc('ad_reserve_booking', params: {
        'p_campaign_id': campaignId, 'p_slot': slot,
        'p_starts': starts.toUtc().toIso8601String(), 'p_ends': ends.toUtc().toIso8601String(),
      });

  Future<void> verifyPayment(String campaignId, int amountCents, String kind, String idempotencyKey) =>
      _c.rpc('ad_verify_payment', params: {
        'p_campaign_id': campaignId, 'p_amount_cents': amountCents, 'p_kind': kind,
        'p_method': 'manual', 'p_idempotency_key': idempotencyKey,
      });

  Future<void> activate(String campaignId) =>
      _c.rpc('ad_activate_campaign', params: {'p_campaign_id': campaignId});

  Future<void> setState(String campaignId, String action, {String? reason}) =>
      _c.rpc('ad_set_campaign_state', params: {'p_campaign_id': campaignId, 'p_action': action, 'p_reason': reason});
}
