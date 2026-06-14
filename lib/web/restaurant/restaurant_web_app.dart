import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import 'restaurant_landing_page.dart';
import 'pages/web_restaurant_onboarding_page.dart';
import 'pages/web_dashboard_page.dart';
import 'pages/web_orders_page.dart';
import 'pages/web_menu_page.dart';
import 'pages/web_analytics_page.dart';
import 'pages/web_settings_page.dart';
import 'pages/web_grocery_page.dart';
import 'pages/web_loyalty_page.dart';
import 'pages/web_pending_approval_page.dart';

enum _RestaurantWebPage {
  dashboard,
  orders,
  menu,
  grocery,
  analytics,
  loyalty,
  settings,
}

class RestaurantWebApp extends ConsumerStatefulWidget {
  const RestaurantWebApp({super.key});

  @override
  ConsumerState<RestaurantWebApp> createState() => _RestaurantWebAppState();
}

// Role-word placeholders written by the old fallback bug — treat as missing.
const _kPlaceholderWords = {'driver', 'customer', 'restaurant', 'user', 'service', 'provider', 'partner'};

class _RestaurantWebAppState extends ConsumerState<RestaurantWebApp> {
  _RestaurantWebPage _currentPage = _RestaurantWebPage.dashboard;
  bool _namePatchDone = false;

  // If the stored name is a known placeholder, overwrite it with the auth
  // provider's display name (Google / email prefix) and refresh the user.
  Future<void> _patchPlaceholderName(String userId) async {
    if (_namePatchDone) return;
    _namePatchDone = true;
    final client = Supabase.instance.client;
    final meta = client.auth.currentUser?.userMetadata;
    final authName = ((meta?['full_name'] as String?)?.trim().isNotEmpty == true
            ? meta!['full_name'] as String
            : (meta?['name'] as String?)?.trim().isNotEmpty == true
                ? meta!['name'] as String
                : null) ??
        client.auth.currentUser?.email?.split('@').first;
    if (authName == null || authName.isEmpty) return;
    try {
      await client
          .from(AppConstants.tableUsers)
          .update({'name': authName})
          .eq('id', userId);
      await ref.read(authNotifierProvider.notifier).refreshUser();
    } catch (_) {}
  }

  static const _navItems = [
    (icon: Icons.dashboard_rounded, label: 'Dashboard', page: _RestaurantWebPage.dashboard),
    (icon: Icons.receipt_long_rounded, label: 'Orders', page: _RestaurantWebPage.orders),
    (icon: Icons.restaurant_menu_rounded, label: 'Menu', page: _RestaurantWebPage.menu),
    (icon: Icons.local_grocery_store_rounded, label: 'Grocery', page: _RestaurantWebPage.grocery),
    (icon: Icons.analytics_rounded, label: 'Analytics', page: _RestaurantWebPage.analytics),
    (icon: Icons.loyalty_rounded, label: 'Loyalty', page: _RestaurantWebPage.loyalty),
    (icon: Icons.settings_rounded, label: 'Settings', page: _RestaurantWebPage.settings),
  ];

  Widget _buildPage() {
    return switch (_currentPage) {
      _RestaurantWebPage.dashboard => const WebDashboardPage(),
      _RestaurantWebPage.orders => const WebOrdersPage(),
      _RestaurantWebPage.menu => const WebMenuPage(),
      _RestaurantWebPage.grocery => const WebGroceryPage(),
      _RestaurantWebPage.analytics => const WebAnalyticsPage(),
      _RestaurantWebPage.loyalty => const WebLoyaltyPage(),
      _RestaurantWebPage.settings => const WebSettingsPage(),
    };
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    if (authState.user == null || currentUserId == null) {
      if (!authState.isAuthenticated) {
        return const RestaurantLandingPage();
      }
      return const Scaffold(body: AppLoadingIndicator());
    }

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(currentUserId));

    // Still fetching restaurant data
    if (restaurantAsync.isLoading) {
      return const Scaffold(body: AppLoadingIndicator());
    }

    final restaurant = restaurantAsync.valueOrNull;

    // No restaurant yet, or still filling in the onboarding form → show onboarding
    if (restaurant == null || restaurant.onboardingStep < 7) {
      return const WebRestaurantOnboardingPage();
    }

    // Restaurant submitted but admin hasn't approved yet → pending screen
    if (!restaurant.isVerified) {
      return WebPendingApprovalPage(restaurantId: restaurant.id);
    }

    // Admin approved → show full dashboard
    final restaurantName = restaurant.name;
    final isOpen = restaurant.isOpen;

    // Patch legacy 'Driver' placeholder name in the background.
    final storedName = authState.user?.name;
    final isPlaceholder = storedName == null ||
        _kPlaceholderWords.contains(storedName.split(' ').first.toLowerCase());

    if (isPlaceholder) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _patchPlaceholderName(currentUserId),
      );
    }

    final userName = isPlaceholder ? 'Owner' : storedName.split(' ').first;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentPage != _RestaurantWebPage.dashboard) {
          // Back from a sub-page → go to dashboard first
          setState(() => _currentPage = _RestaurantWebPage.dashboard);
        } else {
          // Back from dashboard root → sign out, which shows the landing page
          _signOut();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        body: Row(
          children: [
            // ── Sidebar ─────────────────────────────────────────────────
            _WebSidebar(
              restaurantName: restaurantName,
              userName: userName,
              isOpen: isOpen,
              currentPage: _currentPage,
              onPageChanged: (page) => setState(() => _currentPage = page),
              onSignOut: _signOut,
              navItems: _navItems,
            ),
            // ── Main content ─────────────────────────────────────────────
            Expanded(
              child: _buildPage(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sidebar ─────────────────────────────────────────────────────────────────

class _WebSidebar extends StatelessWidget {
  final String restaurantName;
  final String userName;
  final bool isOpen;
  final _RestaurantWebPage currentPage;
  final ValueChanged<_RestaurantWebPage> onPageChanged;
  final VoidCallback onSignOut;
  final List<({IconData icon, String label, _RestaurantWebPage page})> navItems;

  const _WebSidebar({
    required this.restaurantName,
    required this.userName,
    required this.isOpen,
    required this.currentPage,
    required this.onPageChanged,
    required this.onSignOut,
    required this.navItems,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(2, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Brand header ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primaryColor, const Color(0xFFFF8C5A)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        restaurantName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Hi, $userName',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Open/Closed badge ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isOpen
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isOpen
                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                      : Colors.red.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      color: isOpen ? const Color(0xFF10B981) : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isOpen ? 'OPEN' : 'CLOSED',
                    style: TextStyle(
                      color: isOpen ? const Color(0xFF10B981) : Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Nav items ────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'NAVIGATION',
              style: TextStyle(
                color: Colors.white30,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: navItems.map((item) {
                final isSelected = currentPage == item.page;
                return _SidebarItem(
                  icon: item.icon,
                  label: item.label,
                  isSelected: isSelected,
                  onTap: () => onPageChanged(item.page),
                );
              }).toList(),
            ),
          ),
          // ── Sign out ─────────────────────────────────────────────────
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
    final Color activeColor = widget.isDestructive ? Colors.red : AppTheme.primaryColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? activeColor.withValues(alpha: 0.15)
                : _hover
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: widget.isSelected
                ? Border.all(color: activeColor.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: widget.isSelected
                    ? activeColor
                    : _hover
                        ? Colors.white70
                        : Colors.white38,
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.isSelected
                      ? Colors.white
                      : _hover
                          ? Colors.white70
                          : Colors.white54,
                  fontSize: 13,
                  fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (widget.isSelected) ...[
                const Spacer(),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: activeColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
