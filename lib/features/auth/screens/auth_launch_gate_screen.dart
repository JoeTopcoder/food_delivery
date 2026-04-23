import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../../screens/main_navigation_screen.dart';
import '../../../screens/driver/driver_dashboard_screen.dart';
import '../../../screens/restaurant/restaurant_dashboard_screen.dart';
import '../../../screens/admin/admin_dashboard_screen.dart';
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

    if (auth.isAuthenticated) {
      final role = auth.user?.role;
      switch (role) {
        case 'customer':
          return const MainNavigationScreen();
        case 'driver':
          return const DriverDashboardScreen();
        case 'restaurant':
          return const RestaurantDashboardScreen();
        case 'admin':
          return const AdminDashboardScreen();
        default:
          // Unknown / null role — sign out immediately and return to role
          // selection so an unrecognised role can NEVER silently see any
          // home screen.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(authNotifierProvider.notifier).signOut();
          });
          return const RoleSelectionScreen();
      }
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
