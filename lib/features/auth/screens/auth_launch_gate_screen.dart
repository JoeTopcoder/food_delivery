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
import '../../../widgets/role_guard.dart';
import '../models/onboarding_role.dart';
import '../providers/role_provider.dart';
import 'role_selection_screen.dart';

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

      // On web only admin access is allowed.
      if (kIsWeb && role != 'admin') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(authNotifierProvider.notifier).signOut();
        });
        return const _WebAdminOnlyScreen();
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
          return const RoleGuard(
            allowedRoles: ['restaurant'],
            child: RestaurantDashboardScreen(),
          );
        case 'admin':
          return const RoleGuard(
            allowedRoles: ['admin'],
            child: AdminDashboardScreen(),
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
          return kIsWeb ? const _WebAdminOnlyScreen() : const RoleSelectionScreen();
      }
    }

    // Not authenticated — on web navigate to the sign-in route so SignInScreen
    // renders as a proper route (with full context: theme, l10n, navigator).
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/signin');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final roleIntentAsync = ref.watch(roleProvider);
    return roleIntentAsync.when(
      data: (savedRole) {
        final deepLinkRole = _roleFromDeepLink();
        final targetRole = deepLinkRole ?? savedRole;
        if (targetRole == null) return const RoleSelectionScreen();

        _navigateToRole(targetRole);

        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const RoleSelectionScreen(),
    );
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
