import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:food_driver/utils/app_logger.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';
import 'package:food_driver/config/supabase_config.dart';
import 'package:food_driver/config/app_constants.dart';
import 'package:food_driver/providers/feature_providers.dart';
import 'package:food_driver/modules/rides/services/routing_service.dart';
import 'package:food_driver/providers/wallet_provider.dart';

const _kBlue = Color(0xFF2563EB);
const _kRed = Color(0xFFEF4444);

const _kDefaultPickup = LatLng(18.0060, -76.7964);


// ---------------------------------------------------------------------------
// Jamaica airports
// ---------------------------------------------------------------------------

class _Airport {
  final String code;
  final String name;
  final String address;
  final LatLng latLng;
  const _Airport({required this.code, required this.name, required this.address, required this.latLng});

  factory _Airport.fromJson(Map<String, dynamic> json) => _Airport(
    code: json['code'] as String,
    name: json['name'] as String,
    address: (json['address'] as String?)?.isNotEmpty == true
        ? json['address'] as String
        : '${json['name']}, ${json['city']}',
    latLng: LatLng(
      (json['latitude'] as num).toDouble(),
      (json['longitude'] as num).toDouble(),
    ),
  );
}

const _kJamaicaAirports = [
  _Airport(
    code: 'KIN',
    name: 'Norman Manley International',
    address: 'Norman Manley International Airport, Kingston',
    latLng: LatLng(17.9357, -76.7875),
  ),
  _Airport(
    code: 'MBJ',
    name: 'Sangster International',
    address: 'Sangster International Airport, Montego Bay',
    latLng: LatLng(18.5037, -77.9133),
  ),
  _Airport(
    code: 'OCJ',
    name: 'Ian Fleming International',
    address: 'Ian Fleming International Airport, Ocho Rios',
    latLng: LatLng(18.4049, -77.1002),
  ),
];

// ---------------------------------------------------------------------------
// Place suggestion model
// ---------------------------------------------------------------------------

class _PlaceSuggestion {
  final String exactAddress; // street + suburb + city — used in text fields
  final String displayName;  // full Nominatim string — shown as subtitle
  final LatLng latLng;
  const _PlaceSuggestion({
    required this.exactAddress,
    required this.displayName,
    required this.latLng,
  });
}

/// Builds a lot-accurate address from Nominatim data.
/// Priority: OSM feature name (parcel/lot) → extratags ref → house_number → road → locality.
/// e.g. "Lot 14, Birch Tree Hill Road, George Town"
String _buildExactAddress(
  Map<String, dynamic> addressObj,
  String displayName, {
  Map<String, dynamic>? extratags,
  String? featureName,
}) {
  final a = addressObj;
  String s(String key) => (a[key] as String? ?? '').trim();
  String e(String key) => (extratags?[key] as String? ?? '').trim();

  // Lot / parcel: OSM feature name → extratags ref → addr:housenumber → house_number
  // Only use featureName as a lot prefix when it is genuinely distinct from the
  // road name — if they are the same string Nominatim is just echoing the road
  // name and using it would produce "Lindsay Crescent, Lindsay Crescent".
  final road0 = (a['road'] as String? ?? '').trim();
  final rawFeature = (featureName?.trim() ?? '');
  final lotFromName = (rawFeature.isNotEmpty &&
          rawFeature.toLowerCase() != road0.toLowerCase())
      ? rawFeature
      : '';
  final lotFromRef = e('ref');
  String houseNumber = e('addr:housenumber').isNotEmpty
      ? e('addr:housenumber')
      : s('house_number');

  // Fallback: if Nominatim returned a road-level result without house_number,
  // check whether display_name starts with a number/lot pattern.
  // e.g. "15, Main Street, …" or "Lot 14, Orange Crescent, …"
  if (houseNumber.isEmpty && lotFromName.isEmpty && lotFromRef.isEmpty) {
    final firstSeg = displayName.split(',').first.trim();
    if (RegExp(r'^[0-9]+[A-Za-z]?$').hasMatch(firstSeg)) {
      houseNumber = firstSeg;
    } else if (RegExp(r'^[Ll]ot\s+[0-9A-Za-z]+$').hasMatch(firstSeg)) {
      houseNumber = firstSeg;
    }
  }

  final lotPart = lotFromName.isNotEmpty
      ? lotFromName
      : lotFromRef.isNotEmpty
          ? 'Lot $lotFromRef'
          : houseNumber;

  // Road
  final road = s('road').isNotEmpty
      ? s('road')
      : s('pedestrian').isNotEmpty
          ? s('pedestrian')
          : s('footway').isNotEmpty
              ? s('footway')
              : s('path');

  // Sub-locality
  final suburb = s('neighbourhood').isNotEmpty
      ? s('neighbourhood')
      : s('suburb').isNotEmpty
          ? s('suburb')
          : s('quarter').isNotEmpty
              ? s('quarter')
              : s('hamlet');

  // City
  final city = s('city').isNotEmpty
      ? s('city')
      : s('town').isNotEmpty
          ? s('town')
          : s('village').isNotEmpty
              ? s('village')
              : s('municipality');

  // Skip suburb when it is already embedded in the road name
  // e.g. road="Lindsay Crescent", suburb="Lindsay" → don't add "Lindsay" again
  // Join number to road with a space ("12 Lindsay Crescent"),
  // but named lots/parcels use a comma ("Lot 14, Main Street").
  final isPlainNumber = RegExp(r'^[0-9]+[A-Za-z]?$').hasMatch(lotPart);
  final streetPart = lotPart.isNotEmpty && road.isNotEmpty
      ? (isPlainNumber ? '$lotPart $road' : '$lotPart, $road')
      : lotPart.isNotEmpty
          ? lotPart
          : road;

  final parts = <String>[];
  if (streetPart.isNotEmpty) parts.add(streetPart);
  final suburbRedundant = suburb.isEmpty ||
      suburb == road ||
      road.toLowerCase().contains(suburb.toLowerCase());
  if (!suburbRedundant && suburb != parts.lastOrNull) parts.add(suburb);
  if (city.isNotEmpty && city != parts.lastOrNull) parts.add(city);

  if (parts.isNotEmpty) return parts.join(', ');

  // Fallback: first 3 comma-parts of display_name
  return displayName.split(',').take(3).join(',').trim();
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class RideBookingScreen extends ConsumerStatefulWidget {
  const RideBookingScreen({super.key});

  @override
  ConsumerState<RideBookingScreen> createState() => _RideBookingScreenState();
}

class _RideBookingScreenState extends ConsumerState<RideBookingScreen> {
  final _pickupController = TextEditingController();
  final _destinationController = TextEditingController();

  LatLng _pickupLatLng = _kDefaultPickup;
  LatLng? _destinationLatLng;

  // Suggestions
  List<_PlaceSuggestion> _suggestions = [];
  String _activeField = ''; // 'pickup' | 'dest'
  String _activeQuery = ''; // raw text being searched
  bool _fetchingSuggestions = false;
  Timer? _suggestionDebounce;

  // Fare / booking
  Map<String, dynamic>? _fareData;
  bool _isLoadingFare = false;
  bool _isConfirming = false;
  String _selectedPaymentMethod = 'card'; // 'card' | 'wallet' | 'cash'
  bool _isGeocodingPickup = false;
  bool _isGeocodingDest = false;
  String? _error;

  // Real driving route
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  final RoutingService _routingService = RoutingService();

  // Country-scoped search — defaults to Jamaica (jm), updated on first GPS fix
  String _searchCountryCode = 'jm';

  // True after a completed search that returned 0 results
  bool _noResults = false;

  // Scheduled ride
  DateTime? _scheduledFor;

  // Airport
  _Airport? _pickupAirport;
  _Airport? _dropoffAirport;
  final _terminalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateFare();
      _detectCountryFromGps();
    });
  }

  Future<void> _pickScheduleDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledFor = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _clearSchedule() => setState(() => _scheduledFor = null);

  // ── Airport selection ─────────────────────────────────────────────────────

  Future<void> _pickAirport(String field) async {
    final dbRows = ref.read(airportsProvider).valueOrNull;
    final airports = dbRows != null && dbRows.isNotEmpty
        ? dbRows.map(_Airport.fromJson).toList()
        : List<_Airport>.from(_kJamaicaAirports);

    final selected = await showModalBottomSheet<_Airport>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              field == 'pickup' ? 'Pickup from Airport' : 'Drop off at Airport',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ...airports.map((a) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _kBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.flight_rounded, color: _kBlue, size: 22),
              ),
              title: Text(a.name, style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
              subtitle: Text(a.code, style: const TextStyle(color: _kBlue, fontSize: 12, fontWeight: FontWeight.bold)),
              onTap: () => Navigator.of(ctx).pop(a),
            )),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _fareData = null;
      if (field == 'pickup') {
        _pickupAirport = selected;
        _pickupLatLng = selected.latLng;
        _pickupController.text = selected.address;
      } else {
        _dropoffAirport = selected;
        _destinationLatLng = selected.latLng;
        _destinationController.text = selected.address;
      }
    });
    _calculateFare();
  }

  void _clearPickupAirport() {
    setState(() { _pickupAirport = null; _fareData = null; });
  }

  void _clearDropoffAirport() {
    setState(() { _dropoffAirport = null; _fareData = null; });
  }

  Future<String?> _getDefaultSavedCardId() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final rows = await SupabaseConfig.client
          .from('saved_cards')
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      if (rows.isNotEmpty) {
        return rows.first['id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Silently checks GPS country so address searches return local results.
  /// Falls back to 'jm' (Jamaica) if permission denied or GPS unavailable.
  Future<void> _detectCountryFromGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
      final code = await _countryCodeFromLatLng(pos.latitude, pos.longitude);
      if (code != null && mounted) setState(() => _searchCountryCode = code);
    } catch (_) {
      // silently keep default 'jm'
    }
  }

  /// Reverse geocodes a lat/lng and returns the ISO 3166-1 alpha-2 country code.
  Future<String?> _countryCodeFromLatLng(double lat, double lng) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'format': 'json',
      });
      final resp = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'MealHub/1.0 (support@mealhubcayman.com)',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        final code = address?['country_code'] as String?;
        return code?.toLowerCase();
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    _pickupController.dispose();
    _destinationController.dispose();
    _terminalController.dispose();
    super.dispose();
  }

  // ── Autocomplete ───────────────────────────────────────────────────────────

  void _onPickupChanged(String text) {
    _suggestionDebounce?.cancel();
    setState(() {
      _activeField = 'pickup';
      _activeQuery = text.trim();
      _noResults = false;
    });
    if (text.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _suggestionDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _fetchSuggestions(text, 'pickup'),
    );
  }

  void _onDestChanged(String text) {
    _suggestionDebounce?.cancel();
    setState(() {
      _activeField = 'dest';
      _activeQuery = text.trim();
      _noResults = false;
    });
    if (text.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _suggestionDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _fetchSuggestions(text, 'dest'),
    );
  }

  Future<List<_PlaceSuggestion>> _nominatimSearch(
    String query, {
    String? countryCode,
  }) async {
    final params = <String, String>{
      'q': query.trim(),
      'format': 'json',
      'limit': '8',
      'addressdetails': '1',
      'extratags': '1',
      'namedetails': '1',
      'zoom': '18', // building-level detail — maximises house_number in response
    };
    if (countryCode != null) params['countrycodes'] = countryCode;

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
    final resp = await http.get(uri, headers: {
      'User-Agent': 'sevendash.app',
      'Accept-Language': 'en',
    }).timeout(const Duration(seconds: 8));

    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data.map((e) {
      final display = e['display_name'] as String;
      final addressObj = (e['address'] as Map<String, dynamic>?) ?? {};
      final extratags = e['extratags'] as Map<String, dynamic>?;
      final namedetails = e['namedetails'] as Map<String, dynamic>?;
      final featureName = namedetails?['name'] as String?;
      return _PlaceSuggestion(
        displayName: display,
        exactAddress: _buildExactAddress(addressObj, display,
            extratags: extratags, featureName: featureName),
        latLng: LatLng(
          double.parse(e['lat'] as String),
          double.parse(e['lon'] as String),
        ),
      );
    }).toList();
  }

  // Matches a leading lot/house-number prefix in a typed query, e.g.:
  //   "1b Lindsay Crescent"  →  group(1)="1b"
  //   "Lot 14 Main Street"   →  group(1)="Lot 14"
  static final _leadingNumRe =
      RegExp(r'^([Ll]ot\s+[0-9A-Za-z]+|[0-9]+[A-Za-z]?)\s+', caseSensitive: false);

  Future<void> _fetchSuggestions(String query, String field) async {
    if (!mounted) return;
    setState(() {
      _fetchingSuggestions = true;
      _noResults = false;
    });
    try {
      // Try with country restriction first (faster, more local)
      var results = await _nominatimSearch(query, countryCode: _searchCountryCode);

      // Jamaica has limited OSM data — fall back to global search if no results
      if (results.isEmpty) {
        results = await _nominatimSearch(query);
      }

      // Deduplicate by exactAddress (Nominatim can return multiple objects
      // for the same road — e.g. road + named place — that resolve identically).
      final seen = <String>{};
      results = results.where((r) => seen.add(r.exactAddress)).toList();

      // If the user typed a leading number/lot that Nominatim dropped (road-level
      // match, no building data), inject it back as the prefix so the selection
      // field shows exactly what they typed, e.g. "1b Lindsay Crescent, Half Way Tree".
      final numMatch = _leadingNumRe.firstMatch(query.trim());
      if (numMatch != null && results.isNotEmpty) {
        final prefix = numMatch.group(1)!;
        results = results.map((r) {
          final alreadyHas = r.exactAddress
              .toLowerCase()
              .startsWith(prefix.toLowerCase());
          if (alreadyHas) return r;
          final isPlain = RegExp(r'^[0-9]+[A-Za-z]?$').hasMatch(prefix);
          final newAddr = isPlain
              ? '$prefix ${r.exactAddress}'
              : '$prefix, ${r.exactAddress}';
          return _PlaceSuggestion(
            exactAddress: newAddr,
            displayName: r.displayName,
            latLng: r.latLng,
          );
        }).toList();
      }

      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _fetchingSuggestions = false;
        _noResults = results.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestions = [];
        _fetchingSuggestions = false;
        _noResults = false;
      });
    }
  }

  void _selectSuggestion(_PlaceSuggestion s) {
    _suggestionDebounce?.cancel();
    setState(() {
      _suggestions = [];
      _noResults = false;
      _activeQuery = '';
      _fareData = null;
    });
    if (_activeField == 'pickup') {
      _pickupController.text = s.exactAddress;
      setState(() => _pickupLatLng = s.latLng);
      if (_destinationLatLng != null) _calculateFare();
    } else {
      _destinationController.text = s.exactAddress;
      setState(() => _destinationLatLng = s.latLng);
      _calculateFare();
    }
  }

  void _dismissSuggestions() {
    _suggestionDebounce?.cancel();
    setState(() {
      _suggestions = [];
      _fetchingSuggestions = false;
      _noResults = false;
      _activeQuery = '';
    });
  }

  // ── Geocoding (search button / enter) ──────────────────────────────────────

  Future<LatLng?> _geocodeAddress(String address) async {
    if (address.trim().isEmpty) return null;
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': address.trim(),
        'format': 'json',
        'limit': '1',
        'countrycodes': _searchCountryCode,
      });
      final resp = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'MealHub/1.0 (support@mealhubcayman.com)',
              'Accept-Language': 'en',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
        if (data.isNotEmpty) {
          return LatLng(
            double.parse(data[0]['lat'] as String),
            double.parse(data[0]['lon'] as String),
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Called when the user taps the "Search for X" row in the dropdown.
  /// Geocodes whatever is currently typed in the active field.
  Future<void> _geocodeActiveField() async {
    if (_activeField == 'pickup') {
      await _geocodePickup();
    } else {
      await _geocodeDest();
    }
  }

  Future<void> _geocodePickup() async {
    _dismissSuggestions();
    setState(() {
      _isGeocodingPickup = true;
      _error = null;
    });
    final latLng = await _geocodeAddress(_pickupController.text);
    if (!mounted) return;
    if (latLng != null) {
      setState(() {
        _pickupLatLng = latLng;
        _isGeocodingPickup = false;
        _fareData = null;
      });
      if (_destinationLatLng != null) _calculateFare();
    } else {
      setState(() {
        _isGeocodingPickup = false;
        _error = 'Could not find pickup location. Try a more specific address.';
      });
    }
  }

  Future<void> _geocodeDest() async {
    _dismissSuggestions();
    setState(() {
      _isGeocodingDest = true;
      _error = null;
    });
    final latLng = await _geocodeAddress(_destinationController.text);
    if (!mounted) return;
    if (latLng != null) {
      setState(() {
        _destinationLatLng = latLng;
        _isGeocodingDest = false;
        _fareData = null;
      });
      _calculateFare();
    } else {
      setState(() {
        _isGeocodingDest = false;
        _error = 'Could not find destination. Try a more specific address.';
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    _dismissSuggestions();
    setState(() {
      _isGeocodingPickup = true;
      _error = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied)
          throw Exception('Location permission denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission permanently denied. Enable it in Settings.',
        );
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;

      // Reverse geocode for a readable label and to refresh country scope
      String label =
          '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      try {
        final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
          'lat': pos.latitude.toString(),
          'lon': pos.longitude.toString(),
          'format': 'json',
          'addressdetails': '1',
          'namedetails': '1',
          'extratags': '1',
          'zoom': '19',
        });
        final resp = await http
            .get(
              uri,
              headers: {'User-Agent': 'sevendash.app'},
            )
            .timeout(const Duration(seconds: 12));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          // Nominatim returns {"error": "..."} with 200 when no result found
          if (!data.containsKey('error')) {
            final display = data['display_name'] as String? ?? '';
            final addressObj = (data['address'] as Map<String, dynamic>?) ?? {};
            final extratags = data['extratags'] as Map<String, dynamic>?;
            // For /reverse, house_number may live at top-level 'house_number'
            // OR inside extratags as 'addr:housenumber'. Inject it into addressObj
            // so _buildExactAddress picks it up via s('house_number').
            final topHouseNum = data['house_number'] as String?;
            if (topHouseNum != null && topHouseNum.isNotEmpty) {
              addressObj['house_number'] = topHouseNum;
            }
            final featureName = data['name'] as String?;
            final built = _buildExactAddress(addressObj, display,
                extratags: extratags, featureName: featureName);
            // Only replace label when we got a real address back
            if (built.isNotEmpty) label = built;
          }
          // Update search country so subsequent suggestions match user's location
          final address = data['address'] as Map<String, dynamic>?;
          final code = address?['country_code'] as String?;
          if (code != null && mounted) {
            setState(() => _searchCountryCode = code.toLowerCase());
          }
        }
      } catch (_) {}

      setState(() {
        _pickupLatLng = LatLng(pos.latitude, pos.longitude);
        _isGeocodingPickup = false;
        _fareData = null;
      });
      _pickupController.text = label;
      if (_destinationLatLng != null) _calculateFare();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeocodingPickup = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  /// Fetch the actual driving route from OSRM
  Future<void> _fetchDrivingRoute() async {
    if (_destinationLatLng == null || _isLoadingRoute) return;
    setState(() => _isLoadingRoute = true);

    try {
      final routeResult = await _routingService.getDrivingRoute(
        start: _pickupLatLng,
        end: _destinationLatLng!,
      );

      if (!mounted) return;
      setState(() {
        _routePoints = routeResult.routePoints;
      });
    } catch (e) {
      // Fallback to straight line if routing fails
      if (!mounted) return;
      setState(() {
        _routePoints = [_pickupLatLng, _destinationLatLng!];
      });
      AppLogger.warning('Routing failed, using fallback: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingRoute = false);
      }
    }
  }

  // ── Fare ──────────────────────────────────────────────────────────────────

  Future<void> _calculateFare() async {
    if (_destinationLatLng == null) {
      setState(() => _error = 'Please enter a destination.');
      return;
    }
    setState(() {
      _isLoadingFare = true;
      _error = null;
      _fareData = null;
      _routePoints = []; // Clear old route
    });
    try {
      final result = await ref
          .read(rideServiceProvider)
          .calculateRideFare(
            pickupLat: _pickupLatLng.latitude,
            pickupLng: _pickupLatLng.longitude,
            destinationLat: _destinationLatLng!.latitude,
            destinationLng: _destinationLatLng!.longitude,
          );
      if (mounted)
        setState(() {
          _fareData = result;
          _isLoadingFare = false;
        });
      // Fetch the driving route after fare calculation
      _fetchDrivingRoute();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not calculate fare. Please try again.';
          _isLoadingFare = false;
        });
      }
    }
  }

  Future<void> _confirmRide() async {
    if (_isConfirming || _fareData == null || _destinationLatLng == null) return;
    setState(() => _isConfirming = true);

    try {
      final distanceKm = (_fareData!['distance_km'] as num?)?.toDouble() ?? 6.2;
      final durationMinutes =
          (_fareData!['estimated_duration_minutes'] as num?)?.toInt() ?? 18;
      final baseFare =
          (_fareData!['estimated_fare'] as num?)?.toDouble() ?? 12.40;
      final isAirport = _pickupAirport != null || _dropoffAirport != null;
      final surcharge = isAirport ? AppConstants.airportSurcharge : 0.0;
      final estimatedFare = baseFare + surcharge;
      final platformFee =
          (_fareData!['platform_fee'] as num?)?.toDouble() ??
          baseFare * 0.10;
      final ridePlatformServiceFee =
          (_fareData!['platform_service_fee'] as num?)?.toDouble() ??
          AppConstants.calculateServiceFee(estimatedFare);
      final rideStripeFeePortion =
          (_fareData!['stripe_fee_amount'] as num?)?.toDouble() ??
          AppConstants.calculateStripeFee(estimatedFare);

      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null)
        throw Exception('You must be logged in to book a ride.');

      // Wallet: verify balance before hitting the edge function
      if (_selectedPaymentMethod == 'wallet') {
        final walletBalance =
            ref.read(walletBalanceStreamProvider).valueOrNull?.availableBalance ?? 0;
        if (walletBalance < estimatedFare) {
          if (mounted) {
            setState(() => _isConfirming = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Insufficient wallet balance '
                  '(${AppConstants.currencySymbol}${walletBalance.toStringAsFixed(2)}). '
                  'Top up or choose another payment method.',
                ),
              ),
            );
          }
          return;
        }
      }

      // Card: look up the user's saved card silently (no payment UI shown)
      String? savedCardId;
      if (_selectedPaymentMethod == 'card' && _scheduledFor == null) {
        savedCardId = await _getDefaultSavedCardId();
        if (savedCardId == null) {
          if (mounted) {
            setState(() => _isConfirming = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No payment card found. Please add one from Profile → Payment Methods.',
                ),
              ),
            );
          }
          return;
        }
      }

      final params = CreateRideParams(
        pickupAddress: _pickupController.text.trim(),
        pickupLat: _pickupLatLng.latitude,
        pickupLng: _pickupLatLng.longitude,
        destinationAddress: _destinationController.text.trim(),
        destinationLat: _destinationLatLng!.latitude,
        destinationLng: _destinationLatLng!.longitude,
        distanceKm: distanceKm,
        estimatedDurationMinutes: durationMinutes,
        estimatedFare: estimatedFare,
        platformFee: platformFee,
        paymentMethod: _selectedPaymentMethod == 'card' && _scheduledFor != null
            ? 'cash'
            : _selectedPaymentMethod,
        savedCardId: savedCardId,
        stripePaymentIntentId: null,
        scheduledFor: _scheduledFor,
        isAirportPickup: _pickupAirport != null,
        isAirportDropoff: _dropoffAirport != null,
        terminalInfo: _terminalController.text.trim().isEmpty
            ? null
            : _terminalController.text.trim(),
        airportSurcharge: isAirport ? AppConstants.airportSurcharge : null,
        platformServiceFee: ridePlatformServiceFee,
        stripeFeePortion: rideStripeFeePortion,
      );

      final result = await ref.read(createRideRequestProvider(params).future);
      final rideId =
          result['ride_id'] as String? ?? result['id'] as String? ?? '';

      if (mounted) {
        if (rideId.isNotEmpty) {
          if (_scheduledFor != null) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Ride scheduled for ${DateFormat("MMM d 'at' h:mm a").format(_scheduledFor!)}',
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          } else {
            Navigator.pushReplacementNamed(
              context,
              '/rides/searching',
              arguments: rideId,
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unexpected response. Please check your trips.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to book ride: $e')));
      }
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showSuggestions = _activeQuery.isNotEmpty || _suggestions.isNotEmpty || _fetchingSuggestions || _noResults;

    final inputCard = _LocationInputCard(
      pickupController: _pickupController,
      destinationController: _destinationController,
      isGeocodingPickup: _isGeocodingPickup,
      isGeocodingDest: _isGeocodingDest,
      onPickupChanged: _onPickupChanged,
      onDestChanged: _onDestChanged,
      onSearchPickup: _geocodePickup,
      onSearchDest: _geocodeDest,
      onUseMyLocation: _useCurrentLocation,
    );

    final airportBar = _AirportBar(
      pickupAirport: _pickupAirport,
      dropoffAirport: _dropoffAirport,
      terminalController: _terminalController,
      onPickupAirport: () => _pickAirport('pickup'),
      onDropoffAirport: () => _pickAirport('dropoff'),
      onClearPickup: _clearPickupAirport,
      onClearDropoff: _clearDropoffAirport,
    );

    // While searching: show only input + full-height suggestions list.
    // Map and bottom card are hidden — they would overflow on small screens
    // and are irrelevant while the user is still typing an address.
    if (showSuggestions) {
      return GestureDetector(
        onTap: _dismissSuggestions,
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Column(
              children: [
                inputCard,
                airportBar,
                Expanded(
                  child: _SuggestionsCard(
                    suggestions: _suggestions,
                    isLoading: _fetchingSuggestions,
                    noResults: _noResults,
                    searchQuery: _activeQuery,
                    onSelect: _selectSuggestion,
                    onSearchQuery: _geocodeActiveField,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Normal mode: input + map + bottom card.
    return GestureDetector(
      onTap: _dismissSuggestions,
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Column(
            children: [
              inputCard,
              airportBar,

              // ── Error banner ─────────────────────────────────────
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: _kRed, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(fontSize: 13, color: _kRed),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Map ──────────────────────────────────────────────
              Expanded(
                child: _RouteMap(
                  pickupLatLng: _pickupLatLng,
                  destinationLatLng: _destinationLatLng,
                  routePoints: _routePoints,
                  isLoadingRoute: _isLoadingRoute,
                ),
              ),

              // ── Bottom fare/confirm card ──────────────────────────
              _BottomCard(
                fareData: _fareData,
                isLoadingFare: _isLoadingFare,
                isConfirming: _isConfirming,
                scheduledFor: _scheduledFor,
                isAirport: _pickupAirport != null || _dropoffAirport != null,
                selectedPaymentMethod: _selectedPaymentMethod,
                onPaymentMethodChanged: (m) =>
                    setState(() => _selectedPaymentMethod = m),
                onCalculate: _calculateFare,
                onConfirm: _confirmRide,
                onRecalculate: _calculateFare,
                onPickSchedule: _pickScheduleDateTime,
                onClearSchedule: _clearSchedule,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Location input card
// ---------------------------------------------------------------------------

class _LocationInputCard extends StatelessWidget {
  final TextEditingController pickupController;
  final TextEditingController destinationController;
  final bool isGeocodingPickup;
  final bool isGeocodingDest;
  final ValueChanged<String> onPickupChanged;
  final ValueChanged<String> onDestChanged;
  final VoidCallback onSearchPickup;
  final VoidCallback onSearchDest;
  final VoidCallback onUseMyLocation;

  const _LocationInputCard({
    required this.pickupController,
    required this.destinationController,
    required this.isGeocodingPickup,
    required this.isGeocodingDest,
    required this.onPickupChanged,
    required this.onDestChanged,
    required this.onSearchPickup,
    required this.onSearchDest,
    required this.onUseMyLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dotted connector
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: _kBlue,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(
                  width: 2,
                  height: 48,
                  child: CustomPaint(painter: _VerticalDotsPainter()),
                ),
                const Icon(Icons.location_on, color: _kRed, size: 20),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Input fields
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LocationTextField(
                  hint: 'Pickup location',
                  controller: pickupController,
                  isLoading: isGeocodingPickup,
                  onChanged: onPickupChanged,
                  onSearch: onSearchPickup,
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.my_location,
                      size: 18,
                      color: _kBlue,
                    ),
                    onPressed: onUseMyLocation,
                    tooltip: 'Use my location',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 18,
                  ),
                ),
                const SizedBox(height: 10),
                _LocationTextField(
                  hint: 'Where to?',
                  controller: destinationController,
                  isLoading: isGeocodingDest,
                  onChanged: onDestChanged,
                  onSearch: onSearchDest,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const dashH = 4.0;
    const dashGap = 3.0;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, (y + dashH).clamp(0, size.height)),
        paint,
      );
      y += dashH + dashGap;
    }
  }

  @override
  bool shouldRepaint(_VerticalDotsPainter old) => false;
}

class _LocationTextField extends StatelessWidget {
  final String hint;
  final TextEditingController controller;
  final bool isLoading;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearch;
  final Widget? trailing;

  const _LocationTextField({
    required this.hint,
    required this.controller,
    required this.isLoading,
    required this.onChanged,
    required this.onSearch,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: (_) => onSearch(),
              textInputAction: TextInputAction.search,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          const SizedBox(width: 4),
          isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kBlue,
                  ),
                )
              : GestureDetector(
                  onTap: onSearch,
                  child: Icon(Icons.search, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Suggestions dropdown card (overlaid on top of the map)
// ---------------------------------------------------------------------------

class _SuggestionsCard extends StatelessWidget {
  final List<_PlaceSuggestion> suggestions;
  final bool isLoading;
  final bool noResults;
  final String searchQuery;
  final ValueChanged<_PlaceSuggestion> onSelect;
  final VoidCallback onSearchQuery;

  const _SuggestionsCard({
    required this.suggestions,
    required this.isLoading,
    required this.noResults,
    required this.searchQuery,
    required this.onSelect,
    required this.onSearchQuery,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            // Always show the raw typed query as the first tappable row.
            // This lets users search for exactly what they typed (e.g. "5 Lindsay")
            // even when Nominatim has no results for that specific address.
            if (searchQuery.isNotEmpty)
              InkWell(
                onTap: onSearchQuery,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 18, color: _kBlue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          searchQuery,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Text(
                        'Search',
                        style: TextStyle(fontSize: 12, color: _kBlue),
                      ),
                    ],
                  ),
                ),
              ),
            if (searchQuery.isNotEmpty && (isLoading || suggestions.isNotEmpty))
              const Divider(height: 1),
            if (isLoading && suggestions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _kBlue),
                ),
              )
            else if (isLoading)
              const LinearProgressIndicator(
                minHeight: 2,
                color: _kBlue,
                backgroundColor: Colors.transparent,
              ),
            if (noResults && !isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.search_off, size: 36, color: Theme.of(context).colorScheme.outlineVariant),
                    const SizedBox(height: 10),
                    Text(
                      'No results found',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Try a different spelling, or press the search icon to pin the address manually.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            if (suggestions.isNotEmpty)
              Flexible(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 44, endIndent: 12),
                  itemBuilder: (_, i) {
                    final s = suggestions[i];
                    return InkWell(
                      onTap: () => onSelect(s),
                      borderRadius: i == 0
                          ? const BorderRadius.vertical(top: Radius.circular(12))
                          : i == suggestions.length - 1
                              ? const BorderRadius.vertical(
                                  bottom: Radius.circular(12))
                              : BorderRadius.zero,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: Color(0xFF6B7280),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.exactAddress,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    s.displayName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map — StatelessWidget with ValueKey so Flutter rebuilds it cleanly on
// coordinate changes (avoids MapController timing issues entirely).
// ---------------------------------------------------------------------------

class _RouteMap extends StatelessWidget {
  final LatLng pickupLatLng;
  final LatLng? destinationLatLng;
  final List<LatLng> routePoints;
  final bool isLoadingRoute;

  const _RouteMap({
    required this.pickupLatLng,
    required this.destinationLatLng,
    required this.routePoints,
    required this.isLoadingRoute,
  });

  static String _mapKey(LatLng pick, LatLng? dest) {
    final p =
        '${pick.latitude.toStringAsFixed(4)},${pick.longitude.toStringAsFixed(4)}';
    final d = dest != null
        ? ',${dest.latitude.toStringAsFixed(4)},${dest.longitude.toStringAsFixed(4)}'
        : '';
    return '$p$d';
  }

  static double _zoom(LatLng pick, LatLng? dest) {
    if (dest == null) return 13.0;
    final span = [
      (pick.latitude - dest.latitude).abs(),
      (pick.longitude - dest.longitude).abs(),
    ].reduce((a, b) => a > b ? a : b);
    if (span < 0.01) return 15.0;
    if (span < 0.05) return 13.5;
    if (span < 0.2) return 12.0;
    return 10.5;
  }

  @override
  Widget build(BuildContext context) {
    final dest = destinationLatLng;
    final pick = pickupLatLng;
    final center = dest != null
        ? LatLng(
            (pick.latitude + dest.latitude) / 2,
            (pick.longitude + dest.longitude) / 2,
          )
        : pick;

    return FlutterMap(
      key: ValueKey(_mapKey(pick, dest)),
      options: MapOptions(
        initialCenter: center,
        initialZoom: _zoom(pick, dest),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.mealhub.food_driver',
        ),
        if (dest != null)
          PolylineLayer(
            polylines: [
              Polyline(
                // Use actual driving route if available, otherwise fallback to straight line
                points: routePoints.isEmpty ? [pick, dest] : routePoints,
                color: _kBlue,
                strokeWidth: 4.0,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: pick,
              width: 36,
              height: 36,
              child: Container(
                decoration: const BoxDecoration(
                  color: _kBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.circle, color: Colors.white, size: 14),
              ),
            ),
            if (dest != null)
              Marker(
                point: dest,
                width: 36,
                height: 44,
                child: const Icon(Icons.location_on, color: _kRed, size: 36),
              ),
          ],
        ),
        if (dest == null)
          const Align(
            alignment: Alignment.center,
            child: IgnorePointer(
              child: Text(
                'Enter destination above',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        // Show loading indicator while fetching route
        if (isLoadingRoute && dest != null)
          const Center(child: CircularProgressIndicator(color: _kBlue)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom card
// ---------------------------------------------------------------------------

class _BottomCard extends StatelessWidget {
  final Map<String, dynamic>? fareData;
  final bool isLoadingFare;
  final bool isConfirming;
  final DateTime? scheduledFor;
  final bool isAirport;
  final String selectedPaymentMethod;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onCalculate;
  final VoidCallback onConfirm;
  final VoidCallback onRecalculate;
  final VoidCallback onPickSchedule;
  final VoidCallback onClearSchedule;

  const _BottomCard({
    required this.fareData,
    required this.isLoadingFare,
    required this.isConfirming,
    required this.selectedPaymentMethod,
    required this.onPaymentMethodChanged,
    required this.onCalculate,
    required this.onConfirm,
    required this.onRecalculate,
    required this.onPickSchedule,
    required this.onClearSchedule,
    this.scheduledFor,
    this.isAirport = false,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      child: fareData == null
          ? _NoFareContent(isLoading: isLoadingFare, onCalculate: onCalculate)
          : _FareContent(
              fareData: fareData!,
              isConfirming: isConfirming,
              scheduledFor: scheduledFor,
              isAirport: isAirport,
              selectedPaymentMethod: selectedPaymentMethod,
              onPaymentMethodChanged: onPaymentMethodChanged,
              onConfirm: onConfirm,
              onRecalculate: onRecalculate,
              onPickSchedule: onPickSchedule,
              onClearSchedule: onClearSchedule,
            ),
    );
  }
}

class _NoFareContent extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onCalculate;
  const _NoFareContent({required this.isLoading, required this.onCalculate});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Enter addresses above, then tap Search ↵ or Calculate Fare',
          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: isLoading ? null : onCalculate,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Calculate Fare',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }
}

class _FareContent extends ConsumerWidget {
  final Map<String, dynamic> fareData;
  final bool isConfirming;
  final DateTime? scheduledFor;
  final bool isAirport;
  final String selectedPaymentMethod;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onConfirm;
  final VoidCallback onRecalculate;
  final VoidCallback onPickSchedule;
  final VoidCallback onClearSchedule;

  const _FareContent({
    required this.fareData,
    required this.isConfirming,
    required this.selectedPaymentMethod,
    required this.onPaymentMethodChanged,
    required this.onConfirm,
    required this.onRecalculate,
    required this.onPickSchedule,
    required this.onClearSchedule,
    this.scheduledFor,
    this.isAirport = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletBalance =
        ref.watch(walletBalanceStreamProvider).valueOrNull?.availableBalance ?? 0.0;
    final distanceKm = (fareData['distance_km'] as num?)?.toDouble() ?? 0.0;
    final distanceMiles =
        (fareData['distance_miles'] as num?)?.toDouble() ??
        distanceKm / 1.60934;
    final durationMinutes =
        (fareData['estimated_duration_minutes'] as num?)?.toInt() ?? 0;
    final baseFare = (fareData['estimated_fare'] as num?)?.toDouble() ?? 0.0;
    final estimatedFare = baseFare + (isAirport ? AppConstants.airportSurcharge : 0.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(label: 'Est. Time', value: '$durationMinutes min'),
            _StatDivider(),
            _StatItem(
              label: 'Distance',
              value: '${distanceMiles.toStringAsFixed(1)} mi',
            ),
            _StatDivider(),
            _StatItem(
              label: 'Fare',
              value: '${AppConstants.currencySymbol}${estimatedFare.toStringAsFixed(2)}',
            ),
          ],
        ),
        if (isAirport) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBlue.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.flight_rounded, color: _kBlue, size: 15),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Airport surcharge',
                    style: TextStyle(fontSize: 12, color: _kBlue, fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  '+\$${AppConstants.airportSurcharge.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 13, color: _kBlue, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 10),
        // Schedule for later row
        if (scheduledFor != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, size: 18, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    DateFormat("MMM d 'at' h:mm a").format(scheduledFor!),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onClearSchedule,
                  child: const Icon(
                    Icons.close,
                    size: 18,
                    color: Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
          )
        else
          GestureDetector(
            onTap: onPickSchedule,
            child: Row(
              children: [
                Icon(Icons.schedule_outlined, size: 18, color: Theme.of(context).colorScheme.onSurface),
                const SizedBox(width: 8),
                Text(
                  'Schedule for later',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Color(0xFF9CA3AF),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 12),
        // Payment method selector
        Row(
          children: [
            Expanded(
              child: _PayMethodChip(
                icon: Icons.credit_card,
                label: 'Card',
                selected: selectedPaymentMethod == 'card',
                onTap: () => onPaymentMethodChanged('card'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: _PayMethodChip(
                icon: Icons.account_balance_wallet_rounded,
                label: walletBalance > 0
                    ? 'Wallet (${AppConstants.currencySymbol}${walletBalance.toStringAsFixed(2)})'
                    : 'Wallet',
                selected: selectedPaymentMethod == 'wallet',
                enabled: walletBalance > 0,
                onTap: () => onPaymentMethodChanged('wallet'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _PayMethodChip(
                icon: Icons.payments_outlined,
                label: 'Cash',
                selected: selectedPaymentMethod == 'cash',
                onTap: () => onPaymentMethodChanged('cash'),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onRecalculate,
              child: const Text(
                'Recalculate',
                style: TextStyle(
                  fontSize: 12,
                  color: _kBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isConfirming ? null : onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.onSurface,
              foregroundColor: Theme.of(context).colorScheme.surface,
              disabledBackgroundColor: Theme.of(context).colorScheme.outlineVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: isConfirming
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    scheduledFor != null
                        ? 'Schedule Ride'
                        : isAirport
                            ? 'Confirm Airport Ride'
                            : 'Confirm Ride',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: Theme.of(context).colorScheme.outlineVariant);
  }
}

class _PayMethodChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PayMethodChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? _kBlue : Theme.of(context).colorScheme.onSurfaceVariant;
    final bg = selected
        ? _kBlue.withValues(alpha: 0.1)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _kBlue : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Airport quick-select bar + terminal field
// ---------------------------------------------------------------------------

class _AirportBar extends StatelessWidget {
  final _Airport? pickupAirport;
  final _Airport? dropoffAirport;
  final TextEditingController terminalController;
  final VoidCallback onPickupAirport;
  final VoidCallback onDropoffAirport;
  final VoidCallback onClearPickup;
  final VoidCallback onClearDropoff;

  const _AirportBar({
    required this.pickupAirport,
    required this.dropoffAirport,
    required this.terminalController,
    required this.onPickupAirport,
    required this.onDropoffAirport,
    required this.onClearPickup,
    required this.onClearDropoff,
  });

  @override
  Widget build(BuildContext context) {
    final hasAirport = pickupAirport != null || dropoffAirport != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick-select chips
          Row(
            children: [
              _AirportChip(
                label: pickupAirport != null
                    ? '✈ ${pickupAirport!.code} Pickup'
                    : '✈ Airport Pickup',
                active: pickupAirport != null,
                onTap: onPickupAirport,
                onClear: pickupAirport != null ? onClearPickup : null,
              ),
              const SizedBox(width: 8),
              _AirportChip(
                label: dropoffAirport != null
                    ? '✈ ${dropoffAirport!.code} Dropoff'
                    : '✈ Airport Dropoff',
                active: dropoffAirport != null,
                onTap: onDropoffAirport,
                onClear: dropoffAirport != null ? onClearDropoff : null,
              ),
            ],
          ),
          // Terminal / flight number field — shown only when an airport is selected
          if (hasAirport) ...[
            const SizedBox(height: 8),
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _kBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBlue.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.confirmation_number_outlined, color: _kBlue, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: terminalController,
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                      decoration: const InputDecoration(
                        hintText: 'Terminal / Flight number (optional)',
                        hintStyle: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AirportChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _AirportChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? _kBlue.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? _kBlue.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? _kBlue : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 14, color: active ? _kBlue : Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
