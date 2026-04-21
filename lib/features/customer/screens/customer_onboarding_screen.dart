import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../features/auth/models/onboarding_role.dart';
import '../../../features/auth/providers/onboarding_provider.dart';
import '../../../features/auth/providers/role_provider.dart';
import '../../../features/auth/services/onboarding_service.dart';
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
  final _phone = TextEditingController();
  final _otp = TextEditingController();

  bool _otpSending = false;
  bool _otpVerifying = false;
  bool _googleLoading = false;
  bool _resetPendingForLoggedOutUser = false;

  bool get _isBusy => _otpSending || _otpVerifying || _googleLoading;

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
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() => _otpSending = true);
    try {
      final phone = _phone.text.trim();
      await ref.read(onboardingServiceProvider).sendOtp(phone);
      await ref
          .read(onboardingProvider(OnboardingRole.customer).notifier)
          .setStep(1);
      if (!mounted) return;
      AppSnackbar.success(context, 'OTP sent. Check your SMS messages.');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _otpSending = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
      final authState = ref.read(authNotifierProvider);
      final user = authState.user;
      if (user == null) {
        throw Exception('Google sign in did not return a user.');
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
              onboardingCompleted: true,
            );
      } catch (syncError) {
        AppLogger.error(
          'Customer profile sync after Google sign-in failed: $syncError',
        );
      }
      await ref
          .read(onboardingProvider(OnboardingRole.customer).notifier)
          .setStep(2);

      if (!mounted) return;
      final route = _routeForRole(user.role);
      Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    setState(() => _otpVerifying = true);
    try {
      final auth = await ref
          .read(onboardingServiceProvider)
          .verifyOtp(phone: _phone.text.trim(), token: _otp.text.trim());

      final userId = auth.user?.id;
      if (userId == null) throw Exception('Could not verify OTP session.');

      await ref.read(roleProvider.notifier).setRole(OnboardingRole.customer);
      await ref
          .read(onboardingServiceProvider)
          .completeCustomerOnboarding(
            userId: userId,
            phone: _phone.text.trim(),
          );
      await ref
          .read(onboardingProvider(OnboardingRole.customer).notifier)
          .setStep(2);

      if (!mounted) return;
      AppSnackbar.success(context, 'Verified');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _otpVerifying = false);
    }
  }

  Future<void> _finishLocationStep({required bool request}) async {
    if (request) {
      await Geolocator.requestPermission();
    }

    await ref
        .read(onboardingProvider(OnboardingRole.customer).notifier)
        .setStep(3);

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final step =
        ref.watch(onboardingProvider(OnboardingRole.customer)).valueOrNull ?? 0;

    // If a user logged out after completing onboarding, force OTP entry flow again.
    if (!authState.isAuthenticated &&
        step > 1 &&
        !_resetPendingForLoggedOutUser) {
      _resetPendingForLoggedOutUser = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref
            .read(onboardingProvider(OnboardingRole.customer).notifier)
            .setStep(0);
        if (mounted) {
          setState(() => _resetPendingForLoggedOutUser = false);
        }
      });
    }

    final isPhoneStep = step == 0;
    final isOtpStep = step == 1;
    final isLocationStep = step >= 2;

    return Scaffold(
      appBar: AppBar(title: const Text('Customer Onboarding')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Start browsing in seconds',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Step ${step.clamp(0, 2) + 1} of 3'),
              const SizedBox(height: 24),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                readOnly: !isPhoneStep,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+1 345 ...',
                ),
              ),
              const SizedBox(height: 12),
              if (isPhoneStep)
                ElevatedButton(
                  onPressed: _isBusy ? null : _sendOtp,
                  child: _otpSending
                      ? const CircularProgressIndicator()
                      : const Text('Send OTP'),
                ),
              if (isPhoneStep) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _continueWithGoogle,
                  icon: _googleLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.g_mobiledata, size: 26),
                  label: Text(
                    _googleLoading ? 'Signing in...' : 'Sign up with Google',
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Use Google to skip OTP and continue faster.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
              if (isOtpStep) ...[
                TextField(
                  controller: _otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'OTP code'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _isBusy ? null : _verifyOtp,
                  child: _otpVerifying
                      ? const CircularProgressIndicator()
                      : const Text('Verify OTP'),
                ),
              ],
              const Spacer(),
              if (isLocationStep) ...[
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
            ],
          ),
        ),
      ),
    );
  }
}
