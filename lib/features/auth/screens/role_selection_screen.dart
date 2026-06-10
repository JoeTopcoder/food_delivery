import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/auth_provider.dart';
import '../models/onboarding_role.dart';
import '../providers/role_provider.dart';

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  bool _navigating = false;

  Future<void> _continueAs(
    BuildContext context,
    WidgetRef ref,
    OnboardingRole role,
  ) async {
    if (_navigating) return;
    setState(() => _navigating = true);

    final authState = ref.read(authNotifierProvider);
    if (authState.isAuthenticated) {
      final signedInRole = authState.user?.role;
      final route = switch (signedInRole) {
        'driver' => '/driver-dashboard',
        'restaurant' => '/restaurant-dashboard',
        'admin' => '/admin-dashboard',
        'service_provider' => '/car-services/provider',
        _ => '/home',
      };
      if (!context.mounted) return;
      Navigator.of(context).pushReplacementNamed(route);
      return;
    }

    await ref.read(roleProvider.notifier).setRole(role);
    if (!context.mounted) return;
    Navigator.of(context).pushReplacementNamed(role.route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text(
                'Choose your path',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Get value first. Finish details later.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),
              _RoleCard(
                icon: Icons.fastfood_rounded,
                title: 'Order Food',
                subtitle: 'Browse restaurants in under 10 seconds',
                color: const Color(0xFFFF7A1A),
                enabled: !_navigating,
                onTap: () => _continueAs(context, ref, OnboardingRole.customer),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.delivery_dining_rounded,
                title: 'Earn as Driver',
                subtitle: 'Apply in under 2 minutes',
                color: const Color(0xFF16A34A),
                enabled: !_navigating,
                onTap: () => _continueAs(context, ref, OnboardingRole.driver),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.storefront_rounded,
                title: 'Partner Restaurant',
                subtitle: 'Go live in under 5 minutes',
                color: const Color(0xFF2563EB),
                enabled: !_navigating,
                onTap: () =>
                    _continueAs(context, ref, OnboardingRole.restaurant),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.car_repair_rounded,
                title: 'Car Service Provider',
                subtitle: 'List your car wash or detailing service',
                color: const Color(0xFF0D9488),
                enabled: !_navigating,
                onTap: () =>
                    _continueAs(context, ref, OnboardingRole.serviceProvider),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/signin'),
                child: const Text('Already have an account? Sign in'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: enabled ? 0.08 : 0.04),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
