import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../config/supabase_config.dart';
import '../../models/catalog/ad_model.dart';

/// Restaurant-dashboard client for advertising. Reads/writes are gated by RLS
/// (restaurant owner / active staff) and the SECURITY DEFINER lifecycle RPCs.
class RestaurantAdsService {
  final _c = SupabaseConfig.client;

  Future<List<AdRequest>> myRequests(String restaurantId) async {
    final rows = await _c
        .from('ad_requests')
        .select()
        .eq('restaurant_id', restaurantId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => AdRequest.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AdCreative>> creatives(String requestId) async {
    final rows = await _c
        .from('ad_creatives')
        .select()
        .eq('request_id', requestId)
        .order('version', ascending: false);
    return (rows as List)
        .map((e) => AdCreative.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AdQuote>> quotes(String requestId) async {
    final rows = await _c
        .from('ad_quotes')
        .select('*, ad_quote_items(*)')
        .eq('request_id', requestId)
        .order('version', ascending: false);
    return (rows as List)
        .map((e) => AdQuote.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AdCampaign>> campaigns(String restaurantId) async {
    final rows = await _c
        .from('ad_campaigns')
        .select()
        .eq('restaurant_id', restaurantId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => AdCampaign.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Create a draft request. Returns the new request id.
  Future<String> createRequest({
    required String restaurantId,
    required String kind, // self_video | self_image | produce
    required String title,
    String? headline,
    String? description,
    String? productionBrief,
    bool wantsPlacement = true,
    bool rightsConfirmed = false,
    String? contactName,
    String? contactPhone,
    String? contactEmail,
  }) async {
    final row = await _c.from('ad_requests').insert({
      'restaurant_id': restaurantId,
      'kind': kind,
      'title': title,
      'headline': headline,
      'description': description,
      'production_brief': productionBrief,
      'wants_placement': wantsPlacement,
      'rights_confirmed': rightsConfirmed,
      'contact_name': contactName,
      'contact_phone': contactPhone,
      'contact_email': contactEmail,
    }).select('id').single();
    return row['id'] as String;
  }

  /// Upload a creative file to the private raw bucket and attach it to a request
  /// as a new version, then kick off server-side processing.
  Future<void> uploadCreative({
    required String requestId,
    required String restaurantId,
    required String mediaType, // image | video
    required Uint8List bytes,
    required String contentType,
    required String ext,
    bool rightsConfirmed = true,
  }) async {
    final path =
        '$restaurantId/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _c.storage.from('ad-assets-raw').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    final creativeId = await _c.rpc('ad_new_creative', params: {
      'p_request_id': requestId,
      'p_media_type': mediaType,
      'p_source': 'restaurant',
      'p_raw_path': path,
      'p_rights': rightsConfirmed,
    });
    // Best-effort: trigger processing (image auto-promotes; video needs transcode).
    try {
      await _c.functions.invoke('process-ad-media',
          body: {'creative_id': creativeId});
    } catch (_) {/* processing can be retried by admin */}
  }

  Future<void> submitRequest(String requestId) =>
      _c.rpc('ad_submit_request', params: {'p_request_id': requestId});

  Future<void> respondQuote(String quoteId, bool accept) =>
      _c.rpc('ad_respond_quote', params: {'p_quote_id': quoteId, 'p_accept': accept});

  Future<void> decideCreative(String creativeId, bool approve, {String? notes}) =>
      _c.rpc('ad_decide_creative',
          params: {'p_creative_id': creativeId, 'p_approve': approve, 'p_notes': notes});
}
