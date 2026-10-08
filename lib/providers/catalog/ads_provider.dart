import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/catalog/ad_model.dart';
import '../../services/ads/ads_service.dart';

final adsServiceProvider = Provider<AdsService>((ref) => AdsService());

/// A stable session id for the app run — used to dedupe ad impressions/events
/// server-side so widget rebuilds and video loops never inflate counts.
final adSessionIdProvider = Provider<String>((ref) {
  final r = Random();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${r.nextInt(1 << 32).toRadixString(36)}';
});

/// Query key for sponsored ads — rounded delivery coords (value-equal record so
/// the family instance is reused and switching location refetches cleanly).
typedef AdQuery = ({double? lat, double? lng});

AdQuery adQuery(double? lat, double? lng) => (
      lat: lat == null ? null : (lat * 100).roundToDouble() / 100,
      lng: lng == null ? null : (lng * 100).roundToDouble() / 100,
    );

/// Eligible sponsored ads for a delivery point. Empty when the feature is off
/// or there are no eligible ads — the UI then renders nothing.
final sponsoredAdsProvider =
    FutureProvider.autoDispose.family<List<SponsoredAd>, AdQuery>((ref, q) async {
  final link = ref.keepAlive();
  Future.delayed(const Duration(minutes: 5)).then((_) => link.close());
  return ref.watch(adsServiceProvider).getSponsoredAds(lat: q.lat, lng: q.lng);
});
