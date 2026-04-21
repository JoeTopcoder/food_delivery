import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../features/auth/models/onboarding_role.dart';
import '../../../features/auth/providers/onboarding_provider.dart';
import '../../../features/auth/providers/role_provider.dart';
import '../../../features/auth/services/onboarding_service.dart';
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

  bool _loading = false;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() => _loading = true);
    try {
      await ref.read(onboardingServiceProvider).sendOtp(_phone.text.trim());
      await ref
          .read(onboardingProvider(OnboardingRole.customer).notifier)
          .setStep(1);
      if (!mounted) return;
      AppSnackbar.success(context, 'OTP sent');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    setState(() => _loading = true);
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
      if (mounted) setState(() => _loading = false);
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
    final step =
        ref.watch(onboardingProvider(OnboardingRole.customer)).valueOrNull ?? 0;

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
                  onPressed: _loading ? null : _sendOtp,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text('Send OTP'),
                ),
              if (isOtpStep) ...[
                TextField(
                  controller: _otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'OTP code'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loading ? null : _verifyOtp,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text('Verify OTP'),
                ),
              ],
              const Spacer(),
              if (isLocationStep) ...[
                OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _finishLocationStep(request: true),
                  icon: const Icon(Icons.my_location),
                  label: const Text('Enable location'),
                ),
                TextButton(
                  onPressed: _loading
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
