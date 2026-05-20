import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';
import 'package:food_driver/config/app_constants.dart';
import 'package:food_driver/config/supabase_config.dart';
import 'package:food_driver/screens/customer/payment_screen.dart';
import 'package:food_driver/modules/rides/services/routing_service.dart';

const _kBlue = Color(0xFF2563EB);
const _kRed = Color(0xFFEF4444);

const _kDefaultPickup = LatLng(18.0060, -76.7964);
const _kDefaultDest = LatLng(18.0144, -76.7814);

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

/// Builds a street-level address from Nominatim address components.
/// Falls back to the first 3 comma-parts of display_name if components missing.
String _buildExactAddress(
  Map<String, dynamic> addressObj,
  String displayName,
) {
  final a = addressObj;
  final parts = <String>[];

  // Street-level
  final houseNumber = a['house_number'] as String?;
  final road = a['road'] as String?
      ?? a['pedestrian'] as String?
      ?? a['footway'] as String?
      ?? a['path'] as String?;
  if (road != null) {
    parts.add(houseNumber != null ? '$houseNumber $road' : road);
  }

  // Sub-locality / neighbourhood
  final suburb = a['suburb'] as String?
      ?? a['quarter'] as String?
      ?? a['neighbourhood'] as String?
      ?? a['hamlet'] as String?;
  if (suburb != null && suburb != parts.lastOrNull) parts.add(suburb);

  // City / town
  final city = a['city'] as String?
      ?? a['town'] as String?
      ?? a['village'] as String?
      ?? a['municipality'] as String?;
  if (city != null && city != parts.lastOrNull) parts.add(city);

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
  final _pickupController = TextEditingController(
    text: 'Half Way Tree, Kingston',
  );
  final _destinationController = TextEditingController(
    text: 'Sovereign Centre, Kingston',
  );

  LatLng _pickupLatLng = _kDefaultPickup;
  LatLng? _destinationLatLng = _kDefaultDest;

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
              'User-Agent': 'MealHub/1.0 (applizonecentralja@gmail.com)',
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
    };
    if (countryCode != null) params['countrycodes'] = countryCode;

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
    final resp = await http.get(uri, headers: {
      'User-Agent': 'MealHub/1.0 (applizonecentralja@gmail.com)',
      'Accept-Language': 'en',
    }).timeout(const Duration(seconds: 8));

    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data.map((e) {
      final display = e['display_name'] as String;
      final addressObj = (e['address'] as Map<String, dynamic>?) ?? {};
      return _PlaceSuggestion(
        displayName: display,
        exactAddress: _buildExactAddress(addressObj, display),
        latLng: LatLng(
          double.parse(e['lat'] as String),
          double.parse(e['lon'] as String),
        ),
      );
    }).toList();
  }

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
              'User-Agent': 'MealHub/1.0 (applizonecentralja@gmail.com)',
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
          accuracy: LocationAccuracy.high,
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
        });
        final resp = await http
            .get(
              uri,
              headers: {
                'User-Agent': 'MealHub/1.0 (applizonecentralja@gmail.com)',
              },
            )
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final display = data['display_name'] as String?;
          final address = data['address'] as Map<String, dynamic>?;
          if (display != null) {
            label = _buildExactAddress(address ?? {}, display);
          }
          // Update search country so subsequent suggestions match user's location
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
      debugPrint('Routing failed, using fallback: $e');
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
      final estimatedFare =
          (_fareData!['estimated_fare'] as num?)?.toDouble() ?? 12.40;
      final platformFee =
          (_fareData!['platform_fee'] as num?)?.toDouble() ??
          estimatedFare * 0.10;

      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null)
        throw Exception('You must be logged in to book a ride.');

      // For immediate rides, collect payment via Stripe now.
      // Scheduled rides defer payment to when the driver is dispatched.
      if (_scheduledFor == null) {
        final ridePaymentId =
            'ride_${DateTime.now().millisecondsSinceEpoch}';
        final paymentResult = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentScreen(
              orderId: ridePaymentId,
              amount: estimatedFare,
              currency: AppConstants.currencyCode,
              customerEmail: user.email,
              customerName:
                  user.userMetadata?['full_name'] as String? ??
                  user.email ??
                  '',
              restaurantName: 'Ride Payment',
              type: 'ride',
            ),
          ),
        );
        if (paymentResult == null || paymentResult['status'] != 'paid') {
          if (mounted) setState(() => _isConfirming = false);
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
        paymentMethod: 'card',
        savedCardId: null,
        scheduledFor: _scheduledFor,
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
  final VoidCallback onCalculate;
  final VoidCallback onConfirm;
  final VoidCallback onRecalculate;
  final VoidCallback onPickSchedule;
  final VoidCallback onClearSchedule;

  const _BottomCard({
    required this.fareData,
    required this.isLoadingFare,
    required this.isConfirming,
    required this.onCalculate,
    required this.onConfirm,
    required this.onRecalculate,
    required this.onPickSchedule,
    required this.onClearSchedule,
    this.scheduledFor,
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

class _FareContent extends StatelessWidget {
  final Map<String, dynamic> fareData;
  final bool isConfirming;
  final DateTime? scheduledFor;
  final VoidCallback onConfirm;
  final VoidCallback onRecalculate;
  final VoidCallback onPickSchedule;
  final VoidCallback onClearSchedule;

  const _FareContent({
    required this.fareData,
    required this.isConfirming,
    required this.onConfirm,
    required this.onRecalculate,
    required this.onPickSchedule,
    required this.onClearSchedule,
    this.scheduledFor,
  });

  @override
  Widget build(BuildContext context) {
    final distanceKm = (fareData['distance_km'] as num?)?.toDouble() ?? 0.0;
    final distanceMiles =
        (fareData['distance_miles'] as num?)?.toDouble() ??
        distanceKm / 1.60934;
    final durationMinutes =
        (fareData['estimated_duration_minutes'] as num?)?.toInt() ?? 0;
    final estimatedFare =
        (fareData['estimated_fare'] as num?)?.toDouble() ?? 0.0;

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
              value: 'J\$${estimatedFare.toStringAsFixed(0)}',
            ),
          ],
        ),
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
        Row(
          children: [
            Icon(Icons.credit_card, size: 20, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 8),
            Text(
              'Card payment',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _kBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Stripe',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _kBlue,
                ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onRecalculate,
              child: const Text(
                'Recalculate',
                style: TextStyle(
                  fontSize: 13,
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
                    scheduledFor != null ? 'Schedule Ride' : 'Confirm Ride',
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
