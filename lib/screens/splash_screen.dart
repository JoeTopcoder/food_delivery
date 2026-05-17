import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../features/auth/screens/auth_launch_gate_screen.dart';
import '../providers/auth_provider.dart';
import '../screens/driver/driver_dashboard_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../services/notification_service.dart';
import '../screens/restaurant/restaurant_dashboard_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../widgets/role_guard.dart';

/// Role-specific splash screen with animated branding.
/// Shows a beautiful animated intro before navigating to the role's home.
class SplashScreen extends StatefulWidget {
  final String role; // 'customer', 'driver', 'restaurant', 'admin'
  final Widget destination;

  const SplashScreen({
    super.key,
    required this.role,
    required this.destination,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _contentController;
  late final AnimationController _bgController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _titleSlide;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _subtitleOpacity;
  late final Animation<double> _shimmer;
  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    // Logo bounce-in animation
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Content fade-in
    _contentController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Background shimmer loop
    _bgController = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat();

    // Logo: elastic scale-in
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );

    // Expanding ring behind logo
    _ringScale = Tween<double>(begin: 0.5, end: 1.6).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );
    _ringOpacity = Tween<double>(begin: 0.5, end: 0.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    // Title slide-up
    _titleSlide = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeOutCubic),
    );

    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );

    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(_bgController);

    // Start animation sequence
    _logoController.forward().then((_) {
      _contentController.forward().then((_) {
        _navigate();
      });
    });
  }

  void _navigate() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              widget.destination,
          transitionsBuilder: (context, anim, secondaryAnimation, child) {
            return FadeTransition(opacity: anim, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _contentController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = _RoleConfig.of(widget.role);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Gradient background
          AnimatedBuilder(
            animation: _shimmer,
            builder: (_, _) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    config.gradientStart,
                    config.gradientEnd,
                    config.gradientStart,
                  ],
                  stops: [0.0, (_shimmer.value).clamp(0.0, 1.0), 1.0],
                ),
              ),
            ),
          ),

          // Floating circles decoration
          ..._buildFloatingCircles(size, config),

          // Main content
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),

                // Animated logo
                AnimatedBuilder(
                  animation: _logoController,
                  builder: (_, _) => Stack(
                    alignment: Alignment.center,
                    children: [
                      // Expanding ring
                      Transform.scale(
                        scale: _ringScale.value,
                        child: Opacity(
                          opacity: _ringOpacity.value,
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ),
                      // Logo icon
                      Transform.scale(
                        scale: _logoScale.value,
                        child: Opacity(
                          opacity: _logoOpacity.value,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/mealhub_logo.png',
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Title & subtitle
                AnimatedBuilder(
                  animation: _contentController,
                  builder: (_, _) => Transform.translate(
                    offset: Offset(0, _titleSlide.value),
                    child: Column(
                      children: [
                        Opacity(
                          opacity: _titleOpacity.value,
                          child: Text(
                            '7DASH',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Opacity(
                          opacity: _titleOpacity.value,
                          child: Text(
                            'Food. Fast. Delivered.',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.85),
                              fontStyle: FontStyle.italic,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Opacity(
                          opacity: _titleOpacity.value,
                          child: Text(
                            config.title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.95),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Opacity(
                          opacity: _subtitleOpacity.value,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              config.subtitle,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // Loading indicator
                AnimatedBuilder(
                  animation: _contentController,
                  builder: (_, _) => Opacity(
                    opacity: _subtitleOpacity.value,
                    child: Column(
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          config.loadingText,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFloatingCircles(Size size, _RoleConfig config) {
    final random = Random(widget.role.hashCode);
    return List.generate(6, (i) {
      final circleSize = 60.0 + random.nextDouble() * 140;
      final left = random.nextDouble() * size.width;
      final top = random.nextDouble() * size.height;
      return Positioned(
        left: left - circleSize / 2,
        top: top - circleSize / 2,
        child: AnimatedBuilder(
          animation: _bgController,
          builder: (_, _) {
            final phase = (_bgController.value + i * 0.15) % 1.0;
            final scale = 0.8 + sin(phase * pi * 2) * 0.2;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(
                    alpha: 0.04 + random.nextDouble() * 0.04,
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Role configuration
// ─────────────────────────────────────────────────────────────────────────────

class _RoleConfig {
  final Color gradientStart;
  final Color gradientEnd;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final String loadingText;

  const _RoleConfig({
    required this.gradientStart,
    required this.gradientEnd,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.loadingText,
  });

  static _RoleConfig of(String role) {
    switch (role) {
      case 'admin':
        return const _RoleConfig(
          gradientStart: Color(0xFF1E1B4B),
          gradientEnd: Color(0xFF4C1D95),
          iconColor: Color(0xFF7C3AED),
          icon: Icons.admin_panel_settings_rounded,
          title: 'Admin Portal',
          subtitle: 'Manage your platform',
          loadingText: 'Loading dashboard...',
        );
      case 'driver':
        return const _RoleConfig(
          gradientStart: Color(0xFF0F172A),
          gradientEnd: Color(0xFF1E40AF),
          iconColor: Color(0xFF3B82F6),
          icon: Icons.delivery_dining_rounded,
          title: 'Driver Hub',
          subtitle: 'Ready to deliver',
          loadingText: 'Finding deliveries...',
        );
      case 'restaurant':
        return const _RoleConfig(
          gradientStart: Color(0xFF14532D),
          gradientEnd: Color(0xFF15803D),
          iconColor: Color(0xFF22C55E),
          icon: Icons.restaurant_rounded,
          title: 'Restaurant Portal',
          subtitle: 'Manage your kitchen',
          loadingText: 'Loading orders...',
        );
      default: // customer
        return const _RoleConfig(
          gradientStart: Color(0xFF581C87),
          gradientEnd: Color(0xFF7C3AED),
          iconColor: Color(0xFF7C3AED),
          icon: Icons.fastfood_rounded,
          title: 'Welcome Back!',
          subtitle: 'Discover & order deliciou food',
          loadingText: 'Finding restaurants near you...',
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App Launch Splash — shown on every cold start.
// Handles: auth restore, notification permission (once), location permission.
// ─────────────────────────────────────────────────────────────────────────────

class AppLaunchSplash extends ConsumerStatefulWidget {
  const AppLaunchSplash({super.key});

  @override
  ConsumerState<AppLaunchSplash> createState() => _AppLaunchSplashState();
}

class _AppLaunchSplashState extends ConsumerState<AppLaunchSplash>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _contentController;
  late final AnimationController _bgController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _titleSlide;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat();

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _contentController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );
    _titleSlide = Tween<double>(begin: 24.0, end: 0.0).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeOutCubic),
    );
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeIn),
    );
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(_bgController);

    _logoController.forward().then((_) => _contentController.forward());

    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    // Minimum branded splash; FCM init runs in parallel and doesn't block nav.
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 600)),
      _doPermissionsAndAuth(),
    ]);
  }

  Future<void> _doPermissionsAndAuth() async {
    // FCM registration can take several seconds on slow devices — fire and forget
    // so it never blocks navigation. The service sets itself up in the background.
    unawaited(NotificationService().initialize());

    // Location — request once if not yet granted
    final locPerm = await Geolocator.checkPermission();
    if (locPerm == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }

    // Auth — Supabase restores session from secure storage automatically
    if (!mounted) return;
    final auth = ref.read(authNotifierProvider);

    Widget destination;
    if (auth.isAuthenticated) {
      final role = auth.user?.role;
      switch (role) {
        case 'customer':
        case 'user':
          destination = const RoleGuard(
            allowedRoles: ['user', 'customer'],
            child: MainNavigationScreen(),
          );
          break;
        case 'driver':
          destination = const RoleGuard(
            allowedRoles: ['driver'],
            child: DriverDashboardScreen(),
          );
          break;
        case 'restaurant':
          destination = const RoleGuard(
            allowedRoles: ['restaurant'],
            child: RestaurantDashboardScreen(),
          );
          break;
        case 'admin':
          destination = const RoleGuard(
            allowedRoles: ['admin'],
            child: AdminDashboardScreen(),
          );
          break;
        default:
          // Unknown role — sign out to prevent wrong screen
          await ref.read(authNotifierProvider.notifier).signOut();
          destination = const AuthLaunchGateScreen();
      }
    } else {
      destination = const AuthLaunchGateScreen();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );

    // Process any FCM notification that cold-launched the app, now that the
    // main navigator is mounted and the route can be pushed correctly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().processPendingLaunchMessage();
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _contentController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Gradient background
          AnimatedBuilder(
            animation: _shimmer,
            builder: (_, __) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: const [
                    Color(0xFF581C87),
                    Color(0xFF7C3AED),
                    Color(0xFF581C87),
                  ],
                  stops: [0.0, _shimmer.value.clamp(0.0, 1.0), 1.0],
                ),
              ),
            ),
          ),

          // Floating decorative circles
          ..._buildCircles(MediaQuery.of(context).size),

          // Content
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),

                // Logo
                AnimatedBuilder(
                  animation: _logoController,
                  builder: (_, __) => Transform.scale(
                    scale: _logoScale.value,
                    child: Opacity(
                      opacity: _logoOpacity.value,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 32,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/mealhub_logo.png',
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 36),

                // Title
                AnimatedBuilder(
                  animation: _contentController,
                  builder: (_, __) => Transform.translate(
                    offset: Offset(0, _titleSlide.value),
                    child: Opacity(
                      opacity: _titleOpacity.value,
                      child: Column(
                        children: [
                          Text(
                            '7DASH',
                            style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Food. Fast. Delivered.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.85),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // Loading spinner
                AnimatedBuilder(
                  animation: _contentController,
                  builder: (_, __) => Opacity(
                    opacity: _titleOpacity.value,
                    child: Column(
                      children: [
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Getting things ready...',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCircles(Size size) {
    final rng = Random(42);
    return List.generate(6, (i) {
      final sz = 60.0 + rng.nextDouble() * 140;
      final l = rng.nextDouble() * size.width;
      final t = rng.nextDouble() * size.height;
      return Positioned(
        left: l - sz / 2,
        top: t - sz / 2,
        child: AnimatedBuilder(
          animation: _bgController,
          builder: (_, __) {
            final phase = (_bgController.value + i * 0.15) % 1.0;
            final scale = 0.8 + sin(phase * pi * 2) * 0.2;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: sz,
                height: sz,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(
                    alpha: 0.04 + rng.nextDouble() * 0.04,
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }
}
