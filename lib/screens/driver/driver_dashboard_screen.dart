import 'dart:async';
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
import '../../config/app_constants.dart';
import '../shared/ai_voice_screen.dart';
import '../../modules/packages/screens/driver/driver_packages_screen.dart';
import 'driver_verification_screen.dart';

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
  final Set<String> _togglingServices = {};
  bool _serviceTopicsInitialized = false;

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

  Future<void> _toggleService(
    Driver driver,
    String currentUserId,
    String service,
    bool enable,
  ) async {
    final services = List<String>.from(
      driver.activeServices ?? ['food_delivery'],
    );
    if (enable) {
      if (!services.contains(service)) services.add(service);
    } else {
      services.remove(service);
    }
    // Guard: driver must be online to enable any service
    if (enable && !driver.isAvailable) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1B24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF2A2D3E)),
            ),
            icon: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.power_settings_new_rounded,
                color: Colors.orange,
                size: 28,
              ),
            ),
            title: const Text(
              'You\'re Offline',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            content: const Text(
              'Go online first before enabling any services. Toggle the Online / Offline switch on your dashboard.',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Got it',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return;
    }

    setState(() => _togglingServices.add(service));
    try {
      await ref
          .read(driverServiceProvider)
          .updateDriverActiveServices(driver.id, services);
      // Refresh driver profile immediately after DB write — don't wait on FCM
      ref.invalidate(driverProfileProvider(currentUserId));
      // FCM subscription is best-effort; fire and forget so it can't block the UI
      final ns = NotificationService();
      final topic = _serviceTopics[service]!;
      if (enable) {
        unawaited(ns.subscribeToTopic(topic));
      } else {
        unawaited(ns.unsubscribeFromTopic(topic));
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _togglingServices.remove(service));
    }
  }

  bool _canDoRides(Driver driver) {
    final t = (driver.vehicleType ?? '').toLowerCase().trim();
    return t != 'bicycle' && t != 'bike' && t != 'motorcycle' && t != 'scooter';
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
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _creatingProfile = false);
    }
  }

  String _formatPeakHours() {
    String fmt(int h) {
      if (h == 0) return '12 am';
      if (h == 12) return '12 pm';
      return h < 12 ? '$h am' : '${h - 12} pm';
    }

    final w1 =
        '${fmt(AppConstants.peakHoursStart)}–${fmt(AppConstants.peakHoursEnd)}';
    final w2 =
        '${fmt(AppConstants.peakHoursStart2)}–${fmt(AppConstants.peakHoursEnd2)}';
    return 'Peak hours: $w1 & $w2';
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

    // ── Verification gate ─────────────────────────────────────────────────────
    // Drivers who are not yet approved are shown a status screen instead of
    // the full dashboard. Existing drivers without driver_status set ('draft')
    // keep normal access so live production drivers are not disrupted.
    if (driver.driverStatus != 'approved' && driver.driverStatus != 'draft') {
      return _buildVerificationGate(driver);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: _buildDashboard(driver, authState, currentUserId),
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
        message = 'Your application has been submitted and is being reviewed by our team. This typically takes 1–3 business days. You will be notified once approved.';
        buttonLabel = 'View Application Status';
        onButton = () => Navigator.pushNamed(context, '/driver-application-status');
      case 'rejected':
        icon = Icons.cancel_outlined;
        color = Colors.redAccent;
        title = 'Application Rejected';
        message = driver.rejectionReason?.isNotEmpty == true
            ? 'Your application was rejected: ${driver.rejectionReason}'
            : 'Your application was not approved. Please re-upload your documents and resubmit.';
        buttonLabel = 'Re-upload Documents';
        onButton = () => Navigator.pushNamed(context, '/driver-application-status');
      case 'suspended':
        icon = Icons.block_rounded;
        color = Colors.red;
        title = 'Account Suspended';
        message = 'Your driver account has been suspended. Please contact support for assistance.';
        buttonLabel = 'Contact Support';
        onButton = () => Navigator.pushNamed(context, '/driver-application-status');
      case 'expired_documents':
        icon = Icons.warning_amber_rounded;
        color = Colors.amber;
        title = 'Documents Expired';
        message = 'One or more of your verification documents have expired. Please re-upload valid documents to continue driving.';
        buttonLabel = 'Update Documents';
        onButton = () => Navigator.pushNamed(context, '/driver-application-status');
      default:
        icon = Icons.edit_document;
        color = Colors.white54;
        title = 'Complete Verification';
        message = 'Complete your driver verification to start accepting deliveries on our platform.';
        buttonLabel = 'Start Verification';
        onButton = () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DriverVerificationScreen(driver: driver)),
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
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.6),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(buttonLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  final userId = ref.read(currentUserIdProvider);
                  if (userId != null) ref.invalidate(driverProfileProvider(userId));
                },
                child: const Text('Refresh Status', style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(
    Driver driver,
    dynamic authState,
    String currentUserId,
    bool isOnline,
    double balance,
  ) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF0A0B10)),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFF1A1D2E),
                      backgroundImage: authState.user?.profileImageUrl != null
                          ? NetworkImage(authState.user!.profileImageUrl!)
                          : null,
                      child: authState.user?.profileImageUrl == null
                          ? const Icon(
                              Icons.person,
                              color: Colors.white54,
                              size: 22,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(),
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          authState.user?.name?.split(' ').first ?? 'Driver',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _GlassIconButton(
                    icon: Icons.smart_toy_outlined,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AiVoiceScreen(role: 'driver'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _GlassIconButton(
                    icon: Icons.tune_rounded,
                    onTap: () =>
                        Navigator.of(context).pushNamed('/driver-profile'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Hero card ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF12131C),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOnline
                        ? const Color(0xFF22C55E).withValues(alpha: 0.35)
                        : const Color(0xFF1E1F2A),
                  ),
                  boxShadow: isOnline
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF22C55E,
                            ).withValues(alpha: 0.07),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    // Balance + online pill
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Wallet Balance',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${AppConstants.currencySymbol}${balance.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _togglingAvailability
                            ? const SizedBox(
                                width: 80,
                                height: 36,
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF22C55E),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              )
                            : GestureDetector(
                                onTap: () async {
                                  setState(() => _togglingAvailability = true);
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
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isOnline
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFF1A1B24),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: isOnline
                                          ? const Color(0xFF22C55E)
                                          : const Color(0xFF2A2D3E),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedBuilder(
                                        animation: _pulseController,
                                        builder: (_, __) => Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isOnline
                                                ? Colors.white.withValues(
                                                    alpha:
                                                        0.6 +
                                                        _pulseController.value *
                                                            0.4,
                                                  )
                                                : const Color(0xFF4B5563),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isOnline ? 'Online' : 'Offline',
                                        style: TextStyle(
                                          color: isOnline
                                              ? Colors.white
                                              : const Color(0xFF6B7280),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ],
                    ),

                    const SizedBox(height: 18),
                    const Divider(height: 1, color: Color(0xFF1E1F2A)),
                    const SizedBox(height: 16),

                    // Mini stats row
                    Row(
                      children: [
                        _MiniStat(
                          label: 'Trips',
                          value: '${driver.completedDeliveries ?? 0}',
                          color: const Color(0xFF22C55E),
                        ),
                        const _VertDivider(),
                        _MiniStat(
                          label: 'Rating',
                          value: driver.rating != null && driver.rating! > 0
                              ? driver.rating!.toStringAsFixed(1)
                              : '—',
                          color: const Color(0xFFFBBF24),
                        ),
                        const _VertDivider(),
                        _MiniStat(
                          label: 'Success',
                          value: _completionRate(driver),
                          color: const Color(0xFF8B5CF6),
                        ),
                        const _VertDivider(),
                        _MiniStat(
                          label: 'Status',
                          value: driver.isVerified == true
                              ? 'Verified'
                              : 'Pending',
                          color: driver.isVerified == true
                              ? const Color(0xFF14B8A6)
                              : const Color(0xFF6B7280),
                        ),
                      ],
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

  Widget _buildDashboard(
    Driver driver,
    dynamic authState,
    String currentUserId,
  ) {
    ref.watch(driverEarningsRealtimeProvider(driver.id));

    if (!_serviceTopicsInitialized) {
      _serviceTopicsInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncFcmTopics(driver.activeServices ?? ['food_delivery']),
      );
    }

    final isOnline = driver.isAvailable;
    final activeServices = driver.activeServices ?? ['food_delivery'];
    final balance = ((driver.totalEarnings ?? 0) - (driver.totalPaidOut ?? 0))
        .clamp(0.0, double.infinity);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── HERO ────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _buildHero(
            driver,
            authState,
            currentUserId,
            isOnline,
            balance,
          ),
        ),

        // ── ACTIVE SERVICES ─────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('Active Services'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ServiceCard(
                        icon: Icons.restaurant_rounded,
                        label: 'Food',
                        color: const Color(0xFFF97316),
                        isEnabled: activeServices.contains('food_delivery'),
                        isLoading: _togglingServices.contains('food_delivery'),
                        locked:
                            !isOnline &&
                            !activeServices.contains('food_delivery'),
                        onToggle: (v) => _toggleService(
                          driver,
                          currentUserId,
                          'food_delivery',
                          v,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ServiceCard(
                        icon: Icons.inventory_2_rounded,
                        label: 'Packages',
                        color: const Color(0xFF7C3AED),
                        isEnabled: activeServices.contains('package_delivery'),
                        isLoading: _togglingServices.contains(
                          'package_delivery',
                        ),
                        locked:
                            !isOnline &&
                            !activeServices.contains('package_delivery'),
                        onToggle: (v) => _toggleService(
                          driver,
                          currentUserId,
                          'package_delivery',
                          v,
                        ),
                      ),
                    ),
                    if (_canDoRides(driver)) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ServiceCard(
                          icon: Icons.directions_car_rounded,
                          label: 'Rides',
                          color: const Color(0xFF22C55E),
                          isEnabled: activeServices.contains('ride_sharing'),
                          isLoading: _togglingServices.contains('ride_sharing'),
                          locked:
                              !isOnline &&
                              !activeServices.contains('ride_sharing'),
                          onToggle: (v) => _toggleService(
                            driver,
                            currentUserId,
                            'ride_sharing',
                            v,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),

        // ── TIER BADGE ───────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Consumer(
              builder: (context, ref, _) {
                final stats = ref
                    .watch(driverStatsProvider(driver.id))
                    .valueOrNull;
                if (stats == null) return const SizedBox.shrink();
                final Color c;
                switch (stats.tier) {
                  case 'elite':
                    c = const Color(0xFFE879F9);
                    break;
                  case 'gold':
                    c = const Color(0xFFFBBF24);
                    break;
                  case 'silver':
                    c = const Color(0xFF94A3B8);
                    break;
                  default:
                    c = const Color(0xFFD97706);
                }
                return GestureDetector(
                  onTap: () =>
                      Navigator.of(context).pushNamed('/driver-performance'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.withValues(alpha: 0.22)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          stats.tierEmoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${stats.tierLabel} Driver',
                                style: TextStyle(
                                  color: c,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'Score ${stats.score.toStringAsFixed(0)}/100'
                                '${stats.bonusMultiplier > 1 ? "  ·  +${((stats.bonusMultiplier - 1) * 100).toStringAsFixed(0)}% bonus" : ""}',
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: c, size: 18),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // ── QUICK ACTIONS ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: const _SectionLabel('Quick Actions'),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            delegate: SliverChildListDelegate([
              _ActionCard(
                icon: Icons.search_rounded,
                label: 'Find Orders',
                color: AppTheme.primaryColor,
                onTap: () =>
                    Navigator.of(context).pushNamed('/available-orders'),
              ),
              _ActionCard(
                icon: Icons.local_shipping_rounded,
                label: 'Active',
                color: const Color(0xFF14B8A6),
                onTap: () =>
                    Navigator.of(context).pushNamed('/active-deliveries'),
              ),
              _ActionCard(
                icon: Icons.history_rounded,
                label: 'History',
                color: const Color(0xFF3B82F6),
                onTap: () =>
                    Navigator.of(context).pushNamed('/delivery-history'),
              ),
              _ActionCard(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Wallet',
                color: const Color(0xFF10B981),
                onTap: () => Navigator.of(context).pushNamed('/driver-wallet'),
              ),
              if (_canDoRides(driver))
                _ActionCard(
                  icon: Icons.directions_car_rounded,
                  label: 'Rides',
                  color: const Color(0xFF22C55E),
                  onTap: () =>
                      Navigator.of(context).pushNamed('/rides/driver/mode'),
                ),
              _ActionCard(
                icon: Icons.inventory_2_rounded,
                label: 'Packages',
                color: const Color(0xFF7C3AED),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DriverPackagesScreen(),
                  ),
                ),
              ),
            ]),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.95,
            ),
          ),
        ),

        // ── EXPLORE ──────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: const _SectionLabel('Explore'),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF12131C),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1E1F2A)),
              ),
              child: Column(
                children: [
                  _MenuRow(
                    icon: Icons.payments_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    title: 'Earnings & Analytics',
                    subtitle: 'Income, tips & payouts',
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed('/driver-earnings-advanced'),
                    divider: true,
                  ),
                  _MenuRow(
                    icon: Icons.map_rounded,
                    iconColor: const Color(0xFFEF4444),
                    title: 'Demand Heatmap',
                    subtitle: 'Find surge zones nearby',
                    onTap: () =>
                        Navigator.of(context).pushNamed('/driver-heatmap'),
                    divider: true,
                  ),
                  _MenuRow(
                    icon: Icons.insights_rounded,
                    iconColor: const Color(0xFF22C55E),
                    title: 'Performance & Tier',
                    subtitle: 'Score, tier & smart tips',
                    onTap: () =>
                        Navigator.of(context).pushNamed('/driver-performance'),
                    divider: true,
                  ),
                  _MenuRow(
                    icon: Icons.emoji_events_rounded,
                    iconColor: const Color(0xFF6366F1),
                    title: 'Leaderboard',
                    subtitle: 'Your ranking among drivers',
                    onTap: () =>
                        Navigator.of(context).pushNamed('/driver-leaderboard'),
                    divider: true,
                  ),
                  _MenuRow(
                    icon: Icons.card_giftcard_rounded,
                    iconColor: const Color(0xFF10B981),
                    title: 'Refer a Driver',
                    subtitle: 'Earn a bonus for every referral',
                    onTap: () =>
                        Navigator.of(context).pushNamed('/driver-referral'),
                    divider: false,
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── PEAK HOURS TIP ───────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_rounded,
                    color: AppTheme.primaryColor,
                    size: 15,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_formatPeakHours()} — Stay online for more orders.',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
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

// ── Section Label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
  }
}

// ── Mini Stat ────────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Vertical Divider ─────────────────────────────────────────────────────────

class _VertDivider extends StatelessWidget {
  const _VertDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: const Color(0xFF1E1F2A));
  }
}

// ── Service Card ─────────────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isEnabled;
  final bool isLoading;
  final bool locked;
  final ValueChanged<bool> onToggle;

  const _ServiceCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.isEnabled,
    required this.isLoading,
    required this.onToggle,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : () => onToggle(!isEnabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: isEnabled
              ? color.withValues(alpha: 0.08)
              : const Color(0xFF12131C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isEnabled
                ? color.withValues(alpha: 0.35)
                : const Color(0xFF1E1F2A),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isEnabled
                    ? color.withValues(alpha: 0.15)
                    : const Color(0xFF1A1B24),
                borderRadius: BorderRadius.circular(10),
              ),
              child: isLoading
                  ? Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: color,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : locked
                  ? const Icon(
                      Icons.lock_rounded,
                      color: Color(0xFF4B5563),
                      size: 16,
                    )
                  : Icon(
                      icon,
                      color: isEnabled ? color : const Color(0xFF4B5563),
                      size: 18,
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: locked
                    ? const Color(0xFF4B5563)
                    : isEnabled
                    ? Colors.white
                    : const Color(0xFF6B7280),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            // Mini toggle pill
            Container(
              width: 28,
              height: 14,
              decoration: BoxDecoration(
                color: isEnabled ? color : const Color(0xFF2A2D3E),
                borderRadius: BorderRadius.circular(7),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: isEnabled
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action Card ──────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF12131C),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E1F2A)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Menu Row ─────────────────────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool divider;

  const _MenuRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.divider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 18),
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
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF4B5563),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (divider)
          const Divider(
            height: 1,
            indent: 68,
            endIndent: 16,
            color: Color(0xFF1E1F2A),
          ),
      ],
    );
  }
}
