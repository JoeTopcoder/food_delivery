import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/modules/rides/models/index.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';
import 'package:food_driver/modules/rides/services/ride_service.dart';

const _kBlue = Color(0xFF2563EB);
const _kGreen = Color(0xFF22C55E);
const _kDark = Color(0xFF111827);
const _kRed = Color(0xFFEF4444);
const _kGrey = Color(0xFF6B7280);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SearchingDriverScreen extends ConsumerStatefulWidget {
  final String rideId;

  const SearchingDriverScreen({super.key, required this.rideId});

  @override
  ConsumerState<SearchingDriverScreen> createState() =>
      _SearchingDriverScreenState();
}

class _SearchingDriverScreenState extends ConsumerState<SearchingDriverScreen>
    with TickerProviderStateMixin {
  // Pulse animation for "searching" state
  late final AnimationController _pulse1;
  late final AnimationController _pulse2;
  late final AnimationController _pulse3;
  late final Animation<double> _anim1;
  late final Animation<double> _anim2;
  late final Animation<double> _anim3;

  bool _cancelling = false;
  String? _selectingRequestId;

  @override
  void initState() {
    super.initState();
    _pulse1 = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
    _pulse2 = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _pulse3 = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    Future.delayed(const Duration(milliseconds: 300), () { if (mounted) _pulse2.repeat(reverse: true); });
    Future.delayed(const Duration(milliseconds: 600), () { if (mounted) _pulse3.repeat(reverse: true); });
    _anim1 = CurvedAnimation(parent: _pulse1, curve: Curves.easeInOut);
    _anim2 = CurvedAnimation(parent: _pulse2, curve: Curves.easeInOut);
    _anim3 = CurvedAnimation(parent: _pulse3, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulse1.dispose();
    _pulse2.dispose();
    _pulse3.dispose();
    super.dispose();
  }

  void _handleRideUpdate(RideRequest ride) {
    if (!mounted) return;
    if (ride.rideStatus == RideStatus.driverAssigned ||
        ride.rideStatus == RideStatus.driverArriving) {
      Navigator.pushReplacementNamed(context, '/rides/active', arguments: widget.rideId);
    } else if (ride.rideStatus == RideStatus.cancelled ||
        ride.rideStatus == RideStatus.failed) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride was not fulfilled. Please try again.')),
      );
    }
  }

  Future<void> _selectDriver(String driverRequestId) async {
    if (_selectingRequestId != null) return;
    setState(() => _selectingRequestId = driverRequestId);
    try {
      await ref.read(rideServiceProvider).selectDriver(
        rideId: widget.rideId,
        driverRequestId: driverRequestId,
      );
      // Navigation will happen via the rideStatusStreamProvider listener
    } catch (e) {
      if (mounted) {
        setState(() => _selectingRequestId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not confirm driver: $e')),
        );
      }
    }
  }

  Future<void> _cancelRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Ride?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to cancel this ride request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Searching')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Ride', style: TextStyle(color: _kRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await ref.read(rideServiceProvider).updateRideStatus(
        rideId: widget.rideId,
        newStatus: 'cancelled',
      );
      if (mounted) Navigator.pop(context);
    } on RideAuthException {
      if (!mounted) return;
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired — please log in again.')),
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/signin', (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel ride: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for status changes to auto-navigate
    ref.listen<AsyncValue<RideRequest>>(
      rideStatusStreamProvider(widget.rideId),
      (_, next) => next.whenData(_handleRideUpdate),
    );

    // Watch ride for PIN — always available regardless of offers stream
    final rideAsync = ref.watch(rideStatusStreamProvider(widget.rideId));
    final ridePin = rideAsync.valueOrNull?.ridePin;

    // Use valueOrNull so PIN + status header show even while offers stream loads
    final offersAsync = ref.watch(rideDriverOffersProvider(widget.rideId));
    final offers = offersAsync.valueOrNull ?? [];
    final pending = offers.where((o) => o['status'] == 'pending').length;
    final offeredList = offers.where((o) => o['status'] == 'offered').toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please wait or tap "Cancel Ride" to go back.')),
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: SafeArea(
          child: Column(
            children: [
              // ── App bar ────────────────────────────────────────────────
              _TopBar(onCancel: _cancelling ? null : _cancelRide),

              // ── Status header (always visible) ─────────────────────────
              _StatusHeader(
                pendingCount: pending,
                offerCount: offeredList.length,
              ),

              // ── PIN card (always visible once ride data arrives) ────────
              if (ridePin != null && ridePin.isNotEmpty)
                _PinCard(pin: ridePin),

              // ── Driver list or searching animation ─────────────────────
              Expanded(
                child: offeredList.isEmpty
                    ? _SearchingState(anim1: _anim1, anim2: _anim2, anim3: _anim3)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: offeredList.length,
                        itemBuilder: (ctx, i) {
                          final offer = offeredList[i];
                          final reqId = offer['id'] as String;
                          return _DriverOfferCard(
                            offer: offer,
                            isSelecting: _selectingRequestId == reqId,
                            anySelecting: _selectingRequestId != null,
                            onSelect: () => _selectDriver(reqId),
                          );
                        },
                      ),
              ),

              // ── Cancel button ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _cancelling
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _kRed))
                    : SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _cancelRide,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _kRed, width: 1.5),
                            foregroundColor: _kRed,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Cancel Ride', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
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
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final VoidCallback? onCancel;
  const _TopBar({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.directions_car, color: _kBlue, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose Your Driver', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kDark)),
                Text('Select the driver you want', style: TextStyle(fontSize: 12, color: _kGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status header
// ---------------------------------------------------------------------------

class _StatusHeader extends StatelessWidget {
  final int pendingCount;
  final int offerCount;

  const _StatusHeader({required this.pendingCount, required this.offerCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatusChip(
                icon: Icons.remove_red_eye_outlined,
                label: '$pendingCount viewing',
                color: _kGrey,
              ),
              const SizedBox(width: 12),
              if (offerCount > 0)
                _StatusChip(
                  icon: Icons.local_taxi,
                  label: '$offerCount offer${offerCount == 1 ? '' : 's'}',
                  color: _kGreen,
                ),
              if (offerCount == 0)
                _StatusChip(
                  icon: Icons.hourglass_top_outlined,
                  label: 'Waiting for offers',
                  color: Colors.orange,
                ),
            ],
          ),
          if (offerCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app, color: _kGreen, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Tap a driver below to confirm your ride',
                    style: TextStyle(fontSize: 13, color: _kGreen.withValues(alpha: 0.85), fontWeight: FontWeight.w500),
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

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PIN card
// ---------------------------------------------------------------------------

class _PinCard extends StatelessWidget {
  final String pin;
  const _PinCard({required this.pin});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E40AF), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, color: Colors.white70, size: 14),
                SizedBox(width: 6),
                Text(
                  'YOUR RIDE PIN',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              pin,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.bold,
                letterSpacing: 12,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Share this PIN with your driver to start the ride',
              style: TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Searching animation (when no offers yet)
// ---------------------------------------------------------------------------

class _SearchingState extends StatelessWidget {
  final Animation<double> anim1;
  final Animation<double> anim2;
  final Animation<double> anim3;

  const _SearchingState({required this.anim1, required this.anim2, required this.anim3});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _PulseCircle(animation: anim3, maxRadius: 100, color: _kBlue),
                _PulseCircle(animation: anim2, maxRadius: 72, color: _kBlue),
                _PulseCircle(animation: anim1, maxRadius: 48, color: _kBlue),
                Container(
                  width: 60, height: 60,
                  decoration: const BoxDecoration(color: _kBlue, shape: BoxShape.circle),
                  child: const Icon(Icons.directions_car, color: Colors.white, size: 30),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Searching for drivers…', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark)),
          const SizedBox(height: 6),
          const Text('Nearby drivers are being notified', style: TextStyle(fontSize: 13, color: _kGrey)),
        ],
      ),
    );
  }
}

class _PulseCircle extends StatelessWidget {
  final Animation<double> animation;
  final double maxRadius;
  final Color color;

  const _PulseCircle({required this.animation, required this.maxRadius, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final radius = maxRadius * animation.value;
        return Container(
          width: radius * 2, height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: (0.12 * (1.0 - animation.value * 0.6)).clamp(0.0, 1.0)),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Driver offer card
// ---------------------------------------------------------------------------

class _DriverOfferCard extends StatelessWidget {
  final Map<String, dynamic> offer;
  final bool isSelecting;
  final bool anySelecting;
  final VoidCallback onSelect;

  const _DriverOfferCard({
    required this.offer,
    required this.isSelecting,
    required this.anySelecting,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final name = offer['driver_name'] as String? ?? 'Driver';
    final rating = (offer['driver_rating'] as num?)?.toDouble() ?? 0.0;
    final vehicleMake = offer['vehicle_make'] as String? ?? '';
    final vehicleModel = offer['vehicle_model'] as String? ?? '';
    final vehicleColor = offer['vehicle_color'] as String? ?? '';
    final plate = offer['plate_number'] as String? ?? '';
    final vehicleLabel = [vehicleMake, vehicleModel].where((s) => s.isNotEmpty).join(' ');
    final vehicleDetail = [vehicleColor, plate].where((s) => s.isNotEmpty).join(' · ');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'D';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 3)),
        ],
        border: isSelecting ? Border.all(color: _kGreen, width: 2) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                // Avatar
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kDark)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 16),
                          const SizedBox(width: 3),
                          Text(
                            rating > 0 ? rating.toStringAsFixed(1) : 'New',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kDark),
                          ),
                          const SizedBox(width: 8),
                          Container(width: 4, height: 4, decoration: const BoxDecoration(color: _kGrey, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          const Icon(Icons.local_taxi, size: 14, color: _kGrey),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              vehicleLabel.isNotEmpty ? vehicleLabel : 'Vehicle',
                              style: const TextStyle(fontSize: 12, color: _kGrey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (vehicleDetail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(vehicleDetail, style: const TextStyle(fontSize: 12, color: _kGrey)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Select button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (anySelecting) ? null : onSelect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelecting ? _kGreen : _kBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: isSelecting ? _kGreen : _kBlue.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: isSelecting
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 18),
                          SizedBox(width: 8),
                          Text('Select This Driver', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
