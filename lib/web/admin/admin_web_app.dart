import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import 'pages/web_admin_dashboard_page.dart';
import 'pages/web_admin_users_page.dart';
import 'pages/web_admin_restaurants_page.dart';
import 'pages/web_admin_drivers_page.dart';
import 'pages/web_admin_orders_page.dart';
import 'pages/web_admin_analytics_page.dart';
import 'pages/web_admin_promos_page.dart';
import 'pages/web_admin_disputes_page.dart';
import 'pages/web_admin_payouts_page.dart';
import 'pages/web_admin_pricing_page.dart';
import 'pages/web_admin_banners_page.dart';
import 'pages/web_admin_loyalty_page.dart';
import 'pages/web_admin_ai_panel_page.dart';
import 'pages/web_admin_services_page.dart';
import 'pages/web_admin_financials_page.dart';
import 'pages/web_admin_lookup_page.dart';
import 'pages/web_admin_feedback_page.dart';
import 'pages/web_admin_surge_page.dart';
import 'pages/web_admin_platform_earnings_page.dart';
import 'pages/web_admin_chats_page.dart';
import 'pages/web_admin_contract_page.dart';
import 'pages/web_admin_ads_page.dart';
import 'pages/web_admin_mealhub_page.dart';
import 'pages/web_admin_meal_plans_page.dart';
import 'pages/web_admin_shipping_companies_page.dart';
import 'pages/web_admin_package_deliveries_page.dart';
import 'pages/web_admin_regions_page.dart';
import 'pages/web_admin_earnings_page.dart';

enum _AdminPage {
  dashboard,
  users,
  restaurants,
  drivers,
  orders,
  analytics,
  promos,
  disputes,
  payouts,
  pricing,
  banners,
  loyalty,
  aiPanel,
  services,
  financials,
  lookup,
  feedback,
  surge,
  platformEarnings,
  chats,
  contract,
  ads,
  mealhub,
  mealPlans,
  shippingCompanies,
  packageDeliveries,
  regions,
  earnings,
}

class AdminWebApp extends ConsumerStatefulWidget {
  const AdminWebApp({super.key});

  @override
  ConsumerState<AdminWebApp> createState() => _AdminWebAppState();
}

class _AdminWebAppState extends ConsumerState<AdminWebApp> {
  _AdminPage _currentPage = _AdminPage.dashboard;

  static const _navGroups = [
    (
      label: 'OVERVIEW',
      items: [
        (icon: Icons.dashboard_rounded, label: 'Dashboard', page: _AdminPage.dashboard),
        (icon: Icons.analytics_rounded, label: 'Analytics', page: _AdminPage.analytics),
      ]
    ),
    (
      label: 'MANAGEMENT',
      items: [
        (icon: Icons.people_rounded, label: 'Users', page: _AdminPage.users),
        (icon: Icons.storefront_rounded, label: 'Restaurants', page: _AdminPage.restaurants),
        (icon: Icons.delivery_dining_rounded, label: 'Drivers', page: _AdminPage.drivers),
        (icon: Icons.receipt_long_rounded, label: 'Orders', page: _AdminPage.orders),
        (icon: Icons.chat_bubble_rounded, label: 'Chats', page: _AdminPage.chats),
        (icon: Icons.map_rounded, label: 'Regions', page: _AdminPage.regions),
      ]
    ),
    (
      label: 'OPERATIONS',
      items: [
        (icon: Icons.local_offer_rounded, label: 'Promos', page: _AdminPage.promos),
        (icon: Icons.gavel_rounded, label: 'Disputes', page: _AdminPage.disputes),
        (icon: Icons.payments_rounded, label: 'Payouts', page: _AdminPage.payouts),
        (icon: Icons.price_change_rounded, label: 'Pricing', page: _AdminPage.pricing),
        (icon: Icons.campaign_rounded, label: 'Banners', page: _AdminPage.banners),
        (icon: Icons.loyalty_rounded, label: 'Loyalty', page: _AdminPage.loyalty),
        (icon: Icons.bolt_rounded, label: 'Surge Zones', page: _AdminPage.surge),
        (icon: Icons.ads_click_rounded, label: 'Ads', page: _AdminPage.ads),
      ]
    ),
    (
      label: 'SUBSCRIPTIONS',
      items: [
        (icon: Icons.card_membership_rounded, label: 'MealHub+', page: _AdminPage.mealhub),
        (icon: Icons.restaurant_menu_rounded, label: 'Meal Plans', page: _AdminPage.mealPlans),
      ]
    ),
    (
      label: 'DELIVERIES',
      items: [
        (icon: Icons.local_shipping_rounded, label: 'Shipping Cos.', page: _AdminPage.shippingCompanies),
        (icon: Icons.inventory_2_rounded, label: 'Packages', page: _AdminPage.packageDeliveries),
      ]
    ),
    (
      label: 'SYSTEM',
      items: [
        (icon: Icons.psychology_rounded, label: 'AI Panel', page: _AdminPage.aiPanel),
        (icon: Icons.miscellaneous_services_rounded, label: 'Services', page: _AdminPage.services),
        (icon: Icons.account_balance_rounded, label: 'Financials', page: _AdminPage.financials),
        (icon: Icons.bar_chart_rounded, label: 'Platform Revenue', page: _AdminPage.platformEarnings),
        (icon: Icons.monetization_on_rounded, label: 'Earnings', page: _AdminPage.earnings),
        (icon: Icons.description_rounded, label: 'Contract', page: _AdminPage.contract),
        (icon: Icons.manage_search_rounded, label: 'Lookup', page: _AdminPage.lookup),
        (icon: Icons.feedback_rounded, label: 'Feedback', page: _AdminPage.feedback),
      ]
    ),
  ];

  Widget _buildPage() => switch (_currentPage) {
    _AdminPage.dashboard          => const WebAdminDashboardPage(),
    _AdminPage.users              => const WebAdminUsersPage(),
    _AdminPage.restaurants        => const WebAdminRestaurantsPage(),
    _AdminPage.drivers            => const WebAdminDriversPage(),
    _AdminPage.orders             => const WebAdminOrdersPage(),
    _AdminPage.analytics          => const WebAdminAnalyticsPage(),
    _AdminPage.promos             => const WebAdminPromosPage(),
    _AdminPage.disputes           => const WebAdminDisputesPage(),
    _AdminPage.payouts            => const WebAdminPayoutsPage(),
    _AdminPage.pricing            => const WebAdminPricingPage(),
    _AdminPage.banners            => const WebAdminBannersPage(),
    _AdminPage.loyalty            => const WebAdminLoyaltyPage(),
    _AdminPage.aiPanel            => const WebAdminAiPanelPage(),
    _AdminPage.services           => const WebAdminServicesPage(),
    _AdminPage.financials         => const WebAdminFinancialsPage(),
    _AdminPage.lookup             => const WebAdminLookupPage(),
    _AdminPage.feedback           => const WebAdminFeedbackPage(),
    _AdminPage.surge              => const WebAdminSurgePage(),
    _AdminPage.platformEarnings   => const WebAdminPlatformEarningsPage(),
    _AdminPage.chats              => const WebAdminChatsPage(),
    _AdminPage.contract           => const WebAdminContractPage(),
    _AdminPage.ads                => const WebAdminAdsPage(),
    _AdminPage.mealhub            => const WebAdminMealhubPage(),
    _AdminPage.mealPlans          => const WebAdminMealPlansPage(),
    _AdminPage.shippingCompanies  => const WebAdminShippingCompaniesPage(),
    _AdminPage.packageDeliveries  => const WebAdminPackageDeliveriesPage(),
    _AdminPage.regions            => const WebAdminRegionsPage(),
    _AdminPage.earnings           => const WebAdminEarningsPage(),
  };

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(authNotifierProvider.notifier).signOut();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final currentUser = ref.watch(currentUserProvider);

    if (authState.user == null) {
      if (!authState.isAuthenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/signin', (_) => false);
        });
      }
      return const Scaffold(body: AppLoadingIndicator());
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────────────
          _AdminSidebar(
            userName: currentUser?.name?.split(' ').first ?? 'Admin',
            currentPage: _currentPage,
            onPageChanged: (p) => setState(() => _currentPage = p),
            onSignOut: _signOut,
            navGroups: _navGroups,
          ),
          // ── Content ──────────────────────────────────────────────
          Expanded(child: _buildPage()),
        ],
      ),
    );
  }
}

// ─── Sidebar ──────────────────────────────────────────────────────────────────

class _AdminSidebar extends StatelessWidget {
  final String userName;
  final _AdminPage currentPage;
  final ValueChanged<_AdminPage> onPageChanged;
  final VoidCallback onSignOut;
  final List<({String label, List<({IconData icon, String label, _AdminPage page})> items})> navGroups;

  const _AdminSidebar({
    required this.userName,
    required this.currentPage,
    required this.onPageChanged,
    required this.onSignOut,
    required this.navGroups,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(2, 0))],
      ),
      child: Column(
        children: [
          // ── Brand ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppTheme.primaryColor, const Color(0xFFFF8C5A)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Admin Panel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                      Text('Hi, $userName', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Nav groups ───────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: navGroups.map((group) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                    child: Text(group.label, style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  ),
                  ...group.items.map((item) => _SidebarItem(
                    icon: item.icon,
                    label: item.label,
                    isSelected: currentPage == item.page,
                    onTap: () => onPageChanged(item.page),
                  )),
                  const SizedBox(height: 4),
                ],
              )).toList(),
            ),
          ),
          // ── Sign out ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: _SidebarItem(
              icon: Icons.logout_rounded,
              label: 'Sign Out',
              isSelected: false,
              onTap: onSignOut,
              isDestructive: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isDestructive ? Colors.red : AppTheme.primaryColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? color.withValues(alpha: 0.15)
                : _hover ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: widget.isSelected ? Border.all(color: color.withValues(alpha: 0.3)) : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 17,
                color: widget.isSelected ? color : _hover ? Colors.white70 : Colors.white38),
              const SizedBox(width: 11),
              Text(widget.label, style: TextStyle(
                color: widget.isSelected ? Colors.white : _hover ? Colors.white70 : Colors.white54,
                fontSize: 13,
                fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
              )),
              if (widget.isSelected) ...[
                const Spacer(),
                Container(width: 4, height: 4, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
