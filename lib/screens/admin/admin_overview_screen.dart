import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ai_staff_provider.dart';
import 'package:food_driver/config/app_constants.dart';

/// Redesigned admin Overview — matches the HotBite admin mockup: greeting,
/// 2×2 KPI grid, dark AI Staff hero, "Needs attention", "Manage your business"
/// grid, and a bottom nav. Wired to real providers.
class AdminOverviewScreen extends ConsumerWidget {
  const AdminOverviewScreen({super.key});

  static const _orange = Color(0xFFFF6B00);
  static const _ink = Color(0xFF1A1A1A);

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static const _periodLabels = {'today': 'Today', '7d': 'Last 7 days', '30d': 'Last 30 days', 'all': 'All time'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(adminOverviewPeriodProvider);
    final stats = ref.watch(adminOverviewStatsProvider(period));
    final ai = ref.watch(aiStaffOverviewProvider);
    final user = ref.watch(currentUserProvider);
    final fullName = (user?.name ?? '').trim();
    final name = fullName.isNotEmpty ? fullName.split(' ').first : 'Admin';
    final initials = name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();

    final s = stats.valueOrNull ?? const {};
    final totalSales = ((s['total_sales'] ?? s['revenue'] ?? 0) as num).toDouble();
    final platformRevenue = ((s['platform_revenue'] ?? 0) as num).toDouble();
    final orderCount = (s['orders'] ?? 0).toString();
    final onlineRiders = (s['online_riders'] ?? 0).toString();
    final activeStores = (s['active_stores'] ?? 0).toString();
    final loading = stats.isLoading;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminOverviewStatsProvider);
            ref.invalidate(aiStaffOverviewProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // ── Header ──
              Row(children: [
                const Icon(Icons.local_fire_department_rounded, color: _orange, size: 28),
                const SizedBox(width: 6),
                const Text('HotBite', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                const SizedBox(width: 6),
                Text('ADMIN', style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w700, letterSpacing: 1, fontSize: 12)),
                const Spacer(),
                // ① Notifications bell
                _NotificationBell(),
                // ② Account avatar
                GestureDetector(
                  onTap: () => _showAccountMenu(context, ref, name),
                  child: CircleAvatar(radius: 18, backgroundColor: _orange.withValues(alpha: 0.15),
                      child: Text(initials, style: const TextStyle(color: _orange, fontWeight: FontWeight.w800, fontSize: 13))),
                ),
              ]),
              const SizedBox(height: 12),
              // ── Greeting ──
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_greeting()}, $name', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.1)),
                  const SizedBox(height: 4),
                  Text("Here's how HotBite is doing ${period == 'today' ? 'today' : _periodLabels[period]!.toLowerCase()}.",
                      style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                ])),
                // ③ Period selector (working)
                PopupMenuButton<String>(
                  initialValue: period,
                  onSelected: (v) => ref.read(adminOverviewPeriodProvider.notifier).state = v,
                  itemBuilder: (_) => _periodLabels.entries
                      .map((e) => PopupMenuItem(value: e.key, child: Text(e.value))).toList(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_periodLabels[period]!, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 16),

              // ── KPI grid (④ tappable) ──
              // Row 1: money — Total Sales (all sales the company made, GMV)
              // beside Platform Revenue (what HotBite actually earns).
              Row(children: [
                Expanded(child: _kpi('Total sales', '${AppConstants.currencyCode} ${_fmt(totalSales)}', Icons.receipt_long_rounded, const Color(0xFF0EA5E9), loading, () => Navigator.pushNamed(context, '/admin-financials'))),
                const SizedBox(width: 12),
                Expanded(child: _kpi('Platform revenue', '${AppConstants.currencyCode} ${_fmt(platformRevenue)}', Icons.attach_money_rounded, const Color(0xFF10B981), loading, () => Navigator.pushNamed(context, '/admin-platform-earnings'))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _kpi('Orders', orderCount, Icons.shopping_cart_rounded, _orange, loading, () => Navigator.pushNamed(context, '/admin-orders'))),
                const SizedBox(width: 12),
                Expanded(child: _kpi('Online riders', onlineRiders, Icons.groups_rounded, const Color(0xFF2563EB), loading, () => Navigator.pushNamed(context, '/admin-drivers'))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _kpi('Active stores', activeStores, Icons.storefront_rounded, const Color(0xFF7C3AED), loading, () => Navigator.pushNamed(context, '/admin-restaurants'))),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox()),
              ]),
              const SizedBox(height: 16),

              // ── AI Staff hero (⑤ tappable stats) ──
              _aiStaffCard(context, ai),
              const SizedBox(height: 16),

              // ── Needs attention ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Needs attention', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const Divider(height: 20),
                  _attentionRow(context, Icons.access_time_rounded, const Color(0xFFF59E0B),
                      'Orders awaiting riders', 'Assign riders to keep things moving.', '/admin-orders'),
                  const Divider(height: 20),
                  _attentionRow(context, Icons.lightbulb_rounded, _orange,
                      '${ai.valueOrNull?['awaiting'] ?? 0} suggestions ready to review', 'AI found ways to improve your business.', '/admin-ai-staff/suggestions'),
                ]),
              ),
              const SizedBox(height: 20),

              // ── Manage your business ──
              const Text('Manage your business', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _manageTile(context, Icons.receipt_long_rounded, 'Orders', 'View and manage orders', '/admin-orders')),
                const SizedBox(width: 12),
                Expanded(child: _manageTile(context, Icons.storefront_rounded, 'Stores', 'Manage store settings', '/admin-restaurants')),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _manageTile(context, Icons.pedal_bike_rounded, 'Riders', 'Track and manage riders', '/admin-drivers')),
                const SizedBox(width: 12),
                Expanded(child: _manageTile(context, Icons.credit_card_rounded, 'Payments', 'View earnings and payouts', '/admin-payouts')),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _manageTile(context, Icons.people_rounded, 'Customers', 'Manage your customers', '/admin-users')),
                const SizedBox(width: 12),
                Expanded(child: _manageTile(context, Icons.campaign_rounded, 'Marketing', 'Promotions and growth', '/admin-promos')),
              ]),
              const SizedBox(height: 24),

              // ── All admin tools (every function from the classic dashboard) ──
              const Text('All admin tools', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Everything from the classic dashboard.', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              const SizedBox(height: 12),
              ..._allTools.map((cat) => _toolCategory(context, cat)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _bottomNav(context),
    );
  }

  // Complete function catalog carried over from the classic admin dashboard.
  static const List<_ToolCat> _allTools = [
    _ToolCat('Dashboards & Finance', [
      _Tool('Operating', Icons.insights_rounded, '/admin-operating-dashboard'),
      _Tool('Survival', Icons.speed_rounded, '/admin-survival'),
      _Tool('Margins', Icons.trending_up_rounded, '/admin-margins'),
      _Tool('Financials', Icons.account_balance_wallet_rounded, '/admin-financials'),
      _Tool('Commissions', Icons.percent_rounded, '/admin-platform-earnings'),
      _Tool('Analytics', Icons.bar_chart_rounded, '/admin-analytics'),
      _Tool('Banking', Icons.account_balance_rounded, '/admin-banking'),
      _Tool('Payouts', Icons.payments_rounded, '/admin-payouts'),
      _Tool('Payout Run', Icons.batch_prediction_rounded, '/admin-payout-batch'),
      _Tool('Member Savings', Icons.workspace_premium_rounded, '/admin-member-savings'),
      _Tool('Phone Fallback', Icons.phone_forwarded_rounded, '/admin-call-fallback-log'),
      _Tool('Pricing', Icons.sell_rounded, '/admin-pricing'),
      _Tool('Loyalty', Icons.card_giftcard_rounded, '/admin-loyalty'),
      _Tool('Contracts', Icons.description_rounded, '/admin-contract'),
    ]),
    _ToolCat('People & Places', [
      _Tool('Users', Icons.people_rounded, '/admin-users'),
      _Tool('Restaurants', Icons.restaurant_rounded, '/admin-restaurants'),
      _Tool('Drivers', Icons.two_wheeler_rounded, '/admin-drivers'),
      _Tool('Add Driver', Icons.person_add_rounded, '/admin-drivers'),
      _Tool('Add Restaurant', Icons.add_business_rounded, '/admin-restaurants'),
      _Tool('Regions', Icons.map_rounded, '/admin-regions'),
      _Tool('Grocery Products', Icons.local_grocery_store_rounded, '/admin-grocery-products'),
      _Tool('Student Verify', Icons.school_rounded, '/admin-student-verification'),
      _Tool('Peak Time', Icons.schedule_rounded, '/admin-peak-time'),
      _Tool('Categories', Icons.category_rounded, '/admin-categories'),
    ]),
    _ToolCat('Services & Catalog', [
      _Tool('Close App / Holidays', Icons.power_settings_new_rounded, '/admin-app-closure'),
      _Tool('Manage Services', Icons.tune_rounded, '/admin-services'),
      _Tool('HotBite Picks', Icons.local_fire_department_rounded, '/admin-hotbite-picks'),
      _Tool('HotBite+', Icons.workspace_premium_rounded, '/admin-mealhub'),
      _Tool('Meal Plans', Icons.lunch_dining_rounded, '/admin-meal-plans'),
      _Tool('Driver Priority', Icons.star_rounded, '/admin-driver-priority'),
      _Tool('Priority Delivery', Icons.bolt_rounded, '/admin-priority-delivery'),
      _Tool('Shipping Cos', Icons.local_shipping_rounded, '/admin-shipping-companies'),
    ]),
    _ToolCat('Rides / Taxi', [
      _Tool('Rides Hub', Icons.local_taxi_rounded, '/admin-rides'),
      _Tool('All Rides', Icons.list_alt_rounded, '/admin-rides/list'),
      _Tool('Ride Pricing', Icons.attach_money_rounded, '/admin-rides/pricing'),
      _Tool('Driver Approvals', Icons.how_to_reg_rounded, '/admin-rides/driver-approval'),
    ]),
    _ToolCat('Laundry, Car & Packages', [
      _Tool('Laundry', Icons.local_laundry_service_rounded, '/admin/laundry'),
      _Tool('Car Services', Icons.directions_car_rounded, '/admin/car-services'),
      _Tool('Deliveries Hub', Icons.inventory_2_rounded, '/admin-packages'),
      _Tool('All Deliveries', Icons.local_shipping_rounded, '/admin-packages/deliveries'),
      _Tool('Package Records', Icons.receipt_long_rounded, '/admin-packages/records'),
    ]),
    _ToolCat('Ads & Marketing', [
      _Tool('Restaurant Ads', Icons.ad_units_rounded, '/admin-ads'),
      _Tool('Banners', Icons.view_carousel_rounded, '/admin-banners'),
      _Tool('Promos', Icons.local_offer_rounded, '/admin-promos'),
      _Tool('Email Blast', Icons.email_rounded, '/admin-email-notifications'),
      _Tool('Surge Zones', Icons.whatshot_rounded, '/admin-surge'),
      _Tool('Birthday Campaign', Icons.cake_rounded, '/admin-birthday-campaign'),
      _Tool('Home Notice', Icons.campaign_rounded, '/admin-home-notice'),
      _Tool('Referral Rewards', Icons.share_rounded, '/admin-referral'),
    ]),
    _ToolCat('Support & Feedback', [
      _Tool('Support', Icons.support_agent_rounded, '/admin-chats'),
      _Tool('Support Requests', Icons.contact_support_rounded, '/admin-support-requests'),
      _Tool('Disputes', Icons.gavel_rounded, '/admin-disputes'),
      _Tool('Feedback', Icons.rate_review_rounded, '/admin-feedback'),
      _Tool('DB Lookup', Icons.search_rounded, '/admin-lookup'),
    ]),
    _ToolCat('AI Operations', [
      _Tool('AI Staff', Icons.groups_rounded, '/admin-ai-staff'),
      _Tool('Pickup Coordinator', Icons.phone_in_talk_rounded, '/admin-pickup-coordinator'),
      _Tool('AI Ops Hub', Icons.smart_toy_rounded, '/admin-ai-operations'),
      _Tool('AI Engine', Icons.memory_rounded, '/admin-ai-panel'),
      _Tool('Workflow Station', Icons.account_tree_rounded, '/admin-workflow-station'),
      _Tool('Ask AI', Icons.chat_rounded, '/admin-ai/ask'),
    ]),
  ];

  Widget _toolCategory(BuildContext context, _ToolCat cat) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 8, bottom: 8, left: 2),
              child: Text(cat.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.grey[700]))),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.all(6),
            child: Wrap(children: [
              for (final t in cat.items)
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 32 - 12) / 2,
                  child: InkWell(
                    onTap: () => Navigator.pushNamed(context, t.route),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                      child: Row(children: [
                        Icon(t.icon, size: 18, color: _orange),
                        const SizedBox(width: 8),
                        Expanded(child: Text(t.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey[400]),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
        ],
      );

  static String _fmt(double v) {
    final neg = v < 0;
    final cents = (v.abs() * 100).round();
    final whole = (cents ~/ 100).toString();
    final frac = (cents % 100).toString().padLeft(2, '0');
    final b = StringBuffer();
    for (int i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
      b.write(whole[i]);
    }
    return '${neg ? '-' : ''}$b.$frac';
  }

  Widget _kpi(String label, String value, IconData icon, Color color, bool loading, VoidCallback onTap) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 22)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            loading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                    child: Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
          ])),
        ]),
      ),
        ),
      );

  Widget _aiStaffCard(BuildContext context, AsyncValue<Map<String, int>> ai) {
    final d = ai.valueOrNull ?? const {};
    Widget stat(int v, String l, String route) => Expanded(child: InkWell(
          onTap: () => Navigator.pushNamed(context, route),
          borderRadius: BorderRadius.circular(8),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: [
            Text('$v', style: const TextStyle(color: _orange, fontSize: 26, fontWeight: FontWeight.w800)),
            Text(l, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]))));
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.memory_rounded, color: _orange, size: 34),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI Staff', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            Text('${d['roles'] ?? 24} staff members', style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ])),
          const Icon(Icons.auto_awesome_rounded, color: _orange, size: 22),
        ]),
        const SizedBox(height: 16),
        IntrinsicHeight(child: Row(children: [
          stat(d['awaiting'] ?? 0, 'Awaiting approval', '/admin-ai-staff/suggestions'),
          const VerticalDivider(color: Colors.white24),
          stat(d['working'] ?? 0, 'Working', '/admin-ai-staff/suggestions'),
          const VerticalDivider(color: Colors.white24),
          stat(d['verified'] ?? 0, 'Verified fixes', '/admin-ai-staff'),
        ])),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () => Navigator.pushNamed(context, '/admin-ai-staff'),
          style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Review AI activity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            SizedBox(width: 8), Icon(Icons.arrow_forward_rounded, size: 18),
          ]),
        )),
      ]),
    );
  }

  Widget _attentionRow(BuildContext context, IconData icon, Color color, String title, String sub, String route) => InkWell(
        onTap: () => Navigator.pushNamed(context, route),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text(sub, style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
          ])),
          Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
        ]),
      );

  Widget _manageTile(BuildContext context, IconData icon, String title, String sub, String route) => InkWell(
        onTap: () => Navigator.pushNamed(context, route),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(icon, color: _orange, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(sub, style: TextStyle(color: Colors.grey[600], fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 18),
          ]),
        ),
      );

  // ② Account menu: profile, settings, sign out.
  void _showAccountMenu(BuildContext context, WidgetRef ref, String name) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        CircleAvatar(radius: 26, backgroundColor: _orange.withValues(alpha: 0.15),
            child: Icon(Icons.person_rounded, color: _orange, size: 28)),
        const SizedBox(height: 8),
        Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const Text('Administrator', style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 12),
        ListTile(leading: const Icon(Icons.settings_rounded), title: const Text('Settings'),
            onTap: () { Navigator.pop(ctx); Navigator.pushNamed(context, '/settings'); }),
        ListTile(leading: const Icon(Icons.shield_rounded), title: const Text('Two-step verification'),
            onTap: () { Navigator.pop(ctx); Navigator.pushNamed(context, '/admin-mfa-setup'); }),
        ListTile(leading: const Icon(Icons.people_rounded), title: const Text('Manage admins'),
            onTap: () { Navigator.pop(ctx); Navigator.pushNamed(context, '/admin-users'); }),
        ListTile(
          leading: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626)),
          title: const Text('Sign out', style: TextStyle(color: Color(0xFFDC2626))),
          onTap: () async {
            Navigator.pop(ctx);
            await ref.read(authNotifierProvider.notifier).signOut();
          },
        ),
        const SizedBox(height: 8),
      ])),
    );
  }

  Widget _bottomNav(BuildContext context) => BottomNavigationBar(
        currentIndex: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _orange,
        unselectedItemColor: Colors.grey,
        onTap: (i) {
          switch (i) {
            case 1: Navigator.pushNamed(context, '/admin-orders'); break;
            case 2: Navigator.pushNamed(context, '/admin-ai-staff'); break;
            case 3: Navigator.pushNamed(context, '/admin-analytics'); break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Overview'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'Orders'),
          BottomNavigationBarItem(icon: Icon(Icons.smart_toy_rounded), label: 'AI Staff'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Reports'),
        ],
      );
}

class _ToolCat {
  final String title;
  final List<_Tool> items;
  const _ToolCat(this.title, this.items);
}

class _Tool {
  final String label;
  final IconData icon;
  final String route;
  const _Tool(this.label, this.icon, this.route);
}

// ① Notification bell with unread dot + notifications sheet.
class _NotificationBell extends ConsumerWidget {
  static const _orange = Color(0xFFFF6B00);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifs = ref.watch(adminNotificationsProvider);
    final unread = notifs.valueOrNull?.where((n) => n['is_read'] != true).length ?? 0;
    return Stack(clipBehavior: Clip.none, children: [
      IconButton(
        icon: const Icon(Icons.notifications_none_rounded),
        onPressed: () => _open(context, ref),
      ),
      if (unread > 0)
        Positioned(right: 8, top: 8, child: Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(color: _orange, shape: BoxShape.circle),
          constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
        )),
    ]);
  }

  void _open(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.3, expand: false,
        builder: (ctx, sc) {
          final notifs = ref.watch(adminNotificationsProvider);
          return notifs.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
            error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(40), child: Text('$e'))),
            data: (list) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
              Row(children: [
                const Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(adminNotificationsProvider)),
              ]),
              if (list.isEmpty)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No notifications.', style: TextStyle(color: Colors.grey)))),
              for (final n in list) Container(
                margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: n['is_read'] == true ? Colors.grey.withValues(alpha: 0.06) : _orange.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((n['title'] ?? 'Notification').toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  if (n['body'] != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(n['body'].toString(), style: const TextStyle(fontSize: 13))),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}
