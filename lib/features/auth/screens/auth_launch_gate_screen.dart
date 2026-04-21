import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../../../screens/main_navigation_screen.dart';
import '../../../screens/driver/driver_dashboard_screen.dart';
import '../../../screens/restaurant/restaurant_dashboard_screen.dart';
import '../models/onboarding_role.dart';
import '../providers/role_provider.dart';
import 'role_selection_screen.dart';

class AuthLaunchGateScreen extends ConsumerWidget {
  const AuthLaunchGateScreen({super.key});

  static OnboardingRole? _roleFromDeepLink() {
    final route = WidgetsBinding.instance.platformDispatcher.defaultRouteName
        .toLowerCase();

    if (route.contains('/join/driver')) return OnboardingRole.driver;
    if (route.contains('/join/restaurant')) return OnboardingRole.restaurant;
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);

    if (auth.isAuthenticated) {
      final role = auth.user?.role;
      switch (role) {
        case 'driver':
          return const DriverDashboardScreen();
        case 'restaurant':
          return const RestaurantDashboardScreen();
        default:
          return const MainNavigationScreen();
      }
    }

    final roleIntentAsync = ref.watch(roleProvider);
    return roleIntentAsync.when(
      data: (savedRole) {
        final deepLinkRole = _roleFromDeepLink();
        final targetRole = deepLinkRole ?? savedRole;
        if (targetRole == null) return const RoleSelectionScreen();

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!context.mounted) return;
          ref.read(roleProvider.notifier).setRole(targetRole);
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(targetRole.route, (_) => false);
        });

        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const RoleSelectionScreen(),
    );
  }
}
