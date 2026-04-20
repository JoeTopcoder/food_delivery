import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/driver_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/driver_intelligence_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/notification_service.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class DriverDashboardScreen extends ConsumerStatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  ConsumerState<DriverDashboardScreen> createState() =>
      _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends ConsumerState<DriverDashboardScreen>
    with SingleTickerProviderStateMixin {
  bool _togglingAvailability = false;
  bool _creatingProfile = false;
  late AnimationController _pulseController;
  Driver? _lastDriver;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Wire callback so push/realtime notifications refresh available orders
    NotificationService.onNewOrderReceived = () {
      ref.invalidate(availableOrdersProvider);
    };
  }

  @override
  void dispose() {
    _pulseController.dispose();
    NotificationService.onNewOrderReceived = null;
    super.dispose();
  }

  String _completionRate(Driver driver) {
    final completed = driver.completedDeliveries ?? 0;
    final cancelled = driver.cancelledDeliveries ?? 0;
    final total = completed + cancelled;
    if (total == 0) return '—';
    return '${(completed / total * 100).round()}%';
  }

  Future<void> _createProfile(String userId) async {
    setState(() => _creatingProfile = true);
    try {
      final svc = ref.read(driverServiceProvider);
      await svc.createDriverProfile(userId: userId);
      ref.invalidate(driverProfileProvider(userId));
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _creatingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep realtime subscription alive while dashboard is visible
    ref.watch(newOrderRealtimeProvider);

    final authState = ref.watch(authNotifierProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final driverProfileAsync = currentUserId != null
        ? ref.watch(driverProfileProvider(currentUserId))
        : null;

    if (authState.user == null || currentUserId == null) {
      if (!authState.isAuthenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/signin', (_) => false);
          }
        });
      }
      return const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: AppLoadingIndicator(),
      );
    }

    // Use cached driver to avoid full-screen spinner on realtime refresh
    final driver = driverProfileAsync?.valueOrNull ?? _lastDriver;
    if (driverProfileAsync?.hasValue == true &&
        driverProfileAsync?.valueOrNull != null) {
      _lastDriver = driverProfileAsync!.valueOrNull;
    }

    if (driver == null) {
      if (driverProfileAsync?.hasError == true) {
        return Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          body: _buildError(currentUserId, driverProfileAsync!.error!),
        );
      }
      if (driverProfileAsync == null) {
        return Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          body: _buildNoProfile(currentUserId),
        );
      }
      return const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: Center(
          child: AppLoadingIndicator(message: 'Loading dashboard...'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: _buildDashboard(driver, authState, currentUserId),
    );
  }

  Widget _buildDashboard(
    Driver driver,
    dynamic authState,
    String currentUserId,
  ) {
    // Keep realtime subscription alive so Balance / stats update live
    ref.watch(driverEarningsRealtimeProvider(driver.id));

    final isOnline = driver.isAvailable;
    final screenWidth = MediaQuery.of(context).size.width;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Hero Header ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A1D2E), Color(0xFF0F1117)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  children: [
                    // Top bar: avatar + greeting + settings
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: isOnline
                                ? const LinearGradient(
                                    colors: [
                                      AppTheme.primaryColor,
                                      Color(0xFFFF9A5C),
                                    ],
                                  )
                                : null,
                            color: isOnline ? null : const Color(0xFF2A2D3E),
                          ),
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFF1A1D2E),
                            backgroundImage:
                                authState.user?.profileImageUrl != null
                                ? NetworkImage(authState.user!.profileImageUrl!)
                                : null,
                            child: authState.user?.profileImageUrl == null
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.white60,
                                    size: 26,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hey, ${authState.user?.name?.split(' ').first ?? 'Driver'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isOnline
                                          ? const Color(0xFF22C55E)
                                          : const Color(0xFF6B7280),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isOnline ? 'Online' : 'Offline',
                                    style: TextStyle(
                                      color: isOnline
                                          ? const Color(0xFF22C55E)
                                          : const Color(0xFF6B7280),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (driver.vehicleType != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 3,
                                      height: 3,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFF4B5563),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      driver.vehicleType!.toUpperCase(),
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        _GlassIconButton(
                          icon: Icons.settings_rounded,
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed('/driver-profile'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Online Toggle Card ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: isOnline
                            ? const LinearGradient(
                                colors: [
                                  AppTheme.primaryColor,
                                  Color(0xFFFF8F5E),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isOnline ? null : const Color(0xFF1E2030),
                        borderRadius: BorderRadius.circular(20),
                        border: isOnline
                            ? null
                            : Border.all(color: const Color(0xFF2A2D3E)),
                      ),
                      child: Row(
                        children: [
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOnline
                                      ? Colors.white.withValues(
                                          alpha:
                                              0.15 +
                                              _pulseController.value * 0.1,
                                        )
                                      : const Color(0xFF2A2D3E),
                                ),
                                child: Icon(
                                  isOnline
                                      ? Icons.electric_bolt_rounded
                                      : Icons.power_settings_new_rounded,
                                  color: isOnline
                                      ? Colors.white
                                      : const Color(0xFF6B7280),
                                  size: 22,
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isOnline
                                      ? 'You\'re Live!'
                                      : 'You\'re Offline',
                                  style: TextStyle(
                                    color: isOnline
                                        ? Colors.white
                                        : const Color(0xFF9CA3AF),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isOnline
                                      ? 'Receiving new delivery requests'
                                      : 'Go live to start earning',
                                  style: TextStyle(
                                    color: isOnline
                                        ? Colors.white.withValues(alpha: 0.8)
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _togglingAvailability
                              ? SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    color: isOnline
                                        ? Colors.white
                                        : AppTheme.primaryColor,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : GestureDetector(
                                  onTap: () async {
                                    setState(
                                      () => _togglingAvailability = true,
                                    );
                                    try {
                                      await ref
                                          .read(driverServiceProvider)
                                          .updateDriverAvailability(
                                            driver.id,
                                            !isOnline,
                                          );
                                      ref.invalidate(
                                        driverProfileProvider(currentUserId),
                                      );
                                    } catch (e) {
                                      if (mounted) {
                                        AppSnackbar.error(
                                          context,
                                          friendlyError(e),
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(
                                          () => _togglingAvailability = false,
                                        );
                                      }
                                    }
                                  },
                                  child: Container(
                                    width: 56,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(15),
                                      color: isOnline
                                          ? Colors.white.withValues(alpha: 0.3)
                                          : const Color(0xFF2A2D3E),
                                      border: Border.all(
                                        color: isOnline
                                            ? Colors.white.withValues(
                                                alpha: 0.5,
                                              )
                                            : const Color(0xFF3A3D4E),
                                      ),
                                    ),
                                    child: AnimatedAlign(
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      curve: Curves.easeOutBack,
                                      alignment: isOnline
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.all(3),
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isOnline
                                                ? Colors.white
                                                : const Color(0xFF4B5563),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Stats Grid ───────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    _MetricTile(
                      icon: Icons.check_circle_rounded,
                      label: 'Deliveries',
                      value: '${driver.completedDeliveries ?? 0}',
                      color: const Color(0xFF22C55E),
                    ),
                    const SizedBox(width: 10),
                    _MetricTile(
                      icon: Icons.star_rounded,
                      label: 'Rating',
                      value: driver.rating != null && driver.rating! > 0
                          ? driver.rating!.toStringAsFixed(1)
                          : '—',
                      color: const Color(0xFFFBBF24),
                    ),
                    const SizedBox(width: 10),
                    _MetricTile(
                      icon: Icons.payments_rounded,
                      label: 'Balance',
                      value:
                          'J\$${((driver.totalEarnings ?? 0) - (driver.totalPaidOut ?? 0)).clamp(0.0, double.infinity).toStringAsFixed(2)}',
                      color: const Color(0xFF3B82F6),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MetricTile(
                      icon: Icons.verified_rounded,
                      label: 'Status',
                      value: driver.isVerified == true ? 'Verified' : 'Pending',
                      color: driver.isVerified == true
                          ? const Color(0xFF14B8A6)
                          : const Color(0xFF6B7280),
                    ),
                    const SizedBox(width: 10),
                    _MetricTile(
                      icon: Icons.trending_up_rounded,
                      label: 'Success',
                      value: _completionRate(driver),
                      color: const Color(0xFF8B5CF6),
                    ),
                    const SizedBox(width: 10),
                    _MetricTile(
                      icon: Icons.cancel_rounded,
                      label: 'Cancelled',
                      value: '${driver.cancelledDeliveries ?? 0}',
                      color: const Color(0xFFEF4444),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ── Driver Tier Badge ────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Consumer(
              builder: (context, ref, _) {
                final statsAsync = ref.watch(driverStatsProvider(driver.id));
                final stats = statsAsync.valueOrNull;
                if (stats == null) return const SizedBox.shrink();
                final Color tierColor;
                switch (stats.tier) {
                  case 'elite':
                    tierColor = const Color(0xFFE879F9);
                    break;
                  case 'gold':
                    tierColor = const Color(0xFFFBBF24);
                    break;
                  case 'silver':
                    tierColor = const Color(0xFF94A3B8);
                    break;
                  default:
                    tierColor = const Color(0xFFD97706);
                }
                return GestureDetector(
                  onTap: () =>
                      Navigator.of(context).pushNamed('/driver-performance'),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: tierColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: tierColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          stats.tierEmoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${stats.tierLabel} Driver',
                                style: TextStyle(
                                  color: tierColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'Score: ${stats.score.toStringAsFixed(0)}/100  •  ${stats.bonusMultiplier > 1 ? '+${((stats.bonusMultiplier - 1) * 100).toStringAsFixed(0)}% bonus' : 'No bonus yet'}',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: tierColor,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // ── Quick Actions ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            delegate: SliverChildListDelegate([
              _ActionTile(
                icon: Icons.search_rounded,
                label: 'Find Orders',
                subtitle: 'Browse available',
                iconBg: AppTheme.primaryColor,
                onTap: () =>
                    Navigator.of(context).pushNamed('/available-orders'),
              ),
              _ActionTile(
                icon: Icons.local_shipping_rounded,
                label: 'My Deliveries',
                subtitle: 'Active orders',
                iconBg: const Color(0xFF14B8A6),
                onTap: () =>
                    Navigator.of(context).pushNamed('/active-deliveries'),
              ),
              _ActionTile(
                icon: Icons.history_rounded,
                label: 'History',
                subtitle: 'Past deliveries',
                iconBg: const Color(0xFF3B82F6),
                onTap: () =>
                    Navigator.of(context).pushNamed('/delivery-history'),
              ),
              _ActionTile(
                icon: Icons.account_balance_wallet_rounded,
                label: 'My Wallet',
                subtitle: 'Cash out now',
                iconBg: const Color(0xFF10B981),
                onTap: () => Navigator.of(context).pushNamed('/driver-wallet'),
              ),
              _ActionTile(
                icon: Icons.person_rounded,
                label: 'My Profile',
                subtitle: 'Vehicle & docs',
                iconBg: const Color(0xFF8B5CF6),
                onTap: () => Navigator.of(context).pushNamed('/driver-profile'),
              ),
            ]),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: screenWidth > 400 ? 1.3 : 1.15,
            ),
          ),
        ),

        // ── Earnings Banner ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _PromoBanner(
              icon: Icons.payments_rounded,
              title: 'My Earnings',
              subtitle: 'Track income, tips & payouts',
              gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
              onTap: () =>
                  Navigator.of(context).pushNamed('/driver-earnings-advanced'),
            ),
          ),
        ),

        // ── Wallet Banner ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _PromoBanner(
              icon: Icons.bolt_rounded,
              title: 'Instant Wallet',
              subtitle: 'View balance and cash out in minutes',
              gradient: const [Color(0xFF10B981), Color(0xFF059669)],
              onTap: () => Navigator.of(context).pushNamed('/driver-wallet'),
            ),
          ),
        ),

        // ── Performance Banner ───────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _PromoBanner(
              icon: Icons.insights_rounded,
              title: 'Performance & Tier',
              subtitle: 'Score, tier progress & smart tips',
              gradient: const [Color(0xFF22C55E), Color(0xFF16A34A)],
              onTap: () =>
                  Navigator.of(context).pushNamed('/driver-performance'),
            ),
          ),
        ),

        // ── Heatmap Banner ───────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _PromoBanner(
              icon: Icons.map_rounded,
              title: 'Demand Heatmap',
              subtitle: 'Find surge zones & earn more',
              gradient: const [Color(0xFFEF4444), Color(0xFFDC2626)],
              onTap: () => Navigator.of(context).pushNamed('/driver-heatmap'),
            ),
          ),
        ),

        // ── Leaderboard Banner ───────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _PromoBanner(
              icon: Icons.emoji_events_rounded,
              title: 'Leaderboard',
              subtitle: 'See your ranking among drivers',
              gradient: const [Color(0xFF6366F1), Color(0xFF4F46E5)],
              onTap: () =>
                  Navigator.of(context).pushNamed('/driver-leaderboard'),
            ),
          ),
        ),

        // ── Tip of the Day ───────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2030),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lightbulb_rounded,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Peak hours: 12–2 pm & 6–9 pm',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Stay online during peak hours for more orders.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildNoProfile(String userId) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: const Icon(
                  Icons.delivery_dining_rounded,
                  size: 56,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Set Up Your\nDriver Profile',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Create your profile to start accepting\ndelivery requests and earning.',
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _creatingProfile
                      ? null
                      : () => _createProfile(userId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _creatingProfile
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(String userId, Object error) {
    return AppErrorState(
      message: friendlyError(error),
      onRetry: () => ref.invalidate(driverProfileProvider(userId)),
    );
  }
}

// ── Glass Icon Button ────────────────────────────────────────────────────────

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF1E2030),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2D3E)),
        ),
        child: Icon(icon, color: const Color(0xFF9CA3AF), size: 20),
      ),
    );
  }
}

// ── Metric Tile ──────────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2030),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2A2D3E)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action Tile ──────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color iconBg;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.iconBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E2030),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2A2D3E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconBg, size: 22),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Promo Banner ─────────────────────────────────────────────────────────────

class _PromoBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _PromoBanner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white70,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
