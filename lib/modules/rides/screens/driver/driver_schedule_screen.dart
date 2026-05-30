import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:food_driver/modules/rides/models/index.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';

class DriverScheduleScreen extends ConsumerStatefulWidget {
  final String driverId;

  const DriverScheduleScreen({super.key, required this.driverId});

  @override
  ConsumerState<DriverScheduleScreen> createState() => _DriverScheduleScreenState();
}

class _DriverScheduleScreenState extends ConsumerState<DriverScheduleScreen> {
  final Set<String> _cancellingIds = {};

  @override
  Widget build(BuildContext context) {
    final ridesAsync = ref.watch(driverScheduledRidesStreamProvider(widget.driverId));

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
            'My Schedule',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: ridesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E))),
          error: (e, _) => Center(
            child: Text('Error: $e', style: const TextStyle(color: Colors.white70)),
          ),
          data: (rides) {
            if (rides.isEmpty) return _buildEmptyState();
            return _buildList(rides);
          },
        ),
      ),
    );
  }

  // ── Empty state ─────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: const Icon(Icons.calendar_today_outlined, color: Colors.white38, size: 36),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Scheduled Rides',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Scheduled ride requests will appear here\nafter you accept them.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ── Ride list grouped by date ────────────────────────────────────────────────

  Widget _buildList(List<RideRequest> rides) {
    // Group by calendar date
    final groups = <String, List<RideRequest>>{};
    for (final ride in rides) {
      final label = _dayLabel(ride.scheduledFor!);
      groups.putIfAbsent(label, () => []).add(ride);
    }

    return RefreshIndicator(
      color: const Color(0xFF22C55E),
      backgroundColor: const Color(0xFF1E1E1E),
      onRefresh: () async => ref.invalidate(driverScheduledRidesStreamProvider(widget.driverId)),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Header summary
          _buildSummaryBanner(rides.length),
          const SizedBox(height: 20),
          for (final entry in groups.entries) ...[
            _buildDateHeader(entry.key),
            const SizedBox(height: 10),
            for (final ride in entry.value) ...[
              _buildRideCard(ride),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildSummaryBanner(int count) {
    return Container(
      padding: const EdgeInsets.all(18),
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
          const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count Scheduled ${count == 1 ? 'Ride' : 'Rides'}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Sorted by pickup time',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader(String label) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // ── Ride card ────────────────────────────────────────────────────────────────

  Widget _buildRideCard(RideRequest ride) {
    final sf = ride.scheduledFor!.toLocal();
    final timeStr = DateFormat('h:mm a').format(sf);
    final isSoon = sf.difference(DateTime.now()).inHours < 2;
    final isCancelling = _cancellingIds.contains(ride.id);

    final earning = ride.driverEarning != null
        ? 'J\$${ride.driverEarning!.toStringAsFixed(0)}'
        : ride.estimatedFare != null
            ? 'J\$${(ride.estimatedFare! * 0.80).toStringAsFixed(0)}'
            : '—';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSoon
              ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.1),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Time + badge row ──────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time, color: Color(0xFF60A5FA), size: 14),
                      const SizedBox(width: 5),
                      Text(
                        timeStr,
                        style: const TextStyle(
                            color: Color(0xFF60A5FA),
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (ride.isAirportPickup || ride.isAirportDropoff) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flight_rounded, color: Color(0xFF38BDF8), size: 13),
                        SizedBox(width: 4),
                        Text(
                          'Airport',
                          style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isSoon) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_active, color: Color(0xFFF59E0B), size: 13),
                        SizedBox(width: 4),
                        Text(
                          'Coming Soon',
                          style: TextStyle(
                              color: Color(0xFFF59E0B),
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  earning,
                  style: const TextStyle(
                      color: Color(0xFF22C55E),
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Route ────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
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
                          decoration: const BoxDecoration(
                              color: Colors.white38, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                  _AddressRow(isPickup: false, address: ride.destinationAddress),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Stats row ────────────────────────────────────────────────────
            Row(
              children: [
                if (ride.distanceKm != null) ...[
                  const Icon(Icons.straighten_outlined, color: Colors.white38, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${(ride.distanceKm! / 1.60934).toStringAsFixed(1)} mi',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(width: 14),
                ],
                if (ride.estimatedDurationMinutes != null) ...[
                  const Icon(Icons.timer_outlined, color: Colors.white38, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${ride.estimatedDurationMinutes} min',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
                const Spacer(),
                Text(
                  'you earn',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Cancel button ────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: isCancelling ? null : () => _confirmCancel(ride),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                  foregroundColor: const Color(0xFFEF4444),
                  disabledForegroundColor: const Color(0xFFEF4444).withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: isCancelling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Color(0xFFEF4444), strokeWidth: 2),
                      )
                    : const Icon(Icons.cancel_outlined, size: 18),
                label: Text(
                  isCancelling ? 'Cancelling…' : 'Cancel This Ride',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Cancel confirmation ──────────────────────────────────────────────────────

  Future<void> _confirmCancel(RideRequest ride) async {
    final sf = ride.scheduledFor!.toLocal();
    final timeStr = DateFormat('EEE, MMM d · h:mm a').format(sf);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancel Scheduled Ride?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to cancel the ride scheduled for $timeStr?\n\nThe customer will be notified and the ride will be reassigned.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep It', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel',
                style: TextStyle(
                    color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancellingIds.add(ride.id));
    try {
      await ref.read(rideServiceProvider).cancelDriverScheduledRide(
            rideId: ride.id,
            driverId: widget.driverId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scheduled ride cancelled'),
            backgroundColor: Color(0xFF1E1E1E),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to cancel — try again')),
        );
      }
    } finally {
      if (mounted) setState(() => _cancellingIds.remove(ride.id));
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _dayLabel(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final day = DateTime(local.year, local.month, local.day);

    if (day == today) return 'Today';
    if (day == tomorrow) return 'Tomorrow';
    return DateFormat('EEEE, MMM d').format(local);
  }
}

// ── Address row (shared style matching driver_mode_screen) ──────────────────

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
            color: isPickup ? const Color(0xFF2563EB) : const Color(0xFFEF4444),
            size: isPickup ? 9 : 14,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
