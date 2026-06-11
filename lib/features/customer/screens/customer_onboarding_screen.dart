import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../features/auth/models/onboarding_role.dart';
import '../../../features/auth/providers/onboarding_provider.dart';
import '../../../features/auth/providers/role_provider.dart';
import '../../../features/auth/services/onboarding_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../utils/app_logger.dart';
import '../../../services/notification_service.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class CustomerOnboardingScreen extends ConsumerStatefulWidget {
  const CustomerOnboardingScreen({super.key});

  @override
  ConsumerState<CustomerOnboardingScreen> createState() =>
      _CustomerOnboardingScreenState();
}

class _CustomerOnboardingScreenState
    extends ConsumerState<CustomerOnboardingScreen> {
  // ── Controllers & state ────────────────────────────────────────────────────

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  bool _emailLoading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _enableLocation = true;
  bool _enableNotifications = true;
  bool _passwordVisible = false;

  bool get _isBusy => _emailLoading || _googleLoading || _appleLoading;

  bool get _showApple {
    if (kIsWeb) {
      return defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS;
    }
    return Platform.isIOS || Platform.isMacOS;
  }

  // ── Routing ────────────────────────────────────────────────────────────────

  String _routeForRole(String? role) {
    switch (role) {
      case 'driver':
        return '/driver-dashboard';
      case 'restaurant':
        return '/restaurant-dashboard';
      case 'admin':
        return '/admin-dashboard';
      case 'service_provider':
        return '/car-services/provider';
      default:
        return '/home';
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoAdvanceIfReady());
  }

  Future<void> _autoAdvanceIfReady() async {
    if (!mounted) return;
    final isAuth = ref.read(authNotifierProvider).isAuthenticated;
    if (!isAuth) return;

    await ref
        .read(onboardingProvider(OnboardingRole.customer).notifier)
        .setStep(3);
    if (!mounted) return;
    final role = ref.read(authNotifierProvider).user?.role;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(_routeForRole(role), (_) => false);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  // ── Auth handlers (logic unchanged) ───────────────────────────────────────

  Future<void> _signUpWithEmail() async {
    final email = _email.text.trim();
    final password = _password.text;
    final name = _name.text.trim();
    if (name.isEmpty) {
      AppSnackbar.error(context, 'Please enter your full name.');
      return;
    }
    if (email.isEmpty || password.isEmpty) {
      AppSnackbar.error(context, 'Enter your email and password.');
      return;
    }
    setState(() => _emailLoading = true);
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .signUp(email: email, password: password, name: name, role: 'user');
      final authState = ref.read(authNotifierProvider);
      if (authState.emailConfirmationPending) {
        if (!mounted) return;
        AppSnackbar.info(
          context,
          'Account created! Check your email to confirm, then sign in.',
        );
        Navigator.of(context).pushReplacementNamed('/signin');
        return;
      }
      await _afterAuthSuccess();
    } catch (e) {
      AppLogger.error('Customer email signup failed: $e');
      if (!mounted) return;
      AppSnackbar.error(context, _detailedError(e));
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
      await _afterAuthSuccess();
    } catch (e) {
      AppLogger.error('Customer Google sign-in failed: $e');
      if (!mounted) return;
      AppSnackbar.error(context, _detailedError(e));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _continueWithApple() async {
    setState(() => _appleLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithApple();
      await _afterAuthSuccess();
    } catch (e) {
      AppLogger.error('Customer Apple sign-in failed: $e');
      if (!mounted) return;
      AppSnackbar.error(context, _detailedError(e));
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  String _detailedError(Object e) {
    final friendly = friendlyError(e);
    final raw = e.toString();
    if (friendly.startsWith('Something went wrong')) {
      final trimmed = raw.length > 200 ? '${raw.substring(0, 200)}…' : raw;
      return trimmed;
    }
    return friendly;
  }

  Future<void> _afterAuthSuccess() async {
    final authState = ref.read(authNotifierProvider);
    final user = authState.user;
    if (user == null) throw Exception('Sign in did not return a user.');

    if (user.role == 'admin') {
      if (!mounted) return;
      AppSnackbar.success(context, 'Welcome, Admin!');
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/admin-dashboard', (_) => false);
      return;
    }

    await ref.read(roleProvider.notifier).setRole(OnboardingRole.customer);
    try {
      await ref.read(onboardingServiceProvider).ensureUserRecord(
            userId: user.id,
            role: OnboardingRole.customer,
            email: user.email,
            name: user.name,
            onboardingCompleted: false,
          );
    } catch (syncError) {
      AppLogger.error('Customer profile sync failed: $syncError');
    }
    await ref.read(authNotifierProvider.notifier).refreshUser();

    if (_enableLocation) await Geolocator.requestPermission();
    if (_enableNotifications) await NotificationService().initialize();

    await ref
        .read(onboardingProvider(OnboardingRole.customer).notifier)
        .setStep(3);

    if (!mounted) return;
    AppSnackbar.success(context, 'Welcome!');
    final role = ref.read(authNotifierProvider).user?.role;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(_routeForRole(role), (_) => false);
  }

  // ── Design tokens ──────────────────────────────────────────────────────────

  static const _p1 = Color(0xFF3B0764);
  static const _p2 = Color(0xFF6D28D9);
  static const _p3 = Color(0xFF7C3AED);
  static const _fieldFill = Color(0xFFF5F3FF);
  static const _fieldBorder = Color(0xFFDDD6FE);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    ref.watch(onboardingProvider(OnboardingRole.customer));

    ref.listen<AuthState>(authNotifierProvider, (prev, next) {
      if (next.isAuthenticated && !(prev?.isAuthenticated ?? false)) {
        _autoAdvanceIfReady();
      }
    });

    final isAuthStep = !authState.isAuthenticated;
    final mq = MediaQuery.of(context);
    // keyboardH > 0 when soft keyboard is open.
    final keyboardH = mq.viewInsets.bottom;
    // Screen height buckets for adaptive hero.
    final sh = mq.size.height;
    final isCompact = sh < 620; // SE 1st/2nd gen, short landscape
    final isTiny = sh < 520;    // very short landscape / old small phones

    return Scaffold(
      // We handle keyboard insets manually inside the scroll view so the
      // gradient hero stays visible and only the form scrolls.
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen gradient
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_p1, _p2, _p3],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // Decorative circles (clipped so they never overflow)
          ClipRect(
            child: OverflowBox(
              alignment: Alignment.topRight,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: SizedBox(
                width: mq.size.width + 60,
                height: mq.size.height + 60,
                child: Stack(
                  children: [
                    Positioned(
                      top: -60,
                      right: -60,
                      child: _circle(220, 0.06),
                    ),
                    Positioned(
                      top: 80,
                      right: -30,
                      child: _circle(120, 0.04),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Main layout
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Back button ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context)
                        .pushReplacementNamed('/role-selection'),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),

                // ── Hero ─────────────────────────────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    isTiny ? 6 : (isCompact ? 10 : 20),
                    24,
                    isTiny ? 8 : (isCompact ? 14 : 28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt_rounded,
                                color: Colors.amber, size: 16),
                            SizedBox(width: 5),
                            Text(
                              '7DASH',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isTiny ? 6 : (isCompact ? 10 : 16)),
                      // Headline — single-line on small, two-line on full
                      Text(
                        isTiny
                            ? 'Your world, delivered.'
                            : isCompact
                                ? 'Your world,\ndelivered.'
                                : 'Your world,\ndelivered.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isTiny ? 22 : (isCompact ? 28 : 34),
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          letterSpacing: -0.5,
                        ),
                      ),
                      // Subtitle + pills hidden on tiny screens to save space
                      if (!isTiny) ...[
                        SizedBox(height: isCompact ? 6 : 10),
                        Text(
                          'Food, groceries, rides & more.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: isCompact ? 13 : 15,
                          ),
                        ),
                      ],
                      if (!isCompact) ...[
                        const SizedBox(height: 20),
                        // Wrap prevents overflow on narrow screens
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _featurePill('🍔', 'Food'),
                            _featurePill('🛒', 'Grocery'),
                            _featurePill('🚗', 'Rides'),
                            _featurePill('🧺', 'Laundry'),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Form card ─────────────────────────────────────────────
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      // Dismiss keyboard on drag
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        24,
                        isCompact ? 20 : 28,
                        24,
                        // Extra bottom space so the last button clears the keyboard
                        keyboardH > 0 ? keyboardH + 16 : 32,
                      ),
                      child: isAuthStep
                          ? _buildAuthForm(context, isCompact: isCompact)
                          : _buildLoadingState(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helper widgets ─────────────────────────────────────────────────────────

  Widget _circle(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: opacity),
        ),
      );

  Widget _featurePill(String emoji, String label) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  // ── Auth form ──────────────────────────────────────────────────────────────

  Widget _buildAuthForm(BuildContext context, {required bool isCompact}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vGap = isCompact ? 12.0 : 14.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create your account',
          style: TextStyle(
            fontSize: isCompact ? 19 : 22,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF1F1B2E),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Start ordering in seconds',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white54 : const Color(0xFF6B7280),
          ),
        ),
        SizedBox(height: isCompact ? 18 : 24),

        // Google
        _socialButton(
          onTap: _isBusy ? null : _continueWithGoogle,
          loading: _googleLoading,
          icon: Icons.g_mobiledata_rounded,
          iconColor: const Color(0xFF4285F4),
          label: 'Continue with Google',
          isDark: isDark,
        ),

        // Apple (iOS / macOS only)
        if (_showApple) ...[
          SizedBox(height: vGap - 2),
          _socialButton(
            onTap: _isBusy ? null : _continueWithApple,
            loading: _appleLoading,
            icon: Icons.apple_rounded,
            iconColor: isDark ? Colors.white : Colors.black,
            label: 'Continue with Apple',
            isDark: isDark,
          ),
        ],

        // Divider
        Padding(
          padding: EdgeInsets.symmetric(vertical: isCompact ? 16 : 22),
          child: Row(
            children: [
              Expanded(
                child: Divider(
                  color:
                      isDark ? Colors.white24 : const Color(0xFFE5E7EB),
                  thickness: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or sign up with email',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? Colors.white54
                        : const Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  color:
                      isDark ? Colors.white24 : const Color(0xFFE5E7EB),
                  thickness: 1,
                ),
              ),
            ],
          ),
        ),

        // Name
        _field(
          controller: _name,
          hint: 'Full name',
          icon: Icons.person_outline_rounded,
          isDark: isDark,
          textCapitalization: TextCapitalization.words,
        ),
        SizedBox(height: vGap),

        // Email
        _field(
          controller: _email,
          hint: 'Email address',
          icon: Icons.mail_outline_rounded,
          isDark: isDark,
          keyboardType: TextInputType.emailAddress,
        ),
        SizedBox(height: vGap),

        // Password with eye toggle
        _field(
          controller: _password,
          hint: 'Password',
          icon: Icons.lock_outline_rounded,
          isDark: isDark,
          obscureText: !_passwordVisible,
          suffix: IconButton(
            icon: Icon(
              _passwordVisible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: _p3,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _passwordVisible = !_passwordVisible),
          ),
        ),
        SizedBox(height: isCompact ? 18 : 22),

        // Location permission
        _permissionTile(
          icon: Icons.location_on_outlined,
          title: 'Share my location',
          subtitle: 'Find nearby restaurants & track deliveries',
          value: _enableLocation,
          onChanged: (v) => setState(() => _enableLocation = v),
          isDark: isDark,
        ),
        SizedBox(height: vGap - 2),

        // Notifications permission
        _permissionTile(
          icon: Icons.notifications_outlined,
          title: 'Order notifications',
          subtitle: 'Updates on orders, rides and offers',
          value: _enableNotifications,
          onChanged: (v) => setState(() => _enableNotifications = v),
          isDark: isDark,
        ),
        SizedBox(height: isCompact ? 20 : 26),

        // CTA
        _gradientButton(
          onTap: _isBusy ? null : _signUpWithEmail,
          loading: _emailLoading,
          label: 'Create Account',
        ),

        // Sign in link
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Already have an account?',
              style: TextStyle(
                fontSize: 13,
                color:
                    isDark ? Colors.white54 : const Color(0xFF6B7280),
              ),
            ),
            TextButton(
              onPressed: _isBusy
                  ? null
                  : () => Navigator.of(context)
                      .pushNamed('/signin/customer'),
              style: TextButton.styleFrom(
                foregroundColor: _p3,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Sign in',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildLoadingState() => const SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: _p3),
              SizedBox(height: 16),
              Text(
                'Getting things ready…',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 15),
              ),
            ],
          ),
        ),
      );

  // ── Form field ─────────────────────────────────────────────────────────────

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    Widget? suffix,
  }) {
    final fill =
        isDark ? const Color(0xFF1A1625) : _fieldFill;
    final border =
        isDark ? Colors.white12 : _fieldBorder;
    final focusBorder =
        isDark ? const Color(0xFF9333EA) : _p3;

    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style: TextStyle(
        color: isDark ? Colors.white : const Color(0xFF1F1B2E),
        fontSize: 15,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
        prefixIcon: Icon(icon, color: _p3, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: fill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: focusBorder, width: 2),
        ),
      ),
    );
  }

  // ── Social button ──────────────────────────────────────────────────────────

  Widget _socialButton({
    required VoidCallback? onTap,
    required bool loading,
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool isDark,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: onTap == null ? 0.5 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F1B2E) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _p3),
                      )
                    : Icon(icon, color: iconColor, size: 24),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    loading ? 'Signing in…' : label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.white
                          : const Color(0xFF374151),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  // ── Permission tile ────────────────────────────────────────────────────────

  Widget _permissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F1B2E) : _fieldFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? Colors.white12 : _fieldBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _p3.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _p3, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.white
                          : const Color(0xFF1F1B2E),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? Colors.white38
                          : const Color(0xFF9CA3AF),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: const Color(0xFF7C3AED),
              activeTrackColor:
                  const Color(0xFF7C3AED).withValues(alpha: 0.35),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      );

  // ── Gradient CTA button ────────────────────────────────────────────────────

  Widget _gradientButton({
    required VoidCallback? onTap,
    required bool loading,
    required String label,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: onTap == null ? 0.6 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: onTap == null
                  ? null
                  : const LinearGradient(
                      colors: [_p2, _p3],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
              color: onTap == null ? Colors.grey : null,
              borderRadius: BorderRadius.circular(16),
              boxShadow: onTap == null
                  ? null
                  : [
                      BoxShadow(
                        color: _p3.withValues(alpha: 0.38),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      );
}
