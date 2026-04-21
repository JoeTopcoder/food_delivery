import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/onboarding_role.dart';
import '../providers/role_provider.dart';

class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  Future<void> _continueAs(
    BuildContext context,
    WidgetRef ref,
    OnboardingRole role,
  ) async {
    await ref.read(roleProvider.notifier).setRole(role);
    if (!context.mounted) return;
    Navigator.of(context).pushNamed(role.route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
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
                onTap: () => _continueAs(context, ref, OnboardingRole.customer),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.delivery_dining_rounded,
                title: 'Earn as Driver',
                subtitle: 'Apply in under 2 minutes',
                color: const Color(0xFF16A34A),
                onTap: () => _continueAs(context, ref, OnboardingRole.driver),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.storefront_rounded,
                title: 'Partner Restaurant',
                subtitle: 'Go live in under 5 minutes',
                color: const Color(0xFF2563EB),
                onTap: () =>
                    _continueAs(context, ref, OnboardingRole.restaurant),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/signin'),
                child: const Text('Already have an account? Sign in'),
              ),
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
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
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
