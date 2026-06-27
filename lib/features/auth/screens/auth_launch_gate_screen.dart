import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../../screens/main_navigation_screen.dart';
import '../../../screens/driver/driver_dashboard_screen.dart';
import '../../../screens/restaurant/restaurant_dashboard_screen.dart';
import '../../../screens/admin/admin_dashboard_screen.dart';
import '../../../modules/car_services/screens/provider/car_service_provider_dashboard_screen.dart';
import '../../../web/restaurant/restaurant_landing_page.dart';
import '../../../web/restaurant/restaurant_web_app.dart';
import '../../../web/admin/admin_web_app.dart';
import '../../../widgets/role_guard.dart';
import '../models/onboarding_role.dart';
import '../providers/role_provider.dart';
import 'role_selection_screen.dart';

// Injected at build time via --dart-define=WEB_MODE=restaurant|admin|full
const _webMode = String.fromEnvironment('WEB_MODE', defaultValue: 'full');

class AuthLaunchGateScreen extends ConsumerStatefulWidget {
  const AuthLaunchGateScreen({super.key});

  @override
  ConsumerState<AuthLaunchGateScreen> createState() =>
      _AuthLaunchGateScreenState();
}

class _AuthLaunchGateScreenState extends ConsumerState<AuthLaunchGateScreen> {
  bool _navigated = false;
  Timer? _loadingTimer;

  @override
  void initState() {
    super.initState();
    // Hard cap: if auth stays loading for >10 s (e.g. DB query hangs on slow
    // network after a cold restart), fall through to role-selection instead of
    // showing an infinite spinner.
    _loadingTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || _navigated) return;
      if (ref.read(authNotifierProvider).isLoading) {
        _navigated = true;
        Navigator.of(context).pushReplacementNamed('/role-selection');
      }
    });
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  static OnboardingRole? _roleFromDeepLink() {
    final route = WidgetsBinding.instance.platformDispatcher.defaultRouteName
        .toLowerCase();

    if (route.contains('/join/driver')) return OnboardingRole.driver;
    if (route.contains('/join/restaurant')) return OnboardingRole.restaurant;
    return null;
  }

  void _navigateToRole(OnboardingRole targetRole) {
    if (_navigated) return;
    _navigated = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(roleProvider.notifier).setRole(targetRole);
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(targetRole.route, (_) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);

    if (auth.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (auth.isAuthenticated) {
      final role = auth.user?.role;

      // On web, enforce role matches the build mode.
      if (kIsWeb) {
        final allowed = _webMode == 'restaurant'
            ? role == 'restaurant'
            : _webMode == 'admin'
                ? role == 'admin'
                : true; // full mode: allow all
        if (!allowed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(authNotifierProvider.notifier).signOut();
          });
          return _webMode == 'restaurant'
              ? const RestaurantLandingPage()
              : const _WebAdminOnlyScreen();
        }
      }

      switch (role) {
        case 'customer':
        case 'user':
          return const RoleGuard(
            allowedRoles: ['user', 'customer'],
            child: MainNavigationScreen(),
          );
        case 'driver':
          return const RoleGuard(
            allowedRoles: ['driver'],
            child: DriverDashboardScreen(),
          );
        case 'restaurant':
          return RoleGuard(
            allowedRoles: const ['restaurant'],
            child: (kIsWeb && (_webMode == 'full' || _webMode == 'restaurant'))
                ? const RestaurantWebApp()
                : const RestaurantDashboardScreen(),
          );
        case 'admin':
          return RoleGuard(
            allowedRoles: const ['admin'],
            child: (kIsWeb && (_webMode == 'full' || _webMode == 'admin'))
                ? const AdminWebApp()
                : const AdminDashboardScreen(),
          );
        case 'service_provider':
          return const RoleGuard(
            allowedRoles: ['service_provider'],
            child: CarServiceProviderDashboardScreen(),
          );
        default:
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(authNotifierProvider.notifier).signOut();
          });
          return kIsWeb && _webMode == 'restaurant'
              ? const RestaurantLandingPage()
              : kIsWeb
                  ? const _WebAdminOnlyScreen()
                  : const RoleSelectionScreen();
      }
    }

    // Not authenticated
    if (kIsWeb) {
      // Restaurant build: show the marketing landing page directly
      if (_webMode == 'restaurant') return const RestaurantLandingPage();
      // Admin/full build: navigate to sign-in
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/signin');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Deep-link: /join/driver or /join/restaurant → skip guest mode and go
    // straight to the matching onboarding screen so drivers/restaurants can
    // sign up without first seeing the home screen.
    final deepLinkRole = _roleFromDeepLink();
    if (deepLinkRole != null) {
      _navigateToRole(deepLinkRole);
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Guest-browsing: already chose "Browse as Guest" this session → home.
    final isGuestBrowsing = ref.watch(guestBrowsingProvider);
    if (isGuestBrowsing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _navigated) return;
        _navigated = true;
        Navigator.of(context).pushReplacementNamed('/home');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Default unauthenticated path: go straight to home (guest mode).
    // The home screen's profile tab and cart will prompt sign-in when needed.
    // This satisfies App Store guideline 5.1.1(v) — no forced registration
    // before browsing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _navigated) return;
      _navigated = true;
      // Enable guest-browsing flag so future navigations know we're in guest mode.
      ref.read(guestBrowsingProvider.notifier).state = true;
      Navigator.of(context).pushReplacementNamed('/home');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _WebAdminOnlyScreen extends StatelessWidget {
  const _WebAdminOnlyScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.admin_panel_settings_rounded,
                size: 64, color: Color(0xFF7C3AED)),
            const SizedBox(height: 24),
            const Text(
              'Admin Access Only',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This web portal is restricted to administrators.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
              child: const Text('Back to Sign In'),
            ),
          ],
        ),
      ),
    );
  }
}
