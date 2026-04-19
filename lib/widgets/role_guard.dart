import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

/// Wraps a screen and only shows it if the user's role is in [allowedRoles].
/// Otherwise redirects to the correct dashboard for their actual role.
class RoleGuard extends ConsumerWidget {
  final List<String> allowedRoles;
  final Widget child;

  const RoleGuard({super.key, required this.allowedRoles, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authNotifierProvider).user?.role;

    if (role != null && allowedRoles.contains(role)) {
      return child;
    }

    // Redirect to the correct home for this role after the frame completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final route = _homeRouteForRole(role);
      Navigator.of(context).pushNamedAndRemoveUntil(route, (r) => false);
    });

    // Show nothing while redirecting
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }

  static String _homeRouteForRole(String? role) {
    switch (role) {
      case 'driver':
        return '/driver-dashboard';
      case 'restaurant':
        return '/restaurant-dashboard';
      case 'admin':
        return '/admin-dashboard';
      default:
        return '/home';
    }
  }
}
