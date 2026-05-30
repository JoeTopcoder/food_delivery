import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/config/app_constants.dart';
import 'package:food_driver/modules/rides/models/index.dart';
import 'package:food_driver/modules/rides/providers/ride_providers.dart';
import 'package:food_driver/providers/auth_provider.dart';
import 'package:food_driver/providers/feature_providers.dart';
import 'package:intl/intl.dart';

const _kBlue = Color(0xFF2563EB);
const _kGreen = Color(0xFF22C55E);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);

class RideHomeScreen extends ConsumerWidget {
  const RideHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final userId = authState.user?.id;
    final firstName = authState.user?.email?.split('@').first ?? 'there';

    // Rebuilds the banner whenever an admin changes app_config in real time.
    ref.watch(configVersionProvider);

    // True once the customer has at least one ride in history.
    final hasRides = userId != null &&
        (ref.watch(rideHistoryStreamProvider(userId)).valueOrNull?.isNotEmpty ??
            false);

    final hasActiveRide = userId != null &&
        ref.watch(activeCustomerRideStreamProvider(userId)).valueOrNull != null;

    final promoEnabled = AppConstants.ridePromoFirstRideEnabled;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E3A5F), Color(0xFF2563EB)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, $firstName 👋',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Where are you going today?',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            if (userId == null) return;
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => _RideNotificationSheet(userId: userId),
                            );
                          },
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.white.withValues(alpha: 0.2),
                                child: const Icon(
                                  Icons.notifications_outlined,
                                  color: Colors.white,
                                ),
                              ),
                              if (hasActiveRide)
                                Positioned(
                                  top: -2,
                                  right: -2,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: _kRed,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF1E3A5F),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () =>
                          Navigator.pushNamed(context, '/rides/booking'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: _kBlue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Where to?',
                                style: TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _kBlue,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Go',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Active Ride Banner ───────────────────────────────────────────
            if (userId != null) _ActiveRideBannerSliver(userId: userId),

            // ── Quick Actions ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _QuickActionCard(
                            icon: Icons.directions_car,
                            label: 'Book a Ride',
                            color: _kBlue,
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/rides/booking',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickActionCard(
                            icon: Icons.history,
                            label: 'Ride History',
                            color: const Color(0xFF7C3AED),
                            onTap: () {
                              final uid =
                                  ref.read(authNotifierProvider).user?.id ?? '';
                              Navigator.pushNamed(
                                context,
                                '/rides/history',
                                arguments: uid,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickActionCard(
                            icon: Icons.schedule,
                            label: 'Schedule',
                            color: const Color(0xFFF59E0B),
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/rides/booking',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Promo Banner ─────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: hasRides
                    ? _ReturningRiderBanner(
                        title: AppConstants.ridePromoReturningTitle,
                        subtitle: AppConstants.ridePromoReturningSubtitle,
                        cta: AppConstants.ridePromoReturningCta,
                      )
                    : promoEnabled
                        ? _FirstRideBanner(
                            title: AppConstants.ridePromoFirstRideTitle,
                            subtitle: AppConstants.ridePromoFirstRideSubtitle,
                            cta: AppConstants.ridePromoFirstRideCta,
                          )
                        : const SizedBox.shrink(),
              ),
            ),

            // ── Recent Rides ─────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Rides',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            _RecentRidesSliver(),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}

// ── Active Ride Banner Sliver ──────────────────────────────────────────────────

class _ActiveRideBannerSliver extends ConsumerWidget {
  final String userId;

  const _ActiveRideBannerSliver({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeCustomerRideStreamProvider(userId));

    return activeAsync.when(
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (ride) {
        if (ride == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
        return SliverToBoxAdapter(
          child: GestureDetector(
            onTap: () => Navigator.pushNamed(
              context,
              '/rides/active',
              arguments: ride.id,
            ),
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _kBlue.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.directions_car,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active Ride',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ride.rideStatus.toDisplayString(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios,
                            size: 12, color: Colors.white),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Quick Action Card ──────────────────────────────────────────────────────────

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent Rides Sliver ────────────────────────────────────────────────────────

class _RecentRidesSliver extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final userId = authState.user?.id;

    if (userId == null) {
      return const SliverToBoxAdapter(child: _EmptyRidesCard());
    }

    final historyAsync = ref.watch(rideHistoryStreamProvider(userId));

    return historyAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (_, __) => const SliverToBoxAdapter(child: _EmptyRidesCard()),
      data: (rides) {
        if (rides.isEmpty) {
          return const SliverToBoxAdapter(child: _EmptyRidesCard());
        }
        final recent = rides.take(4).toList();
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _RideTile(ride: recent[i]),
            ),
            childCount: recent.length,
          ),
        );
      },
    );
  }
}

class _EmptyRidesCard extends StatelessWidget {
  const _EmptyRidesCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(Icons.directions_car_outlined,
                size: 48, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              'No rides yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your ride history will appear here',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _RideTile extends StatelessWidget {
  final RideRequest ride;

  const _RideTile({required this.ride});

  bool get _isActive =>
      ride.rideStatus != RideStatus.rideCompleted &&
      ride.rideStatus != RideStatus.cancelled &&
      ride.rideStatus != RideStatus.failed;

  @override
  Widget build(BuildContext context) {
    final fare = ride.finalFare ?? ride.estimatedFare ?? 0.0;
    final (statusLabel, statusColor) = _statusInfo(ride.rideStatus);

    return GestureDetector(
      onTap: _isActive
          ? () => Navigator.pushNamed(
                context,
                '/rides/active',
                arguments: ride.id,
              )
          : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: _isActive
              ? Border.all(color: _kBlue.withValues(alpha: 0.35), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.directions_car, color: statusColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_short(ride.pickupAddress)} → ${_short(ride.destinationAddress)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM d, h:mm a').format(ride.requestedAt),
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'J\$${fare.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: statusColor,
                      fontWeight: FontWeight.w600,
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

  String _short(String addr) => addr.split(',').first.trim();

  static (String, Color) _statusInfo(RideStatus status) {
    switch (status) {
      case RideStatus.rideCompleted:
        return ('Completed', _kGreen);
      case RideStatus.cancelled:
      case RideStatus.failed:
        return ('Cancelled', _kRed);
      case RideStatus.rideStarted:
        return ('In Progress', _kBlue);
      case RideStatus.ridePaused:
        return ('Paused', _kAmber);
      case RideStatus.driverArrived:
        return ('Driver Here', _kAmber);
      case RideStatus.driverArriving:
      case RideStatus.driverAssigned:
        return ('Driver Coming', _kAmber);
      default:
        return ('Searching', _kAmber);
    }
  }
}

// ---------------------------------------------------------------------------
// Promo banners
// ---------------------------------------------------------------------------

class _FirstRideBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String cta;

  const _FirstRideBanner({
    required this.title,
    required this.subtitle,
    required this.cta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF065F46), Color(0xFF22C55E)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/rides/booking'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      cta,
                      style: const TextStyle(
                        color: _kGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.local_taxi, color: Colors.white, size: 64),
        ],
      ),
    );
  }
}

// ── Ride Notification Sheet ────────────────────────────────────────────────────

class _RideNotificationSheet extends ConsumerWidget {
  final String userId;
  const _RideNotificationSheet({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(rideHistoryStreamProvider(userId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2937) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.notifications_outlined, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Ride Notifications',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: historyAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(child: Text('Could not load notifications')),
                data: (rides) {
                  final events = _buildEvents(rides);
                  if (events.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_off_outlined,
                              size: 48,
                              color: Theme.of(context).colorScheme.outlineVariant),
                          const SizedBox(height: 12),
                          Text(
                            'No notifications yet',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                    itemBuilder: (_, i) => _NotificationTile(event: events[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_RideEvent> _buildEvents(List<RideRequest> rides) {
    final events = <_RideEvent>[];
    for (final ride in rides) {
      final route =
          '${ride.pickupAddress.split(',').first.trim()} → ${ride.destinationAddress.split(',').first.trim()}';

      if (ride.driverArrivedAt != null) {
        events.add(_RideEvent(
          icon: Icons.location_on_rounded,
          color: _kAmber,
          title: 'Driver arrived at pickup',
          body: route,
          time: ride.driverArrivedAt!,
        ));
      }
      if (ride.startedAt != null) {
        events.add(_RideEvent(
          icon: Icons.directions_car_rounded,
          color: _kBlue,
          title: 'Your ride started',
          body: route,
          time: ride.startedAt!,
        ));
      }
      if (ride.completedAt != null) {
        events.add(_RideEvent(
          icon: Icons.check_circle_outline_rounded,
          color: _kGreen,
          title: 'Ride completed',
          body: route,
          time: ride.completedAt!,
        ));
      }
      if (ride.rideStatus == RideStatus.cancelled) {
        events.add(_RideEvent(
          icon: Icons.cancel_outlined,
          color: _kRed,
          title: 'Ride cancelled',
          body: route,
          time: ride.updatedAt,
        ));
      }
      if (ride.acceptedAt != null &&
          ride.rideStatus != RideStatus.cancelled &&
          ride.rideStatus != RideStatus.failed) {
        events.add(_RideEvent(
          icon: Icons.person_pin_circle_rounded,
          color: _kBlue,
          title: 'Driver assigned to your ride',
          body: route,
          time: ride.acceptedAt!,
        ));
      }
    }
    events.sort((a, b) => b.time.compareTo(a.time));
    return events;
  }
}

class _RideEvent {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final DateTime time;

  const _RideEvent({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.time,
  });
}

class _NotificationTile extends StatelessWidget {
  final _RideEvent event;
  const _NotificationTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final timeAgo = _formatTimeAgo(event.time);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: event.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(event.icon, color: event.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.body,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            timeAgo,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return DateFormat('MMM d').format(time);
  }
}

// ---------------------------------------------------------------------------
// Promo banners
// ---------------------------------------------------------------------------

class _ReturningRiderBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String cta;

  const _ReturningRiderBanner({
    required this.title,
    required this.subtitle,
    required this.cta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/rides/booking'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      cta,
                      style: const TextStyle(
                        color: _kBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.directions_car_rounded, color: Colors.white, size: 64),
        ],
      ),
    );
  }
}
