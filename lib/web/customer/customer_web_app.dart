import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/restaurant_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import 'pages/web_customer_home_page.dart';
import 'pages/web_customer_orders_page.dart';
import 'pages/web_customer_cart_page.dart';
import 'pages/web_customer_wallet_page.dart';
import 'pages/web_customer_favorites_page.dart';
import 'pages/web_customer_addresses_page.dart';
import 'pages/web_customer_loyalty_page.dart';
import 'pages/web_customer_notifications_page.dart';
import 'pages/web_customer_profile_page.dart';
import 'pages/web_customer_restaurant_page.dart';
import 'pages/web_customer_checkout_page.dart';
import 'web_landing_page.dart';

enum _CustomerPage {
  home,
  orders,
  cart,
  wallet,
  favorites,
  addresses,
  loyalty,
  notifications,
  profile,
}

const _protectedPages = <_CustomerPage>{};

class CustomerWebApp extends ConsumerStatefulWidget {
  const CustomerWebApp({super.key});

  @override
  ConsumerState<CustomerWebApp> createState() => _CustomerWebAppState();
}

class _CustomerWebAppState extends ConsumerState<CustomerWebApp> {
  _CustomerPage _currentPage = _CustomerPage.home;
  Restaurant? _selectedRestaurant;
  bool _showCheckout = false;
  bool _showingLanding = true;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  void _openRestaurant(Restaurant r) => setState(() { _selectedRestaurant = r; _showCheckout = false; _showingLanding = false; });
  void _closeRestaurant()            => setState(() { _selectedRestaurant = null; });

  void _navigate(_CustomerPage page) {
    setState(() {
      _currentPage = page;
      _selectedRestaurant = null;
      _showCheckout = false;
      if (page != _CustomerPage.home) _showingLanding = false;
    });
  }

  Widget _buildBody(bool isGuest) {
    if (isGuest && _currentPage == _CustomerPage.home && _showingLanding) {
      return WebLandingPage(
        onBrowseFood: () => setState(() => _showingLanding = false),
        onSignIn:  () => _showAuthDialog(signUp: false),
        onSignUp:  () => _showAuthDialog(signUp: true),
        onRestaurantTapped: _openRestaurant,
      );
    }
    if (_showCheckout) {
      return WebCustomerCheckoutPage(
        onBack: () => setState(() => _showCheckout = false),
        onOrderPlaced: () => setState(() { _showCheckout = false; _currentPage = _CustomerPage.orders; }),
      );
    }
    if (_selectedRestaurant != null) {
      return WebCustomerRestaurantPage(
        restaurant: _selectedRestaurant!,
        onBack: _closeRestaurant,
      );
    }
    if (isGuest && _protectedPages.contains(_currentPage)) {
      return _AuthRequiredPage(
        onSignIn: () => _showAuthDialog(signUp: false),
        onSignUp: () => _showAuthDialog(signUp: true),
      );
    }
    return switch (_currentPage) {
      _CustomerPage.home          => WebCustomerHomePage(onRestaurantTapped: _openRestaurant),
      _CustomerPage.orders        => const WebCustomerOrdersPage(),
      _CustomerPage.cart          => WebCustomerCartPage(
          onCheckout: isGuest
            ? () => _showAuthDialog(signUp: false)
            : () => setState(() => _showCheckout = true),
        ),
      _CustomerPage.wallet        => const WebCustomerWalletPage(),
      _CustomerPage.favorites     => WebCustomerFavoritesPage(onRestaurantTapped: _openRestaurant),
      _CustomerPage.addresses     => const WebCustomerAddressesPage(),
      _CustomerPage.loyalty       => const WebCustomerLoyaltyPage(),
      _CustomerPage.notifications => const WebCustomerNotificationsPage(),
      _CustomerPage.profile       => const WebCustomerProfilePage(),
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
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
      if (mounted) setState(() { _currentPage = _CustomerPage.home; _selectedRestaurant = null; _showCheckout = false; _showingLanding = true; });
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  void _showAuthDialog({bool signUp = false}) {
    showDialog(
      context: context,
      builder: (_) => _AuthDialog(initialSignUp: signUp, onSuccess: () {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState  = ref.watch(authNotifierProvider);
    final isGuest    = !authState.isAuthenticated;
    final cartItems  = ref.watch(cartProvider);
    final cartCount  = cartItems.fold<int>(0, (s, i) => s + i.quantity);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_showCheckout) {
          setState(() => _showCheckout = false);
        } else if (_selectedRestaurant != null) {
          setState(() => _selectedRestaurant = null);
        } else if (!_showingLanding && _currentPage == _CustomerPage.home) {
          setState(() => _showingLanding = true);
        } else if (_currentPage != _CustomerPage.home) {
          setState(() { _currentPage = _CustomerPage.home; _showingLanding = true; });
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF8F8F8),
        // ── Drawer (hamburger navigation) ──────────────────────────────
        drawer: _NavDrawer(
          currentPage: _currentPage,
          isGuest: isGuest,
          userName: authState.user?.name?.split(' ').first ?? 'Guest',
          onNavigate: (p) { _scaffoldKey.currentState?.closeDrawer(); _navigate(p); },
          onSignIn: () { _scaffoldKey.currentState?.closeDrawer(); _showAuthDialog(signUp: false); },
          onSignUp: () { _scaffoldKey.currentState?.closeDrawer(); _showAuthDialog(signUp: true); },
          onSignOut: () { _scaffoldKey.currentState?.closeDrawer(); _signOut(); },
        ),
        // ── Top app bar ────────────────────────────────────────────────
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: _TopBar(
            isGuest: isGuest,
            userName: authState.user?.name ?? '',
            cartCount: cartCount,
            onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
            onCartTap: () => _navigate(_CustomerPage.cart),
            onSignIn: () => _showAuthDialog(signUp: false),
            onSignUp: () => _showAuthDialog(signUp: true),
            onProfileTap: () => _navigate(_CustomerPage.profile),
            onSignOut: _signOut,
          ),
        ),
        body: _buildBody(isGuest),
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool isGuest;
  final String userName;
  final int cartCount;
  final VoidCallback onMenuTap;
  final VoidCallback onCartTap;
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  final VoidCallback onProfileTap;
  final VoidCallback onSignOut;

  const _TopBar({
    required this.isGuest,
    required this.userName,
    required this.cartCount,
    required this.onMenuTap,
    required this.onCartTap,
    required this.onSignIn,
    required this.onSignUp,
    required this.onProfileTap,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 20),
      child: Row(
        children: [
          // Hamburger
          IconButton(
            icon: const Icon(Icons.menu_rounded, color: Color(0xFF1E293B)),
            onPressed: onMenuTap,
            tooltip: 'Menu',
          ),
          const SizedBox(width: 4),

          // Logo
          GestureDetector(
            onTap: onMenuTap,
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF8C5A)]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.fastfood_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 6),
              const Text('7DASH', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B), letterSpacing: -0.5)),
            ]),
          ),

          const Spacer(),

          // Cart
          _CartButton(count: cartCount, onTap: onCartTap, compact: isMobile),
          SizedBox(width: isMobile ? 4 : 16),

          // Auth
          if (isGuest) ...[
            if (!isMobile) ...[
              TextButton(
                onPressed: onSignIn,
                child: const Text('Log in', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              const SizedBox(width: 6),
            ],
            ElevatedButton(
              onPressed: isMobile ? onSignIn : onSignUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                elevation: 0,
              ),
              child: Text(isMobile ? 'Login' : 'Sign up', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ] else ...[
            _UserMenu(userName: userName, onProfile: onProfileTap, onSignOut: onSignOut, compact: isMobile),
          ],
        ],
      ),
    );
  }
}

class _CartButton extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  final bool compact;
  const _CartButton({required this.count, required this.onTap, this.compact = false});

  @override
  State<_CartButton> createState() => _CartButtonState();
}

class _CartButtonState extends State<_CartButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFF1F5F9) : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _hover ? const Color(0xFFE2E8F0) : Colors.transparent),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              const Icon(Icons.shopping_cart_rounded, color: Color(0xFF1E293B), size: 22),
              if (widget.count > 0)
                Positioned(
                  right: -6, top: -6,
                  child: Container(
                    width: 18, height: 18,
                    decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                    child: Center(
                      child: Text('${widget.count > 9 ? '9+' : widget.count}',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
            ]),
            if (!widget.compact) ...[
              const SizedBox(width: 6),
              Text(widget.count == 0 ? 'Cart' : '${widget.count} item${widget.count == 1 ? '' : 's'}',
                  style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _UserMenu extends StatefulWidget {
  final String userName;
  final VoidCallback onProfile;
  final VoidCallback onSignOut;
  final bool compact;
  const _UserMenu({required this.userName, required this.onProfile, required this.onSignOut, this.compact = false});

  @override
  State<_UserMenu> createState() => _UserMenuState();
}

class _UserMenuState extends State<_UserMenu> {
  @override
  Widget build(BuildContext context) {
    final initials = widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : 'U';
    return PopupMenuButton<String>(
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'profile', child: Row(children: [const Icon(Icons.person_outline_rounded, size: 18, color: Color(0xFF64748B)), const SizedBox(width: 10), Text('Profile')])),
        PopupMenuItem(value: 'signout', child: Row(children: [const Icon(Icons.logout_rounded, size: 18, color: Color(0xFF64748B)), const SizedBox(width: 10), const Text('Sign Out')])),
      ],
      onSelected: (v) {
        if (v == 'profile') widget.onProfile();
        if (v == 'signout') widget.onSignOut();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFFFF6B35),
            child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          if (!widget.compact) ...[
            const SizedBox(width: 8),
            Text(widget.userName.split(' ').first, style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(width: 4),
          ],
          const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
        ]),
      ),
    );
  }
}

// ── Navigation Drawer ─────────────────────────────────────────────────────────

class _NavDrawer extends StatelessWidget {
  final _CustomerPage currentPage;
  final bool isGuest;
  final String userName;
  final void Function(_CustomerPage) onNavigate;
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  final VoidCallback onSignOut;

  const _NavDrawer({
    required this.currentPage,
    required this.isGuest,
    required this.userName,
    required this.onNavigate,
    required this.onSignIn,
    required this.onSignUp,
    required this.onSignOut,
  });

  static const _items = [
    (icon: Icons.home_rounded,                   label: 'Home',          page: _CustomerPage.home),
    (icon: Icons.receipt_long_rounded,           label: 'My Orders',     page: _CustomerPage.orders),
    (icon: Icons.shopping_cart_rounded,          label: 'Cart',          page: _CustomerPage.cart),
    (icon: Icons.account_balance_wallet_rounded, label: 'Wallet',        page: _CustomerPage.wallet),
    (icon: Icons.favorite_rounded,               label: 'Favorites',     page: _CustomerPage.favorites),
    (icon: Icons.location_on_rounded,            label: 'Addresses',     page: _CustomerPage.addresses),
    (icon: Icons.loyalty_rounded,                label: 'Loyalty',       page: _CustomerPage.loyalty),
    (icon: Icons.notifications_rounded,          label: 'Notifications', page: _CustomerPage.notifications),
    (icon: Icons.person_rounded,                 label: 'Profile',       page: _CustomerPage.profile),
  ];

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 260,
      backgroundColor: const Color(0xFF0D2137),
      child: Column(children: [
        // Header
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF8C5A)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fastfood_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('7DASH', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                Text(isGuest ? 'Guest' : 'Hi, $userName 👋', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ]),
          ),
        ),

        if (isGuest) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onSignIn,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFFFF6B35), borderRadius: BorderRadius.circular(8)),
                      child: const Center(child: Text('Log in', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: onSignUp,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: const Center(child: Text('Sign up', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600))),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],

        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 8),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: _items.map((item) {
              final isSelected = currentPage == item.page;
              final isLocked   = isGuest && _protectedPages.contains(item.page);
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                tileColor: isSelected ? const Color(0xFFFF6B35).withValues(alpha: 0.15) : null,
                leading: Icon(item.icon, size: 20,
                    color: isLocked ? Colors.white24 : isSelected ? const Color(0xFFFF6B35) : Colors.white54),
                title: Text(item.label,
                    style: TextStyle(
                        color: isLocked ? Colors.white24 : isSelected ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400)),
                trailing: isLocked ? const Icon(Icons.lock_rounded, size: 13, color: Colors.white24) : null,
                onTap: () => onNavigate(item.page),
              );
            }).toList(),
          ),
        ),

        if (!isGuest) ...[
          const Divider(color: Colors.white12, height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 22),
            leading: const Icon(Icons.logout_rounded, size: 20, color: Colors.red),
            title: const Text('Sign Out', style: TextStyle(color: Colors.red, fontSize: 14)),
            onTap: onSignOut,
          ),
        ],

        const SizedBox(height: 16),
      ]),
    );
  }
}

// ── Auth-required page ────────────────────────────────────────────────────────

class _AuthRequiredPage extends StatelessWidget {
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  const _AuthRequiredPage({required this.onSignIn, required this.onSignUp});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF8C5A)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 20),
          const Text('Sign in to continue', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 10),
          const Text('Create a free account or sign in to access your orders, wallet, loyalty points, and more.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.5)),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onSignIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Log In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onSignUp,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1E293B),
                side: const BorderSide(color: Color(0xFF1E293B)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Create Account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('You can still browse restaurants without an account',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ]),
      ),
    );
  }
}

// ── Auth dialog ───────────────────────────────────────────────────────────────

class _AuthDialog extends ConsumerStatefulWidget {
  final bool initialSignUp;
  final VoidCallback onSuccess;
  const _AuthDialog({required this.initialSignUp, required this.onSuccess});

  @override
  ConsumerState<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends ConsumerState<_AuthDialog> {
  late bool _isSignUp;
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl     = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.initialSignUp;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final name     = _nameCtrl.text.trim();
    if (email.isEmpty || password.isEmpty) { setState(() => _error = 'Email and password are required'); return; }
    if (_isSignUp && name.isEmpty) { setState(() => _error = 'Name is required'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      if (_isSignUp) {
        await ref.read(authNotifierProvider.notifier).signUp(email: email, password: password, name: name, role: 'customer');
      } else {
        await ref.read(authNotifierProvider.notifier).signIn(email: email, password: password);
      }
      if (mounted) { Navigator.pop(context); widget.onSuccess(); }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = friendlyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF8C5A)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fastfood_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(_isSignUp ? 'Create Account' : 'Welcome Back',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 6),
            Text(_isSignUp ? 'Join to place orders and track deliveries' : 'Sign in to your account',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            const SizedBox(height: 20),

            if (_isSignUp) ...[
              _field(_nameCtrl, 'Full Name', Icons.person_outline_rounded),
              const SizedBox(height: 12),
            ],
            _field(_emailCtrl, 'Email Address', Icons.email_outlined, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            _pwField(),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(Icons.error_outline, size: 16, color: Colors.red.shade600),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red.shade700))),
                ]),
              ),
            ],
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isSignUp ? 'Create Account' : 'Log In',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: GestureDetector(
                onTap: () => setState(() { _isSignUp = !_isSignUp; _error = null; }),
                child: RichText(text: TextSpan(
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  children: [
                    TextSpan(text: _isSignUp ? 'Already have an account? ' : "Don't have an account? "),
                    TextSpan(
                      text: _isSignUp ? 'Log In' : 'Sign up',
                      style: const TextStyle(color: Color(0xFFFF6B35), fontWeight: FontWeight.w600),
                    ),
                  ],
                )),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon, {TextInputType? keyboardType}) {
    return TextField(
      controller: c,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF94A3B8)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1E293B), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _pwField() {
    return TextField(
      controller: _passwordCtrl,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFF94A3B8)),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: const Color(0xFF94A3B8)),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1E293B), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
