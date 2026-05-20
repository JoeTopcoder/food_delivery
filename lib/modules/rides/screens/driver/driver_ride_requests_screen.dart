import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:food_driver/modules/rides/models/index.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';

// ---------------------------------------------------------------------------
// Driver Ride History Screen — dark theme with filter tabs & earnings summary
// ---------------------------------------------------------------------------

enum _TripFilter { all, completed, cancelled }

class DriverRideRequestsScreen extends ConsumerStatefulWidget {
  final String driverId;

  const DriverRideRequestsScreen({super.key, required this.driverId});

  @override
  ConsumerState<DriverRideRequestsScreen> createState() =>
      _DriverRideRequestsScreenState();
}

class _DriverRideRequestsScreenState
    extends ConsumerState<DriverRideRequestsScreen> {
  _TripFilter _filter = _TripFilter.all;

  @override
  Widget build(BuildContext context) {
    final ridesAsync = ref.watch(driverRidesProvider(widget.driverId));

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Trip History',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ridesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF22C55E)),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Failed to load trips',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () =>
                      ref.invalidate(driverRidesProvider(widget.driverId)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (rides) => _buildContent(rides),
      ),
    );
  }

  Widget _buildContent(List<RideRequest> rides) {
    // Compute earnings summary from completed rides
    final completed = rides
        .where((r) => r.rideStatus == RideStatus.rideCompleted)
        .toList();
    final totalEarned = completed.fold<double>(
      0.0,
      (sum, r) => sum + (r.driverEarning ?? (r.finalFare ?? r.estimatedFare ?? 0) * 0.8),
    );

    // Today's rides
    final today = DateTime.now();
    final todayEarned = completed
        .where((r) =>
            r.completedAt != null &&
            r.completedAt!.year == today.year &&
            r.completedAt!.month == today.month &&
            r.completedAt!.day == today.day)
        .fold<double>(
          0.0,
          (sum, r) => sum + (r.driverEarning ?? (r.finalFare ?? r.estimatedFare ?? 0) * 0.8),
        );

    // Apply filter
    final filtered = rides.where((r) {
      switch (_filter) {
        case _TripFilter.completed:
          return r.rideStatus == RideStatus.rideCompleted;
        case _TripFilter.cancelled:
          return r.rideStatus == RideStatus.cancelled;
        case _TripFilter.all:
          return true;
      }
    }).toList();

    return Column(
      children: [
        // Earnings summary header
        _EarningsSummary(
          totalEarned: totalEarned,
          todayEarned: todayEarned,
          totalTrips: completed.length,
        ),

        // Filter tabs
        _FilterTabs(
          current: _filter,
          onChanged: (f) => setState(() => _filter = f),
        ),

        // Trip list
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _RideTripCard(ride: filtered[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final label = switch (_filter) {
      _TripFilter.completed => 'No completed trips',
      _TripFilter.cancelled => 'No cancelled trips',
      _TripFilter.all => 'No trips yet',
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_car_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant, size: 64),
          const SizedBox(height: 16),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Rides will appear here',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Earnings summary header
// ---------------------------------------------------------------------------

class _EarningsSummary extends StatelessWidget {
  final double totalEarned;
  final double todayEarned;
  final int totalTrips;

  const _EarningsSummary({
    required this.totalEarned,
    required this.todayEarned,
    required this.totalTrips,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
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
          Expanded(
            child: _StatBox(
              label: 'Today',
              value: 'J\$${todayEarned.toStringAsFixed(0)}',
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white24),
          Expanded(
            child: _StatBox(
              label: 'All Time',
              value: 'J\$${totalEarned.toStringAsFixed(0)}',
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white24),
          Expanded(
            child: _StatBox(
              label: 'Trips',
              value: '$totalTrips',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;

  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filter tabs
// ---------------------------------------------------------------------------

class _FilterTabs extends StatelessWidget {
  final _TripFilter current;
  final ValueChanged<_TripFilter> onChanged;

  const _FilterTabs({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          _Tab(
            label: 'All',
            selected: current == _TripFilter.all,
            onTap: () => onChanged(_TripFilter.all),
          ),
          const SizedBox(width: 8),
          _Tab(
            label: 'Completed',
            selected: current == _TripFilter.completed,
            onTap: () => onChanged(_TripFilter.completed),
          ),
          const SizedBox(width: 8),
          _Tab(
            label: 'Cancelled',
            selected: current == _TripFilter.cancelled,
            onTap: () => onChanged(_TripFilter.cancelled),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF22C55E) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF22C55E)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trip card
// ---------------------------------------------------------------------------

class _RideTripCard extends StatelessWidget {
  final RideRequest ride;

  const _RideTripCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    // Show driver earning preferentially; fall back to 80% of final/estimated fare
    final earning = ride.driverEarning ??
        ((ride.finalFare ?? ride.estimatedFare ?? 0) * 0.8);
    final dateLabel =
        DateFormat('MMM d, yyyy • h:mm a').format(ride.requestedAt);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pickup → Destination
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Route line indicator
              Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 28,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const Icon(
                    Icons.location_pin,
                    color: Color(0xFFEF4444),
                    size: 14,
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride.pickupAddress,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      ride.destinationAddress,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Earnings (green for completed, grey otherwise)
              Text(
                ride.rideStatus == RideStatus.rideCompleted
                    ? 'J\$${earning.toStringAsFixed(0)}'
                    : '—',
                style: TextStyle(
                  color: ride.rideStatus == RideStatus.rideCompleted
                      ? const Color(0xFF22C55E)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 10),

          // Bottom row: date + status chip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateLabel,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
              _StatusChip(status: ride.rideStatus),
            ],
          ),

          // Distance & duration if available
          if (ride.distanceKm != null || ride.estimatedDurationMinutes != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (ride.distanceKm != null) ...[
                    Icon(
                      Icons.straighten_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${ride.distanceKm!.toStringAsFixed(1)} km',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                  if (ride.distanceKm != null &&
                      ride.estimatedDurationMinutes != null)
                    const SizedBox(width: 16),
                  if (ride.estimatedDurationMinutes != null) ...[
                    Icon(
                      Icons.access_time_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${ride.estimatedDurationMinutes} min',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status chip
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  final RideStatus status;

  const _StatusChip({required this.status});

  Color _bgColor(BuildContext context) {
    return switch (status) {
      RideStatus.rideCompleted => const Color(0xFF166534),
      RideStatus.cancelled     => const Color(0xFF7F1D1D),
      RideStatus.failed        => const Color(0xFF7F1D1D),
      RideStatus.rideStarted   => const Color(0xFF1E40AF),
      RideStatus.ridePaused    => const Color(0xFF92400E),
      _                        => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  Color _textColor(BuildContext context) {
    return switch (status) {
      RideStatus.rideCompleted => const Color(0xFF4ADE80),
      RideStatus.cancelled     => const Color(0xFFF87171),
      RideStatus.failed        => const Color(0xFFF87171),
      RideStatus.rideStarted   => const Color(0xFF93C5FD),
      RideStatus.ridePaused    => const Color(0xFFFCD34D),
      _                        => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _bgColor(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toDisplayString(),
        style: TextStyle(
          color: _textColor(context),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
