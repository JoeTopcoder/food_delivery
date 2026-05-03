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
  final _signUpName = TextEditingController();
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
    _signUpName.dispose();
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
          .signUp(email: email, password: password, name: name, role: 'driver');
      final authState = ref.read(authNotifierProvider);
      if (authState.emailConfirmationPending) {
        // Email confirmation required but we still advance the onboarding.
        // Pre-fill profile fields from sign-up data so the user doesn't
        // have to retype their name/email on the next step.
        _name.text = _signUpName.text.trim();
        _email.text = _signUpEmail.text.trim();
        await ref
            .read(onboardingProvider(OnboardingRole.driver).notifier)
            .setStep(2);
        if (!mounted) return;
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
    await ref.read(authNotifierProvider.notifier).refreshUser();

    if (user.email != null && _email.text.isEmpty) _email.text = user.email!;
    if (user.name != null && _name.text.isEmpty) _name.text = user.name!;

    await ref
        .read(onboardingProvider(OnboardingRole.driver).notifier)
        .setStep(2);

    if (!mounted) return;
    AppSnackbar.success(context, 'Signed in');
  }

  Future<void> _saveProfile() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      AppSnackbar.error(context, 'Please enter your phone number.');
      return;
    }
    setState(() => _loading = true);
    try {
      final userId = ref.read(onboardingServiceProvider).currentUserId;
      if (userId != null) {
        try {
          await ref
              .read(onboardingServiceProvider)
              .saveDriverProfile(
                userId: userId,
                phone: phone,
                name: _name.text.trim(),
                email: _email.text.trim(),
              );
        } catch (e, st) {
          AppLogger.error('Driver profile save failed (continuing): $e\n$st');
        }
      }
      await ref
          .read(onboardingProvider(OnboardingRole.driver).notifier)
          .setStep(3);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveVehicle() async {
    if (_vehicleType.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Please select a vehicle type.');
      return;
    }
    if (_plate.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Please enter your license plate number.');
      return;
    }
    setState(() => _loading = true);
    try {
      final userId = ref.read(onboardingServiceProvider).currentUserId;
      if (userId != null) {
        try {
          await ref
              .read(onboardingServiceProvider)
              .saveDriverProfile(
                userId: userId,
                phone: _phone.text.trim(),
                name: _name.text.trim().isEmpty ? null : _name.text.trim(),
                email: _email.text.trim().isEmpty ? null : _email.text.trim(),
                vehicleType: _vehicleType.text.trim(),
                licensePlate: _plate.text.trim(),
              );
        } catch (e, st) {
          AppLogger.error('Driver vehicle save failed (continuing): $e\n$st');
        }
      }
      await ref
          .read(onboardingProvider(OnboardingRole.driver).notifier)
          .setStep(4);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finish({required bool uploadedDocs}) async {
    setState(() => _loading = true);
    try {
      final userId = ref.read(onboardingServiceProvider).currentUserId;
      if (userId != null) {
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
      }

      await ref
          .read(onboardingProvider(OnboardingRole.driver).notifier)
          .setStep(5);

      if (!mounted) return;
      // If not yet authenticated (email confirmation pending), send to sign-in.
      // The migration 104 trigger will create their profile on first sign-in.
      final isAuth = ref.read(authNotifierProvider).isAuthenticated;
      if (!isAuth) {
        Navigator.of(context).pushReplacementNamed('/signin/driver');
        return;
      }
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
    final authState = ref.watch(authNotifierProvider);
    final emailPending = authState.emailConfirmationPending;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Onboarding'),
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
            'Start earning fast',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Step ${step.clamp(0, 4) + 1} of 5'),
          if (emailPending && step >= 2) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFD700)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.email_outlined,
                    color: Color(0xFF856404),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Check your email to confirm your account. You can finish setup now.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF856404),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number *'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _saveProfile,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Next'),
            ),
          ],

          if (step == 3) ...[
            DropdownButtonFormField<String>(
              initialValue: _vehicleType.text.isEmpty
                  ? null
                  : _vehicleType.text,
              decoration: const InputDecoration(labelText: 'Vehicle type *'),
              items: const [
                DropdownMenuItem(
                  value: 'bike',
                  child: Text('Bike / Motorcycle'),
                ),
                DropdownMenuItem(value: 'car', child: Text('Car')),
                DropdownMenuItem(value: 'scooter', child: Text('Scooter')),
              ],
              onChanged: (v) {
                if (v != null) _vehicleType.text = v;
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _plate,
              decoration: const InputDecoration(
                labelText: 'License plate / vehicle number *',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _saveVehicle,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Next'),
            ),
          ],

          if (step >= 4) ...[
            const Text(
              'Upload your documents',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Check the box once you have uploaded your ID and any required documents.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I have uploaded my documents'),
              value: _docsUploaded,
              onChanged: (v) => setState(() => _docsUploaded = v ?? false),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading
                  ? null
                  : () => _finish(uploadedDocs: _docsUploaded),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Driver'),
            ),
            const SizedBox(height: 12),
            Text(
              'Status: Pending approval. Limited mode remains available until approval.',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
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
                      : () => Navigator.of(context).pushNamed('/signin/driver'),
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
