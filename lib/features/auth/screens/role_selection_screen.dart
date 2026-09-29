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
    Navigator.of(context).pushReplacementNamed('/signin');
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0F1F3D);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Brand header ────────────────────────────────────────────
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 46,
                      height: 46,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.delivery_dining_rounded,
                        color: Color(0xFF16A34A),
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'HotBite',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: navy,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'More than food.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Text(
                'Choose your path',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: navy,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Get value first. Finish details later.',
                style: TextStyle(fontSize: 15, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 22),
              _RoleCard(
                icon: Icons.restaurant_menu_rounded,
                title: 'Order Food',
                subtitle: 'Browse restaurants in under 10 seconds.',
                color: const Color(0xFFF97316),
                image: 'assets/images/roles/food.jpg',
                imageOnRight: false,
                enabled: !_navigating,
                onTap: () => _continueAs(context, ref, OnboardingRole.customer),
              ),
              const SizedBox(height: 14),
              _RoleCard(
                icon: Icons.directions_car_filled_rounded,
                title: 'Earn as Driver',
                subtitle: 'Apply in under 2 minutes.',
                color: const Color(0xFF16A34A),
                image: 'assets/images/roles/driver.jpg',
                imageOnRight: true,
                enabled: !_navigating,
                onTap: () => _continueAs(context, ref, OnboardingRole.driver),
              ),
              const SizedBox(height: 14),
              _RoleCard(
                icon: Icons.storefront_rounded,
                title: 'Partner Restaurant',
                subtitle: 'Go live in under 5 minutes.',
                color: const Color(0xFF7C3AED),
                image: 'assets/images/roles/chef.jpg',
                imageOnRight: false,
                enabled: !_navigating,
                onTap: () =>
                    _continueAs(context, ref, OnboardingRole.restaurant),
              ),
              const SizedBox(height: 14),
              _RoleCard(
                icon: Icons.local_car_wash_rounded,
                title: 'Car Service Provider',
                subtitle: 'List your car wash or detailing service.',
                color: const Color(0xFF2563EB),
                image: 'assets/images/roles/carwash.jpg',
                imageOnRight: true,
                enabled: !_navigating,
                onTap: () =>
                    _continueAs(context, ref, OnboardingRole.serviceProvider),
              ),
              const SizedBox(height: 26),
              // ── Sign in ────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_outline_rounded,
                      size: 20, color: Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  const Text(
                    'Already have an account?',
                    style: TextStyle(fontSize: 14.5, color: Color(0xFF334155)),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pushNamed('/signin'),
                    child: const Text(
                      'Sign in',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ],
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
    required this.image,
    required this.imageOnRight,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String image;
  final bool imageOnRight;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0F1F3D);

    // Decorative "photo" block (we have no per-role images, so use a branded
    // gradient panel with the role icon — echoes the mockup's image side).
    Widget imageBlock() => ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            image,
            width: 104,
            height: 74,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 104,
              height: 74,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withValues(alpha: 0.72)],
                ),
              ),
              alignment: Alignment.center,
              child: Icon(icon,
                  color: Colors.white.withValues(alpha: 0.9), size: 44),
            ),
          ),
        );

    final textBlock = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: navy,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF475569),
              height: 1.3,
            ),
          ),
        ],
      ),
    );

    final arrow = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const Icon(Icons.arrow_forward_ios_rounded,
          color: Colors.white, size: 16),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(
              children: imageOnRight
                  ? [
                      textBlock,
                      const SizedBox(width: 10),
                      arrow,
                      const SizedBox(width: 10),
                      imageBlock(),
                    ]
                  : [
                      imageBlock(),
                      const SizedBox(width: 14),
                      textBlock,
                      const SizedBox(width: 10),
                      arrow,
                    ],
            ),
          ),
        ),
      ),
    );
  }
}
