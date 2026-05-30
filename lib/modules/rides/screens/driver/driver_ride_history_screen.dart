import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:food_driver/modules/rides/models/index.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';

// ---------------------------------------------------------------------------
// Constants (dark theme — matches DriverModeScreen)
// ---------------------------------------------------------------------------

const _kBg = Color(0xFF121212);
const _kCard = Color(0xFF1E1E1E);
const _kGreen = Color(0xFF22C55E);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kGrey = Color(0xFF6B7280);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class DriverRideHistoryScreen extends ConsumerStatefulWidget {
  final String driverId;

  const DriverRideHistoryScreen({super.key, required this.driverId});

  @override
  ConsumerState<DriverRideHistoryScreen> createState() =>
      _DriverRideHistoryScreenState();
}

class _DriverRideHistoryScreenState
    extends ConsumerState<DriverRideHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Ride History',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _TabBar(controller: _tab),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _HistoryBody(driverId: widget.driverId, filter: _Filter.all),
          _HistoryBody(driverId: widget.driverId, filter: _Filter.completed),
          _HistoryBody(driverId: widget.driverId, filter: _Filter.cancelled),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter enum
// ---------------------------------------------------------------------------

enum _Filter { all, completed, cancelled }

// ---------------------------------------------------------------------------
// Tab bar
// ---------------------------------------------------------------------------

class _TabBar extends StatelessWidget {
  final TabController controller;

  const _TabBar({required this.controller});

  static const _labels = ['All', 'Completed', 'Cancelled'];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kCard,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final selected = controller.index == i;
          final color = i == 1 ? _kGreen : i == 2 ? _kRed : Colors.white;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < _labels.length - 1 ? 8 : 0),
              child: GestureDetector(
                onTap: () => controller.animateTo(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                      color: selected
                          ? color.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    _labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? color : _kGrey,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body (loads data + filters)
// ---------------------------------------------------------------------------

class _HistoryBody extends ConsumerWidget {
  final String driverId;
  final _Filter filter;

  const _HistoryBody({required this.driverId, required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(driverRideHistoryProvider(driverId));

    return async.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: _kGreen)),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: _kGrey),
              const SizedBox(height: 12),
              const Text(
                'Could not load ride history',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                err.toString(),
                style: const TextStyle(color: _kGrey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () =>
                    ref.invalidate(driverRideHistoryProvider(driverId)),
                child: const Text('Retry',
                    style: TextStyle(color: _kGreen)),
              ),
            ],
          ),
        ),
      ),
      data: (all) {
        final rides = switch (filter) {
          _Filter.completed =>
            all.where((r) => r.rideStatus == RideStatus.rideCompleted).toList(),
          _Filter.cancelled => all
              .where((r) =>
                  r.rideStatus == RideStatus.cancelled ||
                  r.rideStatus == RideStatus.failed)
              .toList(),
          _Filter.all => all,
        };
        return _RideList(rides: rides, filter: filter, allRides: all);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Ride list with summary header + date groups
// ---------------------------------------------------------------------------

class _RideList extends StatelessWidget {
  final List<RideRequest> rides;
  final _Filter filter;
  final List<RideRequest> allRides;

  const _RideList({
    required this.rides,
    required this.filter,
    required this.allRides,
  });

  String _groupLabel(DateTime dt) {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(dt.year, dt.month, dt.day);
    final diff = todayDate.difference(itemDate).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('MMMM d, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    // Summary always computed from full list (All tab)
    final completedRides =
        allRides.where((r) => r.rideStatus == RideStatus.rideCompleted).toList();
    final totalEarnings = completedRides.fold<double>(
        0.0, (sum, r) => sum + (r.driverEarning ?? r.finalFare ?? 0.0));

    if (rides.isEmpty) {
      return Column(
        children: [
          if (filter == _Filter.all)
            _SummaryCard(
              totalRides: completedRides.length,
              totalEarnings: totalEarnings,
            ),
          Expanded(child: _EmptyState(filter: filter)),
        ],
      );
    }

    // Build grouped list
    final groups = <String, List<RideRequest>>{};
    for (final ride in rides) {
      final key = _groupLabel(ride.requestedAt);
      groups.putIfAbsent(key, () => []).add(ride);
    }

    final rows = <Object>[];
    for (final entry in groups.entries) {
      rows.add(entry.key);
      rows.addAll(entry.value);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: rows.length + 1, // +1 for summary header
      itemBuilder: (context, i) {
        if (i == 0) {
          return _SummaryCard(
            totalRides: completedRides.length,
            totalEarnings: totalEarnings,
          );
        }
        final row = rows[i - 1];
        if (row is String) return _GroupHeader(label: row);
        return _RideTile(ride: row as RideRequest);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  final int totalRides;
  final double totalEarnings;

  const _SummaryCard({required this.totalRides, required this.totalEarnings});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                  'Total Earnings',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'J\$${totalEarnings.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
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
                '$totalRides',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Completed',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group header
// ---------------------------------------------------------------------------

class _GroupHeader extends StatelessWidget {
  final String label;

  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _kGrey,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ride tile
// ---------------------------------------------------------------------------

class _RideTile extends StatelessWidget {
  final RideRequest ride;

  const _RideTile({required this.ride});

  String _short(String address) {
    final parts = address.split(',');
    return parts.first.trim();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(ride.requestedAt);
    final earning = ride.driverEarning ?? ride.finalFare ?? ride.estimatedFare ?? 0.0;
    final earningStr = 'J\$${earning.toStringAsFixed(0)}';
    final from = _short(ride.pickupAddress);
    final to = _short(ride.destinationAddress);

    final (statusLabel, statusColor) = _statusInfo(ride.rideStatus);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.directions_car_rounded,
            color: statusColor,
            size: 22,
          ),
        ),
        title: Text(
          '$from → $to',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              Text(
                timeStr,
                style: const TextStyle(fontSize: 12, color: _kGrey),
              ),
              if (ride.distanceKm != null) ...[
                const Text('  ·  ', style: TextStyle(color: _kGrey, fontSize: 12)),
                Text(
                  '${ride.distanceKm!.toStringAsFixed(1)} km',
                  style: const TextStyle(fontSize: 12, color: _kGrey),
                ),
              ],
            ],
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              earningStr,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 5),
            _StatusChip(label: statusLabel, color: statusColor),
          ],
        ),
      ),
    );
  }

  static (String, Color) _statusInfo(RideStatus status) {
    switch (status) {
      case RideStatus.rideCompleted:
        return ('Completed', _kGreen);
      case RideStatus.cancelled:
        return ('Cancelled', _kRed);
      case RideStatus.failed:
        return ('Failed', _kRed);
      default:
        return (status.toDisplayString(), _kAmber);
    }
  }
}

// ---------------------------------------------------------------------------
// Status chip
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final _Filter filter;

  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      _Filter.completed => 'completed',
      _Filter.cancelled => 'cancelled',
      _Filter.all => 'past',
    };

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.directions_car_outlined, size: 64, color: _kGrey),
          const SizedBox(height: 16),
          Text(
            'No $label rides yet',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your $label rides will appear here.',
            style: const TextStyle(fontSize: 13, color: _kGrey),
          ),
        ],
      ),
    );
  }
}
