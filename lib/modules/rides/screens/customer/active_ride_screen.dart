import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:food_driver/modules/rides/models/index.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';
import 'package:food_driver/config/supabase_config.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kBlue = Color(0xFF2563EB);
const _kDark = Color(0xFF111827);
const _kRed = Color(0xFFEF4444);
const _kGreen = Color(0xFF22C55E);
const _kAmber = Color(0xFFF59E0B);

const _kDefaultPickup = LatLng(18.0060, -76.7964);
const _kDefaultDestination = LatLng(18.0144, -76.7814);
const _kMapCenter = LatLng(17.9970, -76.7936);

// Grace period before waiting fee starts (5 minutes)
const _kGracePeriodSeconds = 300;

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ActiveRideScreen extends ConsumerStatefulWidget {
  final String rideId;

  const ActiveRideScreen({super.key, required this.rideId});

  @override
  ConsumerState<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends ConsumerState<ActiveRideScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _driverInfo;
  String? _lastFetchedDriverId;
  int _mapRebuildKey = 0;

  // Timer used to refresh the waiting fee display every second
  Timer? _tickTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tickTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() => _now = DateTime.now());
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _mapRebuildKey++);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDriverInfo(String driverId) async {
    if (_lastFetchedDriverId == driverId) return;
    _lastFetchedDriverId = driverId;
    try {
      final result = await SupabaseConfig.client.rpc(
        'get_driver_info_for_ride',
        params: {'p_ride_id': widget.rideId},
      );
      if (!mounted || result == null) return;
      final info = Map<String, dynamic>.from(result as Map);
      setState(() {
        _driverInfo = info;
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Cancellation fee helpers
  // ---------------------------------------------------------------------------

  double _cancellationFee(RideRequest ride) {
    const chargeableStatuses = [
      RideStatus.driverAssigned,
      RideStatus.driverArriving,
      RideStatus.driverArrived,
      RideStatus.rideStarted,
    ];
    if (!chargeableStatuses.contains(ride.rideStatus)) return 0.0;

    final baseFee = (ride.estimatedFare ?? 0) * 0.5;

    double waitingExtra = 0.0;
    if (ride.waitingStartedAt != null) {
      // Once the ride is active (driver resumed or ride started), cap the
      // waiting fee at the last started_at timestamp so it stops growing.
      // During driverArrived the fee is still live so we use _now.
      final upperBound =
          ride.rideStatus == RideStatus.rideStarted && ride.startedAt != null
              ? ride.startedAt!
              : _now;
      final waitedMins =
          upperBound.difference(ride.waitingStartedAt!).inSeconds / 60.0;
      final rate = ride.waitingFeePerMin ?? 75.0;
      waitingExtra = waitedMins.clamp(0.0, double.infinity) * rate;
    }

    return baseFee + waitingExtra;
  }

  Future<void> _cancelRide() async {
    // Read freshest ride from the live stream
    final ride = ref.read(rideStatusStreamProvider(widget.rideId)).valueOrNull;

    // Guard: don't attempt cancel if ride is already in a terminal state
    if (ride != null && !ride.canBeCancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ride.rideStatus == RideStatus.cancelled
                ? 'This ride has already been cancelled.'
                : 'This ride cannot be cancelled.',
          ),
        ),
      );
      return;
    }

    final fee = ride != null ? _cancellationFee(ride) : 0.0;
    final hasFee = fee > 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancel Ride?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!hasFee)
              const Text('Are you sure you want to cancel this ride?')
            else ...[
              const Text(
                'Your driver has already been dispatched.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kRed.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kRed.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cancellation fee',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'J\$${fee.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _kRed,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ride?.waitingStartedAt != null
                          ? 'Driver earning + accumulated waiting fee'
                          : 'This goes directly to your driver',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Ride'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _kRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(hasFee
                ? 'Cancel (J\$${fee.toStringAsFixed(0)} fee)'
                : 'Cancel Ride'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(rideServiceProvider).updateRideStatus(
            rideId: widget.rideId,
            newStatus: 'cancelled',
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cancelling ride: $e')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Waiting timer helpers
  // ---------------------------------------------------------------------------

  /// Grace period remaining in seconds (0 once expired).
  int _graceRemaining(RideRequest ride) {
    if (ride.rideStatus != RideStatus.driverArrived) return 0;
    if (ride.waitingStartedAt != null) return 0;
    final arrivedAt = ride.driverArrivedAt ?? _now;
    final elapsed = _now.difference(arrivedAt).inSeconds;
    final remaining = _kGracePeriodSeconds - elapsed;
    return remaining.clamp(0, _kGracePeriodSeconds);
  }

  String _formatMmSs(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double _currentWaitingFee(RideRequest ride) {
    if (ride.waitingStartedAt == null) return 0.0;
    // Cap at the moment the ride started so the fee freezes once in progress.
    final upperBound =
        (ride.rideStatus == RideStatus.rideStarted ||
                ride.rideStatus == RideStatus.rideCompleted) &&
                ride.startedAt != null
            ? ride.startedAt!
            : _now;
    final mins = upperBound.difference(ride.waitingStartedAt!).inSeconds / 60.0;
    return (mins.clamp(0.0, double.infinity)) * (ride.waitingFeePerMin ?? 75.0);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final rideStreamAsync = ref.watch(rideStatusStreamProvider(widget.rideId));
    final locationAsync = ref.watch(rideLocationStreamProvider(widget.rideId));

    final ride = rideStreamAsync.valueOrNull;

    if (ride?.driverId != null) {
      _fetchDriverInfo(ride!.driverId!);
    }

    final driverLatLng = locationAsync.whenOrNull(
      data: (loc) => LatLng(loc.lat, loc.lng),
    );

    final pickupLatLng = ride != null
        ? LatLng(ride.pickupLat, ride.pickupLng)
        : _kDefaultPickup;
    final destLatLng = ride != null
        ? LatLng(ride.destinationLat, ride.destinationLng)
        : _kDefaultDestination;

    final statusLabel = _statusLabel(ride?.rideStatus);
    final isCompleted = ride?.rideStatus == RideStatus.rideCompleted;

    return Scaffold(
      body: Stack(
        children: [
          _ActiveMap(
            key: ValueKey(_mapRebuildKey),
            pickupLatLng: pickupLatLng,
            destLatLng: destLatLng,
            driverLatLng: driverLatLng,
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: _StatusPill(label: statusLabel),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _DriverCard(
              ride: ride,
              driverInfo: _driverInfo,
              isCompleted: isCompleted,
              graceRemaining: ride != null ? _graceRemaining(ride) : 0,
              waitingFee: ride != null ? _currentWaitingFee(ride) : 0,
              now: _now,
              formatMmSs: _formatMmSs,
              onCall: () {},
              onChat: () {},
              onShare: () {},
              onCancel: _cancelRide,
              onViewHistory: () => Navigator.pushReplacementNamed(
                context,
                '/rides/history',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(RideStatus? status) {
    switch (status) {
      case RideStatus.driverAssigned:
      case RideStatus.driverArriving:
        return 'Driver Arriving';
      case RideStatus.driverArrived:
        return 'Driver Has Arrived';
      case RideStatus.rideStarted:
        return 'Ride in Progress';
      case RideStatus.ridePaused:
        return 'Ride Paused';
      case RideStatus.rideCompleted:
        return 'Ride Completed';
      default:
        return 'Driver Arriving';
    }
  }
}

// ---------------------------------------------------------------------------
// Full-screen map
// ---------------------------------------------------------------------------

class _ActiveMap extends StatelessWidget {
  final LatLng pickupLatLng;
  final LatLng destLatLng;
  final LatLng? driverLatLng;

  const _ActiveMap({
    super.key,
    required this.pickupLatLng,
    required this.destLatLng,
    this.driverLatLng,
  });

  @override
  Widget build(BuildContext context) {
    final routePoints = [
      if (driverLatLng != null) driverLatLng!,
      pickupLatLng,
      LatLng(18.0075, -76.7950),
      LatLng(18.0095, -76.7910),
      LatLng(18.0120, -76.7860),
      destLatLng,
    ];

    return FlutterMap(
      options: const MapOptions(
        initialCenter: _kMapCenter,
        initialZoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.mealhub.food_driver',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: routePoints,
              color: _kBlue,
              strokeWidth: 4.0,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            if (driverLatLng != null)
              Marker(
                point: driverLatLng!,
                width: 44,
                height: 44,
                child: Container(
                  decoration: const BoxDecoration(
                    color: _kBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.directions_car_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            Marker(
              point: pickupLatLng,
              width: 36,
              height: 36,
              child: Container(
                decoration: BoxDecoration(
                  color: _kBlue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: _kBlue, width: 2),
                ),
                child: const Icon(Icons.circle, color: _kBlue, size: 10),
              ),
            ),
            Marker(
              point: destLatLng,
              width: 36,
              height: 44,
              child: const Icon(Icons.location_on, color: _kRed, size: 36),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Top status pill
// ---------------------------------------------------------------------------

class _StatusPill extends StatelessWidget {
  final String label;

  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_car_rounded,
                color: _kBlue, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _kDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom driver info card
// ---------------------------------------------------------------------------

class _DriverCard extends StatelessWidget {
  final RideRequest? ride;
  final Map<String, dynamic>? driverInfo;
  final bool isCompleted;
  final int graceRemaining;
  final double waitingFee;
  final DateTime now;
  final String Function(int) formatMmSs;
  final VoidCallback onCall;
  final VoidCallback onChat;
  final VoidCallback onShare;
  final VoidCallback onCancel;
  final VoidCallback onViewHistory;

  const _DriverCard({
    required this.ride,
    required this.driverInfo,
    required this.isCompleted,
    required this.graceRemaining,
    required this.waitingFee,
    required this.now,
    required this.formatMmSs,
    required this.onCall,
    required this.onChat,
    required this.onShare,
    required this.onCancel,
    required this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final driverName =
        driverInfo?['name'] as String? ?? 'Your Driver';
    final rating =
        (driverInfo?['rating'] as num?)?.toDouble();
    final vehicleType =
        driverInfo?['vehicle_type'] as String? ?? '';
    final vehicleMake =
        driverInfo?['vehicle_make'] as String? ?? '';
    final vehicleModel =
        driverInfo?['vehicle_model'] as String? ?? '';
    final vehicleColor =
        driverInfo?['vehicle_color'] as String? ?? '';
    final plate =
        driverInfo?['plate_number'] as String? ?? '';
    // e.g. "Sedan · Toyota Corolla"
    final vehicleLine = [
      vehicleType,
      [vehicleMake, vehicleModel].where((s) => s.isNotEmpty).join(' '),
    ].where((s) => s.isNotEmpty).join(' · ');
    final colorPlate =
        [vehicleColor, plate].where((s) => s.isNotEmpty).join(' • ');

    final initial =
        driverName.isNotEmpty ? driverName[0].toUpperCase() : 'D';

    final showPin = ride?.ridePin != null &&
        (ride!.rideStatus == RideStatus.driverArrived ||
            ride!.rideStatus == RideStatus.driverAssigned ||
            ride!.rideStatus == RideStatus.driverArriving);

    final isPaused = ride?.rideStatus == RideStatus.ridePaused;
    // Show live waiting banner when driver has arrived (grace + fee meter)
    final showWaiting = ride?.rideStatus == RideStatus.driverArrived;
    // Live pause charge banner — driver confirmed charging during a paused ride
    final pauseChargeActive = isPaused && ride?.waitingStartedAt != null;
    // Show a static "waiting fee was applied" note once ride is underway (post-resume)
    final waitingFeeApplied = !showWaiting &&
        ride?.waitingStartedAt != null &&
        ride?.rideStatus == RideStatus.rideStarted;

    // Accrued waiting fee capped at ride start time
    double displayedWaitingFee = waitingFee;
    final rideSnapshot = ride;
    if (waitingFeeApplied &&
        rideSnapshot != null &&
        rideSnapshot.startedAt != null &&
        rideSnapshot.waitingStartedAt != null) {
      final mins = rideSnapshot.startedAt!
              .difference(rideSnapshot.waitingStartedAt!)
              .inSeconds /
          60.0;
      displayedWaitingFee = mins.clamp(0.0, double.infinity) *
          (rideSnapshot.waitingFeePerMin ?? 75.0);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding:
          EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Ride paused banner ───────────────────────────────────────
          if (isPaused) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              margin: EdgeInsets.only(bottom: pauseChargeActive ? 8 : 12),
              decoration: BoxDecoration(
                color: _kAmber.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kAmber.withValues(alpha: 0.40)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.pause_circle_outline, color: _kAmber, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Driver has paused the ride',
                          style: TextStyle(
                            color: _kAmber,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (ride?.pauseReason != null)
                          Text(
                            ride!.pauseReason!,
                            style: const TextStyle(color: _kAmber, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Live pause charge banner ───────────────────────────────
            if (pauseChargeActive) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _kRed.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kRed.withValues(alpha: 0.30)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_money_rounded, color: _kRed, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Driver is charging a pause fee',
                            style: TextStyle(
                              color: _kRed,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'J\$${waitingFee.toStringAsFixed(0)}  •  J\$75/min',
                            style: const TextStyle(
                              color: _kRed,
                              fontSize: 15,
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
          ],

          // ── Live waiting fee banner (driver arrived, waiting for customer) ──
          if (showWaiting) ...[
            _WaitingBanner(
              graceRemaining: graceRemaining,
              waitingFee: waitingFee,
              waitingStarted: ride?.waitingStartedAt != null,
              formatMmSs: formatMmSs,
            ),
            const SizedBox(height: 12),
          ],

          // ── Waiting fee note (fee already accrued before ride started) ──
          if (waitingFeeApplied) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kRed.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: _kRed, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Waiting fee of J\$${displayedWaitingFee.toStringAsFixed(0)} added to your fare',
                      style: const TextStyle(
                        color: _kRed,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── PIN banner ───────────────────────────────────────────────
          if (showPin) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  vertical: 14, horizontal: 16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  const Text(
                    'Show this code to your driver',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: ride!.ridePin!.split('').map((digit) {
                      return Container(
                        width: 38,
                        height: 46,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color:
                              Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          digit,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Driver will enter this code to start the ride',
                    style: TextStyle(
                        color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],

          // ── Driver info row ──────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _kDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.star_rounded,
                            color: Colors.amber.shade600, size: 16),
                        const SizedBox(width: 3),
                        Text(
                          rating != null
                              ? rating.toStringAsFixed(1)
                              : 'New',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kDark,
                          ),
                        ),
                      ],
                    ),
                    if (vehicleLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        vehicleLine,
                        style: const TextStyle(
                            fontSize: 13,
                            color: _kDark,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                    if (colorPlate.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        colorPlate,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
              if (plate.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kDark,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.directions_car,
                          color: Colors.white54, size: 14),
                      const SizedBox(height: 3),
                      Text(
                        plate,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // ── Action buttons ───────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ActionButton(
                  icon: Icons.phone_rounded,
                  label: 'Call',
                  color: _kBlue,
                  onTap: onCall),
              _ActionButton(
                  icon: Icons.chat_bubble_rounded,
                  label: 'Chat',
                  color: _kBlue,
                  onTap: onChat),
              _ActionButton(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  color: _kBlue,
                  onTap: onShare),
              if (ride?.canBeCancelled != false)
                _ActionButton(
                    icon: Icons.close_rounded,
                    label: 'Cancel',
                    color: _kRed,
                    onTap: onCancel),
            ],
          ),

          const SizedBox(height: 16),

          // ── Ride details ─────────────────────────────────────────────
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Ride Details',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),

          _RouteDetailRow(
            icon: Icons.circle,
            iconColor: _kBlue,
            iconSize: 10,
            text: ride?.pickupAddress ?? 'Pickup location',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Container(
              width: 1.5,
              height: 14,
              color: Colors.grey.shade300,
            ),
          ),
          _RouteDetailRow(
            icon: Icons.location_on,
            iconColor: _kRed,
            iconSize: 18,
            text: ride?.destinationAddress ?? 'Destination',
          ),

          // ── Completed banner ─────────────────────────────────────────
          if (isCompleted) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _kGreen.withValues(alpha: 0.30)),
              ),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: _kGreen, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Ride Completed!',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _kGreen,
                        ),
                      ),
                    ],
                  ),
                  if (ride?.finalFare != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'J\$${ride!.finalFare!.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: _kDark,
                      ),
                    ),
                    Text(
                      'Total charged',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onViewHistory,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kGreen,
                        side: const BorderSide(color: _kGreen),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('View History'),
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

// ---------------------------------------------------------------------------
// Waiting fee banner (shown to customer when driver has arrived)
// ---------------------------------------------------------------------------

class _WaitingBanner extends StatelessWidget {
  final int graceRemaining;
  final double waitingFee;
  final bool waitingStarted;
  final String Function(int) formatMmSs;

  const _WaitingBanner({
    required this.graceRemaining,
    required this.waitingFee,
    required this.waitingStarted,
    required this.formatMmSs,
  });

  @override
  Widget build(BuildContext context) {
    if (!waitingStarted) {
      // Grace period countdown
      if (graceRemaining > 0) {
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: _kGreen.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined,
                  color: _kGreen, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Free wait: ${formatMmSs(graceRemaining)} remaining',
                  style: const TextStyle(
                    color: _kGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        // Grace expired, waiting for driver to confirm
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _kAmber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: _kAmber.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.timer_off_outlined,
                  color: _kAmber, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Free wait ended — waiting fee may apply',
                  style: TextStyle(
                    color: _kAmber,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } else {
      // Waiting fee actively running
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _kRed.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kRed.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.attach_money,
                color: _kRed, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Waiting fee active',
                    style: TextStyle(
                      color: _kRed,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'J\$${waitingFee.toStringAsFixed(0)}  (J\$75/min)',
                    style: const TextStyle(
                      color: _kRed,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Reusable widgets
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color == _kRed ? _kRed : _kDark,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteDetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final double iconSize;
  final String text;

  const _RouteDetailRow({
    required this.icon,
    required this.iconColor,
    required this.iconSize,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: _kDark,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
