import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_logger.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';
import '../shared/ai_voice_screen.dart';
import '../../core/utils/responsive.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  Future<void> _refresh() async {
    ref.invalidate(dashboardSummaryProvider);
  }

  void _showCreateUserDialog(String role) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateUserSheet(role: role),
    ).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final dashboardAsync = ref.watch(dashboardSummaryProvider);
    final currentUser = ref.watch(currentUserProvider);

    // Keep realtime subscription alive for new order notifications
    ref.watch(adminNewOrderRealtimeProvider);
    // Keep realtime subscription for pending drivers/restaurants (Needs Attention)
    ref.watch(adminPendingRealtimeProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppTheme.primaryColor,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // ── Hero Header ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF334155)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.primaryColor,
                                    Color(0xFFFF8C5A),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.rocket_launch_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome back, ${currentUser?.name?.split(' ').first ?? 'Admin'}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: Responsive.headingMedium(context),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Here\'s your business overview',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Material(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const AiVoiceScreen(role: 'admin'),
                                  ),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.smart_toy_outlined,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.of(
                                  context,
                                ).pushNamed('/settings'),
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.translate_rounded,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => ref
                                    .read(authNotifierProvider.notifier)
                                    .signOut(),
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.logout_rounded,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Content ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: dashboardAsync.when(
                data: (data) {
                  final users = data['users'] as Map? ?? {};
                  final restaurants = data['restaurants'] as Map? ?? {};
                  final drivers = data['drivers'] as Map? ?? {};
                  final orders = data['orders'] as Map? ?? {};
                  final revenue = data['revenue'] as Map? ?? {};
                  final laundry = data['laundry'] as Map? ?? {};
                  final carServices = data['car_services'] as Map? ?? {};
                  final rides = data['rides'] as Map? ?? {};

                  final totalRevenue = ((revenue['total_revenue'] ?? 0) as num)
                      .toDouble();
                  final monthlyRevenue =
                      ((revenue['monthly_revenue'] ?? 0) as num).toDouble();
                  final completionRate =
                      ((orders['completion_rate'] ?? 0.0) as num).toDouble();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Revenue banner (overlapping header) ────────────
                      Transform.translate(
                        offset: const Offset(0, -16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.primaryColor,
                                  Color(0xFFFF8C5A),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFFF6B35,
                                  ).withValues(alpha: 0.35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.trending_up_rounded,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Total Revenue',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${AppConstants.currencySymbol}${totalRevenue.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.calendar_month_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'This Month: ${AppConstants.currencySymbol}${monthlyRevenue.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
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

                      // ── KPI metrics ────────────────────────────────────
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
                        child: Row(
                          children: [
                            _KpiCard(
                              label: 'Users',
                              value: '${users['total_users'] ?? 0}',
                              icon: Icons.people_alt_rounded,
                              color: const Color(0xFF6366F1),
                              onTap: () => Navigator.of(context)
                                  .pushNamed('/admin-users')
                                  .then((_) => _refresh()),
                            ),
                            const SizedBox(width: 10),
                            _KpiCard(
                              label: 'Orders',
                              value: '${orders['total_orders'] ?? 0}',
                              icon: Icons.receipt_long_rounded,
                              color: const Color(0xFFF59E0B),
                              badge: '${completionRate.toStringAsFixed(0)}%',
                              onTap: () => Navigator.of(
                                context,
                              ).pushNamed('/admin-orders'),
                            ),
                            const SizedBox(width: 10),
                            _KpiCard(
                              label: 'Restaurants',
                              value: '${restaurants['total_restaurants'] ?? 0}',
                              icon: Icons.storefront_rounded,
                              color: AppTheme.primaryColor,
                              onTap: () => Navigator.of(context)
                                  .pushNamed('/admin-restaurants')
                                  .then((_) => _refresh()),
                            ),
                            const SizedBox(width: 10),
                            _KpiCard(
                              label: 'Drivers',
                              value: '${drivers['total_drivers'] ?? 0}',
                              icon: Icons.delivery_dining_rounded,
                              color: const Color(0xFF10B981),
                              onTap: () => Navigator.of(context)
                                  .pushNamed('/admin-drivers')
                                  .then((_) => _refresh()),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ── Module activity row ────────────────────────────
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: Responsive.horizontalPadding(context),
                        ),
                        child: Row(
                          children: [
                            _KpiCard(
                              label: 'Rides',
                              value: '${rides['total_rides'] ?? 0}',
                              icon: Icons.directions_car_rounded,
                              color: const Color(0xFF8B5CF6),
                              badge: rides['active_rides'] != null
                                  ? '${rides['active_rides']} live'
                                  : null,
                              onTap: () => Navigator.of(
                                context,
                              ).pushNamed('/admin-rides'),
                            ),
                            const SizedBox(width: 10),
                            _KpiCard(
                              label: 'Laundry',
                              value: '${laundry['total_bookings'] ?? 0}',
                              icon: Icons.local_laundry_service_rounded,
                              color: const Color(0xFF0EA5E9),
                              badge: laundry['active_bookings'] != null
                                  ? '${laundry['active_bookings']} live'
                                  : null,
                              onTap: () => Navigator.of(
                                context,
                              ).pushNamed('/admin/laundry'),
                            ),
                            const SizedBox(width: 10),
                            _KpiCard(
                              label: 'Car Svc',
                              value: '${carServices['total_bookings'] ?? 0}',
                              icon: Icons.car_repair_rounded,
                              color: const Color(0xFF0D9488),
                              badge: carServices['active_bookings'] != null
                                  ? '${carServices['active_bookings']} live'
                                  : null,
                              onTap: () => Navigator.of(
                                context,
                              ).pushNamed('/admin/car-services'),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Pending alerts ──────────────────────────────────
                      if ((restaurants['pending'] ?? 0) > 0 ||
                          (drivers['pending'] ?? 0) > 0) ...[
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFFED7AA),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFFB923C,
                                    ).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.notifications_active_rounded,
                                    color: Color(0xFFF97316),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Needs Attention',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Color(0xFF9A3412),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${drivers['pending'] ?? 0} drivers & ${restaurants['pending'] ?? 0} restaurants pending',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFC2410C),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Quick Actions ──────────────────────────────────
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
                        child: Text(
                          'Quick Actions',
                          style: TextStyle(
                            fontSize: Responsive.headingSmall(context),
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
                        child: Row(
                          children: [
                            Expanded(
                              child: _QuickAction(
                                icon: Icons.delivery_dining_rounded,
                                label: 'Add Driver',
                                color: const Color(0xFF10B981),
                                onTap: () => _showCreateUserDialog('driver'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _QuickAction(
                                icon: Icons.add_business_rounded,
                                label: 'Add Restaurant',
                                color: AppTheme.primaryColor,
                                onTap: () =>
                                    _showCreateUserDialog('restaurant'),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── Management Section ──────────────────────────────

                      // People & Places
                      _CategoryRow(
                        title: 'People & Places',
                        children: [
                          _GridAction(
                            icon: Icons.people_alt_rounded,
                            label: 'Users',
                            color: const Color(0xFF6366F1),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-users').then((_) => _refresh()),
                          ),
                          _GridAction(
                            icon: Icons.storefront_rounded,
                            label: 'Restaurants',
                            color: AppTheme.primaryColor,
                            onTap: () => Navigator.of(context)
                                .pushNamed('/admin-restaurants')
                                .then((_) => _refresh()),
                          ),
                          _GridAction(
                            icon: Icons.delivery_dining_rounded,
                            label: 'Drivers',
                            color: const Color(0xFF10B981),
                            onTap: () => Navigator.of(context)
                                .pushNamed('/admin-drivers')
                                .then((_) => _refresh()),
                          ),
                          _GridAction(
                            icon: Icons.map_rounded,
                            label: 'Regions',
                            color: const Color(0xFF10B981),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-regions'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Orders & Payments
                      _CategoryRow(
                        title: 'Orders & Payments',
                        children: [
                          _GridAction(
                            icon: Icons.receipt_long_rounded,
                            label: 'Orders',
                            color: const Color(0xFFF59E0B),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-orders'),
                          ),
                          _GridAction(
                            icon: Icons.payments_rounded,
                            label: 'Payouts',
                            color: const Color(0xFFF97316),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-payouts'),
                          ),
                          _GridAction(
                            icon: Icons.account_balance_rounded,
                            label: 'Financials',
                            color: const Color(0xFF8B5CF6),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-financials'),
                          ),
                          _GridAction(
                            icon: Icons.account_balance_wallet_rounded,
                            label: 'Commissions',
                            color: const Color(0xFF1F2937),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-platform-earnings'),
                          ),
                          _GridAction(
                            icon: Icons.bar_chart_rounded,
                            label: 'Analytics',
                            color: const Color(0xFF0EA5E9),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-analytics'),
                          ),
                          _GridAction(
                            icon: Icons.psychology_rounded,
                            label: 'AI Engine',
                            color: const Color(0xFF8B5CF6),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-ai-panel'),
                          ),
                          _GridAction(
                            icon: Icons.description_rounded,
                            label: 'Contracts',
                            color: const Color(0xFF10B981),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-contract'),
                          ),
                          _GridAction(
                            icon: Icons.loyalty_rounded,
                            label: 'Loyalty',
                            color: const Color(0xFF7C3AED),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-loyalty'),
                          ),
                          _GridAction(
                            icon: Icons.toggle_on_rounded,
                            label: 'Services',
                            color: const Color(0xFF059669),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-services'),
                          ),
                          _GridAction(
                            icon: Icons.local_shipping_rounded,
                            label: 'Pricing',
                            color: const Color(0xFF0891B2),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-pricing'),
                          ),
                          _GridAction(
                            icon: Icons.card_membership_rounded,
                            label: 'MealHub+',
                            color: const Color(0xFF6C63FF),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-mealhub'),
                          ),
                          _GridAction(
                            icon: Icons.restaurant_menu_rounded,
                            label: 'Meal Plans',
                            color: const Color(0xFF0891B2),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-meal-plans'),
                          ),
                          _GridAction(
                            icon: Icons.inventory_2_rounded,
                            label: 'Shipping Cos',
                            color: const Color(0xFF7C3AED),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-shipping-companies'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Rides / Taxi
                      _CategoryRow(
                        title: 'Rides / Taxi',
                        children: [
                          _GridAction(
                            icon: Icons.directions_car_rounded,
                            label: 'Rides Hub',
                            color: const Color(0xFF1E40AF),
                            onTap: () =>
                                Navigator.of(context).pushNamed('/admin-rides'),
                          ),
                          _GridAction(
                            icon: Icons.list_alt_rounded,
                            label: 'All Rides',
                            color: const Color(0xFF2563EB),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-rides/list'),
                          ),
                          _GridAction(
                            icon: Icons.attach_money_rounded,
                            label: 'Ride Pricing',
                            color: const Color(0xFF0284C7),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-rides/pricing'),
                          ),
                          _GridAction(
                            icon: Icons.how_to_reg_rounded,
                            label: 'Driver Approvals',
                            color: const Color(0xFF0891B2),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-rides/driver-approval'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Laundry & Car Services
                      _CategoryRow(
                        title: 'Laundry & Car Services',
                        children: [
                          _GridAction(
                            icon: Icons.local_laundry_service_rounded,
                            label: 'Laundry',
                            color: const Color(0xFF0F4C81),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin/laundry'),
                          ),
                          _GridAction(
                            icon: Icons.car_repair,
                            label: 'Car Services',
                            color: const Color(0xFF7C3AED),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin/car-services'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Package Delivery
                      _CategoryRow(
                        title: 'Package Delivery',
                        children: [
                          _GridAction(
                            icon: Icons.inventory_2_rounded,
                            label: 'Deliveries Hub',
                            color: const Color(0xFF7C3AED),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-packages'),
                          ),
                          _GridAction(
                            icon: Icons.local_shipping_rounded,
                            label: 'All Deliveries',
                            color: const Color(0xFF9333EA),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-packages/deliveries'),
                          ),
                          _GridAction(
                            icon: Icons.qr_code_scanner_rounded,
                            label: 'Package Records',
                            color: const Color(0xFFA855F7),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-packages/records'),
                          ),
                          _GridAction(
                            icon: Icons.business_rounded,
                            label: 'Shipping Cos',
                            color: const Color(0xFF7C3AED),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-shipping-companies'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Ads & Marketing
                      _CategoryRow(
                        title: 'Ads & Marketing',
                        children: [
                          _GridAction(
                            icon: Icons.featured_play_list_rounded,
                            label: 'Restaurant Ads',
                            color: const Color(0xFFEF4444),
                            onTap: () =>
                                Navigator.of(context).pushNamed('/admin-ads'),
                          ),
                          _GridAction(
                            icon: Icons.campaign_rounded,
                            label: 'Banners',
                            color: const Color(0xFF7C3AED),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-banners'),
                          ),
                          _GridAction(
                            icon: Icons.discount_rounded,
                            label: 'Promos',
                            color: const Color(0xFF6366F1),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-promos'),
                          ),
                          _GridAction(
                            icon: Icons.bolt_rounded,
                            label: 'Surge Zones',
                            color: const Color(0xFFFFA630),
                            onTap: () =>
                                Navigator.of(context).pushNamed('/admin-surge'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Support & Feedback
                      _CategoryRow(
                        title: 'Support & Feedback',
                        children: [
                          _GridAction(
                            icon: Icons.support_agent_rounded,
                            label: 'Support',
                            color: const Color(0xFFEF4444),
                            onTap: () =>
                                Navigator.of(context).pushNamed('/admin-chats'),
                          ),
                          _GridAction(
                            icon: Icons.gavel_rounded,
                            label: 'Disputes',
                            color: const Color(0xFFDC2626),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-disputes'),
                          ),
                          _GridAction(
                            icon: Icons.rate_review_rounded,
                            label: 'Feedback',
                            color: const Color(0xFF06B6D4),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-feedback'),
                          ),
                          _GridAction(
                            icon: Icons.manage_search_rounded,
                            label: 'DB Lookup',
                            color: const Color(0xFF0EA5E9),
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/admin-lookup'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.only(top: 100),
                  child: AppLoadingIndicator(message: 'Loading dashboard...'),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: AppErrorState(
                    message: friendlyError(e),
                    onRetry: _refresh,
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

// ─── KPI Card ──────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? badge;
  final VoidCallback? onTap;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    if (badge != null)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Quick Action Button ───────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: Responsive.bodyText(context),
                ),
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

// ─── Category Row (title + horizontal scroll of buttons) ───────────────────

class _CategoryRow extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _CategoryRow({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
          child: Text(
            title,
            style: TextStyle(
              fontSize: Responsive.bodyText(context),
              fontWeight: FontWeight.w700,
              color: const Color(0xFF475569),
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => children[i],
          ),
        ),
      ],
    );
  }
}

// ─── Grid Action Button (fixed width for horizontal scroll) ────────────────

class _GridAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _GridAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: Responsive.bodyText(context),
                ),
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

// ─── Create User Sheet ────────────────────────────────────────────────────────

class _CreateUserSheet extends ConsumerStatefulWidget {
  final String role;
  const _CreateUserSheet({required this.role});

  @override
  ConsumerState<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends ConsumerState<_CreateUserSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _vehicleNumCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _restNameCtrl = TextEditingController();
  final _cuisineCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _vehicleType = 'motorcycle';
  bool _loading = false;
  bool _obscurePass = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _vehicleNumCtrl.dispose();
    _licenseCtrl.dispose();
    _restNameCtrl.dispose();
    _cuisineCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final adminService = ref.read(adminServiceProvider);
      await adminService.createUserWithRole(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        name: _nameCtrl.text.trim(),
        role: widget.role,
        vehicleType: _vehicleType,
        vehicleNumber: _vehicleNumCtrl.text.trim(),
        licenseNumber: _licenseCtrl.text.trim(),
        restaurantName: _restNameCtrl.text.trim(),
        cuisineType: _cuisineCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop();
        AppSnackbar.success(
          context,
          '${widget.role == 'driver' ? 'Driver' : 'Restaurant'} account created successfully!',
        );
        ref.invalidate(dashboardSummaryProvider);
        ref.invalidate(allDriversAdminProvider);
        ref.invalidate(allRestaurantsAdminProvider);
        ref.invalidate(pendingDriversProvider);
        ref.invalidate(pendingRestaurantsProvider);
      }
    } catch (e) {
      AppLogger.error('Create user error: $e');
      if (mounted) {
        setState(() => _loading = false);
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = widget.role == 'driver';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isDriver
                    ? 'Create Driver Account'
                    : 'Create Restaurant Account',
                style: TextStyle(
                  fontSize: Responsive.headingMedium(context),
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isDriver
                    ? 'The driver will receive login credentials'
                    : 'The owner will receive login credentials',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Common fields
              _field(
                _nameCtrl,
                'Full Name',
                Icons.person_outline,
                validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              _field(
                _emailCtrl,
                'Email Address',
                Icons.email_outlined,
                type: TextInputType.emailAddress,
                validator: (v) {
                  if (v?.isEmpty ?? true) return 'Required';
                  if (!v!.contains('@')) return 'Invalid email';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                validator: (v) {
                  if (v?.isEmpty ?? true) return 'Required';
                  if (v!.length < 6) return 'Min 6 characters';
                  return null;
                },
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: _dec('Password', Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: const Color(0xFF9CA3AF),
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Divider(color: Colors.grey[200]),
              const SizedBox(height: 8),

              // Role-specific fields
              if (isDriver) ...[
                Text(
                  'Vehicle Details',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _vehicleType,
                  decoration: _dec(
                    'Vehicle Type',
                    Icons.directions_car_outlined,
                  ),
                  items: ['motorcycle', 'car', 'bicycle', 'scooter']
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v[0].toUpperCase() + v.substring(1)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _vehicleType = v ?? 'motorcycle'),
                ),
                const SizedBox(height: 10),
                _field(_vehicleNumCtrl, 'Vehicle Number', Icons.numbers),
                const SizedBox(height: 10),
                _field(_licenseCtrl, 'License Number', Icons.badge_outlined),
              ] else ...[
                Text(
                  'Restaurant Details',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _field(
                  _restNameCtrl,
                  'Restaurant Name',
                  Icons.store_outlined,
                  validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                _field(_cuisineCtrl, 'Cuisine Type', Icons.restaurant_outlined),
                const SizedBox(height: 10),
                _field(_addressCtrl, 'Address', Icons.location_on_outlined),
                const SizedBox(height: 10),
                _field(
                  _phoneCtrl,
                  'Phone Number',
                  Icons.phone_outlined,
                  type: TextInputType.phone,
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          isDriver
                              ? 'Create Driver Account'
                              : 'Create Restaurant Account',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
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

  InputDecoration _dec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      prefixIcon: Icon(icon, color: AppTheme.primaryColor, size: 20),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? type,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      validator: validator,
      style: TextStyle(
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: _dec(label, icon),
    );
  }
}
