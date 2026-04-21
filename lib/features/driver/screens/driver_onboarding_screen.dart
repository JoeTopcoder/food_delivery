import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/models/onboarding_role.dart';
import '../../../features/auth/providers/onboarding_provider.dart';
import '../../../features/auth/providers/role_provider.dart';
import '../../../features/auth/services/onboarding_service.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class DriverOnboardingScreen extends ConsumerStatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  ConsumerState<DriverOnboardingScreen> createState() =>
      _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState
    extends ConsumerState<DriverOnboardingScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _vehicleType = TextEditingController();
  final _plate = TextEditingController();

  bool _loading = false;
  bool _docsUploaded = false;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _name.dispose();
    _email.dispose();
    _vehicleType.dispose();
    _plate.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() => _loading = true);
    try {
      await ref.read(onboardingServiceProvider).sendOtp(_phone.text.trim());
      await ref
          .read(onboardingProvider(OnboardingRole.driver).notifier)
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

      await ref.read(roleProvider.notifier).setRole(OnboardingRole.driver);
      await ref
          .read(onboardingServiceProvider)
          .saveDriverProfile(userId: userId, phone: _phone.text.trim());

      await ref
          .read(onboardingProvider(OnboardingRole.driver).notifier)
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

  Future<void> _saveProfile({required bool skip}) async {
    setState(() => _loading = true);
    try {
      final userId = ref.read(onboardingServiceProvider).currentUserId;
      if (userId == null) throw Exception('Not authenticated');

      await ref
          .read(onboardingServiceProvider)
          .saveDriverProfile(
            userId: userId,
            phone: _phone.text.trim(),
            name: skip ? null : _name.text.trim(),
            email: skip ? null : _email.text.trim(),
          );

      await ref
          .read(onboardingProvider(OnboardingRole.driver).notifier)
          .setStep(3);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveVehicle({required bool skip}) async {
    setState(() => _loading = true);
    try {
      final userId = ref.read(onboardingServiceProvider).currentUserId;
      if (userId == null) throw Exception('Not authenticated');

      await ref
          .read(onboardingServiceProvider)
          .saveDriverProfile(
            userId: userId,
            phone: _phone.text.trim(),
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            vehicleType: skip ? null : _vehicleType.text.trim(),
            licensePlate: skip ? null : _plate.text.trim(),
          );

      await ref
          .read(onboardingProvider(OnboardingRole.driver).notifier)
          .setStep(4);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finish({required bool uploadedDocs}) async {
    setState(() => _loading = true);
    try {
      final userId = ref.read(onboardingServiceProvider).currentUserId;
      if (userId == null) throw Exception('Not authenticated');

      await ref
          .read(onboardingServiceProvider)
          .saveDriverProfile(
            userId: userId,
            phone: _phone.text.trim(),
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            vehicleType: _vehicleType.text.trim().isEmpty
                ? null
                : _vehicleType.text.trim(),
            licensePlate: _plate.text.trim().isEmpty
                ? null
                : _plate.text.trim(),
            documentsUploaded: uploadedDocs,
          );

      await ref
          .read(onboardingProvider(OnboardingRole.driver).notifier)
          .setStep(5);

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/driver-dashboard', (_) => false);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step =
        ref.watch(onboardingProvider(OnboardingRole.driver)).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Driver Onboarding')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Start earning fast',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Step ${step.clamp(0, 4) + 1} of 5'),
          const SizedBox(height: 20),

          if (step == 0) ...[
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _sendOtp,
              child: const Text('Send OTP'),
            ),
          ],

          if (step == 1) ...[
            TextField(
              controller: _phone,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _otp,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'OTP code'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _verifyOtp,
              child: const Text('Verify OTP'),
            ),
          ],

          if (step == 2) ...[
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => _saveProfile(skip: true),
                    child: const Text('Skip for now'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () => _saveProfile(skip: false),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ],

          if (step == 3) ...[
            TextField(
              controller: _vehicleType,
              decoration: const InputDecoration(labelText: 'Vehicle type'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _plate,
              decoration: const InputDecoration(labelText: 'License plate'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => _saveVehicle(skip: true),
                    child: const Text('Skip for now'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () => _saveVehicle(skip: false),
                    child: const Text('Save vehicle'),
                  ),
                ),
              ],
            ),
          ],

          if (step >= 4) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I uploaded documents'),
              subtitle: const Text('You can skip this and complete later.'),
              value: _docsUploaded,
              onChanged: (v) => setState(() => _docsUploaded = v ?? false),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading
                        ? null
                        : () => _finish(uploadedDocs: false),
                    child: const Text('Skip for now'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () => _finish(uploadedDocs: _docsUploaded),
                    child: const Text('Finish'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Status: Pending approval. Limited mode remains available until approval.',
            ),
          ],
        ],
      ),
    );
  }
}
