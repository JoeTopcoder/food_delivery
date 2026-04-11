import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

class EtaService {
  final SupabaseClient _client;
  EtaService(this._client);

  // Calculate and save ETA for an order
  Future<DateTime?> calculateEta({
    required String orderId,
    required String restaurantId,
    double? deliveryLatitude,
    double? deliveryLongitude,
  }) async {
    try {
      // Get default prep time from config
      final configResponse = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'default_prep_minutes')
          .maybeSingle();
      final prepMinutes = int.tryParse(configResponse?['value'] ?? '25') ?? 25;

      // Get buffer
      final bufferResponse = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'eta_buffer_minutes')
          .maybeSingle();
      final bufferMinutes =
          int.tryParse(bufferResponse?['value'] ?? '10') ?? 10;

      // Get restaurant location
      final restaurant = await _client
          .from('restaurants')
          .select('latitude, longitude, estimated_delivery_time')
          .eq('id', restaurantId)
          .single();

      int deliveryMinutes = restaurant['estimated_delivery_time'] as int? ?? 15;

      // If we have coordinates, estimate driving time (rough: 30km/h average)
      if (deliveryLatitude != null &&
          deliveryLongitude != null &&
          restaurant['latitude'] != null &&
          restaurant['longitude'] != null) {
        final rLat = (restaurant['latitude'] as num).toDouble();
        final rLng = (restaurant['longitude'] as num).toDouble();
        final distKm = _estimateDistance(
          rLat,
          rLng,
          deliveryLatitude,
          deliveryLongitude,
        );
        deliveryMinutes = (distKm / 30 * 60).ceil(); // 30 km/h average
        if (deliveryMinutes < 5) deliveryMinutes = 5;
      }

      final totalMinutes = prepMinutes + deliveryMinutes + bufferMinutes;
      final eta = DateTime.now().add(Duration(minutes: totalMinutes));

      // Save to order
      await _client
          .from('orders')
          .update({
            'estimated_delivery_at': eta.toIso8601String(),
            'estimated_prep_minutes': prepMinutes,
          })
          .eq('id', orderId);

      return eta;
    } catch (e) {
      AppLogger.error('Error calculating ETA: $e');
      return null;
    }
  }

  // Update ETA when driver picks up
  Future<DateTime?> updateEtaForPickup({
    required String orderId,
    required double driverLatitude,
    required double driverLongitude,
    required double deliveryLatitude,
    required double deliveryLongitude,
  }) async {
    try {
      final bufferResponse = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'eta_buffer_minutes')
          .maybeSingle();
      final bufferMinutes =
          int.tryParse(bufferResponse?['value'] ?? '10') ?? 10;

      final distKm = _estimateDistance(
        driverLatitude,
        driverLongitude,
        deliveryLatitude,
        deliveryLongitude,
      );
      final deliveryMinutes = (distKm / 30 * 60).ceil().clamp(3, 120);
      final eta = DateTime.now().add(
        Duration(minutes: deliveryMinutes + bufferMinutes),
      );

      await _client
          .from('orders')
          .update({'estimated_delivery_at': eta.toIso8601String()})
          .eq('id', orderId);

      return eta;
    } catch (e) {
      AppLogger.error('Error updating ETA: $e');
      return null;
    }
  }

  double _estimateDistance(double lat1, double lng1, double lat2, double lng2) {
    // Simple approximation in km
    final dLat = (lat2 - lat1) * 111.0;
    final dLng = (lng2 - lng1) * 111.0 * 0.85; // Jamaica ~18°N
    return (dLat * dLat + dLng * dLng).abs();
  }
}
