import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:food_driver/modules/rides/models/index.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';
import 'package:food_driver/providers/auth_provider.dart';
import 'package:food_driver/config/supabase_config.dart';

// ---------------------------------------------------------------------------
// Driver Ride Sharing Screen — simplified: toggle + earnings + rides
// ---------------------------------------------------------------------------

class DriverModeScreen extends ConsumerStatefulWidget {
  const DriverModeScreen({super.key});

  @override
  ConsumerState<DriverModeScreen> createState() => _DriverModeScreenState();
}

class _DriverModeScreenState extends ConsumerState<DriverModeScreen>
    with SingleTickerProviderStateMixin {
  bool _isOnline = false;
  bool _canDoRides = false;
  String? _driverId;
  bool _isLoadingDriver = true;
  bool _isTogglingMode = false;

  // Today's earnings (sum of driver_earning for completed rides today)
  double _todayEarnings = 0.0;
  int _todayRidesCount = 0;

  // Active ride (driver already accepted — show return banner)
  RideRequest? _activeRide;

  // Pulse animation for the status dot
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Live pending ride requests (each entry already has ride details embedded)
  List<DriverRideOffer> _pendingRequests = [];
  Timer? _countdownTimer;
  Timer? _locationTimer;
  ProviderSubscription<AsyncValue<List<DriverRideOffer>>>? _requestSub;
  final Set<String> _processingIds = {};
  // Track which offer IDs have already triggered a pop-up so we don't re-show
  final Set<String> _shownPopupIds = {};

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDriver());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _requestSub?.close();
    _countdownTimer?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Load the driver record
  // ------------------------------------------------------------------
  Future<void> _loadDriver() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      setState(() => _isLoadingDriver = false);
      return;
    }

    try {
      final response = await SupabaseConfig.client
          .from('drivers')
          .select('id, is_online, active_services')
          .eq('user_id', userId)
          .maybeSingle();

      if (!mounted) return;

      if (response != null) {
        final driverId = response['id'] as String;
        final isOnline = response['is_online'] as bool? ?? false;
        final activeServices = (response['active_services'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            ['food_delivery'];
        final canDoRides = activeServices.contains('ride_sharing');

        setState(() {
          _driverId = driverId;
          _canDoRides = canDoRides;
          _isOnline = isOnline && canDoRides;
          _isLoadingDriver = false;
        });

        unawaited(_checkActiveRide(driverId));
        unawaited(_loadTodayEarnings(driverId));

        if (_isOnline) {
          _startListeningForRequests(driverId);
          _startLocationUpdates(driverId);
        }
      } else {
        setState(() => _isLoadingDriver = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDriver = false);
    }
  }

  // ------------------------------------------------------------------
  // Today's earnings
  // ------------------------------------------------------------------
  Future<void> _loadTodayEarnings(String driverId) async {
    try {
      final todayStart = DateTime.now().copyWith(
        hour: 0, minute: 0, second: 0, millisecond: 0,
      );
      final response = await SupabaseConfig.client
          .from('ride_requests')
          .select('driver_earning')
          .eq('driver_id', driverId)
          .eq('ride_status', 'ride_completed')
          .gte('completed_at', todayStart.toIso8601String());

      if (!mounted) return;
      final list = response as List<dynamic>;
      double total = 0;
      for (final row in list) {
        total += (row['driver_earning'] as num?)?.toDouble() ?? 0.0;
      }
      setState(() {
        _todayEarnings = total;
        _todayRidesCount = list.length;
      });
    } catch (_) {
      // Non-critical
    }
  }

  // ------------------------------------------------------------------
  // Check for an in-progress ride this driver already accepted
  // ------------------------------------------------------------------
  Future<void> _checkActiveRide(String driverId) async {
    try {
      final ride = await ref
          .read(rideServiceProvider)
          .getActiveRideForDriver(driverId);
      if (!mounted) return;
      const activeStatuses = {
        RideStatus.driverAssigned,
        RideStatus.driverArriving,
        RideStatus.driverArrived,
        RideStatus.rideStarted,
        RideStatus.ridePaused,
      };
      setState(() {
        _activeRide = (ride != null && activeStatuses.contains(ride.rideStatus))
            ? ride
            : null;
      });
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // GPS helper
  // ------------------------------------------------------------------
  Future<({double? lat, double? lng})> _getCurrentGps() async {
    try {
      final service = await Geolocator.isLocationServiceEnabled();
      if (!service) return (lat: null, lng: null);
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return (lat: null, lng: null);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 8));
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return (lat: null, lng: null);
    }
  }

  // ------------------------------------------------------------------
  // Toggle online / offline
  // ------------------------------------------------------------------
  Future<void> _toggleOnline() async {
    final driverId = _driverId;
    if (driverId == null || _isTogglingMode) return;

    if (!_canDoRides) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enable Ride Sharing in Active Services on your dashboard first.',
          ),
        ),
      );
      return;
    }

    setState(() => _isTogglingMode = true);

    try {
      if (_isOnline) {
        // Go offline
        await ref.read(driverOnlineModeProvider.notifier)
            .setMode(DriverOnlineMode.offline, driverId);
        _stopListeningForRequests();
        _stopLocationUpdates();
        if (mounted) setState(() => _isOnline = false);
      } else {
        // Go online for ride sharing — get GPS first
        final gps = await _getCurrentGps();
        await ref.read(driverOnlineModeProvider.notifier)
            .setMode(DriverOnlineMode.rideSharing, driverId,
                lat: gps.lat, lng: gps.lng);
        _startListeningForRequests(driverId);
        _startLocationUpdates(driverId);
        if (mounted) setState(() => _isOnline = true);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isOnline ? 'You are now online' : 'You are now offline'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update status')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingMode = false);
    }
  }

  // ------------------------------------------------------------------
  // Periodic location push (every 30 s while online)
  // ------------------------------------------------------------------
  void _startLocationUpdates(String driverId) {
    _locationTimer?.cancel();
    // Push immediately, then every 30 seconds
    unawaited(_pushLocation(driverId));
    _locationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) unawaited(_pushLocation(driverId));
    });
  }

  void _stopLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _pushLocation(String driverId) async {
    final gps = await _getCurrentGps();
    if (gps.lat == null || gps.lng == null) return;
    try {
      await SupabaseConfig.client.from('drivers').update({
        'current_lat': gps.lat,
        'current_lng': gps.lng,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', driverId);
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Real-time request stream
  // ------------------------------------------------------------------
  void _startListeningForRequests(String driverId) {
    _requestSub?.close();
    // Clear shown set so requests that arrived while off-screen get a popup
    _shownPopupIds.clear();

    // Immediate one-shot fetch — shows any pending requests without waiting
    // for the realtime stream to emit its first event (which can take seconds).
    unawaited(_fetchPendingRequestsNow(driverId));

    _requestSub = ref.listenManual(
      driverRideOffersStreamProvider(driverId),
      (_, next) => next.whenData(_onRequestListUpdate),
    );

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final before = _pendingRequests.length;
      _pendingRequests.removeWhere((o) => o.request.expiresAt.isBefore(now));
      if (_pendingRequests.length != before) setState(() {});
    });
  }

  /// Directly queries the DB for this driver's pending, non-expired requests
  /// and feeds them through [_onRequestListUpdate] immediately on screen entry.
  Future<void> _fetchPendingRequestsNow(String driverId) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      final reqRows = await SupabaseConfig.client
          .from('ride_driver_requests')
          .select()
          .eq('driver_id', driverId)
          .eq('status', 'pending')
          .gt('expires_at', now)
          .order('sent_at', ascending: false);

      if (!mounted) return;

      final requests = (reqRows as List<dynamic>)
          .map((r) => RideDriverRequest.fromJson(r as Map<String, dynamic>))
          .toList();

      if (requests.isEmpty) return;

      // Batch-fetch the associated ride details
      final rideIds = requests.map((r) => r.rideId).toList();
      final rideRows = await SupabaseConfig.client
          .from('ride_requests')
          .select()
          .inFilter('id', rideIds);

      if (!mounted) return;

      final rideMap = <String, RideRequest>{};
      for (final row in rideRows as List<dynamic>) {
        final ride = RideRequest.fromJson(row as Map<String, dynamic>);
        rideMap[ride.id] = ride;
      }

      final offers = requests
          .map((req) => DriverRideOffer(request: req, ride: rideMap[req.rideId]))
          .toList();

      _onRequestListUpdate(offers);
    } catch (_) {
      // Non-critical — stream will catch anything we miss
    }
  }

  void _stopListeningForRequests() {
    _requestSub?.close();
    _requestSub = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (mounted) setState(() => _pendingRequests.clear());
  }

  void _onRequestListUpdate(List<DriverRideOffer> offers) {
    if (!mounted) return;
    final now = DateTime.now();
    final fresh = offers.where((o) => o.request.expiresAt.isAfter(now)).toList();
    setState(() => _pendingRequests = fresh);

    // Pop-up each new offer that hasn't been shown yet
    for (final offer in fresh) {
      final id = offer.request.id;
      if (!_shownPopupIds.contains(id)) {
        _shownPopupIds.add(id);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showRideRequestPopup(offer);
        });
      }
    }
  }

  void _showRideRequestPopup(DriverRideOffer offer) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => _RideRequestPopup(
        offer: offer,
        onAccept: () {
          Navigator.of(ctx).pop();
          _handleAccept(offer);
        },
        onDecline: () {
          Navigator.of(ctx).pop();
          _handleDecline(offer);
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // Accept / Decline
  // ------------------------------------------------------------------
  Future<void> _handleAccept(DriverRideOffer offer) async {
    final reqId = offer.request.id;
    if (_processingIds.contains(reqId)) return;
    setState(() => _processingIds.add(reqId));

    try {
      final result = await ref.read(rideServiceProvider).respondToDriverRideRequest(
        rideDriverRequestId: reqId,
        accept: true,
      );

      if (!mounted) return;

      final accepted = result['accepted'] as bool? ?? false;
      if (accepted) {
        setState(() {
          _pendingRequests.removeWhere((o) => o.request.id == reqId);
          _processingIds.remove(reqId);
        });
        await Navigator.of(context).pushNamed(
          '/rides/driver/active',
          arguments: {
            'rideId': offer.request.rideId,
            'pickupAddress': offer.ride?.pickupAddress,
            'destinationAddress': offer.ride?.destinationAddress,
          },
        );
        if (mounted && _driverId != null) unawaited(_checkActiveRide(_driverId!));
      } else {
        setState(() => _processingIds.remove(reqId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ride already taken by another driver')),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _processingIds.remove(reqId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to accept ride — try again')),
      );
    }
  }

  Future<void> _handleDecline(DriverRideOffer offer) async {
    final reqId = offer.request.id;
    if (_processingIds.contains(reqId)) return;
    setState(() => _pendingRequests.removeWhere((o) => o.request.id == reqId));
    try {
      await ref.read(rideServiceProvider).respondToDriverRideRequest(
        rideDriverRequestId: reqId,
        accept: false,
      );
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 0,
          leading: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          title: const Text(
            'Ride Sharing',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _driverId != null
                  ? () => Navigator.of(context).pushNamed(
                        '/rides/driver/trips',
                        arguments: {'driverId': _driverId},
                      )
                  : null,
              icon: const Icon(Icons.history, color: Colors.white),
            ),
          ],
        ),
        body: _isLoadingDriver
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF22C55E)),
              )
            : CustomScrollView(
                slivers: [
                  // Active ride return banner
                  if (_activeRide != null)
                    SliverToBoxAdapter(
                      child: _buildActiveRideBanner(_activeRide!),
                    ),

                  // Earnings summary
                  SliverToBoxAdapter(child: _buildEarningsCard()),

                  // Online / Offline toggle
                  SliverToBoxAdapter(child: _buildOnlineToggle()),

                  // Incoming ride requests
                  if (_isOnline)
                    SliverToBoxAdapter(child: _buildRequestsSection()),

                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Active ride return banner
  // ------------------------------------------------------------------
  Widget _buildActiveRideBanner(RideRequest ride) {
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).pushNamed(
          '/rides/driver/active',
          arguments: {
            'rideId': ride.id,
            'pickupAddress': ride.pickupAddress,
            'destinationAddress': ride.destinationAddress,
          },
        );
        if (mounted && _driverId != null) unawaited(_checkActiveRide(_driverId!));
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF22C55E), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_car,
                color: Color(0xFF22C55E),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ride.rideStatus == RideStatus.ridePaused
                        ? 'Paused Ride — Tap to resume'
                        : 'Active Ride — Tap to return',
                    style: const TextStyle(
                      color: Color(0xFF22C55E),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ride.rideStatus.toDisplayString(),
                    style: TextStyle(color: Theme.of(context).colorScheme.outlineVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF22C55E), size: 22),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Earnings card
  // ------------------------------------------------------------------
  Widget _buildEarningsCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Today's Earnings",
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'J\$${_todayEarnings.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$_todayRidesCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Rides Today',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Online / Offline toggle
  // ------------------------------------------------------------------
  Widget _buildOnlineToggle() {
    if (!_canDoRides) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.lock_rounded, color: Colors.orange, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ride Sharing Disabled',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Enable Ride Sharing in Active Services on your dashboard to go online.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GestureDetector(
        onTap: _isTogglingMode ? null : _toggleOnline,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: _isOnline ? const Color(0xFF166534) : const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isOnline
                  ? const Color(0xFF22C55E)
                  : Colors.white.withValues(alpha: 0.12),
              width: 1.5,
            ),
          ),
          child: _isTogglingMode
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Color(0xFF22C55E),
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, __) => Opacity(
                        opacity: _isOnline ? _pulseAnim.value : 1.0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _isOnline
                                ? const Color(0xFF22C55E)
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isOnline ? 'You Are Online' : 'Go Online',
                      style: TextStyle(
                        color: _isOnline ? const Color(0xFF22C55E) : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!_isOnline) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.power_settings_new,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Incoming requests section
  // ------------------------------------------------------------------
  Widget _buildRequestsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_pendingRequests.isNotEmpty)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                _pendingRequests.isEmpty
                    ? 'Waiting for Ride Requests…'
                    : 'Incoming Rides (${_pendingRequests.length})',
                style: TextStyle(
                  color: _pendingRequests.isEmpty ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_pendingRequests.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 36),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.directions_car_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant, size: 44),
                  const SizedBox(height: 10),
                  Text(
                    'No ride requests nearby',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'New requests will appear here',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            ...(_pendingRequests.map((offer) => _buildRequestCard(offer))),
        ],
      ),
    );
  }

  Widget _buildRequestCard(DriverRideOffer offer) {
    final request = offer.request;
    final ride = offer.ride;
    final isProcessing = _processingIds.contains(request.id);
    final secsLeft = request.secondsUntilExpiry;
    final isUrgent = secsLeft <= 15;
    final urgentColor =
        isUrgent ? const Color(0xFFEF4444) : const Color(0xFF22C55E);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: urgentColor.withValues(alpha: isUrgent ? 0.6 : 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'New Ride Request',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: urgentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 13, color: urgentColor),
                      const SizedBox(width: 4),
                      Text(
                        '${secsLeft}s',
                        style: TextStyle(
                          color: urgentColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (ride == null)
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.onSurfaceVariant, strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text('Loading ride details…',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                ],
              )
            else ...[
              _AddressRow(isPickup: true, address: ride.pickupAddress),
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
                child: Column(
                  children: List.generate(
                    3,
                    (_) => Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurfaceVariant, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
              _AddressRow(isPickup: false, address: ride.destinationAddress),

              const SizedBox(height: 10),

              Row(
                children: [
                  _StatChip(
                    icon: Icons.straighten_outlined,
                    value: ride.distanceKm != null
                        ? '${(ride.distanceKm! / 1.60934).toStringAsFixed(1)} mi'
                        : '—',
                  ),
                  const SizedBox(width: 12),
                  _StatChip(
                    icon: Icons.access_time_outlined,
                    value: ride.estimatedDurationMinutes != null
                        ? '${ride.estimatedDurationMinutes} min'
                        : '—',
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        ride.driverEarning != null
                            ? 'J\$${ride.driverEarning!.toStringAsFixed(0)}'
                            : ride.estimatedFare != null
                                ? 'J\$${(ride.estimatedFare! * 0.80).toStringAsFixed(0)}'
                                : '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'you earn',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: isProcessing ? null : () => _handleDecline(offer),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                        foregroundColor: const Color(0xFFEF4444),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Decline',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: isProcessing ? null : () => _handleAccept(offer),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            const Color(0xFF22C55E).withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Text('Accept',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Address row
// ---------------------------------------------------------------------------

class _AddressRow extends StatelessWidget {
  final bool isPickup;
  final String address;

  const _AddressRow({required this.isPickup, required this.address});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: isPickup
                ? const Color(0xFF2563EB).withValues(alpha: 0.15)
                : const Color(0xFFEF4444).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isPickup ? Icons.circle : Icons.location_pin,
            color: isPickup
                ? const Color(0xFF2563EB)
                : const Color(0xFFEF4444),
            size: isPickup ? 9 : 14,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stat chip
// ---------------------------------------------------------------------------

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;

  const _StatChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 14),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(color: Theme.of(context).colorScheme.outlineVariant, fontSize: 12)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ride request pop-up bottom sheet
// ---------------------------------------------------------------------------

class _RideRequestPopup extends StatefulWidget {
  final DriverRideOffer offer;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _RideRequestPopup({
    required this.offer,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<_RideRequestPopup> createState() => _RideRequestPopupState();
}

class _RideRequestPopupState extends State<_RideRequestPopup> {
  late Timer _timer;
  int _secsLeft = 0;

  @override
  void initState() {
    super.initState();
    _secsLeft = widget.offer.request.secondsUntilExpiry.clamp(0, 999);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secsLeft = (_secsLeft - 1).clamp(0, 999));
      if (_secsLeft <= 0) {
        _timer.cancel();
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.offer.ride;
    final isUrgent = _secsLeft <= 15;
    final urgentColor = isUrgent ? const Color(0xFFEF4444) : const Color(0xFF22C55E);

    final earning = ride?.driverEarning != null
        ? 'J\$${ride!.driverEarning!.toStringAsFixed(0)}'
        : ride?.estimatedFare != null
            ? 'J\$${(ride!.estimatedFare! * 0.80).toStringAsFixed(0)}'
            : '—';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'New Ride Request',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: urgentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: urgentColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 14, color: urgentColor),
                    const SizedBox(width: 5),
                    Text(
                      '${_secsLeft}s',
                      style: TextStyle(
                        color: urgentColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          if (ride == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: CircularProgressIndicator(color: Color(0xFF22C55E)),
            )
          else ...[
            // Earnings highlight
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF166534), Color(0xFF15803D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.attach_money, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        earning,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'You earn',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (ride.distanceKm != null)
                        Text(
                          '${(ride.distanceKm! / 1.60934).toStringAsFixed(1)} mi',
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      if (ride.estimatedDurationMinutes != null)
                        Text(
                          '${ride.estimatedDurationMinutes} min',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Route
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _AddressRow(isPickup: true, address: ride.pickupAddress),
                  Padding(
                    padding: const EdgeInsets.only(left: 10, top: 3, bottom: 3),
                    child: Column(
                      children: List.generate(3, (_) => Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        width: 3, height: 3,
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurfaceVariant, shape: BoxShape.circle),
                      )),
                    ),
                  ),
                  _AddressRow(isPickup: false, address: ride.destinationAddress),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: widget.onDecline,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                      foregroundColor: const Color(0xFFEF4444),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: widget.onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Accept Ride', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
