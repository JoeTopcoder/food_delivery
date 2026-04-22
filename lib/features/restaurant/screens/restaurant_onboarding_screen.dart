import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/models/onboarding_role.dart';
import '../../../features/auth/providers/onboarding_provider.dart';
import '../../../features/auth/providers/role_provider.dart';
import '../../../features/auth/services/onboarding_service.dart';
import '../../../features/auth/widgets/social_auth_panel.dart';
import '../../../providers/auth_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/friendly_error.dart';

class RestaurantOnboardingScreen extends ConsumerStatefulWidget {
  const RestaurantOnboardingScreen({super.key});

  @override
  ConsumerState<RestaurantOnboardingScreen> createState() =>
      _RestaurantOnboardingScreenState();
}

class _RestaurantOnboardingScreenState
    extends ConsumerState<RestaurantOnboardingScreen> {
  final _signUpEmail = TextEditingController();
  final _signUpPassword = TextEditingController();
  final _signUpName = TextEditingController();
  final _business = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;

  bool get _isBusy => _loading || _googleLoading || _appleLoading;

  @override
  void dispose() {
    _signUpEmail.dispose();
    _signUpPassword.dispose();
    _signUpName.dispose();
    _business.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _signUpWithEmail() async {
    final email = _signUpEmail.text.trim();
    final password = _signUpPassword.text;
    final name = _signUpName.text.trim();
    if (name.isEmpty) {
      AppSnackbar.error(context, 'Please enter your full name.');
      return;
    }
    if (email.isEmpty || password.isEmpty) {
      AppSnackbar.error(context, 'Enter your email and password.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .signUp(
            email: email,
            password: password,
            name: name,
            role: 'restaurant',
          );
      final authState = ref.read(authNotifierProvider);
      if (authState.emailConfirmationPending) {
        // Still advance so they can fill in business details.
        await ref
            .read(onboardingProvider(OnboardingRole.restaurant).notifier)
            .setStep(0);
        if (!mounted) return;
        AppSnackbar.info(
          context,
          'Account created! Check your email to confirm. You can finish setup now.',
        );
        return;
      }
      await _afterAuthSuccess();
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final user = ref.read(authNotifierProvider).user;
    if (user == null) throw Exception('Sign in did not return a user.');

    await ref.read(roleProvider.notifier).setRole(OnboardingRole.restaurant);
    try {
      await ref
          .read(onboardingServiceProvider)
          .ensureUserRecord(
            userId: user.id,
            role: OnboardingRole.restaurant,
            email: user.email,
            name: user.name,
          );
    } catch (e) {
      AppLogger.error('Restaurant profile sync failed: $e');
    }
    await ref.read(authNotifierProvider.notifier).refreshUser();

    final stepNotifier = ref.read(
      onboardingProvider(OnboardingRole.restaurant).notifier,
    );
    final currentStep =
        ref.read(onboardingProvider(OnboardingRole.restaurant)).valueOrNull ??
        0;
    if (currentStep < 1) await stepNotifier.setStep(0);

    if (!mounted) return;
    AppSnackbar.success(context, 'Signed in');
  }

  Future<void> _saveStep({required int nextStep, bool goLive = false}) async {
    setState(() => _loading = true);
    try {
      final userId = ref.read(onboardingServiceProvider).currentUserId;
      if (userId == null) throw Exception('Please sign in first to continue.');

      await ref.read(roleProvider.notifier).setRole(OnboardingRole.restaurant);
      await ref
          .read(onboardingServiceProvider)
          .saveRestaurantDraft(
            userId: userId,
            businessName: _business.text.trim(),
            phone: _phone.text.trim(),
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            onboardingStep: nextStep,
            goLive: goLive,
          );

      await ref
          .read(onboardingProvider(OnboardingRole.restaurant).notifier)
          .setStep(nextStep);

      if (goLive) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/restaurant-dashboard', (_) => false);
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final step =
        ref.watch(onboardingProvider(OnboardingRole.restaurant)).valueOrNull ??
        0;

    // isAuthStep is true only when not yet authenticated AND no pending email confirmation.
    final isAuthStep =
        !authState.isAuthenticated && !authState.emailConfirmationPending;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurant Onboarding'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Change role',
          onPressed: () =>
              Navigator.of(context).pushReplacementNamed('/role-selection'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Go live in minutes',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isAuthStep ? 'Step 1 of 4' : 'Step ${(step.clamp(0, 2) + 2)} of 4',
          ),
          const SizedBox(height: 20),

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
              controller: _signUpName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _signUpEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _signUpPassword,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isBusy ? null : _signUpWithEmail,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Next'),
            ),
          ],

          if (!isAuthStep && step == 0) ...[
            TextField(
              controller: _business,
              decoration: const InputDecoration(labelText: 'Business name *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Business phone *'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading
                  ? null
                  : () {
                      if (_business.text.trim().isEmpty) {
                        AppSnackbar.error(
                          context,
                          'Please enter your business name.',
                        );
                        return;
                      }
                      if (_phone.text.trim().isEmpty) {
                        AppSnackbar.error(
                          context,
                          'Please enter a business phone number.',
                        );
                        return;
                      }
                      _saveStep(nextStep: 1);
                    },
              child: const Text('Next'),
            ),
          ],

          if (!isAuthStep && step == 1) ...[
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Address *',
                hintText: 'Enter your restaurant address',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading
                  ? null
                  : () {
                      if (_address.text.trim().isEmpty) {
                        AppSnackbar.error(
                          context,
                          'Please enter your restaurant address.',
                        );
                        return;
                      }
                      _saveStep(nextStep: 3);
                    },
              child: const Text('Next'),
            ),
          ],

          if (!isAuthStep && step >= 3) ...[
            const Text(
              'Almost done!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Review your details above, then tap Create Restaurant to go live.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loading
                  ? null
                  : () => _saveStep(nextStep: 4, goLive: true),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.rocket_launch),
              label: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Restaurant'),
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
                        ).pushNamed('/signin/restaurant'),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
