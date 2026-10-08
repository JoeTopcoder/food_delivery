import 'package:flutter_test/flutter_test.dart';
import 'package:food_driver/models/catalog/ad_model.dart';

void main() {
  group('SponsoredAd.fromJson', () {
    test('parses the safe selection fields', () {
      final a = SponsoredAd.fromJson({
        'campaign_id': 'c1',
        'creative_id': 'cr1',
        'restaurant_id': 'r1',
        'restaurant_name': 'Tasty',
        'logo_url': 'https://x/logo.png',
        'media_type': 'video',
        'playback_url': 'https://x/v.mp4',
        'thumbnail_url': 'https://x/t.jpg',
        'headline': 'Eat now',
        'destination_type': 'dish',
        'destination_dish_id': 'd9',
      });
      expect(a.campaignId, 'c1');
      expect(a.isVideo, isTrue);
      expect(a.playbackUrl, 'https://x/v.mp4');
      expect(a.destinationDishId, 'd9');
    });

    test('defaults media type to image and tolerates missing optionals', () {
      final a = SponsoredAd.fromJson({
        'campaign_id': 'c',
        'creative_id': 'cr',
        'restaurant_id': 'r',
      });
      expect(a.mediaType, 'image');
      expect(a.isVideo, isFalse);
      expect(a.restaurantName, isNull);
      expect(a.headline, isNull);
    });
  });

  group('AdRequest / AdCreative', () {
    test('request parses status + kind + flags', () {
      final r = AdRequest.fromJson({
        'id': 'q', 'restaurant_id': 'r', 'kind': 'self_video',
        'wants_placement': true, 'title': 'Promo', 'status': 'submitted',
        'created_at': '2026-10-08T10:00:00Z',
      });
      expect(r.kind, 'self_video');
      expect(r.wantsPlacement, isTrue);
      expect(r.status, 'submitted');
    });

    test('creative parses version as int from string + surfaces errors', () {
      final c = AdCreative.fromJson({
        'id': 'c', 'request_id': 'q', 'version': '3',
        'media_type': 'video', 'source': 'restaurant', 'status': 'failed',
        'processing_error': 'too large',
      });
      expect(c.version, 3);
      expect(c.isVideo, isTrue);
      expect(c.processingError, 'too large');
    });
  });

  group('AdQuote', () {
    test('parses nested line items and totals', () {
      final q = AdQuote.fromJson({
        'id': 'qid', 'request_id': 'rq', 'version': 2, 'total_cents': 750000,
        'status': 'issued',
        'ad_quote_items': [
          {'kind': 'production', 'description': 'Shoot', 'amount_cents': 500000},
          {'kind': 'placement', 'description': '7 days', 'amount_cents': 250000},
        ],
      });
      expect(q.version, 2);
      expect(q.totalCents, 750000);
      expect(q.items.length, 2);
      final prod = q.items.where((i) => i.kind == 'production').fold<int>(0, (a, b) => a + b.amountCents);
      final place = q.items.where((i) => i.kind == 'placement').fold<int>(0, (a, b) => a + b.amountCents);
      expect(prod, 500000);
      expect(place, 250000);
      expect(prod + place, q.totalCents); // production + placement kept separate but sum to total
    });

    test('handles no line items', () {
      final q = AdQuote.fromJson({
        'id': 'q', 'request_id': 'r', 'version': 1, 'total_cents': 0, 'status': 'issued',
      });
      expect(q.items, isEmpty);
    });
  });

  group('AdCampaign', () {
    test('parses status + payment flag + schedule', () {
      final c = AdCampaign.fromJson({
        'id': 'c', 'restaurant_id': 'r', 'status': 'active',
        'payment_satisfied': true,
        'starts_at': '2026-10-08T00:00:00Z', 'ends_at': '2026-10-15T00:00:00Z',
      });
      expect(c.status, 'active');
      expect(c.paymentSatisfied, isTrue);
      expect(c.startsAt!.isBefore(c.endsAt!), isTrue);
    });
  });
}
