import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/delivery/weather_model.dart';
import '../../utils/app_logger.dart';

/// Thrown when the weather backend reports a failure we want to surface as a
/// retryable error state in the UI. [code] is the stable machine code from the
/// Edge Function (e.g. weather_quota, weather_unreachable).
class WeatherException implements Exception {
  final String code;
  final String message;
  WeatherException(this.code, [String? message])
    : message = message ?? code;
  @override
  String toString() => 'WeatherException($code)';
}

/// Client for the secure `get-weather` Edge Function. The function holds the
/// WeatherAPI key server-side; this client only ever sends coordinates and
/// receives a small normalized payload. Works for guests and authenticated
/// users (the function is deployed with --no-verify-jwt).
class WeatherService {
  final SupabaseClient _client;
  WeatherService(this._client);

  Future<Weather> fetch({required double lat, required double lon}) async {
    final res = await _client.functions.invoke(
      'get-weather',
      body: {'lat': lat, 'lon': lon},
    );

    final data = res.data;
    if (data is Map && data['error'] != null) {
      // Never log coordinates — only the error code.
      final code = data['error'].toString();
      AppLogger.warning('get-weather returned $code');
      throw WeatherException(code);
    }
    if (data is! Map) {
      throw WeatherException('weather_malformed');
    }
    return Weather.fromJson(Map<String, dynamic>.from(data));
  }
}
