import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:food_driver/modules/rides/models/index.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kBlue = Color(0xFF2563EB);
const _kDark = Color(0xFF111827);
const _kGreen = Color(0xFF22C55E);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class RideHistoryScreen extends ConsumerStatefulWidget {
  final String customerId;

  const RideHistoryScreen({super.key, required this.customerId});

  @override
  ConsumerState<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends ConsumerState<RideHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Ride History',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _HistoryTabBar(controller: _tab),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _ActiveRideTab(customerId: widget.customerId),
          _HistoryTabBody(
            customerId: widget.customerId,
            filter: _HistoryFilter.completed,
          ),
          _HistoryTabBody(
            customerId: widget.customerId,
            filter: _HistoryFilter.cancelled,
          ),
          _HistoryTabBody(
            customerId: widget.customerId,
            filter: _HistoryFilter.all,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter enum
// ---------------------------------------------------------------------------

enum _HistoryFilter { completed, cancelled, all }

// ---------------------------------------------------------------------------
// Active ride tab
// ---------------------------------------------------------------------------

class _ActiveRideTab extends ConsumerWidget {
  final String customerId;

  const _ActiveRideTab({required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeCustomerRideStreamProvider(customerId));

    return activeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'Could not load active ride',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                e.toString(),
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      data: (ride) {
        if (ride == null) {
          return const _EmptyActiveState();
        }
        return _ActiveRideCard(ride: ride);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Active ride card
// ---------------------------------------------------------------------------

class _ActiveRideCard extends ConsumerStatefulWidget {
  final RideRequest ride;

  const _ActiveRideCard({required this.ride});

  @override
  ConsumerState<_ActiveRideCard> createState() => _ActiveRideCardState();
}

class _ActiveRideCardState extends ConsumerState<_ActiveRideCard> {
  String? _driverName;
  String? _vehicleLine;
  String? _plate;
  String? _lastDriverId;

  @override
  void initState() {
    super.initState();
    if (widget.ride.driverId != null) {
      _fetchDriver(widget.ride.driverId!);
    }
  }

  @override
  void didUpdateWidget(_ActiveRideCard old) {
    super.didUpdateWidget(old);
    if (widget.ride.driverId != null && widget.ride.driverId != _lastDriverId) {
      _fetchDriver(widget.ride.driverId!);
    }
  }

  Future<void> _fetchDriver(String driverId) async {
    if (driverId == _lastDriverId) return;
    _lastDriverId = driverId;
    try {
      final result = await Supabase.instance.client.rpc(
        'get_driver_info_for_ride',
        params: {'p_ride_id': widget.ride.id},
      );
      if (!mounted || result == null) return;
      final info = Map<String, dynamic>.from(result as Map);

      final name = info['name'] as String? ?? 'Your Driver';
      final type = info['vehicle_type'] as String? ?? '';
      final make = info['vehicle_make'] as String? ?? '';
      final model = info['vehicle_model'] as String? ?? '';
      final color = info['vehicle_color'] as String? ?? '';
      final plate = info['plate_number'] as String? ?? '';
      // e.g. "Sedan · Toyota Corolla — White · ABC 1234"
      final vehicle = [
        [type, [make, model].where((s) => s.isNotEmpty).join(' ')]
            .where((s) => s.isNotEmpty).join(' · '),
        [color, plate].where((s) => s.isNotEmpty).join(' · '),
      ].where((s) => s.isNotEmpty).join(' — ');

      setState(() {
        _driverName = name;
        _plate = plate.isNotEmpty ? plate : null;
        _vehicleLine = vehicle.isNotEmpty ? vehicle : null;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final fare = ride.estimatedFare ?? 0.0;
    final fareStr = 'J\$${fare.toStringAsFixed(0)}';
    final (statusLabel, statusColor) = _statusInfo(ride.rideStatus);
    final hasDriver = ride.driverId != null && _driverName != null;
    final initial = (_driverName ?? 'D')[0].toUpperCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live indicator header
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: _kGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Live Ride',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _kGreen,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Main ride card
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBlue.withValues(alpha: 0.25), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status bar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.directions_car_rounded, color: statusColor, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _kBlue,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Driver row (shown when a driver is assigned)
                      if (hasDriver) ...[
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  initial,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _driverName!,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  if (_vehicleLine != null && _vehicleLine!.isNotEmpty)
                                    Text(
                                      _vehicleLine!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (_plate != null)
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
                                      _plate!,
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
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                      ],

                      // Route
                      _RouteRow(
                        icon: Icons.circle,
                        iconColor: _kBlue,
                        iconSize: 10,
                        label: 'From',
                        address: ride.pickupAddress,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Container(
                          width: 1.5,
                          height: 18,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      _RouteRow(
                        icon: Icons.location_on,
                        iconColor: _kRed,
                        iconSize: 18,
                        label: 'To',
                        address: ride.destinationAddress,
                      ),

                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 14),

                      // Fare row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Estimated Fare',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            fareStr,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
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

          const SizedBox(height: 20),

          // Track Ride button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(
                context,
                '/rides/active',
                arguments: ride.id,
              ),
              icon: const Icon(Icons.near_me_rounded),
              label: const Text(
                'Track Ride',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static (String, Color) _statusInfo(RideStatus status) {
    switch (status) {
      case RideStatus.driverAssigned:
      case RideStatus.driverArriving:
        return ('Driver Arriving', _kAmber);
      case RideStatus.driverArrived:
        return ('Driver Has Arrived', _kGreen);
      case RideStatus.rideStarted:
        return ('Ride in Progress', _kBlue);
      case RideStatus.ridePaused:
        return ('Ride Paused', _kAmber);
      case RideStatus.searchingDriver:
        return ('Finding a Driver', _kAmber);
      default:
        return ('Ride Requested', _kAmber);
    }
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final double iconSize;
  final String label;
  final String address;

  const _RouteRow({
    required this.icon,
    required this.iconColor,
    required this.iconSize,
    required this.label,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: iconColor, size: iconSize),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                address,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty active state
// ---------------------------------------------------------------------------

class _EmptyActiveState extends StatelessWidget {
  const _EmptyActiveState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No active ride',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your current ride will appear here.',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History tab body (Completed / Cancelled / All)
// ---------------------------------------------------------------------------

class _HistoryTabBody extends ConsumerWidget {
  final String customerId;
  final _HistoryFilter filter;

  const _HistoryTabBody({
    required this.customerId,
    required this.filter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(rideHistoryStreamProvider(customerId));

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'Could not load ride history',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                err.toString(),
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () =>
                    ref.invalidate(rideHistoryStreamProvider(customerId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (rides) {
        final filtered = switch (filter) {
          _HistoryFilter.completed =>
            rides.where((r) => r.rideStatus == RideStatus.rideCompleted).toList(),
          _HistoryFilter.cancelled => rides
              .where(
                (r) =>
                    r.rideStatus == RideStatus.cancelled ||
                    r.rideStatus == RideStatus.failed,
              )
              .toList(),
          _HistoryFilter.all => rides,
        };

        final tabIndex = filter.index + 1; // offset by 1 for the Active tab
        return _RideListByTab(rides: filtered, tabIndex: tabIndex);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Custom chip-style tab bar
// ---------------------------------------------------------------------------

class _HistoryTabBar extends StatelessWidget {
  final TabController controller;

  const _HistoryTabBar({required this.controller});

  static const _labels = ['Active', 'Completed', 'Cancelled', 'All'];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final selected = controller.index == i;
          final isActive = i == 0;
          return Padding(
            padding: EdgeInsets.only(right: i < _labels.length - 1 ? 8 : 0),
            child: GestureDetector(
              onTap: () => controller.animateTo(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? (isActive ? _kBlue : _kDark)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isActive) ...[
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : _kGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    Text(
                      _labels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
// Per-tab ride list (grouped by date)
// ---------------------------------------------------------------------------

class _RideListByTab extends StatelessWidget {
  final List<RideRequest> rides;
  final int tabIndex;

  const _RideListByTab({required this.rides, required this.tabIndex});

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
    if (rides.isEmpty) return _EmptyState(tabIndex: tabIndex);

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
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is String) return _GroupHeader(label: row);
        return _RideTile(ride: row as RideRequest);
      },
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
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  String _shortAddress(String address) {
    final parts = address.split(',');
    return parts.first.trim();
  }

  bool get _isActive =>
      ride.isActive &&
      ride.rideStatus != RideStatus.rideCompleted &&
      ride.rideStatus != RideStatus.cancelled &&
      ride.rideStatus != RideStatus.failed;

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(ride.requestedAt);
    final fare = ride.finalFare ?? ride.estimatedFare ?? 0.0;
    final fareStr = 'J\$${fare.toStringAsFixed(0)}';
    final fromStr = _shortAddress(ride.pickupAddress);
    final toStr = _shortAddress(ride.destinationAddress);

    final iconColor = _statusIconColor(ride.rideStatus, context);

    return GestureDetector(
      onTap: _isActive
          ? () => Navigator.pushNamed(
                context,
                '/rides/active',
                arguments: ride.id,
              )
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: _isActive
              ? Border.all(color: _kBlue.withValues(alpha: 0.4), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.directions_car_rounded,
              color: iconColor,
              size: 24,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  '$fromStr → $toStr',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isActive)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _kBlue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              timeStr,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fareStr,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 5),
              _StatusChip(status: ride.rideStatus),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusIconColor(RideStatus status, BuildContext context) {
    switch (status) {
      case RideStatus.rideCompleted:
        return _kBlue;
      case RideStatus.cancelled:
      case RideStatus.failed:
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case RideStatus.rideStarted:
        return _kGreen;
      default:
        return _kAmber;
    }
  }
}

// ---------------------------------------------------------------------------
// Status chip
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  final RideStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _labelAndColor(status);
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

  static (String, Color) _labelAndColor(RideStatus status) {
    switch (status) {
      case RideStatus.rideCompleted:
        return ('Completed', _kGreen);
      case RideStatus.cancelled:
        return ('Cancelled', _kRed);
      case RideStatus.failed:
        return ('Failed', _kRed);
      case RideStatus.rideStarted:
        return ('In Progress', _kBlue);
      case RideStatus.driverArrived:
        return ('Driver Here', _kAmber);
      case RideStatus.driverArriving:
        return ('On the Way', _kAmber);
      case RideStatus.driverAssigned:
        return ('Assigned', _kAmber);
      case RideStatus.searchingDriver:
        return ('Searching', _kAmber);
      case RideStatus.scheduled:
        return ('Scheduled', const Color(0xFF7C3AED));
      default:
        return ('Requested', _kAmber);
    }
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final int tabIndex;

  const _EmptyState({required this.tabIndex});

  @override
  Widget build(BuildContext context) {
    // tabIndex: 1=completed, 2=cancelled, 3=all (0=active handled separately)
    const labels = ['active', 'completed', 'cancelled', 'past'];
    final label = labels[tabIndex.clamp(0, 3)];

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No $label rides yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your $label rides will appear here.',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
