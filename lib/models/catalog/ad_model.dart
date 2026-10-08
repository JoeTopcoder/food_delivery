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
