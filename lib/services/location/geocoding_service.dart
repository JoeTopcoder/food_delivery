import 'dart:convert';
import 'package:http/http.dart' as http;

/// Forward-geocode a typed address string to coordinates using Nominatim
/// (OpenStreetMap) — the same provider the map picker uses. Lets a customer who
/// types an address (instead of dropping a map pin) still get latitude/longitude
/// so checkout accepts it.
class GeocodingService {
  /// Returns the best coordinate match for [address], or null if none / on error.
  /// [countryCode] (ISO-2, e.g. 'jm') biases the search to the right country.
  static Future<({double lat, double lng})?> geocode(
    String address, {
    String? countryCode,
  }) async {
    final q = address.trim();
    if (q.isEmpty) return null;
    try {
      final params = <String, String>{
        'q': q,
        'format': 'json',
        'limit': '1',
        'addressdetails': '0',
      };
      if (countryCode != null && countryCode.isNotEmpty) {
        params['countrycodes'] = countryCode;
      }
      final res = await http
          .get(
            Uri.https('nominatim.openstreetmap.org', '/search', params),
            headers: const {
              'User-Agent': 'HotBite/1.0 (hotbite.app)',
              'Accept-Language': 'en',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final list = json.decode(res.body) as List;
      if (list.isEmpty) return null;
      final first = list.first as Map<String, dynamic>;
      final lat = double.tryParse('${first['lat']}');
      final lng = double.tryParse('${first['lon']}');
      if (lat == null || lng == null) return null;
      return (lat: lat, lng: lng);
    } catch (_) {
      return null;
    }
  }
}
