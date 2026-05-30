import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../features/auth/models/onboarding_role.dart';
import '../../../features/auth/providers/onboarding_provider.dart';
import '../../../features/auth/providers/role_provider.dart';
import '../../../features/auth/services/onboarding_service.dart';
import '../../../features/auth/widgets/social_auth_panel.dart';
import '../../../providers/auth_provider.dart';
import '../../../config/supabase_config.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/friendly_error.dart';
import '../../../core/utils/responsive.dart';
import '../../../modules/rides/services/driver_document_service.dart';
import '../../../modules/rides/providers/driver_document_provider.dart';

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
  String? _selectedVehicleType;

  final _picker = ImagePicker();
  final Map<String, File?> _docFiles = {'license': null, 'registration': null};
  final Set<String> _uploadedDocTypes = {};

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
      try {
        await ref
            .read(authNotifierProvider.notifier)
            .signUp(
              email: email,
              password: password,
              name: name,
              role: 'driver',
            );
      } catch (e, st) {
        // Auth signup itself can throw "Account created. Please check
        // your email..." — that is success, not failure. Detect it and
        // continue to the email-pending branch instead of bailing out.
        AppLogger.error('Driver email signup raised: $e\n$st');
        final msg = e.toString().toLowerCase();
        final isEmailPending =
            msg.contains('check your email') ||
            msg.contains('email_not_confirmed') ||
            msg.contains('email not confirmed') ||
            msg.contains('confirmation') ||
            ref.read(authNotifierProvider).emailConfirmationPending;
        if (!isEmailPending) {
          if (mounted) AppSnackbar.error(context, friendlyError(e));
          return;
        }
      }

      final authState = ref.read(authNotifierProvider);

      // Email confirmation flow OR direct authentication — both should
      // advance the user. Pre-fill profile fields so they don't retype.
      _name.text = _signUpName.text.trim();
      _email.text = _signUpEmail.text.trim();

      if (authState.isAuthenticated) {
        await _afterAuthSuccess();
        return;
      }

      // Email-confirm pending: keep the flow moving locally.
      await ref
          .read(onboardingProvider(OnboardingRole.driver).notifier)
          .setStep(2);
      if (!mounted) return;
      AppSnackbar.info(
        context,
        'Account created! Confirm your email when you can — keep filling in your details.',
      );
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

    // Admin logging in from any portal — skip role upsert and go straight to
    // the admin dashboard so their DB role is never overwritten.
    if (user.role == 'admin') {
      if (!mounted) return;
      AppSnackbar.success(context, 'Welcome, Admin!');
      Navigator.of(context).pushNamedAndRemoveUntil('/admin-dashboard', (_) => false);
      return;
    }

    await ref.read(roleProvider.notifier).setRole(OnboardingRole.driver);
    try {
      // user.name may be null right after sign-up (before refreshUser);
      // fall back to what the user typed in the sign-up form.
      final nameToSave = (user.name != null && user.name!.isNotEmpty)
          ? user.name
          : _signUpName.text.trim().isNotEmpty
          ? _signUpName.text.trim()
          : null;
      await ref
          .read(onboardingServiceProvider)
          .saveDriverProfile(
            userId: user.id,
            email: user.email,
            name: nameToSave,
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
    if (_selectedVehicleType == null) {
      AppSnackbar.error(context, 'Please select a vehicle type.');
      return;
    }
    if (_plate.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Please enter your license plate number.');
      return;
    }
    _vehicleType.text = _selectedVehicleType!;
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

  Future<void> _pickDocFile(String type) async {
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked == null) return;
    setState(() => _docFiles[type] = File(picked.path));
  }

  Future<void> _finish() async {
    setState(() => _loading = true);
    try {
      final userId = ref.read(onboardingServiceProvider).currentUserId;

      // Upload any selected document files
      if (userId != null) {
        for (final entry in _docFiles.entries) {
          final file = entry.value;
          if (file == null) continue;
          try {
            await ref
                .read(driverDocumentServiceProvider)
                .uploadDocument(
                  UploadDriverDocumentParams(
                    driverId: userId,
                    documentType: entry.key,
                    filePath: file.path,
                  ),
                );
            _uploadedDocTypes.add(entry.key);
          } catch (e) {
            AppLogger.error('Doc upload failed for ${entry.key}: $e');
          }
        }
      }

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
              documentsUploaded: _uploadedDocTypes.isNotEmpty,
            );
      }

      if (userId != null) {
        try {
          await SupabaseConfig.client
              .from('drivers')
              .update({'driver_status': 'pending_review'})
              .eq('user_id', userId);
        } catch (e) {
          AppLogger.error('Failed to set pending_review status: $e');
        }
      }

      await ref
          .read(onboardingProvider(OnboardingRole.driver).notifier)
          .setStep(5);

      if (!mounted) return;
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
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.horizontalPadding(context),
          vertical: Responsive.cardPadding(context),
        ),
        children: [
          Text(
            'Start earning fast',
            style: TextStyle(
              fontSize: Responsive.headingLarge(context),
              fontWeight: FontWeight.bold,
            ),
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
                      style: TextStyle(
                        fontSize: Responsive.smallText(context),
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
              initialValue: _selectedVehicleType,
              decoration: const InputDecoration(labelText: 'Vehicle type *'),
              items: const [
                DropdownMenuItem(
                  value: 'bike',
                  child: Text('Bike / Motorcycle'),
                ),
                DropdownMenuItem(value: 'car', child: Text('Car')),
                DropdownMenuItem(value: 'scooter', child: Text('Scooter')),
              ],
              onChanged: (v) => setState(() => _selectedVehicleType = v),
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
            Text(
              'Upload Documents',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: Responsive.headingSmall(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Upload your Driver\'s ID and vehicle registration. You can also skip and submit later.',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Driver's ID / License card
            _DocUploadTile(
              label: "Driver's ID / License",
              icon: Icons.badge_outlined,
              file: _docFiles['license'],
              uploaded: _uploadedDocTypes.contains('license'),
              disabled: _loading,
              onPick: () => _pickDocFile('license'),
              onRemove: () => setState(() {
                _docFiles['license'] = null;
                _uploadedDocTypes.remove('license');
              }),
            ),
            const SizedBox(height: 12),

            // Vehicle Registration card
            _DocUploadTile(
              label: 'Vehicle Registration',
              icon: Icons.directions_car_outlined,
              file: _docFiles['registration'],
              uploaded: _uploadedDocTypes.contains('registration'),
              disabled: _loading,
              onPick: () => _pickDocFile('registration'),
              onRemove: () => setState(() {
                _docFiles['registration'] = null;
                _uploadedDocTypes.remove('registration');
              }),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _loading ? null : _finish,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit Application'),
            ),
            const SizedBox(height: 12),
            Text(
              'Your application will be reviewed before you can start delivering.',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: Responsive.smallText(context),
              ),
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

// ─── Document Upload Tile ─────────────────────────────────────────────────────

class _DocUploadTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final File? file;
  final bool uploaded;
  final bool disabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _DocUploadTile({
    required this.label,
    required this.icon,
    required this.file,
    required this.uploaded,
    required this.disabled,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = file != null;
    final statusColor = uploaded
        ? const Color(0xFF10B981)
        : hasFile
        ? const Color(0xFFF59E0B)
        : Colors.grey[400]!;
    final statusLabel = uploaded
        ? 'Uploaded'
        : hasFile
        ? 'Ready to upload'
        : 'Not selected';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasFile
              ? statusColor.withValues(alpha: 0.4)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasFile
                      ? file!.path.split(RegExp(r'[/\\]')).last
                      : statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: hasFile
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Colors.grey[500],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (hasFile)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: Colors.grey[500],
              tooltip: 'Remove',
              onPressed: disabled ? null : onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: disabled ? null : onPick,
            icon: Icon(
              hasFile ? Icons.refresh_rounded : Icons.upload_rounded,
              size: 16,
            ),
            label: Text(hasFile ? 'Change' : 'Upload'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }
}
