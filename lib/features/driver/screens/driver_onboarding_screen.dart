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

class DriverOnboardingScreen extends ConsumerStatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  ConsumerState<DriverOnboardingScreen> createState() =>
      _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState
    extends ConsumerState<DriverOnboardingScreen> {
  final _signUpEmail = TextEditingController();
  final _signUpPassword = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _vehicleType = TextEditingController();
  final _plate = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _docsUploaded = false;

  bool get _isBusy => _loading || _googleLoading || _appleLoading;

  @override
  void dispose() {
    _signUpEmail.dispose();
    _signUpPassword.dispose();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _vehicleType.dispose();
    _plate.dispose();
    super.dispose();
  }

  Future<void> _signUpWithEmail() async {
    final email = _signUpEmail.text.trim();
    final password = _signUpPassword.text;
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
            name: email.split('@').first,
            role: 'driver',
          );
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

    await ref.read(roleProvider.notifier).setRole(OnboardingRole.driver);
    try {
      await ref
          .read(onboardingServiceProvider)
          .saveDriverProfile(
            userId: user.id,
            email: user.email,
            name: user.name,
          );
    } catch (e) {
      AppLogger.error('Driver profile sync failed: $e');
    }

    if (user.email != null && _email.text.isEmpty) _email.text = user.email!;
    if (user.name != null && _name.text.isEmpty) _name.text = user.name!;

    await ref
        .read(onboardingProvider(OnboardingRole.driver).notifier)
        .setStep(2);

    if (!mounted) return;
    AppSnackbar.success(context, 'Signed in');
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

          if (step < 2) ...[
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
                  : const Text('Create driver account'),
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

          if (step < 2) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Already have an account?'),
                TextButton(
                  onPressed: _isBusy
                      ? null
                      : () => Navigator.of(context).pushNamed('/signin'),
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
