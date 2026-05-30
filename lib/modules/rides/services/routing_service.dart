import 'dart:convert';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

/// Service for calculating real driving routes using OSRM (Open Source Routing Machine).
/// This provides actual road-based routing instead of straight-line distances.
class RoutingService {
  /// OSRM demo server endpoint (free, no API key required)
  static const String _osrmBaseUrl =
      'https://router.project-osrm.org/route/v1/driving';

  /// In-memory route cache — keyed by rounded start+end coords so small GPS
  /// jitter doesn't bypass the cache.  Cleared when the service is disposed.
  final Map<String, RouteResult> _cache = {};

  String _cacheKey(LatLng start, LatLng end) {
    // Round to 4 decimal places (~11 m precision) to hit cache on minor jitter
    String r(double v) => v.toStringAsFixed(4);
    return '${r(start.latitude)},${r(start.longitude)}-${r(end.latitude)},${r(end.longitude)}';
  }

  void clearCache() => _cache.clear();

  /// Get driving route between two points.
  /// Returns a list of LatLng points representing the actual driving route.
  ///
  /// [start] - Starting coordinates (latitude, longitude)
  /// [end] - Ending coordinates (latitude, longitude)
  /// [alternatives] - Whether to return alternative routes (default: false)
  ///
  /// Returns [RouteResult] containing the route geometry and metadata.
  Future<RouteResult> getDrivingRoute({
    required LatLng start,
    required LatLng end,
    bool alternatives = false,
  }) async {
    final key = _cacheKey(start, end);
    if (_cache.containsKey(key)) return _cache[key]!;

    try {
      // OSRM uses {longitude},{latitude} format
      final String url =
          Uri.parse(
                '$_osrmBaseUrl/${start.longitude},${start.latitude};${end.longitude},${end.latitude}',
              )
              .replace(
                queryParameters: {
                  'overview': 'full',
                  'geometries': 'geojson',
                  'alternatives': alternatives.toString(),
                  'steps':
                      'false', // We don't need turn-by-turn steps for map display
                },
              )
              .toString();

      final response = await http
          .get(Uri.parse(url))
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => http.Response('{"code": "timeout"}', 408),
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final result = _parseRouteResponse(data);
        _cache[key] = result;
        return result;
      } else {
        throw RoutingException('Failed to get route: ${response.statusCode}');
      }
    } catch (e) {
      if (e is RoutingException) rethrow;
      throw RoutingException('Failed to get route: $e');
    }
  }

  /// Parse OSRM response into RouteResult
  RouteResult _parseRouteResponse(Map<String, dynamic> data) {
    final code = data['code'] as String?;
    if (code != 'Ok') {
      throw RoutingException('OSRM error: $code');
    }

    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      throw RoutingException('No routes found');
    }

    // Parse the primary route (first one)
    final primaryRoute = routes.first as Map<String, dynamic>;

    // Parse GeoJSON geometry
    final geometry = primaryRoute['geometry'] as Map<String, dynamic>?;
    if (geometry == null) {
      throw RoutingException('No geometry in route');
    }

    final coordinates = geometry['coordinates'] as List<dynamic>;
    final routePoints = coordinates
        .map(
          (coord) => LatLng(
            (coord[1] as num).toDouble(), // latitude
            (coord[0] as num).toDouble(), // longitude
          ),
        )
        .toList();

    final distanceMeters = (primaryRoute['distance'] as num?)?.toDouble() ?? 0;
    final durationSeconds = (primaryRoute['duration'] as num?)?.toDouble() ?? 0;

    // Parse alternative routes if available
    List<RouteGeometry> alternativeRoutes = [];
    if (routes.length > 1) {
      alternativeRoutes = routes
          .skip(1)
          .map((route) {
            final routeData = route as Map<String, dynamic>;
            final routeGeometry =
                routeData['geometry'] as Map<String, dynamic>?;
            if (routeGeometry == null) return null;

            final routeCoords = routeGeometry['coordinates'] as List<dynamic>;
            final points = routeCoords
                .map(
                  (coord) => LatLng(
                    (coord[1] as num).toDouble(),
                    (coord[0] as num).toDouble(),
                  ),
                )
                .toList();

            return RouteGeometry(
              points: points,
              distanceMeters: (routeData['distance'] as num?)?.toDouble() ?? 0,
              durationSeconds: (routeData['duration'] as num?)?.toDouble() ?? 0,
            );
          })
          .whereType<RouteGeometry>()
          .toList();
    }

    return RouteResult(
      routePoints: routePoints,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      alternativeRoutes: alternativeRoutes,
    );
  }

  /// Calculate straight-line distance between two points (Haversine formula).
  /// This is kept for fallback or comparison purposes.
  static double calculateStraightLineDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371; // km
    final lat1 = start.latitude * (3.141592653589793 / 180);
    final lat2 = end.latitude * (3.141592653589793 / 180);
    final dLat = lat2 - lat1;
    final dLon = (end.longitude - start.longitude) * (3.141592653589793 / 180);

    final a = (dLat / 2) * (dLat / 2) + lat1 * lat2 * (dLon / 2) * (dLon / 2);
    final c = 2 * math.asin(math.sqrt(a));

    return earthRadius * c;
  }
}

/// Result of a route calculation
class RouteResult {
  /// The list of coordinates representing the route
  final List<LatLng> routePoints;

  /// Total distance in meters
  final double distanceMeters;

  /// Estimated duration in seconds
  final double durationSeconds;

  /// Alternative routes (if requested)
  final List<RouteGeometry> alternativeRoutes;

  RouteResult({
    required this.routePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    this.alternativeRoutes = const [],
  });

  /// Distance in kilometers
  double get distanceKm => distanceMeters / 1000;

  /// Distance in miles
  double get distanceMiles => distanceMeters * 0.000621371;

  /// Duration in minutes
  double get durationMinutes => durationSeconds / 60;

  /// Estimated arrival time string (e.g., "15 min")
  String get estimatedTimeText {
    final minutes = durationMinutes.round();
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = (minutes / 60).floor();
      final remainingMins = minutes % 60;
      return remainingMins > 0 ? '${hours}h ${remainingMins}m' : '${hours}h';
    }
  }
}

/// Geometry data for a route
class RouteGeometry {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  RouteGeometry({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

/// Exception thrown when routing fails
class RoutingException implements Exception {
  final String message;
  RoutingException(this.message);

  @override
  String toString() => 'RoutingException: $message';
}
