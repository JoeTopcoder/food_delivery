import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/driver_model.dart';
import '../../models/order_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/driver_intelligence_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/notification_service.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../config/app_constants.dart';
import '../../widgets/peak_time_banner.dart';
import '../../widgets/driver_order_alert.dart';
import '../../widgets/app_map_tiles.dart';
import '../../providers/user_provider.dart'
    show restaurantServiceProvider, restaurantByIdProvider, orderServiceProvider;
import '../../services/driver/delivery_fee_service.dart';
import 'driver_verification_screen.dart';
import 'student_delivery_confirm.dart';

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
  bool _redirecting = false;
  late AnimationController _pulseController;
  Driver? _lastDriver;
  bool _serviceTopicsInitialized = false;
  // Ready orders already shown to this driver, so a nearby order isn't
  // re-popped on every refresh. Cleared when the driver goes offline.
  final Set<String> _poppedReadyIds = {};
  bool _readyScanScheduled = false;
  String? _advancingOrderId;

  static const Map<String, String> _serviceTopics = {
    'food_delivery': 'food_delivery_orders',
    'package_delivery': 'package_delivery_orders',
    'ride_sharing': 'ride_sharing_requests',
  };

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    NotificationService.onNewOrderReceived = () {
      ref.invalidate(availableOrdersProvider);
      // An order just became ready — pop it on the dashboard (not only the
      // one-time scan when going online). Uses the last-known driver profile.
      final d = _lastDriver;
      if (d != null && d.isAvailable && mounted) {
        _scanNearbyReadyOrders(d);
      }
    };
    NotificationService.onNewPackageReceived = null;
    NotificationService.onNewRideReceived = null;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    NotificationService.onNewOrderReceived = null;
    NotificationService.onNewPackageReceived = null;
    NotificationService.onNewRideReceived = null;
    super.dispose();
  }

  /// Pops the Uber-style order card for orders that are ALREADY ready and
  /// nearby — so a driver who logs in (or comes online) after an order became
  /// ready still sees it, not only orders that turn ready while already online.
  /// Shows one card at a time (the newest un-shown ready order).
  Future<void> _scanNearbyReadyOrders(Driver driver) async {
    if (!driver.isAvailable || !mounted) return;
    double? lat = driver.currentLatitude;
    double? lng = driver.currentLongitude;
    // Fall back to a live GPS fix if the profile has no location yet, so the
    // popup still fires right after going online. If we still have no location
    // we scan without a proximity filter (same as the Get Orders tab).
    if (lat == null || lng == null) {
      try {
        final pos = await ref.read(locationServiceProvider).getCurrentPosition();
        if (pos != null) {
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } catch (_) {}
    }
    try {
      final orders = await ref.read(driverServiceProvider).getAvailableOrders(
            driverId: driver.id,
            driverLat: lat,
            driverLng: lng,
          );
      // Only orders currently in the "ready" tab, newest first. The list is
      // already capped by getAvailableOrders to the driver's remaining slots
      // (3 - active), so a driver with 1 active order sees up to 2 here.
      final ready = orders
          .where((o) => o.status == AppConstants.orderReady)
          .where((o) => !_poppedReadyIds.contains(o.id))
          .toList();
      if (ready.isEmpty) return;

      final cards = <Map<String, dynamic>>[];
      for (final o in ready) {
        _poppedReadyIds.add(o.id);
        String storeName = 'New Order';
        double? distanceKm;
        try {
          final rest = await ref
              .read(restaurantServiceProvider)
              .getRestaurantById(o.restaurantId);
          if (rest != null) {
            storeName = rest.name;
            if (lat != null &&
                lng != null &&
                rest.latitude != null &&
                rest.longitude != null) {
              distanceKm = DeliveryFeeService.haversineKm(
                lat,
                lng,
                rest.latitude!,
                rest.longitude!,
              );
            }
          }
        } catch (_) {}
        cards.add({
          'order_id': o.id,
          'store_name': storeName,
          'address': o.deliveryAddress ?? '',
          'delivery_fee': o.deliveryFee.toString(),
          'tip': (o.driverTip ?? 0).toString(),
          if (distanceKm != null) 'distance_km': distanceKm.toStringAsFixed(2),
        });
      }

      if (!mounted || cards.isEmpty) return;
      // Show every order the driver can still take, together in one popup.
      DriverOrderAlert.showOrders(cards);
    } catch (e) {
      // Non-fatal: the orders are still visible in the Orders screen.
    }
  }

  Future<void> _syncFcmTopics(List<String> activeServices) async {
    final ns = NotificationService();
    for (final entry in _serviceTopics.entries) {
      if (activeServices.contains(entry.key)) {
        await ns.subscribeToTopic(entry.value);
      } else {
        await ns.unsubscribeFromTopic(entry.value);
      }
    }
  }


  Future<void> _createProfile(String userId) async {
    setState(() => _creatingProfile = true);
    try {
      final svc = ref.read(driverServiceProvider);
      await svc.createDriverProfile(userId: userId);
      ref.invalidate(driverProfileProvider(userId));
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _creatingProfile = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    ref.watch(newOrderRealtimeProvider);

    final authState = ref.watch(authNotifierProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final driverProfileAsync = currentUserId != null
        ? ref.watch(driverProfileProvider(currentUserId))
        : null;

    if (authState.user == null || currentUserId == null) {
      if (!authState.isAuthenticated && !_redirecting) {
        _redirecting = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
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
      // Show no-profile screen when the provider resolved with null
      // (auto-create failed) OR when the async value itself is null.
      if (driverProfileAsync == null || driverProfileAsync.hasValue == true) {
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

    // ── Verification gate ─────────────────────────────────────────────────────
    // Only fully approved drivers reach the dashboard.
    // 'draft' is no longer treated as a bypass — new signups are set to
    // 'pending_review' at the end of onboarding and must wait for admin approval.
    if (driver.driverStatus != 'approved') {
      return _buildVerificationGate(driver);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: _buildDashboard(driver, authState, currentUserId),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0B10),
        border: Border(top: BorderSide(color: Color(0xFF1A1B24))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.home_rounded, 'Home', active: true, onTap: () {}),
              _navItem(Icons.receipt_long_rounded, 'Orders',
                  onTap: () => Navigator.of(context).pushNamed('/driver-orders')),
              _navItem(Icons.location_on_rounded, 'Map',
                  onTap: () =>
                      Navigator.of(context).pushNamed('/active-deliveries')),
              _navItem(Icons.account_balance_wallet_rounded, 'Earnings',
                  onTap: () => Navigator.of(context)
                      .pushNamed('/driver-earnings-advanced')),
              _navItem(Icons.person_rounded, 'Profile',
                  onTap: () => Navigator.of(context).pushNamed('/driver-profile')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label,
      {bool active = false, required VoidCallback onTap}) {
    final color =
        active ? const Color(0xFF22C55E) : const Color(0xFF6B7280);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildVerificationGate(Driver driver) {
    final status = driver.driverStatus;
    late final IconData icon;
    late final Color color;
    late final String title;
    late final String message;
    late final String buttonLabel;
    late final VoidCallback onButton;

    switch (status) {
      case 'pending_review':
      case 'under_review':
        icon = Icons.hourglass_top_rounded;
        color = Colors.orangeAccent;
        title = 'Application Under Review';
        message =
            'Your application has been submitted and is being reviewed by our team. This typically takes 1–3 business days. You will be notified once approved.';
        buttonLabel = 'View Application Status';
        onButton = () =>
            Navigator.pushNamed(context, '/driver-application-status');
      case 'rejected':
        icon = Icons.cancel_outlined;
        color = Colors.redAccent;
        title = 'Application Rejected';
        message = driver.rejectionReason?.isNotEmpty == true
            ? 'Your application was rejected: ${driver.rejectionReason}'
            : 'Your application was not approved. Please re-upload your documents and resubmit.';
        buttonLabel = 'Re-upload Documents';
        onButton = () =>
            Navigator.pushNamed(context, '/driver-application-status');
      case 'suspended':
        icon = Icons.block_rounded;
        color = Colors.red;
        title = 'Account Suspended';
        message =
            'Your driver account has been suspended. Please contact support for assistance.';
        buttonLabel = 'Contact Support';
        onButton = () =>
            Navigator.pushNamed(context, '/driver-application-status');
      case 'expired_documents':
        icon = Icons.warning_amber_rounded;
        color = Colors.amber;
        title = 'Documents Expired';
        message =
            'One or more of your verification documents have expired. Please re-upload valid documents to continue driving.';
        buttonLabel = 'Update Documents';
        onButton = () =>
            Navigator.pushNamed(context, '/driver-application-status');
      default:
        icon = Icons.edit_document;
        color = Colors.white54;
        title = 'Complete Verification';
        message =
            'Complete your driver verification to start accepting deliveries on our platform.';
        buttonLabel = 'Start Verification';
        onButton = () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DriverVerificationScreen(driver: driver),
          ),
        );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 48),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 14,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onButton,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    buttonLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  final userId = ref.read(currentUserIdProvider);
                  if (userId != null)
                    ref.invalidate(driverProfileProvider(userId));
                },
                child: const Text(
                  'Refresh Status',
                  style: TextStyle(color: Color(0xFF9CA3AF)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.read(authNotifierProvider.notifier).signOut(),
                child: const Text(
                  '← Back to role selection',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Availability toggle (Go Online / Go Offline) ──────────────────────────
  Future<void> _toggleAvailability(Driver driver, String currentUserId) async {
    if (_togglingAvailability) return;
    final isOnline = driver.isAvailable;
    setState(() => _togglingAvailability = true);
    try {
      await ref
          .read(driverServiceProvider)
          .updateDriverAvailability(driver.id, !isOnline);
      final ls = ref.read(locationServiceProvider);
      if (!isOnline) {
        _readyScanScheduled = false;
        _poppedReadyIds.clear();
        await ls.startTracking(driverId: driver.id);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) ref.invalidate(driverProfileProvider(currentUserId));
        });
      } else {
        await ls.stopTracking();
      }
      ref.invalidate(driverProfileProvider(currentUserId));
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _togglingAvailability = false);
    }
  }

  Widget _buildDashboard(
    Driver driver,
    dynamic authState,
    String currentUserId,
  ) {
    ref.watch(driverEarningsRealtimeProvider(driver.id));

    // Keep FCM order-type topic subscriptions in sync with the driver's
    // active services (the toggle UI moved off this screen, but the driver
    // still receives the right pushes).
    if (!_serviceTopicsInitialized) {
      _serviceTopicsInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncFcmTopics(driver.activeServices ?? ['food_delivery']),
      );
    }

    final isOnline = driver.isAvailable;

    if (isOnline) {
      if (!_readyScanScheduled) {
        _readyScanScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scanNearbyReadyOrders(driver);
        });
      }
    } else {
      _readyScanScheduled = false;
      _poppedReadyIds.clear();
    }

    final activeOrders =
        ref.watch(activeDeliveriesProvider(driver.id)).valueOrNull;
    final Order? activeOrder =
        (activeOrders != null && activeOrders.isNotEmpty)
            ? activeOrders.first
            : null;

    final stats = ref.watch(driverStatsProvider(driver.id)).valueOrNull;
    final balance = ((driver.totalEarnings ?? 0) - (driver.totalPaidOut ?? 0))
        .clamp(0.0, double.infinity);
    final todayEarnings =
        (stats?.sessionEarnings ?? 0) > 0 ? stats!.sessionEarnings : balance;

    return RefreshIndicator(
      color: const Color(0xFF22C55E),
      backgroundColor: const Color(0xFF12131C),
      onRefresh: () async {
        ref.invalidate(driverProfileProvider(currentUserId));
        ref.invalidate(activeDeliveriesProvider(driver.id));
      },
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.zero,
        children: [
          _header(driver, authState, isOnline),
          const PeakTimeBanner(
            driver: true,
            margin: EdgeInsets.fromLTRB(16, 4, 16, 0),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _dutyEarningsCard(
              driver,
              currentUserId,
              isOnline,
              todayEarnings,
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _mapCard(driver, activeOrder),
          ),
          if (activeOrder != null) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _currentDeliveryCard(activeOrder),
            ),
          ],
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _quickActions(driver),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
            child: Text(
              'More',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _moreSection(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── More / Explore ─────────────────────────────────────────────────────────
  Widget _moreSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12131C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1F2A)),
      ),
      child: Column(
        children: [
          _moreRow(
            Icons.payments_rounded,
            const Color(0xFFF59E0B),
            'Earnings & Analytics',
            'Income, tips & payouts',
            () => Navigator.of(context).pushNamed('/driver-earnings-advanced'),
            divider: true,
          ),
          _moreRow(
            Icons.map_rounded,
            const Color(0xFFEF4444),
            'Demand Heatmap',
            'Find surge zones nearby',
            () => Navigator.of(context).pushNamed('/driver-heatmap'),
            divider: true,
          ),
          _moreRow(
            Icons.insights_rounded,
            const Color(0xFF22C55E),
            'Performance & Tier',
            'Score, tier & smart tips',
            () => Navigator.of(context).pushNamed('/driver-performance'),
            divider: true,
          ),
          _moreRow(
            Icons.emoji_events_rounded,
            const Color(0xFF6366F1),
            'Leaderboard',
            'Your ranking among drivers',
            () => Navigator.of(context).pushNamed('/driver-leaderboard'),
            divider: true,
          ),
          _moreRow(
            Icons.card_giftcard_rounded,
            const Color(0xFF10B981),
            'Refer a Driver',
            'Earn a bonus for every referral',
            () => Navigator.of(context).pushNamed('/driver-referral'),
            divider: false,
          ),
        ],
      ),
    );
  }

  Widget _moreRow(
    IconData icon,
    Color color,
    String title,
    String subtitle,
    VoidCallback onTap, {
    required bool divider,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: color, size: 19),
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
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: Color(0xFF4B5563), size: 18),
                ],
              ),
            ),
          ),
        ),
        if (divider)
          const Divider(
            height: 1,
            indent: 68,
            endIndent: 14,
            color: Color(0xFF1E1F2A),
          ),
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _header(Driver driver, dynamic authState, bool isOnline) {
    return Container(
      color: const Color(0xFF0A0B10),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isOnline
                      ? const LinearGradient(
                          colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                        )
                      : null,
                  color: isOnline ? null : const Color(0xFF2A2D3E),
                ),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFF1A1D2E),
                      backgroundImage: authState.user?.profileImageUrl != null
                          ? NetworkImage(authState.user!.profileImageUrl!)
                          : null,
                      child: authState.user?.profileImageUrl == null
                          ? const Icon(Icons.person,
                              color: Colors.white54, size: 26)
                          : null,
                    ),
                    if (isOnline)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 15,
                          height: 15,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: const Color(0xFF0A0B10), width: 2.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_greeting()},',
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      authState.user?.name ?? 'Driver',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isOnline
                                ? const Color(0xFF22C55E)
                                : const Color(0xFF6B7280))
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF6B7280),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: isOnline
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF9CA3AF),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _GlassIconButton(
                icon: Icons.notifications_none_rounded,
                onTap: () => Navigator.of(context).pushNamed('/notifications'),
              ),
              const SizedBox(width: 8),
              _GlassIconButton(
                icon: Icons.settings_outlined,
                onTap: () => Navigator.of(context).pushNamed('/driver-profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Earnings + On-duty card ────────────────────────────────────────────────
  Widget _dutyEarningsCard(
    Driver driver,
    String currentUserId,
    bool isOnline,
    double todayEarnings,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12131C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOnline
              ? const Color(0xFF22C55E).withValues(alpha: 0.30)
              : const Color(0xFF1E1F2A),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Earnings
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context)
                    .pushNamed('/driver-earnings-advanced'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          "Today's Earnings",
                          style: TextStyle(
                              color: Color(0xFF9CA3AF), fontSize: 12.5),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded,
                            color: Color(0xFF6B7280), size: 16),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${AppConstants.currencySymbol}${todayEarnings.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${driver.completedDeliveries ?? 0} deliveries completed',
                      style: const TextStyle(
                          color: Color(0xFF6B7280), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 28, color: Color(0xFF1E1F2A)),
            // On duty
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (isOnline
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF6B7280))
                          .withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isOnline
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF6B7280),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.drive_eta_rounded,
                      color: isOnline
                          ? const Color(0xFF22C55E)
                          : const Color(0xFF6B7280),
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isOnline ? "You're On Duty" : "You're Off Duty",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isOnline
                        ? 'Ready to receive new orders'
                        : 'Go online to get orders',
                    style: const TextStyle(
                        color: Color(0xFF6B7280), fontSize: 12, height: 1.3),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: _togglingAvailability
                          ? null
                          : () => _toggleAvailability(driver, currentUserId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isOnline
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF1A1B24),
                        foregroundColor:
                            isOnline ? Colors.white : const Color(0xFF22C55E),
                        elevation: 0,
                        side: isOnline
                            ? null
                            : const BorderSide(color: Color(0xFF22C55E)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      icon: _togglingAvailability
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.power_settings_new_rounded,
                              size: 18),
                      label: Text(
                        isOnline ? 'Go Offline' : 'Go Online',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Live map card ──────────────────────────────────────────────────────────
  Widget _mapCard(Driver driver, Order? order) {
    final driverLat = driver.currentLatitude;
    final driverLng = driver.currentLongitude;
    final dropLat = order?.deliveryLatitude;
    final dropLng = order?.deliveryLongitude;

    // No active delivery → simple placeholder panel.
    if (order == null || dropLat == null || dropLng == null) {
      return Container(
        height: 150,
        decoration: BoxDecoration(
          color: const Color(0xFF12131C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1E1F2A)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_rounded, color: Color(0xFF2A2D3E), size: 40),
              SizedBox(height: 8),
              Text(
                'No active delivery',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final drop = LatLng(dropLat, dropLng);
    final points = <LatLng>[drop];
    final markers = <Marker>[
      Marker(
        point: drop,
        width: 40,
        height: 40,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 18),
        ),
      ),
    ];

    double? distanceKm;
    LatLng? driverPos;
    if (driverLat != null && driverLng != null) {
      driverPos = LatLng(driverLat, driverLng);
      points.add(driverPos);
      distanceKm =
          DeliveryFeeService.haversineKm(driverLat, driverLng, dropLat, dropLng);
      markers.add(
        Marker(
          point: driverPos,
          width: 34,
          height: 34,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.two_wheeler_rounded,
                color: Colors.white, size: 16),
          ),
        ),
      );
    }

    final etaMin = distanceKm != null ? (distanceKm / 25 * 60).round() : null;
    final center = _centerOf(points);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 200,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: distanceKm != null && distanceKm < 3 ? 14 : 12.5,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom |
                      InteractiveFlag.drag |
                      InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                appMapTileLayer(),
                if (driverPos != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [driverPos, drop],
                        strokeWidth: 4,
                        color: const Color(0xFF3B82F6),
                      ),
                    ],
                  ),
                MarkerLayer(markers: markers),
              ],
            ),
            // "Next delivery in X min" pill
            if (etaMin != null)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0B10).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF22C55E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Next delivery in',
                            style: TextStyle(
                                color: Color(0xFF9CA3AF), fontSize: 10),
                          ),
                          Text(
                            '$etaMin min',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            // Customer distance pill
            if (distanceKm != null)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0B10).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.home_rounded,
                          color: Color(0xFFEF4444), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Customer  ${distanceKm.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  LatLng _centerOf(List<LatLng> pts) {
    if (pts.isEmpty) return const LatLng(18.0179, -76.8099); // Kingston
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  // ── Current delivery card ──────────────────────────────────────────────────
  Widget _currentDeliveryCard(Order order) {
    final restaurant =
        ref.watch(restaurantByIdProvider(order.restaurantId)).valueOrNull;
    final earnings = order.deliveryFee + (order.driverTip ?? 0);
    final displayId = order.id.substring(0, 8).toUpperCase();

    // Stage: 0 at pickup, 1 picked up, 2 on the way, 3 delivered.
    final int stage;
    switch (order.status) {
      case 'delivered':
        stage = 3;
        break;
      case 'out_for_delivery':
        stage = 2;
        break;
      case 'picked_up':
        stage = 1;
        break;
      default:
        stage = 0;
    }

    String fmtTime(DateTime? t) {
      if (t == null) return '';
      final l = t.toLocal();
      final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
      final m = l.minute.toString().padLeft(2, '0');
      return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12131C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E1F2A)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: (restaurant?.imageUrl != null &&
                          restaurant!.imageUrl!.isNotEmpty)
                      ? Image.network(
                          restaurant.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _restThumbFallback(),
                        )
                      : _restThumbFallback(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Food',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      restaurant?.name ?? 'Restaurant',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            color: Color(0xFF6B7280), size: 13),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            order.deliveryAddress ?? 'Delivery address',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Color(0xFF9CA3AF), fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1B24),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Order #$displayId',
                        style: const TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Earnings',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                  ),
                  Text(
                    '${AppConstants.currencySymbol}${earnings.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Color(0xFF22C55E),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _statusActionButton(order, stage),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed('/active-deliveries'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF2A2D3E)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text('View Details',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFF1E1F2A)),
          const SizedBox(height: 14),
          Row(
            children: [
              _progressStep('Picked Up', stage >= 1 ? fmtTime(order.confirmedAt) : '',
                  Icons.check_rounded, stage >= 1, stage == 1),
              _progressLine(stage >= 2),
              _progressStep('On the Way',
                  stage == 2 ? 'ETA soon' : '', Icons.two_wheeler_rounded,
                  stage >= 2, stage == 2),
              _progressLine(stage >= 3),
              _progressStep('Deliver', fmtTime(order.estimatedDeliveryAt),
                  Icons.home_rounded, stage >= 3, false),
              _progressLine(stage >= 3),
              _progressStep('Completed', fmtTime(order.completedAt),
                  Icons.check_circle_rounded, stage >= 3, false),
            ],
          ),
        ],
      ),
    );
  }

  /// Primary action that advances the delivery status. The final "delivered"
  /// step routes to Active Deliveries, which handles PIN / cash-on-delivery /
  /// float via the audited completeDelivery flow — we never mark delivered here.
  Widget _statusActionButton(Order order, int stage) {
    final busy = _advancingOrderId == order.id;
    late final String label;
    late final IconData icon;
    late final VoidCallback onPressed;

    switch (order.status) {
      case 'ready':
        label = 'Confirm Pickup';
        icon = Icons.shopping_bag_rounded;
        onPressed = () => _advanceOrderStatus(order, AppConstants.orderPickedUp);
        break;
      case 'picked_up':
        label = 'Start Delivery — On the Way';
        icon = Icons.two_wheeler_rounded;
        onPressed =
            () => _advanceOrderStatus(order, AppConstants.orderOnTheWay);
        break;
      case 'out_for_delivery':
        label = 'Complete Delivery';
        icon = Icons.check_circle_rounded;
        onPressed = () => _completeDelivery(order);
        break;
      default:
        label = 'View Details';
        icon = Icons.chevron_right_rounded;
        onPressed = () => Navigator.of(context).pushNamed('/active-deliveries');
    }

    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton.icon(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF22C55E),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<void> _advanceOrderStatus(Order order, String toStatus) async {
    if (_advancingOrderId != null) return;
    setState(() => _advancingOrderId = order.id);
    try {
      await ref.read(orderServiceProvider).updateOrderStatus(order.id, toStatus);
      final driverId = _lastDriver?.id;
      if (driverId != null) {
        ref.invalidate(activeDeliveriesProvider(driverId));
      }
      if (mounted) {
        AppSnackbar.success(
          context,
          toStatus == AppConstants.orderPickedUp
              ? 'Marked as picked up'
              : 'On the way to the customer',
        );
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _advancingOrderId = null);
    }
  }

  /// Completes a delivery from the dashboard using the same audited flow as
  /// Active Deliveries (COD confirmation, student-delivery check, float via
  /// completeDelivery). Contactless orders still require PIN verification,
  /// which lives on the Active Deliveries screen, so those are routed there.
  Future<void> _completeDelivery(Order order) async {
    if (order.contactlessDelivery && order.deliveryOtpVerified != true) {
      AppSnackbar.info(
        context,
        'Contactless order — verify the customer\'s PIN in Order Details first.',
      );
      Navigator.of(context).pushNamed('/active-deliveries');
      return;
    }

    final isCash = order.paymentMethod == 'cash';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isCash ? 'Cash collected?' : 'Mark as Delivered?',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          isCash
              ? 'This is a Cash on Delivery order. Confirm you collected ${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(0)} from the customer.'
              : 'Confirm delivery of Order #${order.id.substring(0, 8).toUpperCase()}?',
          style: const TextStyle(color: Color(0xFF9CA3AF)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF9CA3AF))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(isCash
                ? 'Yes, collected ${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(0)}'
                : 'Yes, Delivered'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _advancingOrderId = order.id);
    try {
      final proceed =
          await ensureStudentDeliveryConfirmed(context, ref, order.id);
      if (!proceed) return;

      await ref.read(driverServiceProvider).completeDelivery(order.id);

      final driverId = _lastDriver?.id;
      if (driverId != null) {
        ref.invalidate(activeDeliveriesProvider(driverId));
        ref.invalidate(deliveryHistoryProvider(driverId));
        ref.invalidate(driverStatsProvider(driverId));
      }
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) ref.invalidate(driverProfileProvider(userId));
      if (mounted) AppSnackbar.success(context, 'Delivery completed!');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _advancingOrderId = null);
    }
  }

  Widget _restThumbFallback() {
    return Container(
      color: const Color(0xFF1A1B24),
      alignment: Alignment.center,
      child: const Icon(Icons.restaurant_rounded,
          color: Color(0xFF4B5563), size: 26),
    );
  }

  Widget _progressStep(
    String label,
    String time,
    IconData icon,
    bool done,
    bool current,
  ) {
    final active = done;
    final color =
        active ? const Color(0xFF22C55E) : const Color(0xFF2A2D3E);
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: active ? color : const Color(0xFF1A1B24),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
            ),
            child: Icon(
              icon,
              color: active ? Colors.white : const Color(0xFF4B5563),
              size: 17,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF6B7280),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (time.isNotEmpty)
            Text(
              time,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: current
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF6B7280),
                fontSize: 9.5,
              ),
            ),
        ],
      ),
    );
  }

  Widget _progressLine(bool active) {
    return Container(
      width: 16,
      height: 2,
      margin: const EdgeInsets.only(bottom: 26),
      color: active ? const Color(0xFF22C55E) : const Color(0xFF2A2D3E),
    );
  }

  // ── Quick actions ──────────────────────────────────────────────────────────
  Widget _quickActions(Driver driver) {
    final availableCount = ref
            .watch(availableOrdersProvider((
              driverId: driver.id,
              lat: driver.currentLatitude,
              lng: driver.currentLongitude,
            )))
            .valueOrNull
            ?.length ??
        0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _quickAction(
                Icons.map_rounded,
                'View Map',
                'Your current route',
                const Color(0xFF22C55E),
                () => Navigator.of(context).pushNamed('/active-deliveries'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _quickAction(
                Icons.inbox_rounded,
                'Available Orders',
                availableCount == 1
                    ? '1 new order'
                    : '$availableCount new orders',
                const Color(0xFF7C3AED),
                () => Navigator.of(context).pushNamed('/available-orders'),
                badge: availableCount > 0 ? '$availableCount' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _quickAction(
                Icons.account_balance_wallet_rounded,
                'Earnings',
                "Today's summary",
                const Color(0xFFF59E0B),
                () => Navigator.of(context)
                    .pushNamed('/driver-earnings-advanced'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _quickAction(
                Icons.headset_mic_rounded,
                'Support',
                'Need help?',
                const Color(0xFF2563EB),
                () => Navigator.of(context).pushNamed('/contact-support'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickAction(
    IconData icon,
    String title,
    String subtitle,
    Color color,
    VoidCallback onTap, {
    String? badge,
  }) {
    return Material(
      color: const Color(0xFF12131C),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E1F2A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 21),
                  ),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.rectangle,
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const Icon(Icons.chevron_right_rounded,
                        color: Color(0xFF4B5563), size: 18),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
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
                child: Icon(
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
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1B24),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2D3E)),
        ),
        child: Icon(icon, color: const Color(0xFF9CA3AF), size: 19),
      ),
    );
  }
}
