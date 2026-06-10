import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/index.dart';
import '../../providers/car_services_providers.dart';
import 'service_provider_status_screen.dart';
import 'package:food_driver/utils/app_logger.dart';
import 'package:food_driver/utils/friendly_error.dart';

const _kBlue = Color(0xFF1D4ED8);
const _kBlueDark = Color(0xFF1E3A8A);
const _kBg = Color(0xFFF8FAFC);
const _kAmber = Color(0xFFF59E0B);

class CarServiceProviderDashboardScreen extends ConsumerStatefulWidget {
  const CarServiceProviderDashboardScreen({super.key});

  @override
  ConsumerState<CarServiceProviderDashboardScreen> createState() =>
      _CarServiceProviderDashboardScreenState();
}

class _CarServiceProviderDashboardScreenState
    extends ConsumerState<CarServiceProviderDashboardScreen> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myCarServiceProviderProfileProvider);

    return Scaffold(
      backgroundColor: _kBg,
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _kBlue)),
        error: (e, _) {
          AppLogger.error('Dashboard profile error', e);
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Could not load profile.\n${friendlyError(e)}',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      ref.invalidate(myCarServiceProviderProfileProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        },
        data: (provider) {
          if (provider == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _kBlue.withAlpha(20),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.store_outlined,
                          size: 56, color: _kBlue),
                    ),
                    const SizedBox(height: 20),
                    const Text('Complete your registration',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    const Text(
                      "Your email is confirmed! Now finish setting up\nyour car service provider profile.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context)
                          .pushReplacementNamed('/onboarding/service-provider'),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Continue Registration'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Approval gate — check status before showing dashboard
          if (provider.isSuspended) {
            return const ServiceProviderStatusScreen(
              status: ProviderStatus.suspended,
            );
          }
          if (provider.approvalStatus == 'rejected') {
            return ServiceProviderStatusScreen(
              status: ProviderStatus.rejected,
              reason: provider.rejectionReason,
            );
          }
          if (!provider.isApproved || provider.approvalStatus == 'pending') {
            return const ServiceProviderStatusScreen(
              status: ProviderStatus.pending,
            );
          }

          return _DashboardBody(
            provider: provider,
            navIndex: _navIndex,
            onNavTap: (i) => _handleNavTap(context, i, provider),
          );
        },
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _navIndex,
        onTap: (i) {
          final profileAsync = ref.read(myCarServiceProviderProfileProvider);
          profileAsync.whenData((provider) {
            if (provider != null) _handleNavTap(context, i, provider);
          });
        },
      ),
    );
  }

  void _handleNavTap(
      BuildContext context, int i, CarServiceProvider provider) {
    switch (i) {
      case 0:
        setState(() => _navIndex = 0);
        break;
      case 1:
        Navigator.pushNamed(
          context,
          '/car-services/provider/bookings',
          arguments: provider.id,
        );
        break;
      case 2:
        Navigator.pushNamed(
          context,
          '/car-services/provider/services',
          arguments: provider.id,
        );
        break;
      case 3:
        Navigator.pushNamed(
          context,
          '/car-services/provider/availability',
          arguments: provider.id,
        );
        break;
      case 4:
        Navigator.pushNamed(
          context,
          '/car-services/provider/earnings',
          arguments: provider.id,
        );
        break;
    }
  }
}

// ── Dashboard body ─────────────────────────────────────────────────────────────

class _DashboardBody extends ConsumerWidget {
  final CarServiceProvider provider;
  final int navIndex;
  final ValueChanged<int> onNavTap;

  const _DashboardBody({
    required this.provider,
    required this.navIndex,
    required this.onNavTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(providerBookingsProvider(provider.id));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myCarServiceProviderProfileProvider);
        ref.invalidate(providerBookingsProvider(provider.id));
      },
      color: _kBlue,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // ── Header ──────────────────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildHeader(context)),

          // ── Stats row ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: bookingsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: CircularProgressIndicator(color: _kBlue)),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (bookings) => _buildStats(context, bookings),
            ),
          ),

          // ── Recent bookings ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Bookings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  TextButton(
                    onPressed: () => onNavTap(1),
                    child: const Text('View all',
                        style: TextStyle(color: _kBlue)),
                  ),
                ],
              ),
            ),
          ),

          bookingsAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                    child: CircularProgressIndicator(color: _kBlue)),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child:
                    Text('Failed to load bookings: ${friendlyError(e)}'),
              ),
            ),
            data: (bookings) {
              final recent = bookings.take(5).toList();
              if (recent.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          'No bookings yet',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _BookingCard(booking: recent[i]),
                    childCount: recent.length,
                  ),
                ),
              );
            },
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBlueDark, _kBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_ios_rounded,
                    color: Colors.white, size: 20),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.businessName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF4ADE80),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          provider.isVerified ? 'Active · Verified' : 'Active',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context)
                    .pushNamed('/car-services/provider/profile'),
                icon: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white.withAlpha(40),
                  backgroundImage: provider.profileImageUrl != null
                      ? NetworkImage(provider.profileImageUrl!)
                      : null,
                  child: provider.profileImageUrl == null
                      ? const Icon(Icons.person_outline,
                          color: Colors.white, size: 20)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStats(
      BuildContext context, List<CarServiceBooking> bookings) {
    final today = DateTime.now();
    final todayCount = bookings
        .where((b) =>
            b.scheduledAt.year == today.year &&
            b.scheduledAt.month == today.month &&
            b.scheduledAt.day == today.day)
        .length;

    final totalEarnings = bookings
        .where((b) => b.status == CarServiceBookingStatus.completed)
        .fold<double>(0,
            (s, b) => s + (b.totalAmount - b.platformFee - b.serviceFee));

    final pendingCount = bookings
        .where((b) => b.status == CarServiceBookingStatus.pending)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          _StatCard(
            label: "Today's Bookings",
            value: '$todayCount',
            icon: Icons.today_rounded,
            color: _kBlue,
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'Total Earned',
            value: '\$${totalEarnings.toStringAsFixed(0)}',
            icon: Icons.attach_money_rounded,
            color: const Color(0xFF059669),
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: 'Pending',
            value: '$pendingCount',
            icon: Icons.pending_actions_rounded,
            color: _kAmber,
          ),
        ],
      ),
    );
  }
}

// ── Bottom navigation ──────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFEFF6FF),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded, color: _kBlue),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded, color: _kBlue),
          label: 'Bookings',
        ),
        NavigationDestination(
          icon: Icon(Icons.local_car_wash_outlined),
          selectedIcon: Icon(Icons.local_car_wash_rounded, color: _kBlue),
          label: 'Services',
        ),
        NavigationDestination(
          icon: Icon(Icons.schedule_outlined),
          selectedIcon: Icon(Icons.schedule_rounded, color: _kBlue),
          label: 'Availability',
        ),
        NavigationDestination(
          icon: Icon(Icons.attach_money_outlined),
          selectedIcon: Icon(Icons.attach_money_rounded, color: _kBlue),
          label: 'Earnings',
        ),
      ],
    );
  }
}

// ── Stat card ──────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Booking card ───────────────────────────────────────────────────────────────

class _BookingCard extends StatelessWidget {
  final CarServiceBooking booking;
  const _BookingCard({required this.booking});

  Color get _statusColor {
    switch (booking.status) {
      case CarServiceBookingStatus.pending:
        return _kAmber;
      case CarServiceBookingStatus.confirmed:
      case CarServiceBookingStatus.providerEnRoute:
      case CarServiceBookingStatus.arrived:
      case CarServiceBookingStatus.inProgress:
        return _kBlue;
      case CarServiceBookingStatus.completed:
        return const Color(0xFF059669);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('EEE, MMM d · h:mm a').format(booking.scheduledAt);
    final color = _statusColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 10,
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
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.local_car_wash_rounded,
                color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.offering?.name ?? 'Service',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  booking.status.toDisplayString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '\$${booking.totalAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF059669)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
