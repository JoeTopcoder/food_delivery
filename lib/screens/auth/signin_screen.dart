import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../utils/app_theme.dart';
import '../../utils/context_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_logger.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../core/utils/responsive.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.role});

  /// Expected role for this sign-in: 'user' (customer), 'driver', or
  /// 'restaurant'. If null, any role is allowed and we route by actual role.
  final String? role;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;

  String get _roleLabel {
    switch (widget.role) {
      case 'driver':
        return 'Driver';
      case 'restaurant':
        return 'Restaurant';
      case 'user':
      case 'customer':
        return 'Customer';
      default:
        return '';
    }
  }

  IconData get _roleIcon {
    switch (widget.role) {
      case 'driver':
        return Icons.delivery_dining;
      case 'restaurant':
        return Icons.storefront;
      case 'user':
      case 'customer':
        return Icons.person_outline;
      default:
        return Icons.login;
    }
  }

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

  bool _rolesMatch(String? userRole) {
    if (userRole == 'admin') return true; // admin can sign in from any portal
    if (widget.role == null) return true;
    final expected = widget.role;
    if (expected == 'user' && (userRole == 'user' || userRole == 'customer')) {
      return true;
    }
    return userRole == expected;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      _navigateAfterSignIn();
    } catch (e) {
      // Log the full raw Supabase error (visible in `flutter logs`) so the
      // exact error code from GoTrue can be read during debugging.
      AppLogger.error('Sign in raw error: ${e.runtimeType}: $e');
      _showError(e);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
      _navigateAfterSignIn();
    } catch (e) {
      AppLogger.error('Google sign-in error: $e');
      if (!mounted) return;
      // Show specific error for debugging social sign-in issues
      final msg = e.toString();
      AppSnackbar.error(
        context,
        msg.contains('cancelled')
            ? 'Google sign-in was cancelled'
            : 'Google sign-in failed: ${msg.length > 120 ? msg.substring(0, 120) : msg}',
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() => _isAppleLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithApple();
      if (!mounted) return;
      _navigateAfterSignIn();
    } catch (e) {
      AppLogger.error('Apple sign-in error: $e');
      if (!mounted) return;
      final msg = e.toString();
      if (msg.toLowerCase().contains('cancelled')) return;
      AppSnackbar.error(
        context,
        msg.contains('identity token') || msg.contains('bundle ID')
            ? 'Apple Sign-In is not available right now. Please try again later.'
            : 'Apple sign-in failed. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isAppleLoading = false);
    }
  }

  void _navigateAfterSignIn() {
    if (!mounted) return;
    final role = ref.read(authNotifierProvider).user?.role;

    if (!_rolesMatch(role)) {
      // The account exists but belongs to a different role. Sign out and warn.
      ref.read(authNotifierProvider.notifier).signOut();
      AppSnackbar.error(
        context,
        'This account is not a $_roleLabel account. Please use the correct sign-in.',
      );
      return;
    }

    Navigator.of(context).pushReplacementNamed(_routeForRole(role));
  }

  void _showError(Object e) {
    if (!mounted) return;
    AppSnackbar.error(context, friendlyError(e));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
          children: [
            // ── Gradient Header ──────────────────────────────────────────
            Container(
              width: double.infinity,
              height: size.height * 0.35,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryColor, Color(0xFFFF8C42)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/mealhub_logo.png',
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '7DASH',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Food. Fast. Delivered.',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_roleLabel.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_roleIcon, size: 16, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              '$_roleLabel sign in',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        'Welcome back!',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Form ─────────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                Responsive.horizontalPadding(context),
                36,
                Responsive.horizontalPadding(context),
                Responsive.cardPadding(context),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _roleLabel.isEmpty
                          ? context.l10n.signIn
                          : '${context.l10n.signIn} as $_roleLabel',
                      style: TextStyle(
                        fontSize: Responsive.headingLarge(context),
                        fontWeight: FontWeight.bold,
                        color: context.colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _roleLabel.isEmpty
                          ? 'Enter your credentials to continue'
                          : 'Sign in to your $_roleLabel account',
                      style: TextStyle(
                        fontSize: Responsive.bodyText(context),
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Email
                    _buildField(
                      controller: _emailController,
                      label: context.l10n.email,
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v?.isEmpty ?? true) {
                          return 'Please enter your email';
                        }
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v!)) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password
                    _buildField(
                      controller: _passwordController,
                      label: context.l10n.password,
                      icon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: const Color(0xFF9CA3AF),
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      validator: (v) {
                        if (v?.isEmpty ?? true) {
                          return 'Please enter your password';
                        }
                        return null;
                      },
                    ),

                    // Forgot password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/forgot-password'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: Text(
                          context.l10n.forgotPassword,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Sign In button
                    _GradientButton(
                      onPressed: (authState.isLoading || _isGoogleLoading) ? null : _handleSignIn,
                      isLoading: authState.isLoading && !_isGoogleLoading,
                      label: context.l10n.signIn,
                    ),
                    const SizedBox(height: 24),

                    // Divider
                    Row(
                      children: [
                        const Expanded(
                          child: Divider(color: Color(0xFFE5E7EB)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'or continue with',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                        const Expanded(
                          child: Divider(color: Color(0xFFE5E7EB)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Social login buttons
                    // Google is shown on Android/web; Apple is shown on iOS/macOS.
                    // On iOS both can be shown side-by-side (Google hidden by default
                    // per Apple HIG, but allowed). We show Google on non-iOS only and
                    // Apple on iOS/macOS only to keep the UI clean.
                    Row(
                      children: [
                        // Google — Android + Web only
                        if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) ...[
                          Expanded(
                            child: _SocialButton(
                              onPressed: (_isGoogleLoading || authState.isLoading)
                                  ? null
                                  : _handleGoogleSignIn,
                              icon: _googleIcon(),
                              label: 'Google',
                              isLoading: _isGoogleLoading,
                            ),
                          ),
                        ],
                        // Apple — iOS + macOS only
                        if (!kIsWeb &&
                            (defaultTargetPlatform == TargetPlatform.iOS ||
                                defaultTargetPlatform == TargetPlatform.macOS)) ...[
                          Expanded(
                            child: SignInWithAppleButton(
                              onPressed: (authState.isLoading ||
                                      _isGoogleLoading ||
                                      _isAppleLoading)
                                  ? null
                                  : _handleAppleSignIn,
                              style: SignInWithAppleButtonStyle.black,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Sign up link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          context.l10n.dontHaveAccount,
                          style: TextStyle(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            // Route back to the matching onboarding screen so
                            // social + email sign-up stays role-specific.
                            switch (widget.role) {
                              case 'driver':
                                Navigator.of(
                                  context,
                                ).pushReplacementNamed('/onboarding/driver');
                                break;
                              case 'restaurant':
                                Navigator.of(context).pushReplacementNamed(
                                  '/onboarding/restaurant',
                                );
                                break;
                              default:
                                Navigator.of(
                                  context,
                                ).pushReplacementNamed('/onboarding/customer');
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          child: Text(
                            context.l10n.signUp,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _googleIcon() {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: context.colors.onSurfaceVariant,
          fontSize: 14,
        ),
        prefixIcon: Icon(icon, color: AppTheme.primaryColor, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: context.isDark
            ? context.colors.surfaceContainerHighest
            : const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;

  const _GradientButton({
    required this.onPressed,
    required this.isLoading,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        decoration: BoxDecoration(
          gradient: onPressed == null
              ? const LinearGradient(
                  colors: [Color(0xFFD1D5DB), Color(0xFFD1D5DB)],
                )
              : LinearGradient(
                  colors: [AppTheme.primaryColor, Color(0xFFFF8C42)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: onPressed == null
              ? []
              : [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  final bool isLoading;

  const _SocialButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: Theme.of(context).dividerColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: isLoading
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: Responsive.bodyText(context),
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double cx = w / 2;
    final double cy = h / 2;
    final double r = w / 2;

    // Blue
    final bluePaint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -0.6,
      1.8,
      true,
      bluePaint,
    );

    // Green
    final greenPaint = Paint()..color = const Color(0xFF34A853);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      1.2,
      1.2,
      true,
      greenPaint,
    );

    // Yellow
    final yellowPaint = Paint()..color = const Color(0xFFFBBC05);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      2.4,
      1.0,
      true,
      yellowPaint,
    );

    // Red
    final redPaint = Paint()..color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      3.4,
      1.6,
      true,
      redPaint,
    );

    // White inner circle
    final whitePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), r * 0.55, whitePaint);

    // Blue bar for the "G" cutout
    canvas.drawRect(
      Rect.fromLTRB(cx, cy - r * 0.15, cx + r, cy + r * 0.15),
      bluePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
