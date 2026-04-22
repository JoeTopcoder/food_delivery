import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../features/auth/models/onboarding_role.dart';
import '../../../features/auth/providers/onboarding_provider.dart';
import '../../../features/auth/providers/role_provider.dart';
import '../../../features/auth/services/onboarding_service.dart';
import '../../../features/auth/widgets/social_auth_panel.dart';
import '../../../providers/auth_provider.dart';
import '../../../utils/app_logger.dart';
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
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  bool _emailLoading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _enableLocation = true;

  bool get _isBusy => _emailLoading || _googleLoading || _appleLoading;

  String _routeForRole(String? role) {
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

  @override
  void initState() {
    super.initState();
    // If user is already authenticated, check location and go straight home.
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
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(_routeForRole(role), (_) => false);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

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
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
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
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
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
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  Future<void> _afterAuthSuccess() async {
    final authState = ref.read(authNotifierProvider);
    final user = authState.user;
    if (user == null) {
      throw Exception('Sign in did not return a user.');
    }

    await ref.read(roleProvider.notifier).setRole(OnboardingRole.customer);
    try {
      await ref
          .read(onboardingServiceProvider)
          .ensureUserRecord(
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

    // Request location inline if user opted in.
    if (_enableLocation) {
      await Geolocator.requestPermission();
    }

    await ref
        .read(onboardingProvider(OnboardingRole.customer).notifier)
        .setStep(3);

    if (!mounted) return;
    AppSnackbar.success(context, 'Welcome!');
    final role = ref.read(authNotifierProvider).user?.role;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(_routeForRole(role), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    // Watch step to trigger rebuild on auth step changes (e.g. auto-advance).
    ref.watch(onboardingProvider(OnboardingRole.customer));

    // When auth state becomes authenticated mid-lifecycle (e.g. auth loaded
    // after initState already ran), auto-advance to skip location if granted.
    ref.listen<AuthState>(authNotifierProvider, (previous, next) {
      if (next.isAuthenticated && !(previous?.isAuthenticated ?? false)) {
        _autoAdvanceIfReady();
      }
    });

    final isAuthStep = !authState.isAuthenticated;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Onboarding'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Change role',
          onPressed: () =>
              Navigator.of(context).pushReplacementNamed('/role-selection'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const Text(
                'Start browsing in seconds',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(isAuthStep ? 'Step 1 of 1' : 'Getting ready...'),
              const SizedBox(height: 24),
              if (isAuthStep) ...[
                SocialAuthPanel(
                  onGoogle: _isBusy ? null : _continueWithGoogle,
                  onApple: _isBusy ? null : _continueWithApple,
                  googleLoading: _googleLoading,
                  appleLoading: _appleLoading,
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or sign up with email'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable location'),
                  subtitle: const Text(
                    'Show nearby restaurants and track deliveries',
                  ),
                  value: _enableLocation,
                  onChanged: (v) => setState(() => _enableLocation = v ?? true),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _isBusy ? null : _signUpWithEmail,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _emailLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Account'),
                ),
              ],
              if (isAuthStep) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account?'),
                    TextButton(
                      onPressed: _isBusy
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pushNamed('/signin/customer'),
                      child: const Text('Sign in'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
