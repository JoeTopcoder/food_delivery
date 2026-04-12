import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_logger.dart';
import '../../utils/friendly_error.dart';

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

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppTheme.primaryColor,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
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
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                    ),
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
                              gradient: const LinearGradient(
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
                                  '\$${totalRevenue.toStringAsFixed(0)}',
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
                                        'This Month: \$${monthlyRevenue.toStringAsFixed(0)}',
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
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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

                      const SizedBox(height: 24),

                      // ── Pending alerts ──────────────────────────────────
                      if ((restaurants['pending'] ?? 0) > 0 ||
                          (drivers['pending'] ?? 0) > 0) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Text(
                              'Quick Actions',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '2 actions',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: const Text(
                          'Manage',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            _MgmtCard(
                              items: [
                                _MgmtItem(
                                  icon: Icons.people_alt_rounded,
                                  label: 'Users',
                                  sub:
                                      '${users['total_users'] ?? 0} registered',
                                  color: const Color(0xFF6366F1),
                                  onTap: () => Navigator.of(context)
                                      .pushNamed('/admin-users')
                                      .then((_) => _refresh()),
                                ),
                                _MgmtItem(
                                  icon: Icons.storefront_rounded,
                                  label: 'Restaurants',
                                  sub: '${restaurants['pending'] ?? 0} pending',
                                  color: AppTheme.primaryColor,
                                  onTap: () => Navigator.of(context)
                                      .pushNamed('/admin-restaurants')
                                      .then((_) => _refresh()),
                                ),
                                _MgmtItem(
                                  icon: Icons.delivery_dining_rounded,
                                  label: 'Drivers',
                                  sub: '${drivers['pending'] ?? 0} pending',
                                  color: const Color(0xFF10B981),
                                  onTap: () => Navigator.of(context)
                                      .pushNamed('/admin-drivers')
                                      .then((_) => _refresh()),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _MgmtCard(
                              items: [
                                _MgmtItem(
                                  icon: Icons.receipt_long_rounded,
                                  label: 'Orders',
                                  sub: '${orders['total_orders'] ?? 0} total',
                                  color: const Color(0xFFF59E0B),
                                  onTap: () => Navigator.of(context)
                                      .pushNamed('/admin-orders')
                                      .then((_) => _refresh()),
                                ),
                                _MgmtItem(
                                  icon: Icons.payments_rounded,
                                  label: 'Payouts',
                                  sub: 'Manage requests',
                                  color: const Color(0xFFF97316),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pushNamed('/admin-payouts'),
                                ),
                                _MgmtItem(
                                  icon: Icons.account_balance_rounded,
                                  label: 'Financials',
                                  sub: 'Commission & sales',
                                  color: const Color(0xFF8B5CF6),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pushNamed('/admin-financials'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _MgmtCard(
                              items: [
                                _MgmtItem(
                                  icon: Icons.discount_rounded,
                                  label: 'Promos',
                                  sub: 'Coupons & codes',
                                  color: const Color(0xFF6366F1),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pushNamed('/admin-promos'),
                                ),
                                _MgmtItem(
                                  icon: Icons.support_agent_rounded,
                                  label: 'Support',
                                  sub: 'Customer chats',
                                  color: const Color(0xFFEF4444),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pushNamed('/admin-chats'),
                                ),
                                _MgmtItem(
                                  icon: Icons.gavel_rounded,
                                  label: 'Disputes',
                                  sub: 'Refunds & claims',
                                  color: const Color(0xFFDC2626),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pushNamed('/admin-disputes'),
                                ),
                                _MgmtItem(
                                  icon: Icons.rate_review_rounded,
                                  label: 'Feedback',
                                  sub: 'App reviews',
                                  color: const Color(0xFF06B6D4),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pushNamed('/admin-feedback'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _MgmtCard(
                              items: [
                                _MgmtItem(
                                  icon: Icons.bolt_rounded,
                                  label: 'Surge Zones',
                                  sub: 'Pricing areas',
                                  color: const Color(0xFFFFA630),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pushNamed('/admin-surge'),
                                ),
                                _MgmtItem(
                                  icon: Icons.campaign_rounded,
                                  label: 'Banners',
                                  sub: 'Promo ads',
                                  color: const Color(0xFF7C3AED),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pushNamed('/admin-banners'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _MgmtCard(
                              items: [
                                _MgmtItem(
                                  icon: Icons.manage_search_rounded,
                                  label: 'DB Lookup',
                                  sub: 'Cards, orders, customers',
                                  color: const Color(0xFF0EA5E9),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pushNamed('/admin-lookup'),
                                ),
                                _MgmtItem(
                                  icon: Icons.description_rounded,
                                  label: 'Contracts',
                                  sub: 'Service agreements',
                                  color: const Color(0xFF10B981),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pushNamed('/admin-contract'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.only(top: 100),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.error_outline,
                            size: 40,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Something went wrong',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            '$e',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Try Again'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                          ),
                        ),
                      ],
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
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
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
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Management Card (grouped) ─────────────────────────────────────────────────

class _MgmtCard extends StatelessWidget {
  final List<_MgmtItem> items;
  const _MgmtCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          for (int i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              Divider(
                height: 1,
                indent: 62,
                endIndent: 16,
                color: Colors.grey.shade100,
              ),
          ],
        ],
      ),
    );
  }
}

class _MgmtItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;

  const _MgmtItem({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
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
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade300,
                size: 22,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.role == 'driver' ? 'Driver' : 'Restaurant'} account created successfully!',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isDriver
                    ? 'The driver will receive login credentials'
                    : 'The owner will receive login credentials',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
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
                style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937)),
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
                const Text(
                  'Vehicle Details',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF374151),
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
                const Text(
                  'Restaurant Details',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF374151),
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
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
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
      style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937)),
      decoration: _dec(label, icon),
    );
  }
}
