import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../models/order_model.dart';
import '../../utils/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../shared/bank_info_screen.dart';
import '../shared/payout_request_screen.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';
import 'restaurant_offer_screen.dart';
import 'restaurant_onboarding_screen.dart';
import '../../models/restaurant_model.dart';

class RestaurantDashboardScreen extends ConsumerStatefulWidget {
  const RestaurantDashboardScreen({super.key});

  @override
  ConsumerState<RestaurantDashboardScreen> createState() =>
      _RestaurantDashboardScreenState();
}

class _RestaurantDashboardScreenState
    extends ConsumerState<RestaurantDashboardScreen> {
  bool _togglingAvailability = false;
  bool _creatingRestaurant = false;
  bool _secondaryReady = false;

  // Setup form
  final _nameController = TextEditingController();
  final _cuisineController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _setupFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Defer non-visible work (realtime subscription, KPI/orders watch)
    // until after the hero header has painted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _secondaryReady = true);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cuisineController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(authNotifierProvider.notifier).signOut();
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  Future<void> _createRestaurant(String ownerId) async {
    if (!_setupFormKey.currentState!.validate()) return;
    setState(() => _creatingRestaurant = true);
    try {
      final restaurantService = ref.read(restaurantServiceProvider);
      await restaurantService.createRestaurant(
        ownerId: ownerId,
        name: _nameController.text.trim(),
        cuisineType: _cuisineController.text.trim().isEmpty
            ? null
            : _cuisineController.text.trim(),
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
      );
      ref.invalidate(restaurantByOwnerProvider(ownerId));
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _creatingRestaurant = false);
    }
  }

  Future<void> _toggleAvailability(
    String restaurantId,
    bool currentIsOpen,
  ) async {
    setState(() => _togglingAvailability = true);
    try {
      final restaurantService = ref.read(restaurantServiceProvider);
      await restaurantService.updateRestaurant(
        restaurantId: restaurantId,
        isOpen: !currentIsOpen,
      );
      final currentUserId = ref.read(currentUserIdProvider);
      if (currentUserId != null) {
        ref.invalidate(restaurantByOwnerProvider(currentUserId));
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _togglingAvailability = false);
      }
    }
  }

  Future<void> _refresh() async {
    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId != null) {
      ref.invalidate(restaurantByOwnerProvider(currentUserId));
      ref.invalidate(ownerAllOrdersProvider(currentUserId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

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
      return const Scaffold(body: AppLoadingIndicator());
    }

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(currentUserId));

    return restaurantAsync.when(
      loading: () => const Scaffold(
        body: AppLoadingIndicator(message: 'Loading restaurant...'),
      ),
      error: (error, stack) => Scaffold(
        body: AppErrorState(
          message: friendlyError(error),
          onRetry: () {
            ref.invalidate(restaurantByOwnerProvider(currentUserId));
          },
        ),
      ),
      data: (restaurant) {
        if (restaurant == null) {
          return _buildSetupRestaurant(currentUserId);
        }

        // Show rejection screen so they can update & resubmit.
        if (restaurant.status == 'rejected') {
          return _buildVerificationGate(restaurant);
        }

        if (restaurant.status == 'draft' && !restaurant.isVerified) {
          // bankName is required by the onboarding form validator, so it's only
          // non-null if the restaurant completed and submitted the 5-step form.
          // onboardingStep >= 3 catches future submissions where the step is saved.
          final hasSubmitted =
              (restaurant.bankName != null && restaurant.bankName!.isNotEmpty) ||
              restaurant.onboardingStep >= 3;
          if (hasSubmitted) {
            return _buildPendingReview(restaurant);
          }
          return _buildVerificationGate(restaurant);
        }

        // Legacy status values.
        if (restaurant.status == 'pending_review' ||
            restaurant.status == 'under_review') {
          return _buildPendingReview(restaurant);
        }

        // Defer realtime subscription and orders fetch until after first paint.
        final ordersAsync = _secondaryReady
            ? ref.watch(ownerAllOrdersProvider(currentUserId))
            : const AsyncValue<List<Order>>.loading();
        if (_secondaryReady) {
          ref.watch(ownerOrderRealtimeProvider(currentUserId));
        }

        return _buildApprovedDashboard(
          restaurant,
          authState,
          currentUserId,
          ordersAsync,
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Approved dashboard — mockup layout (HotBite Restaurant Partner)
  // ═══════════════════════════════════════════════════════════════════════════

  static const _bg = Color(0xFF0B1120);
  static const _card = Color(0xFF131B2E);
  static const _cardBorder = Color(0xFF23304A);

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Widget _buildApprovedDashboard(
    Restaurant restaurant,
    dynamic authState,
    String currentUserId,
    AsyncValue<List<Order>> ordersAsync,
  ) {
    final orders = ordersAsync.valueOrNull ?? const <Order>[];

    // ── Metrics ──────────────────────────────────────────────────────────────
    int cNew = 0, cPrep = 0, cOfd = 0, cDelivered = 0, cCancelled = 0;
    double totalSales = 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final o in orders) {
      switch (o.status) {
        case 'pending':
        case 'confirmed':
          cNew++;
          break;
        case 'preparing':
          cPrep++;
          break;
        case 'ready':
        case 'picked_up':
        case 'out_for_delivery':
          cOfd++;
          break;
        case 'delivered':
          cDelivered++;
          break;
        case 'cancelled':
          cCancelled++;
          break;
      }
      if (o.status != 'cancelled') totalSales += o.subtotal;
    }
    final totalOrders = orders.length;

    // Avg prep/turnaround for delivered orders with timestamps.
    final durations = <int>[];
    for (final o in orders) {
      if (o.completedAt != null) {
        final start = o.confirmedAt ?? o.orderedAt;
        final mins = o.completedAt!.difference(start).inMinutes;
        if (mins > 0 && mins < 600) durations.add(mins);
      }
    }
    final avgPrep = durations.isEmpty
        ? null
        : (durations.reduce((a, b) => a + b) / durations.length).round();

    // Last 7 days sales for the bar chart.
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final daySales = List<double>.filled(7, 0);
    for (final o in orders) {
      if (o.status == 'cancelled') continue;
      final d = DateTime(o.orderedAt.year, o.orderedAt.month, o.orderedAt.day);
      final idx = days.indexWhere((x) => x == d);
      if (idx >= 0) daySales[idx] += o.subtotal;
    }

    final isOpen = restaurant.isOpen;

    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: _bottomNav(),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppTheme.primaryColor,
        backgroundColor: _card,
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.zero,
          children: [
            _dashHeader(restaurant, authState),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _dashHero(restaurant, authState, isOpen),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _kpiRow(
                totalOrders,
                totalSales,
                avgPrep,
                restaurant.rating,
                restaurant.reviewCount ?? 0,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _salesCard(daySales, days),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _orderStatusCard(
                cNew,
                cPrep,
                cOfd,
                cDelivered,
                cCancelled,
                totalOrders,
              ),
            ),
            const SizedBox(height: 18),
            _recentOrders(orders, ordersAsync, currentUserId),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _quickActionsCard(),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _growBanner(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _dashHeader(Restaurant restaurant, dynamic authState) {
    return Container(
      color: const Color(0xFF0A0F1C),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(
            children: [
              Image.asset(
                'assets/images/app_icon.png',
                width: 34,
                height: 34,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.restaurant_rounded,
                  color: Color(0xFFF97316),
                  size: 28,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'HotBite',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Restaurant Partner',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Store chip
              Container(
                constraints: const BoxConstraints(maxWidth: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _cardBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: (restaurant.imageUrl != null &&
                              restaurant.imageUrl!.isNotEmpty)
                          ? Image.network(restaurant.imageUrl!,
                              width: 26, height: 26, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _storeIcon())
                          : _storeIcon(),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            restaurant.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            restaurant.isOpen ? 'Open' : 'Closed',
                            style: TextStyle(
                              color: restaurant.isOpen
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF94A3B8),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _headerIcon(Icons.notifications_none_rounded,
                  () => Navigator.of(context).pushNamed('/notifications')),
              const SizedBox(width: 6),
              _headerIcon(Icons.person_rounded, _signOut),
            ],
          ),
        ),
      ),
    );
  }

  Widget _storeIcon() => Container(
        width: 26,
        height: 26,
        color: const Color(0xFF23304A),
        child: const Icon(Icons.storefront_rounded,
            color: Color(0xFF94A3B8), size: 15),
      );

  Widget _headerIcon(IconData icon, VoidCallback onTap) {
    return Material(
      color: _card,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: const Color(0xFFCBD5E1), size: 20),
        ),
      ),
    );
  }

  // ── Hero greeting + open toggle ────────────────────────────────────────────
  Widget _dashHero(Restaurant restaurant, dynamic authState, bool isOpen) {
    final name = (authState.user?.name as String?)?.split(' ').first ?? 'Chef';
    final hours = (restaurant.openingTime != null &&
            restaurant.closingTime != null)
        ? 'Today: ${restaurant.openingTime} – ${restaurant.closingTime}'
        : 'Set your opening hours';
    return Container(
      height: 150,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (restaurant.imageUrl != null && restaurant.imageUrl!.isNotEmpty)
            Image.network(restaurant.imageUrl!, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: _card))
          else
            Image.asset('assets/images/roles/food.jpg', fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: _card)),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.85),
                  Colors.black.withValues(alpha: 0.35),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_greeting()},',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                          Text(
                            'Chef $name!',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _openToggle(restaurant, isOpen),
                  ],
                ),
                const Spacer(),
                Text(
                  "Here's your restaurant overview for today.",
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                Text(
                  hours,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _openToggle(Restaurant restaurant, bool isOpen) {
    return GestureDetector(
      onTap: _togglingAvailability
          ? null
          : () => _toggleAvailability(restaurant.id, isOpen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isOpen
              ? const Color(0xFF22C55E).withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isOpen ? const Color(0xFF22C55E) : const Color(0xFF64748B),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_togglingAvailability)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOpen
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF94A3B8),
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 7),
            Text(
              isOpen ? 'Open' : 'Closed',
              style: TextStyle(
                color: isOpen ? const Color(0xFF22C55E) : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── KPI row (2×2) ──────────────────────────────────────────────────────────
  Widget _kpiRow(int totalOrders, double totalSales, int? avgPrep,
      double? rating, int reviewCount) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                Icons.shopping_bag_rounded,
                const Color(0xFF22C55E),
                'Total Orders',
                '$totalOrders',
                null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                Icons.attach_money_rounded,
                const Color(0xFFF59E0B),
                'Total Sales',
                '${AppConstants.currencySymbol}${totalSales.toStringAsFixed(0)}',
                null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _statCard(
                Icons.timer_rounded,
                const Color(0xFF8B5CF6),
                'Avg Prep Time',
                avgPrep == null ? '—' : '$avgPrep min',
                null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                Icons.star_rounded,
                const Color(0xFF3B82F6),
                'Customer Rating',
                (rating != null && rating > 0)
                    ? rating.toStringAsFixed(1)
                    : 'New',
                reviewCount > 0 ? '($reviewCount reviews)' : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard(IconData icon, Color color, String label, String value,
      String? sub) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(label,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          if (sub != null)
            Text(sub,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5)),
        ],
      ),
    );
  }

  // ── Sales overview (bar chart) ─────────────────────────────────────────────
  Widget _salesCard(List<double> daySales, List<DateTime> days) {
    final total = daySales.fold<double>(0, (a, b) => a + b);
    const dowNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final wLabels = days.map((d) => dowNames[d.weekday - 1]).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Sales Overview',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0F1C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _cardBorder),
                ),
                child: const Text('Last 7 days',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${AppConstants.currencySymbol}${total.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: CustomPaint(
              size: const Size(double.infinity, 140),
              painter: _BarChartPainter(
                values: daySales,
                labels: wLabels,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Order status (donut) ───────────────────────────────────────────────────
  Widget _orderStatusCard(int cNew, int cPrep, int cOfd, int cDelivered,
      int cCancelled, int total) {
    final segs = <_DonutSeg>[
      _DonutSeg('New', cNew, const Color(0xFF22C55E)),
      _DonutSeg('Preparing', cPrep, const Color(0xFFF59E0B)),
      _DonutSeg('Out for Delivery', cOfd, const Color(0xFF3B82F6)),
      _DonutSeg('Delivered', cDelivered, const Color(0xFF8B5CF6)),
      _DonutSeg('Cancelled', cCancelled, const Color(0xFFEF4444)),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Order Status',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(
                  painter: _DonutPainter(segs),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$total',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800)),
                        const Text('Total',
                            style: TextStyle(
                                color: Color(0xFF94A3B8), fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: segs
                      .map((s) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                      color: s.color, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(s.label,
                                      style: const TextStyle(
                                          color: Color(0xFFCBD5E1),
                                          fontSize: 12.5)),
                                ),
                                Text('${s.value}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Recent orders ──────────────────────────────────────────────────────────
  Widget _recentOrders(List<Order> orders, AsyncValue<List<Order>> ordersAsync,
      String currentUserId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Text('Recent Orders',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    Navigator.of(context).pushNamed('/restaurant-orders'),
                child: const Text('View All →',
                    style: TextStyle(
                        color: Color(0xFF60A5FA),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ordersAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _emptyCard('Failed to load orders'),
            data: (list) {
              if (list.isEmpty) return _emptyCard('No orders yet');
              return Container(
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _cardBorder),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < list.take(5).length; i++) ...[
                      if (i > 0)
                        const Divider(
                            height: 1, color: _cardBorder, indent: 14, endIndent: 14),
                      _recentTile(list[i]),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _emptyCard(String msg) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorder),
        ),
        child: Center(
          child: Text(msg,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
        ),
      );

  Widget _recentTile(Order order) {
    final first = order.items.isNotEmpty ? order.items.first : null;
    final itemLabel = first == null
        ? 'Order'
        : '${first.itemName} x ${first.quantity}';
    final id = order.id.substring(0, 6).toUpperCase();
    final time = _fmtTime(order.orderedAt);
    final color = _statusColor(order.status);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed('/restaurant-orders'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0F1C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.restaurant_rounded,
                    color: Color(0xFF64748B), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('#$id',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    Text(itemLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(order.status),
                  style: TextStyle(
                      color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(time,
                      style: const TextStyle(
                          color: Color(0xFF94A3B8), fontSize: 11)),
                  Text(
                    '${AppConstants.currencySymbol}${order.subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtTime(DateTime t) {
    final l = t.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'delivered':
        return const Color(0xFF8B5CF6);
      case 'out_for_delivery':
      case 'picked_up':
      case 'ready':
        return const Color(0xFF3B82F6);
      case 'preparing':
      case 'confirmed':
        return const Color(0xFFF59E0B);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF22C55E);
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'picked_up':
        return 'Picked Up';
      case 'pending':
        return 'New';
      default:
        return s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
    }
  }

  // ── Quick actions ──────────────────────────────────────────────────────────
  Widget _quickActionsCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text('Quick Actions',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ),
        Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            children: [
              _qaRow(Icons.restaurant_menu_rounded, const Color(0xFFF59E0B),
                  'Manage Menu', 'Add / Edit menu items',
                  () => Navigator.of(context).pushNamed('/menu-management'),
                  divider: true),
              _qaRow(Icons.inventory_2_rounded, const Color(0xFF22C55E),
                  'Update Inventory', 'Track stock levels',
                  () => Navigator.of(context).pushNamed('/grocery-management'),
                  divider: true),
              _qaRow(Icons.receipt_long_rounded, const Color(0xFF3B82F6),
                  'View Orders', 'See all incoming orders',
                  () => Navigator.of(context).pushNamed('/restaurant-orders'),
                  divider: true),
              _qaRow(Icons.campaign_rounded, const Color(0xFF8B5CF6),
                  'Marketing Tools', 'Promote your restaurant',
                  () => Navigator.of(context).pushNamed('/restaurant-offer'),
                  divider: true),
              _qaRow(Icons.payments_rounded, const Color(0xFF06B6D4),
                  'Payouts', 'View earnings & transactions',
                  () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const PayoutRequestScreen(role: 'restaurant'),
                        ),
                      ),
                  divider: false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _qaRow(IconData icon, Color color, String title, String subtitle,
      VoidCallback onTap,
      {required bool divider}) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                        Text(subtitle,
                            style: const TextStyle(
                                color: Color(0xFF94A3B8), fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: Color(0xFF64748B), size: 20),
                ],
              ),
            ),
          ),
        ),
        if (divider)
          const Divider(
              height: 1, color: _cardBorder, indent: 70, endIndent: 14),
      ],
    );
  }

  // ── Grow banner ────────────────────────────────────────────────────────────
  Widget _growBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.campaign_rounded,
                color: Color(0xFFF97316), size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Grow Your Business',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('Enable promotions, update your menu, reach more customers.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: const Color(0xFFF97316),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () =>
                  Navigator.of(context).pushNamed('/restaurant-offer'),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────
  Widget _bottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0F1C),
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.home_rounded, 'Dashboard',
                  active: true, onTap: () {}),
              _navItem(Icons.receipt_long_rounded, 'Orders',
                  onTap: () =>
                      Navigator.of(context).pushNamed('/restaurant-orders')),
              _navItem(Icons.restaurant_menu_rounded, 'Menu',
                  onTap: () =>
                      Navigator.of(context).pushNamed('/menu-management')),
              _navItem(Icons.inventory_2_rounded, 'Inventory',
                  onTap: () =>
                      Navigator.of(context).pushNamed('/grocery-management')),
              _navItem(Icons.menu_rounded, 'More', onTap: _showMoreSheet),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label,
      {bool active = false, required VoidCallback onTap}) {
    final color =
        active ? const Color(0xFFF97316) : const Color(0xFF64748B);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 23),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 10.5,
                      fontWeight:
                          active ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  // "More" holds every remaining function so nothing is lost.
  void _showMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        Widget row(IconData i, Color c, String t, VoidCallback tap) => ListTile(
              leading: CircleAvatar(
                backgroundColor: c.withValues(alpha: 0.15),
                child: Icon(i, color: c, size: 20),
              ),
              title: Text(t,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFF64748B)),
              onTap: () {
                Navigator.pop(ctx);
                tap();
              },
            );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                row(Icons.analytics_rounded, const Color(0xFF10B981),
                    'Analytics',
                    () => Navigator.of(context)
                        .pushNamed('/restaurant-analytics')),
                row(Icons.local_grocery_store_rounded,
                    const Color(0xFF14B8A6), 'Grocery Management',
                    () => Navigator.of(context)
                        .pushNamed('/grocery-management')),
                row(Icons.account_balance_rounded, const Color(0xFF0EA5E9),
                    'Bank Info',
                    () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const BankInfoScreen(role: 'restaurant'),
                          ),
                        )),
                row(Icons.loyalty_rounded, const Color(0xFF155EEF), 'Loyalty',
                    () => Navigator.of(context)
                        .pushNamed('/restaurant-loyalty')),
                row(Icons.local_fire_department_rounded,
                    const Color(0xFFEF4444), 'Our Offer',
                    () => Navigator.of(context).pushNamed('/restaurant-offer')),
                row(Icons.description_rounded, const Color(0xFF0891B2),
                    'Contract',
                    () => Navigator.of(context)
                        .pushNamed('/restaurant-contract')),
                row(Icons.card_giftcard_rounded, const Color(0xFF10B981),
                    'Refer & Earn',
                    () => Navigator.of(context)
                        .pushNamed('/restaurant-referral')),
                row(Icons.settings_rounded, const Color(0xFF528BFF),
                    'Settings',
                    () => Navigator.of(context)
                        .pushNamed('/restaurant-settings')),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVerificationGate(Restaurant restaurant) {
    final isRejected = restaurant.status == 'rejected';
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: (isRejected ? Colors.red : AppTheme.primaryColor)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isRejected ? Icons.cancel_rounded : Icons.storefront_rounded,
                  color: isRejected ? Colors.red : AppTheme.primaryColor,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isRejected ? 'Application Rejected' : 'Complete Your Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: Responsive.headingLarge(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                isRejected
                    ? 'Your application was rejected. Please update your documents and resubmit.'
                    : 'Set up your restaurant profile and upload the required documents to get approved.',
                style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RestaurantVerificationScreen(restaurant: restaurant),
                    ),
                  ).then((_) {
                    final uid = ref.read(currentUserIdProvider);
                    if (uid != null) ref.invalidate(restaurantByOwnerProvider(uid));
                  }),
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  label: Text(
                    isRejected ? 'Update & Resubmit' : 'Start Verification',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRejected ? Colors.red : AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout_rounded, size: 16, color: Colors.white38),
                label: const Text('Sign Out', style: TextStyle(color: Colors.white38)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingReview(Restaurant restaurant) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Success badge
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(Icons.hourglass_top_rounded,
                    color: Color(0xFFF59E0B), size: 42),
              ),
              const SizedBox(height: 20),
              // Submitted confirmation chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Color(0xFF10B981), size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Application Submitted',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Under Review',
                style: TextStyle(
                  color: Colors.white, fontSize: 26,
                  fontWeight: FontWeight.w800, letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Our team is reviewing your restaurant application. '
                'This typically takes 24–48 hours. You\'ll be notified once approved.',
                style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              // Review timeline
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1F2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'What happens next?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _TimelineStep(
                      icon: Icons.task_alt_rounded,
                      color: const Color(0xFF10B981),
                      title: 'Application submitted',
                      subtitle: 'All your details have been received',
                      isDone: true,
                    ),
                    _TimelineStep(
                      icon: Icons.manage_search_rounded,
                      color: const Color(0xFFF59E0B),
                      title: 'Under admin review',
                      subtitle: 'Our team verifies your documents',
                      isActive: true,
                    ),
                    _TimelineStep(
                      icon: Icons.verified_rounded,
                      color: const Color(0xFF6366F1),
                      title: 'Approval decision',
                      subtitle: 'You\'ll receive a notification',
                      isLast: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Restaurant info summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1F2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    _ReviewItem(icon: Icons.store_rounded,
                        label: 'Restaurant Name', value: restaurant.name),
                    if (restaurant.cuisineType != null) ...[
                      const SizedBox(height: 10),
                      _ReviewItem(icon: Icons.category_rounded,
                          label: 'Cuisine', value: restaurant.cuisineType!),
                    ],
                    if (restaurant.address != null) ...[
                      const SizedBox(height: 10),
                      _ReviewItem(icon: Icons.place_rounded,
                          label: 'Address', value: restaurant.address!),
                    ],
                    if (restaurant.phone != null) ...[
                      const SizedBox(height: 10),
                      _ReviewItem(icon: Icons.phone_rounded,
                          label: 'Phone', value: restaurant.phone!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),
              // Refresh button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () {
                    final uid = ref.read(currentUserIdProvider);
                    if (uid != null) ref.invalidate(restaurantByOwnerProvider(uid));
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check Status',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout_rounded, size: 16, color: Colors.white38),
                label: const Text('Sign Out', style: TextStyle(color: Colors.white38)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetupRestaurant(String ownerId) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _setupFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.primaryColor, Color(0xFFFF8C5A)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Create Your Restaurant',
                    style: TextStyle(
                      fontSize: Responsive.headingLarge(context),
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Fill in your restaurant details to get started',
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                // ── See Our Offer link ──
                Center(
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const RestaurantOfferScreen(showGetStarted: true),
                      ),
                    ),
                    icon: const Icon(
                      Icons.local_fire_department_rounded,
                      size: 18,
                      color: Color(0xFFEF4444),
                    ),
                    label: const Text(
                      'See Why Restaurants Love HotBite',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSetupField(
                  controller: _nameController,
                  label: 'Restaurant Name',
                  icon: Icons.storefront_rounded,
                  required: true,
                ),
                const SizedBox(height: 16),
                _buildSetupField(
                  controller: _cuisineController,
                  label: 'Cuisine Type (e.g. Pizza, Burger)',
                  icon: Icons.local_dining_rounded,
                ),
                const SizedBox(height: 16),
                _buildSetupField(
                  controller: _addressController,
                  label: 'Address',
                  icon: Icons.location_on_rounded,
                ),
                const SizedBox(height: 16),
                _buildSetupField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _creatingRestaurant
                        ? null
                        : () => _createRestaurant(ownerId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _creatingRestaurant
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Create Restaurant',
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
      ),
    );
  }

  Widget _buildSetupField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool required = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(
        fontSize: 15,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        prefixIcon: Icon(icon, color: AppTheme.primaryColor, size: 20),
        filled: true,
        fillColor: Theme.of(context).inputDecorationTheme.fillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
      ),
      validator: required
          ? (v) => v == null || v.isEmpty ? 'Required' : null
          : null,
    );
  }
}

// ─── Quick Action ──────────────────────────────────────────────────────────────

class _QuickAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).cardColor;
    final shadowColor = widget.color.withValues(alpha: _hover ? 0.30 : 0.12);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.identity()
          ..translateByDouble(0.0, _hover ? -3.0 : 0.0, 0.0, 1.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: _hover ? 18 : 10,
              offset: Offset(0, _hover ? 8 : 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  surface,
                  Color.lerp(surface, widget.color, isDark ? 0.18 : 0.08)!,
                ],
              ),
              border: Border.all(
                color: widget.color.withValues(alpha: _hover ? 0.55 : 0.18),
                width: _hover ? 1.4 : 1.0,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.color.withValues(alpha: 0.95),
                            widget.color.withValues(alpha: 0.70),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ReviewItem({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 18),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            Text(value, style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool isDone;
  final bool isActive;
  final bool isLast;

  const _TimelineStep({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.isDone = false,
    this.isActive = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: (isDone || isActive)
                        ? color.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (isDone || isActive) ? color : Colors.white24,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(icon,
                      color: (isDone || isActive) ? color : Colors.white24,
                      size: 16),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: isDone ? color.withValues(alpha: 0.4) : Colors.white12,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: TextStyle(
                      color: (isDone || isActive) ? Colors.white : Colors.white38,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: (isDone || isActive)
                          ? Colors.white54
                          : Colors.white24,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Charts (drawn — no chart dependency)
// ═══════════════════════════════════════════════════════════════════════════

class _DonutSeg {
  final String label;
  final int value;
  final Color color;
  const _DonutSeg(this.label, this.value, this.color);
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSeg> segs;
  _DonutPainter(this.segs);

  @override
  void paint(Canvas canvas, Size size) {
    final total = segs.fold<int>(0, (a, s) => a + s.value);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    const stroke = 16.0;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    if (total == 0) {
      canvas.drawArc(
        rect,
        0,
        6.28318,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = const Color(0xFF23304A),
      );
      return;
    }

    double start = -1.5708; // top
    const gap = 0.04;
    for (final s in segs) {
      if (s.value == 0) continue;
      final sweep = (s.value / total) * 6.28318 - gap;
      canvas.drawArc(
        rect,
        start + gap / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = s.color,
      );
      start += (s.value / total) * 6.28318;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.segs != segs;
}

class _BarChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  _BarChartPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 20.0;
    final chartH = size.height - labelH;
    final maxV = values.fold<double>(0, (a, b) => b > a ? b : a);
    final n = values.length;
    if (n == 0) return;
    final slot = size.width / n;
    final barW = slot * 0.5;

    // Baseline
    final axis = Paint()..color = const Color(0xFF23304A)..strokeWidth = 1;
    canvas.drawLine(Offset(0, chartH), Offset(size.width, chartH), axis);

    for (int i = 0; i < n; i++) {
      final v = values[i];
      final h = maxV <= 0 ? 0.0 : (v / maxV) * (chartH - 8);
      final left = slot * i + (slot - barW) / 2;
      final top = chartH - h;
      final rrect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barW, h),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF34D399), Color(0xFF10B981)],
        ).createShader(Rect.fromLTWH(left, top, barW, h <= 0 ? 1 : h));
      canvas.drawRRect(rrect, paint);

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: labels.length > i ? labels[i] : '',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 0, maxWidth: slot);
      tp.paint(
        canvas,
        Offset(slot * i + (slot - tp.width) / 2, chartH + 5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.values != values;
}
