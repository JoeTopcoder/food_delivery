import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

/// Wraps a screen and only shows it if the user's role is in [allowedRoles].
/// Otherwise redirects to the correct dashboard for their actual role.
class RoleGuard extends ConsumerStatefulWidget {
  final List<String> allowedRoles;
  final Widget child;

  const RoleGuard({super.key, required this.allowedRoles, required this.child});

  @override
  ConsumerState<RoleGuard> createState() => _RoleGuardState();
}

class _RoleGuardState extends ConsumerState<RoleGuard> {
  bool _navigating = false;

  void _redirectOnce(String route) {
    if (_navigating) return;
    _navigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(route, (r) => false);
    });
  }

  static String _homeRouteForRole(String? role) {
    switch (role) {
      case 'driver':
        return '/driver-dashboard';
      case 'restaurant':
        return '/restaurant-dashboard';
      case 'admin':
        return '/admin-dashboard';
      case 'service_provider':
        return '/car-services/provider';
      case 'laundry_provider':
        return '/laundry/provider-dashboard';
      case 'customer':
      default:
        return '/home';
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final rawRole = authState.user?.role;
    final role = rawRole == 'customer' ? 'user' : rawRole;

    if (!authState.isAuthenticated || role == null) {
      _redirectOnce('/signin');
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (widget.allowedRoles.contains(role) || rawRole == 'admin') {
      return widget.child;
    }

    _redirectOnce(_homeRouteForRole(rawRole));
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
