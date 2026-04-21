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

    final permission = await Geolocator.checkPermission();
    final locationGranted =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    if (!mounted) return;
    final role = ref.read(authNotifierProvider).user?.role;
    if (locationGranted) {
      // Permission already granted — skip all onboarding and go home.
      await ref
          .read(onboardingProvider(OnboardingRole.customer).notifier)
          .setStep(3);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(_routeForRole(role), (_) => false);
    } else {
      // Authenticated but location not yet granted — jump to location step.
      await ref
          .read(onboardingProvider(OnboardingRole.customer).notifier)
          .setStep(2);
    }
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
    await ref
        .read(onboardingProvider(OnboardingRole.customer).notifier)
        .setStep(2);

    if (!mounted) return;
    // Skip location step immediately if permission already granted.
    await _autoAdvanceIfReady();
    if (!mounted) return;
    AppSnackbar.success(context, 'Welcome!');
  }

  Future<void> _finishLocationStep({required bool request}) async {
    if (request) {
      await Geolocator.requestPermission();
    }

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
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final step =
        ref.watch(onboardingProvider(OnboardingRole.customer)).valueOrNull ?? 0;

    final isAuthStep = !authState.isAuthenticated || step < 2;
    final isLocationStep = authState.isAuthenticated && step >= 2;

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
              Text(isAuthStep ? 'Step 1 of 2' : 'Step 2 of 2'),
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
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _isBusy ? null : _signUpWithEmail,
                  child: _emailLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create account'),
                ),
              ],
              if (isLocationStep) ...[
                const Text('Enable location so we can show nearby options.'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _isBusy
                      ? null
                      : () => _finishLocationStep(request: true),
                  icon: const Icon(Icons.my_location),
                  label: const Text('Enable location'),
                ),
                TextButton(
                  onPressed: _isBusy
                      ? null
                      : () => _finishLocationStep(request: false),
                  child: const Text('Skip for now'),
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
