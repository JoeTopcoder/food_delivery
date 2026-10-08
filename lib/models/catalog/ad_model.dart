/// A sponsored ad returned by the `get_sponsored_ads` RPC. Contains ONLY the
/// safe, customer-visible fields — never quotes, payments or raw assets.
class SponsoredAd {
  final String campaignId;
  final String creativeId;
  final String restaurantId;
  final String? restaurantName;
  final String? logoUrl;
  final String mediaType; // 'image' | 'video'
  final String? playbackUrl;
  final String? thumbnailUrl;
  final String? captionsUrl;
  final String? headline;
  final String? destinationType; // 'menu' | 'dish'
  final String? destinationDishId;

  const SponsoredAd({
    required this.campaignId,
    required this.creativeId,
    required this.restaurantId,
    this.restaurantName,
    this.logoUrl,
    required this.mediaType,
    this.playbackUrl,
    this.thumbnailUrl,
    this.captionsUrl,
    this.headline,
    this.destinationType,
    this.destinationDishId,
  });

  bool get isVideo => mediaType == 'video';

  factory SponsoredAd.fromJson(Map<String, dynamic> j) => SponsoredAd(
    campaignId: j['campaign_id'] as String,
    creativeId: j['creative_id'] as String,
    restaurantId: j['restaurant_id'] as String,
    restaurantName: j['restaurant_name'] as String?,
    logoUrl: j['logo_url'] as String?,
    mediaType: (j['media_type'] as String?) ?? 'image',
    playbackUrl: j['playback_url'] as String?,
    thumbnailUrl: j['thumbnail_url'] as String?,
    captionsUrl: j['captions_url'] as String?,
    headline: j['headline'] as String?,
    destinationType: j['destination_type'] as String?,
    destinationDishId: j['destination_dish_id'] as String?,
  );
}

int? _asInt(dynamic v) => v == null ? null : (v is int ? v : int.tryParse(v.toString()));

/// An advertising request (dashboard-side; full record, restaurant-scoped by RLS).
class AdRequest {
  final String id;
  final String restaurantId;
  final String kind; // self_video | self_image | produce
  final bool wantsPlacement;
  final String title;
  final String? headline;
  final String? description;
  final String? productionBrief;
  final String status; // draft|submitted|in_review|approved|rejected|withdrawn
  final String? reviewReason;
  final DateTime createdAt;

  const AdRequest({
    required this.id,
    required this.restaurantId,
    required this.kind,
    required this.wantsPlacement,
    required this.title,
    this.headline,
    this.description,
    this.productionBrief,
    required this.status,
    this.reviewReason,
    required this.createdAt,
  });

  factory AdRequest.fromJson(Map<String, dynamic> j) => AdRequest(
    id: j['id'] as String,
    restaurantId: j['restaurant_id'] as String,
    kind: j['kind'] as String,
    wantsPlacement: j['wants_placement'] == true,
    title: (j['title'] as String?) ?? 'Untitled',
    headline: j['headline'] as String?,
    description: j['description'] as String?,
    productionBrief: j['production_brief'] as String?,
    status: (j['status'] as String?) ?? 'draft',
    reviewReason: j['review_reason'] as String?,
    createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
  );
}

class AdCreative {
  final String id;
  final String requestId;
  final int version;
  final String mediaType; // image|video
  final String source; // restaurant|hotbite
  final String status;
  final String? playbackUrl;
  final String? thumbnailUrl;
  final String? headline;
  final String? changeNotes;
  final String? processingError;

  const AdCreative({
    required this.id,
    required this.requestId,
    required this.version,
    required this.mediaType,
    required this.source,
    required this.status,
    this.playbackUrl,
    this.thumbnailUrl,
    this.headline,
    this.changeNotes,
    this.processingError,
  });

  bool get isVideo => mediaType == 'video';

  factory AdCreative.fromJson(Map<String, dynamic> j) => AdCreative(
    id: j['id'] as String,
    requestId: j['request_id'] as String,
    version: _asInt(j['version']) ?? 1,
    mediaType: (j['media_type'] as String?) ?? 'image',
    source: (j['source'] as String?) ?? 'restaurant',
    status: (j['status'] as String?) ?? 'uploaded',
    playbackUrl: j['playback_url'] as String?,
    thumbnailUrl: j['thumbnail_url'] as String?,
    headline: j['headline'] as String?,
    changeNotes: j['change_notes'] as String?,
    processingError: j['processing_error'] as String?,
  );
}

class AdQuoteItem {
  final String kind; // production|placement
  final String? description;
  final int amountCents;
  const AdQuoteItem({required this.kind, this.description, required this.amountCents});
  factory AdQuoteItem.fromJson(Map<String, dynamic> j) => AdQuoteItem(
    kind: j['kind'] as String,
    description: j['description'] as String?,
    amountCents: _asInt(j['amount_cents']) ?? 0,
  );
}

class AdQuote {
  final String id;
  final String requestId;
  final int version;
  final int totalCents;
  final String status; // issued|accepted|declined|superseded|expired
  final DateTime? validUntil;
  final List<AdQuoteItem> items;
  const AdQuote({
    required this.id,
    required this.requestId,
    required this.version,
    required this.totalCents,
    required this.status,
    this.validUntil,
    this.items = const [],
  });
  factory AdQuote.fromJson(Map<String, dynamic> j) => AdQuote(
    id: j['id'] as String,
    requestId: j['request_id'] as String,
    version: _asInt(j['version']) ?? 1,
    totalCents: _asInt(j['total_cents']) ?? 0,
    status: (j['status'] as String?) ?? 'issued',
    validUntil: DateTime.tryParse(j['valid_until']?.toString() ?? ''),
    items: (j['ad_quote_items'] is List)
        ? (j['ad_quote_items'] as List)
            .whereType<Map>()
            .map((e) => AdQuoteItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const [],
  );
}

class AdCampaign {
  final String id;
  final String restaurantId;
  final String status; // scheduled|active|paused|completed|cancelled
  final bool paymentSatisfied;
  final DateTime? startsAt;
  final DateTime? endsAt;
  const AdCampaign({
    required this.id,
    required this.restaurantId,
    required this.status,
    required this.paymentSatisfied,
    this.startsAt,
    this.endsAt,
  });
  factory AdCampaign.fromJson(Map<String, dynamic> j) => AdCampaign(
    id: j['id'] as String,
    restaurantId: j['restaurant_id'] as String,
    status: (j['status'] as String?) ?? 'scheduled',
    paymentSatisfied: j['payment_satisfied'] == true,
    startsAt: DateTime.tryParse(j['starts_at']?.toString() ?? ''),
    endsAt: DateTime.tryParse(j['ends_at']?.toString() ?? ''),
  );
}
