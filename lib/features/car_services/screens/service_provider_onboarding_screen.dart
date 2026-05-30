import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/models/onboarding_role.dart';
import '../../../features/auth/providers/role_provider.dart';
import '../../../features/auth/services/onboarding_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/friendly_error.dart';
import '../../../modules/car_services/providers/car_services_providers.dart';

const _kBlue = Color(0xFF1D4ED8);
const _kBlueDark = Color(0xFF1E3A8A);
const _kBg = Color(0xFFF8FAFC);

const _kBusinessTypes = [
  'Car Wash',
  'Auto Detailing',
  'Oil Change',
  'Tire Service',
  'Auto Repair',
  'Body Shop',
  'Mobile Mechanic',
  'Other',
];

class ServiceProviderOnboardingScreen extends ConsumerStatefulWidget {
  const ServiceProviderOnboardingScreen({super.key});

  @override
  ConsumerState<ServiceProviderOnboardingScreen> createState() =>
      _ServiceProviderOnboardingScreenState();
}

class _ServiceProviderOnboardingScreenState
    extends ConsumerState<ServiceProviderOnboardingScreen> {
  // step 0=Account, 1=Business, 2=Location, 99=AwaitingEmailConfirmation
  int _step = 0;
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // If the user is already authenticated (returned after email confirmation),
    // skip the account-creation step and go straight to business details.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authNotifierProvider);
      if (authState.user != null && mounted) {
        setState(() => _step = 1);
      }
    });
  }

  // Step 0 — Account
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  // Step 1 — Business
  final _businessNameCtrl = TextEditingController();
  final _businessPhoneCtrl = TextEditingController();
  final _businessEmailCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  String? _selectedBusinessType;

  // Step 2 — Location & Options
  final _addressCtrl = TextEditingController();
  bool _mobileService = false;
  bool _pickupDropoff = false;
  double _radiusKm = 10.0;

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _businessNameCtrl.dispose();
    _businessPhoneCtrl.dispose();
    _businessEmailCtrl.dispose();
    _bioCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _nextStep() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_step == 0) {
      await _signUp();
    } else if (_step < 2) {
      setState(() => _step++);
    } else {
      await _submit();
    }
  }

  Future<void> _signUp() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showError('Please fill in all fields.');
      return;
    }
    if (password.length < 6) {
      _showError('Password must be at least 6 characters.');
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signUp(
        email: email,
        password: password,
        name: name,
        role: 'service_provider',
      );

      final authState = ref.read(authNotifierProvider);

      // Supabase has email confirmation enabled — email was sent, wait for it.
      if (authState.emailConfirmationPending) {
        await ref.read(roleProvider.notifier).setRole(OnboardingRole.serviceProvider);
        if (mounted) setState(() => _step = 99);
        return;
      }

      if (authState.user == null) {
        _showError('Sign-up failed. Please try again.');
        return;
      }

      await ref.read(roleProvider.notifier).setRole(OnboardingRole.serviceProvider);
      if (mounted) setState(() => _step = 1);
    } catch (e, st) {
      AppLogger.error('ServiceProvider signUp error', e, st);
      _showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final authState = ref.read(authNotifierProvider);
    final userId = authState.user?.id;
    if (userId == null) {
      _showError('Not authenticated. Please restart the app.');
      return;
    }

    final businessName = _businessNameCtrl.text.trim();
    if (businessName.isEmpty) {
      _showError('Business name is required.');
      return;
    }

    setState(() => _loading = true);
    try {
      final service = ref.read(onboardingServiceProvider);
      await service.saveServiceProviderDraft(
        userId: userId,
        businessName: businessName,
        ownerName: _nameCtrl.text.trim(),
        businessPhone: _businessPhoneCtrl.text.trim(),
        businessEmail: _businessEmailCtrl.text.trim().isNotEmpty
            ? _businessEmailCtrl.text.trim()
            : _emailCtrl.text.trim(),
        businessType: _selectedBusinessType,
        bio: _bioCtrl.text.trim(),
        mobileServiceAvailable: _mobileService,
        pickupDropoffAvailable: _pickupDropoff,
        serviceAreaRadiusKm: _radiusKm,
        baseLocationAddress: _addressCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        submitted: true,
      );

      // Reload auth state from DB so the role in memory matches what was
      // just written (service_provider). Without this, RoleGuard would see
      // the stale customer role and redirect to the wrong screen.
      await ref.read(authNotifierProvider.notifier).refreshUser();
      ref.invalidate(myCarServiceProviderProfileProvider);

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/car-services/provider',
        (_) => false,
      );
    } catch (e, st) {
      AppLogger.error('ServiceProvider submit error', e, st);
      _showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    // When email confirmation deep link fires, Supabase auto-establishes a
    // session. Listen here so step 99 auto-advances to step 1 without making
    // the user tap "Sign in" and re-enter credentials.
    ref.listen<AuthState>(authNotifierProvider, (prev, next) {
      if (!mounted) return;
      if (_step == 99 && next.isAuthenticated && next.user != null) {
        setState(() => _step = 1);
      }
    });

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBlueDark,
        foregroundColor: Colors.white,
        title: const Text('Car Service Provider'),
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_step != 99) _StepIndicator(currentStep: _step, totalSteps: 3),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: _buildStep(),
              ),
            ),
          ),
          if (_step != 99)
            _BottomBar(
              step: _step,
              loading: _loading,
              onBack: _step > 0 ? () => setState(() => _step--) : null,
              onNext: _nextStep,
            ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _StepAccount(
          nameCtrl: _nameCtrl,
          emailCtrl: _emailCtrl,
          passwordCtrl: _passwordCtrl,
          obscurePassword: _obscurePassword,
          onTogglePassword: () => setState(() => _obscurePassword = !_obscurePassword),
        );
      case 1:
        return _StepBusiness(
          businessNameCtrl: _businessNameCtrl,
          businessPhoneCtrl: _businessPhoneCtrl,
          businessEmailCtrl: _businessEmailCtrl,
          bioCtrl: _bioCtrl,
          selectedType: _selectedBusinessType,
          onTypeChanged: (v) => setState(() => _selectedBusinessType = v),
        );
      case 2:
        return _StepLocation(
          addressCtrl: _addressCtrl,
          mobileService: _mobileService,
          pickupDropoff: _pickupDropoff,
          radiusKm: _radiusKm,
          onMobileChanged: (v) => setState(() => _mobileService = v),
          onPickupChanged: (v) => setState(() => _pickupDropoff = v),
          onRadiusChanged: (v) => setState(() => _radiusKm = v),
        );
      case 99:
        return _StepEmailConfirmation(
          email: _emailCtrl.text.trim(),
          onSignIn: () {
            final auth = ref.read(authNotifierProvider);
            if (auth.isAuthenticated && auth.user != null) {
              // Deep link already established a session — continue onboarding
              setState(() => _step = 1);
            } else {
              // Not yet authenticated — go to sign-in to confirm manually
              Navigator.of(context).pushReplacementNamed('/signin');
            }
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Steps ──────────────────────────────────────────────────────────────────────

class _StepAccount extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;

  const _StepAccount({
    required this.nameCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscurePassword,
    required this.onTogglePassword,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Create your account'),
        const SizedBox(height: 4),
        const Text(
          'You\'ll use these credentials to log in to the provider portal.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 20),
        _Field(controller: nameCtrl, label: 'Your Full Name', icon: Icons.person_outline),
        const SizedBox(height: 12),
        _Field(
          controller: emailCtrl,
          label: 'Email Address',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: passwordCtrl,
          obscureText: obscurePassword,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility),
              onPressed: onTogglePassword,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
          validator: (v) =>
              (v == null || v.length < 6) ? 'Minimum 6 characters' : null,
        ),
        const SizedBox(height: 24),
        const _Divider(),
        const SizedBox(height: 16),
        const Text(
          'Already have an account?',
          style: TextStyle(color: Colors.grey, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.of(context)
                .pushReplacementNamed('/signin', arguments: 'service_provider'),
            child: const Text('Sign in instead'),
          ),
        ),
      ],
    );
  }
}

class _StepBusiness extends StatelessWidget {
  final TextEditingController businessNameCtrl;
  final TextEditingController businessPhoneCtrl;
  final TextEditingController businessEmailCtrl;
  final TextEditingController bioCtrl;
  final String? selectedType;
  final ValueChanged<String?> onTypeChanged;

  const _StepBusiness({
    required this.businessNameCtrl,
    required this.businessPhoneCtrl,
    required this.businessEmailCtrl,
    required this.bioCtrl,
    required this.selectedType,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Business details'),
        const SizedBox(height: 4),
        const Text(
          'Tell customers about your car service business.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 20),
        _Field(
          controller: businessNameCtrl,
          label: 'Business Name',
          icon: Icons.business_outlined,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Business name required' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: selectedType,
          decoration: InputDecoration(
            labelText: 'Business Type',
            prefixIcon: const Icon(Icons.car_repair),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
          items: _kBusinessTypes
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: onTypeChanged,
        ),
        const SizedBox(height: 12),
        _Field(
          controller: businessPhoneCtrl,
          label: 'Business Phone',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        _Field(
          controller: businessEmailCtrl,
          label: 'Business Email (optional)',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _Field(
          controller: bioCtrl,
          label: 'Short Description',
          icon: Icons.info_outline,
          maxLines: 3,
        ),
      ],
    );
  }
}

class _StepLocation extends StatelessWidget {
  final TextEditingController addressCtrl;
  final bool mobileService;
  final bool pickupDropoff;
  final double radiusKm;
  final ValueChanged<bool> onMobileChanged;
  final ValueChanged<bool> onPickupChanged;
  final ValueChanged<double> onRadiusChanged;

  const _StepLocation({
    required this.addressCtrl,
    required this.mobileService,
    required this.pickupDropoff,
    required this.radiusKm,
    required this.onMobileChanged,
    required this.onPickupChanged,
    required this.onRadiusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Location & services'),
        const SizedBox(height: 4),
        const Text(
          'Where are you based and what service options do you offer?',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 20),
        _Field(
          controller: addressCtrl,
          label: 'Business / Base Address',
          icon: Icons.location_on_outlined,
        ),
        const SizedBox(height: 20),
        Text(
          'Service Radius: ${radiusKm.toStringAsFixed(0)} km',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Slider(
          value: radiusKm,
          min: 5,
          max: 50,
          divisions: 9,
          activeColor: _kBlue,
          label: '${radiusKm.toStringAsFixed(0)} km',
          onChanged: onRadiusChanged,
        ),
        const SizedBox(height: 12),
        const Divider(),
        SwitchListTile(
          value: mobileService,
          title: const Text('Mobile / On-site service'),
          subtitle: const Text('You come to the customer\'s location'),
          onChanged: onMobileChanged,
        ),
        SwitchListTile(
          value: pickupDropoff,
          title: const Text('Pickup & Drop-off'),
          subtitle: const Text('You pick up and return the customer\'s vehicle'),
          onChanged: onPickupChanged,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kBlue.withAlpha(12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBlue.withAlpha(40)),
          ),
          child: Row(
            children: const [
              Icon(Icons.info_outline, color: _kBlue, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your application will be reviewed by our team. Once approved, you\'ll be able to receive bookings.',
                  style: TextStyle(fontSize: 12, color: _kBlue),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepEmailConfirmation extends StatelessWidget {
  final String email;
  final VoidCallback onSignIn;

  const _StepEmailConfirmation({required this.email, required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _kBlue.withAlpha(20),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.mark_email_unread_outlined,
              size: 64, color: _kBlue),
        ),
        const SizedBox(height: 28),
        const Text(
          'Confirm your email',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _kBlueDark,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'We sent a confirmation link to:\n$email',
          style: const TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap the link in the email, then come back and sign in to continue your application.',
          style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onSignIn,
            icon: const Icon(Icons.login_rounded),
            label: const Text("I've confirmed — Sign in",
                style: TextStyle(fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          "Didn't receive the email? Check your spam folder,\nor go back and verify your email address.",
          style: TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepIndicator({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: _kBlueDark,
      child: Row(
        children: List.generate(totalSteps, (i) {
          final done = i < currentStep;
          final active = i == currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: (done || active)
                          ? Colors.white
                          : Colors.white.withAlpha(60),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (i < totalSteps - 1) const SizedBox(width: 4),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: _kBlueDark,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(color: Colors.grey.shade400)),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int step;
  final bool loading;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  const _BottomBar({
    required this.step,
    required this.loading,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final labels = ['Create Account', 'Next: Location', 'Submit Application'];
    final label = step < labels.length ? labels[step] : 'Submit';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            OutlinedButton(
              onPressed: loading ? null : onBack,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: ElevatedButton(
              onPressed: loading ? null : onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(label, style: const TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
