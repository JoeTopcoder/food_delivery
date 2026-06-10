import 'dart:async';

import 'package:flutter/material.dart';
import 'package:food_driver/utils/app_logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:food_driver/modules/rides/models/index.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';
import 'package:food_driver/providers/auth_provider.dart';
import 'package:food_driver/providers/chat_provider.dart';
import 'package:food_driver/config/supabase_config.dart';
import 'package:food_driver/modules/rides/services/routing_service.dart';
import 'package:food_driver/utils/app_feedback_widgets.dart';
import 'package:food_driver/utils/friendly_error.dart';

import 'ride_complete_screen.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum DriverRidePhase { arriving, inRide }

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ActiveRideDriverScreen extends ConsumerStatefulWidget {
  final String rideId;
  final String? pickupAddress;
  final String? destinationAddress;

  const ActiveRideDriverScreen({
    super.key,
    required this.rideId,
    this.pickupAddress,
    this.destinationAddress,
  });

  @override
  ConsumerState<ActiveRideDriverScreen> createState() =>
      _ActiveRideDriverScreenState();
}

class _ActiveRideDriverScreenState
    extends ConsumerState<ActiveRideDriverScreen>
    with WidgetsBindingObserver {
  DriverRidePhase _phase = DriverRidePhase.arriving;
  bool _isUpdating = false;
  bool _isLoadingRoute = false;
  int _mapRebuildKey = 0;

  // PIN entry for starting the ride
  final List<TextEditingController> _pinControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _pinFocusNodes =
      List.generate(6, (_) => FocusNode());
  String get _enteredPin =>
      _pinControllers.map((c) => c.text).join();

  // Default to Kingston, Jamaica; will be replaced by real GPS when available
  LatLng _driverPos = const LatLng(18.0060, -76.7964);

  // Derived from the ride record once loaded
  LatLng _pickupLatLng = const LatLng(18.0060, -76.7964);
  LatLng _destLatLng = const LatLng(18.0144, -76.7814);
  int _estimatedMin = 0;
  double _distanceKm = 0.0;

  // Real driving route points (from OSRM)
  List<LatLng> _routePoints = [];

  String? _driverId;
  Timer? _locationTimer;
  final RoutingService _routingService = RoutingService();
  Position? _lastSentPosition;

  // Waiting fee state
  Timer? _graceTimer;       // fires after 5-min grace period
  Timer? _waitingTicker;    // ticks every second once waiting is active
  bool _waitingActive = false;
  DateTime? _waitingStartedAt;
  DateTime? _waitingFrozenAt; // set when ride starts — freezes the displayed fee
  // Populated from ride.waitingFeePerMin once the waiting/pause fee is started.
  // Falls back to 75.0 only if the DB hasn't set it yet.
  double _ratePerMin = 75.0;

  double get _waitingRatePerMin => _ratePerMin;
  static const int _gracePeriodSeconds = 300; // 5 minutes

  // Pause state
  bool _isPaused = false;
  String? _pauseReason;
  DateTime? _pauseBeganAt;           // when pause started (for duration display)
  DateTime? _pauseChargeStartedAt;   // when charging actually started (null = free grace)
  bool _pauseChargeActive = false;
  Timer? _pauseGraceTimer;
  Timer? _pauseTicker;

  // Set to true only after PIN is verified and ride_started
  bool _rideStarted = false;

  // True while the ride is still in searching_driver (waiting for customer to confirm)
  bool _waitingForCustomer = false;
  ProviderSubscription<AsyncValue<RideRequest>>? _rideStatusSub;

  // Customer info for calling
  String? _customerUserId;
  String _customerName = 'Passenger';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeToRideStatus();
      _loadRideData();
      _resolveDriverId();
      _startLocationUpdates();
      _fetchCustomerInfo();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _mapRebuildKey++);
      _loadRideData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rideStatusSub?.close();
    _locationTimer?.cancel();
    _graceTimer?.cancel();
    _waitingTicker?.cancel();
    _pauseGraceTimer?.cancel();
    _pauseTicker?.cancel();
    for (final c in _pinControllers) c.dispose();
    for (final f in _pinFocusNodes) f.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Initialisation helpers
  // ------------------------------------------------------------------

  // Subscribe to realtime ride status changes so we know when the customer
  // confirms (searching_driver → driver_assigned) or cancels.
  void _subscribeToRideStatus() {
    _rideStatusSub = ref.listenManual(
      rideStatusStreamProvider(widget.rideId),
      (_, next) => next.whenData(_handleRideStatusUpdate),
    );
  }

  void _handleRideStatusUpdate(RideRequest ride) {
    if (!mounted) return;

    if (ride.rideStatus == RideStatus.cancelled ||
        ride.rideStatus == RideStatus.failed) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride was cancelled.')),
      );
      return;
    }

    // Customer just confirmed — ride is now ours
    if (_waitingForCustomer &&
        (ride.rideStatus == RideStatus.driverAssigned ||
            ride.rideStatus == RideStatus.driverArriving)) {
      setState(() => _waitingForCustomer = false);
      _silentlyAdvanceToArriving();
      return;
    }

    // Keep phase and pause state in sync with the live stream.
    // This is critical when returning to the screen — the stream fires
    // before _loadRideData() resolves, so we restore state here too.
    if (ride.rideStatus == RideStatus.driverArrived ||
        ride.rideStatus == RideStatus.rideStarted ||
        ride.rideStatus == RideStatus.ridePaused) {
      setState(() {
        _phase = DriverRidePhase.inRide;

        if (ride.rideStatus == RideStatus.ridePaused) {
          _rideStarted = true;
          _isPaused = true;
          _pauseReason ??= ride.pauseReason;
        } else if (ride.rideStatus == RideStatus.rideStarted) {
          _rideStarted = true;
          _isPaused = false;
          if (_waitingFrozenAt == null && _waitingStartedAt != null) {
            _waitingFrozenAt = ride.startedAt ?? DateTime.now();
            _waitingTicker?.cancel();
            _waitingTicker = null;
          }
        }
      });
    }
  }

  Future<void> _loadRideData() async {
    try {
      final ride = await ref
          .read(rideServiceProvider)
          .getRideRequest(widget.rideId);
      if (!mounted) return;
      setState(() {
        _pickupLatLng = LatLng(ride.pickupLat, ride.pickupLng);
        _destLatLng = LatLng(ride.destinationLat, ride.destinationLng);
        _estimatedMin = ride.estimatedDurationMinutes ?? 0;
        _distanceKm = ride.distanceKm ?? 0.0;
        // Only set initial driver position — don't overwrite live GPS position
        if (_driverPos == const LatLng(18.0060, -76.7964)) {
          _driverPos = _pickupLatLng;
        }

        // Waiting for the customer to choose us from the offered list
        if (ride.rideStatus == RideStatus.searchingDriver) {
          _waitingForCustomer = true;
          return;
        }

        // Restore correct phase if ride is already further along
        if (ride.rideStatus == RideStatus.driverArrived ||
            ride.rideStatus == RideStatus.rideStarted ||
            ride.rideStatus == RideStatus.ridePaused) {
          _phase = DriverRidePhase.inRide;
        }
        if (ride.rideStatus == RideStatus.rideStarted ||
            ride.rideStatus == RideStatus.ridePaused) {
          _rideStarted = true;
        }
        if (ride.rideStatus == RideStatus.ridePaused) {
          _isPaused = true;
          _pauseReason ??= ride.pauseReason;
          // Use the DB timestamp so the timer survives screen navigation,
          // app background, or even a full app restart.
          _pauseBeganAt ??= ride.pausedAt ?? DateTime.now();
          if (ride.waitingStartedAt != null && !_pauseChargeActive) {
            _pauseChargeActive = true;
            _pauseChargeStartedAt = ride.waitingStartedAt;
          }
          if (ride.waitingFeePerMin != null) {
            _ratePerMin = ride.waitingFeePerMin!;
          }
        }
      });

      if (_waitingForCustomer) return;

      // Restore pause ticker if ride is already paused — guards prevent
      // duplicate timers when _loadRideData is called more than once.
      if (_isPaused && _pauseTicker == null) {
        _pauseTicker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
        if (!_pauseChargeActive && _pauseGraceTimer == null) {
          // Calculate how much grace time is left based on the actual pause
          // start time from the DB so the dialog fires at the right moment
          // even after the driver leaves and returns to the screen.
          final elapsed =
              DateTime.now().difference(_pauseBeganAt!).inSeconds;
          final remaining = (_gracePeriodSeconds - elapsed).clamp(0, _gracePeriodSeconds);
          if (remaining > 0) {
            _pauseGraceTimer = Timer(
              Duration(seconds: remaining),
              _showPauseChargeDialog,
            );
          } else {
            // Grace already expired while driver was away — show dialog now.
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _showPauseChargeDialog(),
            );
          }
        }
      }

      // Auto-advance to driver_arriving so the state machine stays valid
      if (ride.rideStatus == RideStatus.driverAssigned) {
        _silentlyAdvanceToArriving();
      }

      _fetchDrivingRoute();
    } catch (_) {
      // Use defaults already set in state
    }
  }

  /// Silently advance the ride status to driver_arriving when the screen first
  /// loads. This keeps the DB state machine consistent without blocking the UI.
  Future<void> _silentlyAdvanceToArriving() async {
    try {
      await ref.read(rideServiceProvider).updateRideStatus(
        rideId: widget.rideId,
        newStatus: 'driver_arriving',
        latitude: _driverPos.latitude,
        longitude: _driverPos.longitude,
      );
    } catch (_) {
      // Non-critical — the edge function now also accepts driver_assigned → driver_arrived
    }
  }

  /// Fetch the actual driving route from OSRM
  Future<void> _fetchDrivingRoute() async {
    if (_isLoadingRoute) return;
    setState(() => _isLoadingRoute = true);

    try {
      final routeResult = await _routingService.getDrivingRoute(
        start: _pickupLatLng,
        end: _destLatLng,
      );

      if (!mounted) return;
      setState(() {
        _routePoints = routeResult.routePoints;
        // Update distance and time with actual driving values
        _distanceKm = routeResult.distanceKm;
        _estimatedMin = routeResult.durationMinutes.round();
      });
    } catch (e) {
      // Fallback to straight line if routing fails
      if (!mounted) return;
      setState(() {
        _routePoints = [_pickupLatLng, _destLatLng];
      });
      AppLogger.warning('Routing failed, using fallback: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingRoute = false);
      }
    }
  }

  Future<void> _resolveDriverId() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    try {
      final response = await SupabaseConfig.client
          .from('drivers')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted) return;
      _driverId = response?['id'] as String?;
    } catch (_) {}
  }

  Future<void> _fetchCustomerInfo() async {
    try {
      final row = await SupabaseConfig.client
          .from('ride_requests')
          .select('customer_id')
          .eq('id', widget.rideId)
          .maybeSingle();
      if (!mounted || row == null) return;
      final customerId = row['customer_id'] as String?;
      if (customerId == null) return;
      final userRow = await SupabaseConfig.client
          .from('users')
          .select('name')
          .eq('id', customerId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _customerUserId = customerId;
        _customerName =
            (userRow?['name'] as String?)?.trim().isNotEmpty == true
                ? userRow!['name'] as String
                : 'Passenger';
      });
    } catch (_) {}
  }

  void _openChat() {
    Navigator.pushNamed(context, '/chat', arguments: {
      'rideId': widget.rideId,
      'otherPartyName': _customerName,
      'receiverId': _customerUserId,
    });
  }

  Future<void> _callCustomer() async {
    if (_customerUserId == null || _customerUserId!.isEmpty) {
      AppSnackbar.warning(context, 'Passenger info not loaded yet — try again.');
      return;
    }
    try {
      final call = await ref
          .read(chatServiceProvider)
          .initiateCall(orderId: widget.rideId, receiverId: _customerUserId!);
      if (!mounted) return;
      Navigator.pushNamed(context, '/call', arguments: {
        'call': call,
        'isCaller': true,
        'otherPartyName': _customerName,
      });
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  void _startLocationUpdates() {
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _sendLocation();
    });
  }

  Future<void> _sendLocation() async {
    final driverId = _driverId;
    if (driverId == null) return;

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      // Skip poor-accuracy fixes (e.g. indoors / weak signal)
      if (position.accuracy > 40) return;

      // Only push if moved >15 m or heading changed >10°
      final prev = _lastSentPosition;
      if (prev != null) {
        final moved = Geolocator.distanceBetween(
          prev.latitude, prev.longitude, position.latitude, position.longitude,
        );
        final dHeading = (position.heading - prev.heading).abs();
        final normDHeading = dHeading > 180 ? 360 - dHeading : dHeading;
        if (moved < 15 && normDHeading < 10) return;
      }
      _lastSentPosition = position;

      if (!mounted) return;
      setState(() {
        _driverPos = LatLng(position.latitude, position.longitude);
      });

      await ref
          .read(rideServiceProvider)
          .updateDriverLocation(
            rideId: widget.rideId,
            driverId: driverId,
            latitude: position.latitude,
            longitude: position.longitude,
            heading: position.heading,
            speed: position.speed,
          );
    } catch (_) {
      // Location unavailable — silently continue using last known position
    }
  }

  /// Open turn-by-turn navigation to [dest] in Google Maps or Waze.
  Future<void> _openNavigation(LatLng dest) async {
    final lat = dest.latitude;
    final lng = dest.longitude;

    // Try Google Maps first
    final gmUrl = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    if (await canLaunchUrl(gmUrl)) {
      await launchUrl(gmUrl);
      return;
    }
    // Fall back to Waze
    final wazeUrl = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
    if (await canLaunchUrl(wazeUrl)) {
      await launchUrl(wazeUrl);
      return;
    }
    // Last resort: browser Google Maps
    await launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'),
      mode: LaunchMode.externalApplication,
    );
  }

  // ------------------------------------------------------------------
  // Phase actions
  // ------------------------------------------------------------------

  Future<void> _onArrived() async {
    setState(() => _isUpdating = true);
    try {
      await ref
          .read(rideServiceProvider)
          .updateRideStatus(
            rideId: widget.rideId,
            newStatus: 'driver_arrived',
            latitude: _driverPos.latitude,
            longitude: _driverPos.longitude,
          );
      if (!mounted) return;
      setState(() {
        _phase = DriverRidePhase.inRide;
        _isUpdating = false;
      });
      _startGraceCountdown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  // ── Waiting fee helpers ────────────────────────────────────────────────────

  void _startGraceCountdown() {
    _graceTimer?.cancel();
    _graceTimer = Timer(
      const Duration(seconds: _gracePeriodSeconds),
      _showWaitingDialog,
    );
  }

  Future<void> _showWaitingDialog() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Customer not at vehicle?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'The free 5-minute wait has ended.\n\n'
          'Is the customer still not here? You can start the waiting fee '
          '(J\$75/min) which will be added to the ride total.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("I'll wait"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start waiting fee'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _startWaitingFee();
    }
  }

  Future<void> _startWaitingFee() async {
    try {
      final rate = await ref.read(rideServiceProvider).startWaitingFee(
        rideId: widget.rideId,
      );
      if (!mounted) return;
      setState(() {
        _waitingActive = true;
        _waitingStartedAt = DateTime.now();
        _ratePerMin = rate;
      });
      // Tick every second to update the displayed waiting fee
      _waitingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start waiting fee: $e')),
      );
    }
  }

  double get _accruedWaitingFee {
    if (_waitingStartedAt == null) return 0.0;
    final upperBound = _waitingFrozenAt ?? DateTime.now();
    final mins = upperBound.difference(_waitingStartedAt!).inSeconds / 60.0;
    return mins.clamp(0.0, double.infinity) * _waitingRatePerMin;
  }

  double get _accruedPauseFee {
    if (_pauseChargeStartedAt == null) return 0.0;
    final mins =
        DateTime.now().difference(_pauseChargeStartedAt!).inSeconds / 60.0;
    return mins.clamp(0.0, double.infinity) * _waitingRatePerMin;
  }

  String get _pauseDurationText {
    if (_pauseBeganAt == null) return '';
    final dur = DateTime.now().difference(_pauseBeganAt!);
    final m = dur.inMinutes;
    final s = dur.inSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  String get _pauseGraceRemainingText {
    if (_pauseBeganAt == null || _pauseChargeActive) return '';
    final elapsed = DateTime.now().difference(_pauseBeganAt!).inSeconds;
    final remaining = (300 - elapsed).clamp(0, 300);
    if (remaining <= 0) return '';
    final m = remaining ~/ 60;
    final s = remaining % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // ── Pause / Resume helpers ─────────────────────────────────────────────────

  Future<void> _onPauseRide() async {
    const reasons = [
      'Restroom break',
      'Quick shop stop',
      'Vehicle issue',
      'Traffic / road closure',
      'Other',
    ];

    String? selected = reasons.first;
    final customController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Why are you pausing?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The customer will be notified',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 16),
                ...reasons.map((r) => GestureDetector(
                      onTap: () => setInner(() => selected = r),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected == r
                                      ? const Color(0xFFF59E0B)
                                      : Theme.of(ctx).colorScheme.onSurfaceVariant,
                                  width: 2,
                                ),
                              ),
                              child: selected == r
                                  ? Center(
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFFF59E0B),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Text(r,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14)),
                          ],
                        ),
                      ),
                    )),
                if (selected == 'Other') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: customController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Describe the reason…',
                      hintStyle: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'Pause Ride',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    final reason = selected == 'Other'
        ? (customController.text.trim().isNotEmpty
            ? customController.text.trim()
            : 'Other')
        : selected ?? 'Paused';

    setState(() => _isUpdating = true);
    try {
      final pausedAt = DateTime.now();
      await ref.read(rideServiceProvider).updateRideStatus(
            rideId: widget.rideId,
            newStatus: 'ride_paused',
            pauseReason: reason,
          );
      if (!mounted) return;

      // Persist the exact pause timestamp so the timer survives navigation.
      // The RPC may not write paused_at, so we write it directly here.
      SupabaseConfig.client
          .from('ride_requests')
          .update({'paused_at': pausedAt.toUtc().toIso8601String()})
          .eq('id', widget.rideId)
          .catchError((_) {});

      setState(() {
        _isPaused = true;
        _pauseReason = reason;
        _pauseBeganAt = pausedAt;
        _pauseChargeActive = false;
        _pauseChargeStartedAt = null;
        _isUpdating = false;
      });
      _pauseTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      _pauseGraceTimer = Timer(
        const Duration(minutes: 5),
        _showPauseChargeDialog,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pause ride: $e')),
      );
    }
  }

  Future<void> _onResumeRide() async {
    setState(() => _isUpdating = true);
    try {
      // Charge the accrued pause fee before resuming
      if (_pauseChargeActive) {
        await _chargePauseFeeAndNotify();
      }

      await ref.read(rideServiceProvider).updateRideStatus(
            rideId: widget.rideId,
            newStatus: 'ride_started',
          );
      if (!mounted) return;
      _pauseGraceTimer?.cancel();
      _pauseGraceTimer = null;
      _pauseTicker?.cancel();
      _pauseTicker = null;
      setState(() {
        _isPaused = false;
        _pauseReason = null;
        _pauseBeganAt = null;
        _pauseChargeStartedAt = null;
        _pauseChargeActive = false;
        _isUpdating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resume ride: $e')),
      );
    }
  }

  Future<void> _chargePauseFeeAndNotify() async {
    try {
      final result = await ref
          .read(rideServiceProvider)
          .chargePauseFee(rideId: widget.rideId);

      if (!mounted) return;

      final amount =
          (result['amount'] as num?)?.toDouble() ?? 0.0;
      final status = result['status'] as String? ?? 'unknown';
      final paymentMethod =
          result['payment_method'] as String? ?? '';

      if (amount < 1 || status == 'no_charge') return;

      final String message;
      final Color bgColor;
      switch (status) {
        case 'charged':
          message =
              'J\$${amount.toStringAsFixed(0)} charged to customer\'s '
              '${paymentMethod == 'wallet' ? 'wallet' : 'card'}';
          bgColor = const Color(0xFF22C55E);
          break;
        case 'charge_failed':
          message =
              'J\$${amount.toStringAsFixed(0)} pause fee — payment failed, will be added to final fare';
          bgColor = const Color(0xFFEF4444);
          break;
        case 'insufficient_funds':
          message =
              'J\$${amount.toStringAsFixed(0)} pause fee — insufficient wallet balance, added to final fare';
          bgColor = const Color(0xFFEF4444);
          break;
        default:
          message = 'Pause fee: J\$${amount.toStringAsFixed(0)}';
          bgColor = const Color(0xFFF59E0B);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: bgColor,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (_) {
      // Charge attempt failed — resume ride anyway, driver was notified
    }
  }

  Future<void> _showPauseChargeDialog() async {
    if (!mounted || !_isPaused) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Customer not back yet?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'The 5-minute free pause has ended.\n\n'
          'Would you like to start charging the customer J\$75/min for the wait?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("No, I'll wait"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, start charging'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _startPauseCharge();
  }

  Future<void> _startPauseCharge() async {
    try {
      final rate = await ref.read(rideServiceProvider).startWaitingFee(rideId: widget.rideId);
      if (!mounted) return;
      setState(() {
        _pauseChargeActive = true;
        _pauseChargeStartedAt = DateTime.now();
        _ratePerMin = rate;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start pause charge: $e')),
      );
    }
  }

  Future<void> _onStartRide() async {
    final pin = _enteredPin;
    if (pin.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit code from the customer')),
      );
      return;
    }

    setState(() => _isUpdating = true);
    try {
      await ref
          .read(rideServiceProvider)
          .updateRideStatus(
            rideId: widget.rideId,
            newStatus: 'ride_started',
            latitude: _driverPos.latitude,
            longitude: _driverPos.longitude,
            pin: pin,
          );
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
        _rideStarted = true;
        if (_waitingFrozenAt == null && _waitingStartedAt != null) {
          _waitingFrozenAt = DateTime.now();
          _waitingTicker?.cancel();
          _waitingTicker = null;
        }
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RideCompleteScreen(rideId: widget.rideId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      final msg = e.toString().contains('Invalid PIN')
          ? 'Wrong code — ask the customer for their 6-digit code'
          : 'Failed to start ride: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildMap(),
          Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomCard()),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // AppBar
  // ------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar() {
    final title = _waitingForCustomer
        ? 'Waiting for Confirmation'
        : _phase == DriverRidePhase.arriving
            ? 'Arriving at Pickup'
            : _isPaused
                ? 'Ride Paused'
                : 'Ride in Progress';

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
              ),
            ],
          ),
          child: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface, size: 20),
        ),
      ),
      title: _phase == DriverRidePhase.inRide
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _isPaused
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF22C55E),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isPaused) ...[
                    const Icon(Icons.pause_circle_outline,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      'PAUSED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ] else ...[
                    const _PulsingDot(),
                    const SizedBox(width: 6),
                    Text(
                      '$_estimatedMin min  •  ${_distanceKm.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
      centerTitle: true,
      actions: [
        _MapIconButton(icon: Icons.phone_outlined, onTap: _callCustomer),
        _MapIconButton(icon: Icons.chat_bubble_outline, onTap: _openChat),
        const SizedBox(width: 4),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Map
  // ------------------------------------------------------------------

  Widget _buildMap() {
    final markers = <Marker>[
      // Driver position
      Marker(
        point: _driverPos,
        width: 36,
        height: 36,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF2563EB),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.directions_car,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
      // Pickup blue dot
      Marker(
        point: _pickupLatLng,
        width: 24,
        height: 24,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      ),
      // Destination red pin
      Marker(
        point: _destLatLng,
        width: 36,
        height: 44,
        child: const Icon(
          Icons.location_pin,
          color: Color(0xFFEF4444),
          size: 44,
        ),
      ),
    ];

    final mapCenter = LatLng(
      (_pickupLatLng.latitude + _destLatLng.latitude) / 2,
      (_pickupLatLng.longitude + _destLatLng.longitude) / 2,
    );

    // Use actual driving route if available, otherwise fallback to straight line
    final routePolylinePoints = _routePoints.isEmpty
        ? [_pickupLatLng, _destLatLng]
        : _routePoints;

    return FlutterMap(
      key: ValueKey(_mapRebuildKey),
      options: MapOptions(initialCenter: mapCenter, initialZoom: 13.0),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.mealhub.food_driver',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: routePolylinePoints,
              strokeWidth: 4,
              color: const Color(0xFF2563EB),
            ),
          ],
        ),
        MarkerLayer(markers: markers),
        // Show loading indicator while fetching route
        if (_isLoadingRoute)
          const Center(
            child: CircularProgressIndicator(color: Color(0xFF2563EB)),
          ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Bottom card
  // ------------------------------------------------------------------

  Widget _buildBottomCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: _phase == DriverRidePhase.arriving
          ? _buildArrivingContent()
          : _buildInRideContent(),
    );
  }

  Widget _buildArrivingContent() {
    if (_waitingForCustomer) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PICKUP',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.pickupAddress ?? 'Pickup Location',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF2563EB),
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Waiting for customer confirmation',
                        style: TextStyle(
                          color: Color(0xFF2563EB),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'The customer is selecting their driver',
                        style: TextStyle(
                          color: Color(0xFF2563EB),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PICKUP',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.pickupAddress ?? 'Pickup Location',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isUpdating ? null : _onArrived,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isUpdating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'I Have Arrived',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _CircleIconButton(
              icon: Icons.navigation_rounded,
              onTap: () => _openNavigation(_pickupLatLng),
            ),
            const SizedBox(width: 8),
            _CircleIconButton(icon: Icons.phone_outlined, onTap: _callCustomer),
            const SizedBox(width: 8),
            _CircleIconButton(icon: Icons.chat_bubble_outline, onTap: _openChat),
          ],
        ),
      ],
    );
  }

  Widget _buildInRideContent() {
    final pinFull = _enteredPin.length == 6;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Pause banner with live charge meter ─────────────────────────
        if (_isPaused) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.pause_circle_outline,
                    color: Color(0xFFF59E0B), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Ride is paused',
                            style: TextStyle(
                              color: Color(0xFFF59E0B),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (_pauseDurationText.isNotEmpty)
                            Text(
                              _pauseDurationText,
                              style: const TextStyle(
                                color: Color(0xFFF59E0B),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (_pauseReason != null)
                            Text(
                              _pauseReason!,
                              style: const TextStyle(
                                color: Color(0xFFF59E0B),
                                fontSize: 12,
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                          if (_pauseChargeActive)
                            Text(
                              'J\$${_accruedPauseFee.toStringAsFixed(0)}  •  J\$75/min',
                              style: const TextStyle(
                                color: Color(0xFFF59E0B),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else if (_pauseGraceRemainingText.isNotEmpty)
                            Text(
                              'Free: $_pauseGraceRemainingText left',
                              style: const TextStyle(
                                color: Color(0xFFF59E0B),
                                fontSize: 12,
                              ),
                            )
                          else
                            const Text(
                              'Grace period ended',
                              style: TextStyle(
                                color: Color(0xFFF59E0B),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Waiting fee meter (only before ride starts; fee freezes at ride_started) ──
        if (_waitingActive && !_rideStarted) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer,
                    color: Color(0xFFEF4444), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Waiting fee running',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'J\$${_accruedWaitingFee.toStringAsFixed(0)}  •  J\$75/min',
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        Text(
          'DESTINATION',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.destinationAddress ?? 'Destination',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        if (_isPaused) ...[
          // ── Paused: show Resume button only ─────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isUpdating ? null : _onResumeRide,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    const Color(0xFF22C55E).withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              icon: _isUpdating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text(
                'Resume Ride',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ] else if (!_rideStarted) ...[
          // ── PIN entry — only before the ride has been started ─────────

          // PIN instruction
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF2563EB).withValues(alpha: 0.2),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline,
                    color: Color(0xFF2563EB), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ask customer for their 6-digit code',
                    style: TextStyle(
                      color: Color(0xFF2563EB),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 6 PIN boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (i) {
              return SizedBox(
                width: 44,
                height: 52,
                child: TextField(
                  controller: _pinControllers[i],
                  focusNode: _pinFocusNodes[i],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFF2563EB), width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: _pinControllers[i].text.isNotEmpty
                            ? const Color(0xFF2563EB)
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  onChanged: (val) {
                    if (val.isNotEmpty && i < 5) {
                      _pinFocusNodes[i + 1].requestFocus();
                    } else if (val.isEmpty && i > 0) {
                      _pinFocusNodes[i - 1].requestFocus();
                    }
                    setState(() {});
                  },
                ),
              );
            }),
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_isUpdating || !pinFull) ? null : _onStartRide,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    const Color(0xFF2563EB).withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isUpdating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Start Ride',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ] else ...[
          // ── Ride active: Complete + Pause ─────────────────────────────
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isUpdating
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    RideCompleteScreen(rideId: widget.rideId),
                              ),
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Complete Ride',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _isUpdating ? null : _onPauseRide,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF59E0B),
                    side: const BorderSide(color: Color(0xFFF59E0B)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.pause_rounded, size: 18),
                  label: const Text('Pause',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _MapIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
            ),
          ],
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.onSurface, size: 18),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.onSurface, size: 20),
      ),
    );
  }
}
