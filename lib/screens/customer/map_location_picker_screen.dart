import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../utils/safe_state_mixin.dart';

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

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen>
    with SafeStateMixin<MapLocationPickerScreen> {
  final MapController _mapController = MapController();

  // Null until GPS resolves or initial coords are provided — no hardcoded default.
  LatLng? _selectedPosition;
  String _address = 'Move the pin to select address';
  bool _loadingAddress = false;
  bool _locatingUser = true;
  Timer? _debounce;

  // Address search
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  Timer? _searchDebounce;

  // House / unit number entered by the user
  final TextEditingController _unitController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPosition =
          LatLng(widget.initialLatitude!, widget.initialLongitude!);
      _locatingUser = false;
      _reverseGeocode(_selectedPosition!);
    } else {
      _goToCurrentLocation();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _unitController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      if (mounted) setState(() => _searchResults = []);
      return;
    }
    _searchDebounce =
        Timer(const Duration(milliseconds: 500), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    setState(() => _searching = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=json&q=${Uri.encodeComponent(query)}&limit=5&addressdetails=1',
      );
      final response =
          await http.get(url, headers: {'User-Agent': 'sevendash.app'});
      if (!mounted) return;
      if (response.statusCode == 200) {
        final results = List<Map<String, dynamic>>.from(
            json.decode(response.body) as List);
        setState(() => _searchResults = results);
      }
    } catch (_) {
      if (mounted) setState(() => _searchResults = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectSearchResult(Map<String, dynamic> result) {
    final lat = double.tryParse(result['lat'] as String? ?? '');
    final lng = double.tryParse(result['lon'] as String? ?? '');
    final name = result['display_name'] as String? ?? '';
    if (lat == null || lng == null) return;
    final pos = LatLng(lat, lng);
    setState(() {
      _selectedPosition = pos;
      _address = name;
      _searchResults = [];
      _searchController.clear();
    });
    _mapController.move(pos, 17);
    FocusScope.of(context).unfocus();
  }

  Future<void> _goToCurrentLocation() async {
    if (mounted) setState(() => _locatingUser = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locatingUser = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final newPos = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _selectedPosition = newPos;
        _locatingUser = false;
      });

      _mapController.move(newPos, 17);
      _reverseGeocode(newPos);
    } catch (_) {
      if (mounted) setState(() => _locatingUser = false);
    }
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    if (!mounted) return;
    setState(() => _loadingAddress = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json'
        '&lat=${pos.latitude}'
        '&lon=${pos.longitude}'
        '&zoom=19'
        '&addressdetails=1'
        '&namedetails=1'
        '&extratags=1',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'sevendash.app'},
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;
        final extratags = data['extratags'] as Map<String, dynamic>?;
        // Top-level 'name' is the OSM name tag of the matched feature —
        // for parcels this is often "Lot 14 Block 5" or similar.
        final featureName = data['name'] as String?;
        final formatted = addr != null
            ? _formatAddress(addr,
                extratags: extratags, featureName: featureName)
            : null;
        if (formatted != null && formatted.isNotEmpty) {
          setState(() => _address = formatted);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _address =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
      );
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  /// Builds a clean, lot-accurate address string from Nominatim data.
  /// Priority: lot/parcel name → house number → road → locality
  /// e.g. "Lot 14, Birch Tree Hill Road, George Town"
  String _formatAddress(
    Map<String, dynamic> addr, {
    Map<String, dynamic>? extratags,
    String? featureName,
  }) {
    String s(String key) => (addr[key] as String? ?? '').trim();
    String e(String key) => (extratags?[key] as String? ?? '').trim();

    // Lot / parcel number: check OSM feature name, extratags ref, then house_number
    final lotFromName =
        (featureName != null && featureName.trim().isNotEmpty)
            ? featureName.trim()
            : '';
    final lotFromRef = e('ref');
    final houseNumber = e('addr:housenumber').isNotEmpty
        ? e('addr:housenumber')
        : s('house_number');

    // Pick the most specific lot identifier available
    final lotPart = lotFromName.isNotEmpty
        ? lotFromName
        : lotFromRef.isNotEmpty
            ? 'Lot $lotFromRef'
            : houseNumber;

    final road = s('road').isNotEmpty ? s('road') : s('pedestrian');

    final neighbourhood =
        s('neighbourhood').isNotEmpty ? s('neighbourhood') : s('suburb');

    final city = s('city').isNotEmpty
        ? s('city')
        : s('town').isNotEmpty
            ? s('town')
            : s('village').isNotEmpty
                ? s('village')
                : s('county');

    // Join number to road with a space ("12 Main Street"),
    // but named lots use a comma ("Lot 14, Main Street").
    final isPlainNumber = RegExp(r'^[0-9]+[A-Za-z]?$').hasMatch(lotPart);
    final streetPart = lotPart.isNotEmpty && road.isNotEmpty
        ? (isPlainNumber ? '$lotPart $road' : '$lotPart, $road')
        : lotPart.isNotEmpty
            ? lotPart
            : road;

    // Skip neighbourhood when it's already embedded in the road name
    final neighbourhoodRedundant = neighbourhood.isEmpty ||
        road.toLowerCase().contains(neighbourhood.toLowerCase());

    final localityPart = [
      if (!neighbourhoodRedundant) neighbourhood,
      if (city.isNotEmpty) city,
    ].join(', ');

    return [
      if (streetPart.isNotEmpty) streetPart,
      if (localityPart.isNotEmpty) localityPart,
    ].join(', ');
  }

  void _onMapEvent(MapCamera camera, bool hasGesture) {
    _selectedPosition = camera.center;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final pos = _selectedPosition;
      if (pos != null) _reverseGeocode(pos);
    });
  }

  void _confirmLocation() {
    final pos = _selectedPosition;
    if (pos == null) return;
    final unit = _unitController.text.trim();
    final fullAddress = unit.isNotEmpty ? '$unit, $_address' : _address;
    Navigator.pop(
      context,
      PickedLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        address: fullAddress,
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
      body: _selectedPosition == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Getting your location…'),
                ],
              ),
            )
          : Stack(
              children: [
                // ── OpenStreetMap via flutter_map ───────
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedPosition!,
                    initialZoom: 17,
                    onPositionChanged: _onMapEvent,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'sevendash.app',
                    ),
                  ],
                ),

                // ── Address search bar ────────────────
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Search address…',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searching
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                            filled: true,
                            fillColor: Theme.of(context).cardColor,
                          ),
                        ),
                      ),
                      if (_searchResults.isNotEmpty)
                        Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final r = _searchResults[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.location_on_outlined,
                                    size: 18),
                                title: Text(
                                  r['display_name'] as String? ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                onTap: () => _selectSearchResult(r),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Centre pin icon ────────────────────
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 36),
                    child: Icon(
                      Icons.location_pin,
                      size: 48,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),

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
                        TextField(
                          controller: _unitController,
                          keyboardType: TextInputType.streetAddress,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'House / Unit No. (optional)',
                            prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 12),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
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
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
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
                            onPressed: _loadingAddress ||
                                    _locatingUser ||
                                    _selectedPosition == null
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
