import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/weather_model.dart';
import '../../services/weather_service.dart';
import '../auth_user/address_provider.dart';
import '../delivery/location_provider.dart';

/// Where the weather location came from, so the card can clearly label whether
/// it is showing the delivery address or the device's current location.
enum WeatherSource { deliveryAddress, currentLocation }

/// An immutable, value-equal weather request. Coordinates are rounded to 2 dp
/// (~1 km) so tiny jitter doesn't refetch, and so the family key matches the
/// backend cache cell. Equality is what makes stale-response races safe: when
/// the selected location changes, the home card watches a *different* family
/// instance, the previous autoDispose future is dropped, and its late result
/// can never overwrite the latest location's weather.
class WeatherQuery {
  final double lat;
  final double lon;
  final WeatherSource source;

  /// A human label for the place (address label / "Current location").
  final String? label;

  WeatherQuery({
    required double lat,
    required double lon,
    required this.source,
    this.label,
  }) : lat = _round2(lat),
       lon = _round2(lon);

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  @override
  bool operator ==(Object other) =>
      other is WeatherQuery &&
      other.lat == lat &&
      other.lon == lon &&
      other.source == source;

  @override
  int get hashCode => Object.hash(lat, lon, source);
}

final weatherServiceProvider = Provider<WeatherService>((ref) {
  return WeatherService(Supabase.instance.client);
});

/// Explicit "Use my current location" override. Null = follow the selected
/// delivery address. Set only after the user taps the action and we resolve a
/// GPS fix — using GPS here never mutates the delivery address.
final weatherLocationOverrideProvider = StateProvider<WeatherQuery?>(
  (ref) => null,
);

/// The effective location the weather card should show: the explicit current
/// -location override if present, otherwise the selected delivery address
/// (when it has coordinates). Null means "no location to show".
final effectiveWeatherQueryProvider = Provider<WeatherQuery?>((ref) {
  final override = ref.watch(weatherLocationOverrideProvider);
  if (override != null) return override;

  final addr = ref.watch(selectedAddressProvider);
  if (addr?.latitude != null && addr?.longitude != null) {
    return WeatherQuery(
      lat: addr!.latitude!,
      lon: addr.longitude!,
      source: WeatherSource.deliveryAddress,
      label: addr.label,
    );
  }
  return null;
});

/// Weather for a specific query. autoDispose + family: each distinct location
/// is its own provider instance, so switching locations cancels the old one.
final weatherProvider = FutureProvider.autoDispose
    .family<Weather, WeatherQuery>((ref, query) async {
      // Keep the result briefly after the card stops watching so an app-resume
      // or quick re-open reuses it instead of refetching.
      final link = ref.keepAlive();
      final timer = Future.delayed(const Duration(minutes: 5));
      timer.then((_) => link.close());

      return ref
          .watch(weatherServiceProvider)
          .fetch(lat: query.lat, lon: query.lon);
    });

/// Resolves the device's current GPS position into a [WeatherQuery] and sets it
/// as the override. Reuses the app's existing [LocationService] permission flow.
/// Returns false if permission/location is unavailable. Does NOT change the
/// delivery address and does not start any persistent tracking.
Future<bool> useCurrentLocationForWeather(WidgetRef ref) async {
  final Position? pos = await ref
      .read(locationServiceProvider)
      .getCurrentPosition();
  if (pos == null) return false;
  ref.read(weatherLocationOverrideProvider.notifier).state = WeatherQuery(
    lat: pos.latitude,
    lon: pos.longitude,
    source: WeatherSource.currentLocation,
    label: 'Current location',
  );
  return true;
}
