import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Result returned when a user picks a location on the map.
class PickedLocation {
  final double latitude;
  final double longitude;
  final String address;

  const PickedLocation({
    required this.latitude,
    required this.longitude,
    required this.address,
  });
}

/// Full-screen map (OpenStreetMap) where customers can drag a pin to choose a
/// delivery address. Returns a [PickedLocation] via `Navigator.pop`.
class MapLocationPickerScreen extends StatefulWidget {
  /// Optional initial coordinates (e.g. from an already-saved address).
  final double? initialLatitude;
  final double? initialLongitude;

  const MapLocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<MapLocationPickerScreen> createState() =>
      _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  final MapController _mapController = MapController();

  // Default to George Town, Grand Cayman
  static const _defaultLat = 19.2869;
  static const _defaultLng = -81.3812;

  late LatLng _selectedPosition;
  String _address = 'Move the pin to select address';
  bool _loadingAddress = false;
  bool _locatingUser = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selectedPosition = LatLng(
      widget.initialLatitude ?? _defaultLat,
      widget.initialLongitude ?? _defaultLng,
    );

    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _locatingUser = false;
      _reverseGeocode(_selectedPosition);
    } else {
      _goToCurrentLocation();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _goToCurrentLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _locatingUser = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final newPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _selectedPosition = newPos;
        _locatingUser = false;
      });

      _mapController.move(newPos, 16);
      _reverseGeocode(newPos);
    } catch (_) {
      setState(() => _locatingUser = false);
    }
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    setState(() => _loadingAddress = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=${pos.latitude}&lon=${pos.longitude}&zoom=18&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'sevendash.app'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          setState(() => _address = displayName);
        }
      }
    } catch (_) {
      setState(
        () => _address =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
      );
    } finally {
      setState(() => _loadingAddress = false);
    }
  }

  void _onMapEvent(MapCamera camera, bool hasGesture) {
    _selectedPosition = camera.center;
    // Debounce reverse-geocode so we don't spam on every frame
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _reverseGeocode(_selectedPosition);
    });
  }

  void _confirmLocation() {
    Navigator.pop(
      context,
      PickedLocation(
        latitude: _selectedPosition.latitude,
        longitude: _selectedPosition.longitude,
        address: _address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pick Delivery Location',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // ── OpenStreetMap via flutter_map ───────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedPosition,
              initialZoom: 15,
              onPositionChanged: _onMapEvent,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'sevendash.app',
              ),
            ],
          ),

          // ── Centre pin icon ────────────────────
          Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(
                Icons.location_pin,
                size: 48,
                color: AppTheme.primaryColor,
              ),
            ),
          ),

          // ── Loading spinner while getting user location ──
          if (_locatingUser) const Center(child: CircularProgressIndicator()),

          // ── My-location FAB ────────────────────
          Positioned(
            right: 16,
            bottom: 180,
            child: FloatingActionButton.small(
              heroTag: 'myLoc',
              backgroundColor: Theme.of(context).cardColor,
              onPressed: _goToCurrentLocation,
              child: Icon(
                Icons.my_location,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // ── Bottom address card ────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: AppTheme.primaryColor,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _loadingAddress
                            ? Text(
                                'Finding address...',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              )
                            : Text(
                                _address,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loadingAddress || _locatingUser
                          ? null
                          : _confirmLocation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Confirm Location',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
