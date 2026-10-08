import '../../config/supabase_config.dart';
import '../../models/catalog/ad_model.dart';
import '../../utils/app_logger.dart';

/// Customer-facing client for the sponsored-ads backend. Reads eligible ads and
/// reports analytics events. All calls are best-effort: advertising must never
/// block browsing or checkout, so failures are swallowed (logged only).
class AdsService {
  final _c = SupabaseConfig.client;

  /// Eligible sponsored ads for the given delivery point. Returns [] on any
  /// failure or when the feature is disabled (the RPC returns nothing then).
  Future<List<SponsoredAd>> getSponsoredAds({
    double? lat,
    double? lng,
    int limit = 3,
  }) async {
    try {
      final res = await _c.rpc('get_sponsored_ads', params: {
        'p_lat': lat,
        'p_lng': lng,
        'p_limit': limit,
      });
      if (res is! List) return const [];
      return res
          .whereType<Map>()
          .map((e) => SponsoredAd.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      AppLogger.warning('getSponsoredAds failed: $e');
      return const [];
    }
  }

  /// Report an analytics event. Deduped server-side via [dedupeKey]; never throws.
  Future<void> recordEvent({
    required String campaignId,
    required String eventType, // impression | video_start | video_complete | cta_click
    required String sessionId,
    String? creativeId,
    String? dedupeKey,
  }) async {
    try {
      await _c.rpc('ad_record_event', params: {
        'p_campaign_id': campaignId,
        'p_event_type': eventType,
        'p_session_id': sessionId,
        'p_creative_id': creativeId,
        'p_dedupe_key': dedupeKey,
      });
    } catch (e) {
      AppLogger.warning('ad recordEvent($eventType) failed: $e');
    }
  }
}
