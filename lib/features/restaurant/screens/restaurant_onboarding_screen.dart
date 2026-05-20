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
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';

const _kCuisineTypes = [
  'Caribbean', 'Jamaican', 'American', 'Chinese', 'Indian', 'Italian',
  'Mexican', 'Japanese', 'Thai', 'Mediterranean', 'Fast Food', 'Seafood',
  'Vegetarian', 'Vegan', 'Bakery', 'Café', 'Desserts', 'Other',
];

class RestaurantOnboardingScreen extends ConsumerStatefulWidget {
  const RestaurantOnboardingScreen({super.key});

  @override
  ConsumerState<RestaurantOnboardingScreen> createState() =>
      _RestaurantOnboardingScreenState();
}

class _RestaurantOnboardingScreenState
    extends ConsumerState<RestaurantOnboardingScreen> {
  // ── Auth ──────────────────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  // ── Business ──────────────────────────────────────────────────────────────
  final _businessNameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _businessPhoneCtrl = TextEditingController();
  final _businessEmailCtrl = TextEditingController();
  String? _selectedCuisine;

  // ── Location & Hours ──────────────────────────────────────────────────────
  final _addressCtrl = TextEditingController();
  String _openingTime = '08:00';
  String _closingTime = '22:00';
  String _storeType = 'food';

  // ── Banking ───────────────────────────────────────────────────────────────
  final _bankNameCtrl = TextEditingController();
  final _bankHolderCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _bankBranchCtrl = TextEditingController();
  String _bankAccountType = 'checking';

  // ── Misc ──────────────────────────────────────────────────────────────────
  bool _agreedToTerms = false;
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;

  bool get _isBusy => _loading || _googleLoading || _appleLoading;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _businessNameCtrl.dispose();
    _descriptionCtrl.dispose();
    _businessPhoneCtrl.dispose();
    _businessEmailCtrl.dispose();
    _addressCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankHolderCtrl.dispose();
    _bankAccountCtrl.dispose();
    _bankBranchCtrl.dispose();
    super.dispose();
  }

  // ── Auth handlers ─────────────────────────────────────────────────────────

  Future<void> _signUpWithEmail() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (name.isEmpty) {
      AppSnackbar.error(context, 'Enter your full name.');
      return;
    }
    if (email.isEmpty) {
      AppSnackbar.error(context, 'Enter your email address.');
      return;
    }
    if (password.length < 6) {
      AppSnackbar.error(context, 'Password must be at least 6 characters.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signUp(
        email: email,
        password: password,
        name: name,
        role: 'restaurant',
      );
      await _afterAuthSuccess();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
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
      if (mounted) AppSnackbar.error(context, friendlyError(e));
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
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  Future<void> _afterAuthSuccess() async {
    final user = ref.read(authNotifierProvider).user;
    if (user == null) throw Exception('Sign in did not return a user.');

    if (user.role == 'admin') {
      if (mounted) {
        AppSnackbar.success(context, 'Welcome, Admin!');
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/admin-dashboard', (_) => false);
      }
      return;
    }

    await ref.read(roleProvider.notifier).setRole(OnboardingRole.restaurant);
    try {
      await ref.read(onboardingServiceProvider).ensureUserRecord(
        userId: user.id,
        role: OnboardingRole.restaurant,
        email: user.email,
        name: user.name,
      );
    } catch (e) {
      AppLogger.error('Restaurant profile sync failed: $e');
    }
    await ref.read(authNotifierProvider.notifier).refreshUser();
    await ref
        .read(onboardingProvider(OnboardingRole.restaurant).notifier)
        .setStep(0);
    if (mounted) {
      AppSnackbar.success(
        context,
        'Account created! Fill in your restaurant details.',
      );
    }
  }

  // ── Step save ─────────────────────────────────────────────────────────────

  Future<void> _saveAndNext(int nextStep, {bool submit = false}) async {
    setState(() => _loading = true);
    try {
      final userId = ref.read(onboardingServiceProvider).currentUserId;
      if (userId != null) {
        try {
          await ref.read(onboardingServiceProvider).saveRestaurantDraft(
            userId: userId,
            businessName: _businessNameCtrl.text.trim(),
            description: _descriptionCtrl.text.trim().isEmpty
                ? null
                : _descriptionCtrl.text.trim(),
            cuisineType: _selectedCuisine,
            phone: _businessPhoneCtrl.text.trim(),
            email: _businessEmailCtrl.text.trim().isEmpty
                ? null
                : _businessEmailCtrl.text.trim(),
            address: _addressCtrl.text.trim().isEmpty
                ? null
                : _addressCtrl.text.trim(),
            openingTime: _openingTime,
            closingTime: _closingTime,
            storeType: _storeType,
            bankName: _bankNameCtrl.text.trim().isEmpty
                ? null
                : _bankNameCtrl.text.trim(),
            bankAccountHolder: _bankHolderCtrl.text.trim().isEmpty
                ? null
                : _bankHolderCtrl.text.trim(),
            bankAccountNumber: _bankAccountCtrl.text.trim().isEmpty
                ? null
                : _bankAccountCtrl.text.trim(),
            bankAccountType: _bankAccountType,
            bankBranch: _bankBranchCtrl.text.trim().isEmpty
                ? null
                : _bankBranchCtrl.text.trim(),
            onboardingStep: nextStep,
            goLive: submit,
          );
        } catch (e, st) {
          AppLogger.error('Restaurant draft save failed: $e\n$st');
          if (submit) {
            if (mounted) {
              AppSnackbar.error(
                context,
                'Failed to submit application. ${friendlyError(e)}',
              );
            }
            return;
          }
        }
      }

      await ref
          .read(onboardingProvider(OnboardingRole.restaurant).notifier)
          .setStep(nextStep);

      if (submit && mounted) {
        if (userId == null) {
          AppSnackbar.info(
            context,
            'Confirm your email, then sign in to complete your application.',
          );
          Navigator.of(context).pushReplacementNamed('/signin/restaurant');
          return;
        }
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/restaurant-dashboard', (_) => false);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Time picker ───────────────────────────────────────────────────────────

  Future<void> _pickTime(bool isOpening) async {
    final parts = (isOpening ? _openingTime : _closingTime).split(':');
    final initial = TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null && mounted) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isOpening) {
          _openingTime = formatted;
        } else {
          _closingTime = formatted;
        }
      });
    }
  }

  String _fmt(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return hhmm;
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final period = h >= 12 ? 'PM' : 'AM';
    final displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$displayH:${m.toString().padLeft(2, '0')} $period';
  }

  // ── Validation ────────────────────────────────────────────────────────────

  bool _validateBusiness() {
    if (_businessNameCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Enter your restaurant name.');
      return false;
    }
    if (_selectedCuisine == null) {
      AppSnackbar.error(context, 'Select a cuisine type.');
      return false;
    }
    if (_businessPhoneCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Enter a business phone number.');
      return false;
    }
    return true;
  }

  bool _validateLocation() {
    if (_addressCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Enter your restaurant address.');
      return false;
    }
    return true;
  }

  bool _validateBanking() {
    if (_bankNameCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Enter your bank name.');
      return false;
    }
    if (_bankHolderCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Enter the account holder name.');
      return false;
    }
    if (_bankAccountCtrl.text.trim().isEmpty) {
      AppSnackbar.error(context, 'Enter your account number.');
      return false;
    }
    return true;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final step =
        ref.watch(onboardingProvider(OnboardingRole.restaurant)).valueOrNull ??
        0;
    final isAuthStep =
        !authState.isAuthenticated && !authState.emailConfirmationPending;

    final displayStep = isAuthStep ? 1 : (step.clamp(0, 3) + 2);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (!isAuthStep && step > 0) {
              ref
                  .read(onboardingProvider(OnboardingRole.restaurant).notifier)
                  .setStep(step - 1);
            } else {
              Navigator.of(context).pushReplacementNamed('/role-selection');
            }
          },
        ),
        title: Text(
          'Restaurant Application',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      body: Column(
        children: [
          _StepIndicator(currentStep: displayStep, totalSteps: 5),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isAuthStep) _buildAuthStep(),
                  if (!isAuthStep && step == 0) _buildBusinessStep(),
                  if (!isAuthStep && step == 1) _buildLocationStep(),
                  if (!isAuthStep && step == 2) _buildBankingStep(),
                  if (!isAuthStep && step >= 3) _buildReviewStep(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Account ───────────────────────────────────────────────────────

  Widget _buildAuthStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeader(
          icon: Icons.store_rounded,
          title: 'Create Your Account',
          subtitle: 'Get started with your restaurant application',
        ),
        const SizedBox(height: 24),
        SocialAuthPanel(
          onGoogle: _isBusy ? null : _continueWithGoogle,
          onApple: _isBusy ? null : _continueWithApple,
          googleLoading: _googleLoading,
          appleLoading: _appleLoading,
        ),
        const SizedBox(height: 16),
        _divider('or sign up with email'),
        const SizedBox(height: 16),
        _field(_nameCtrl, 'Full name', icon: Icons.person_outline),
        const SizedBox(height: 12),
        _field(
          _emailCtrl,
          'Email address',
          keyboardType: TextInputType.emailAddress,
          icon: Icons.email_outlined,
        ),
        const SizedBox(height: 12),
        _passwordField(),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: 'Continue',
          onPressed: _isBusy ? null : _signUpWithEmail,
          isLoading: _loading,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Already have an account? ',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            TextButton(
              onPressed: _isBusy
                  ? null
                  : () =>
                      Navigator.of(context).pushNamed('/signin/restaurant'),
              child: Text(
                'Sign in',
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Step 2: Business Details ──────────────────────────────────────────────

  Widget _buildBusinessStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeader(
          icon: Icons.restaurant_menu_rounded,
          title: 'Business Details',
          subtitle: 'Tell us about your restaurant',
        ),
        const SizedBox(height: 24),
        _field(
          _businessNameCtrl,
          'Restaurant name *',
          icon: Icons.storefront_outlined,
        ),
        const SizedBox(height: 12),
        _field(
          _descriptionCtrl,
          'Description',
          maxLines: 3,
          icon: Icons.description_outlined,
          hint: 'Brief description of your food, cuisine, and vibe…',
        ),
        const SizedBox(height: 16),
        _label('Cuisine Type *'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kCuisineTypes.map((c) => _CuisineChip(
            label: c,
            selected: _selectedCuisine == c,
            onTap: () => setState(() => _selectedCuisine = c),
          )).toList(),
        ),
        const SizedBox(height: 16),
        _field(
          _businessPhoneCtrl,
          'Business phone *',
          keyboardType: TextInputType.phone,
          icon: Icons.phone_outlined,
        ),
        const SizedBox(height: 12),
        _field(
          _businessEmailCtrl,
          'Business email (optional)',
          keyboardType: TextInputType.emailAddress,
          icon: Icons.alternate_email,
        ),
        const SizedBox(height: 28),
        _PrimaryButton(
          label: 'Continue',
          onPressed: _loading
              ? null
              : () { if (_validateBusiness()) _saveAndNext(1); },
          isLoading: _loading,
        ),
      ],
    );
  }

  // ── Step 3: Location & Hours ──────────────────────────────────────────────

  Widget _buildLocationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeader(
          icon: Icons.location_on_rounded,
          title: 'Location & Hours',
          subtitle: 'Where are you located and when are you open?',
        ),
        const SizedBox(height: 24),
        _field(
          _addressCtrl,
          'Full address *',
          icon: Icons.place_outlined,
          hint: '123 Main St, Kingston, Jamaica',
        ),
        const SizedBox(height: 20),
        _label('Operating Hours'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _TimePickerTile(
                label: 'Opening Time',
                displayTime: _fmt(_openingTime),
                onTap: () => _pickTime(true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TimePickerTile(
                label: 'Closing Time',
                displayTime: _fmt(_closingTime),
                onTap: () => _pickTime(false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _label('Store Type'),
        const SizedBox(height: 8),
        Row(
          children: [
            _StoreTypeChip(
              value: 'food',
              label: 'Food Only',
              icon: Icons.restaurant,
              selected: _storeType == 'food',
              onTap: () => setState(() => _storeType = 'food'),
            ),
            const SizedBox(width: 8),
            _StoreTypeChip(
              value: 'grocery',
              label: 'Grocery',
              icon: Icons.shopping_bag_outlined,
              selected: _storeType == 'grocery',
              onTap: () => setState(() => _storeType = 'grocery'),
            ),
            const SizedBox(width: 8),
            _StoreTypeChip(
              value: 'both',
              label: 'Both',
              icon: Icons.store,
              selected: _storeType == 'both',
              onTap: () => setState(() => _storeType = 'both'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        _PrimaryButton(
          label: 'Continue',
          onPressed: _loading
              ? null
              : () { if (_validateLocation()) _saveAndNext(2); },
          isLoading: _loading,
        ),
      ],
    );
  }

  // ── Step 4: Banking ───────────────────────────────────────────────────────

  Widget _buildBankingStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeader(
          icon: Icons.account_balance_rounded,
          title: 'Banking Details',
          subtitle: 'Required for receiving your restaurant payouts',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your banking details are encrypted and only used for payout processing.',
                  style: TextStyle(fontSize: 12, color: Colors.blue[800]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _field(
          _bankNameCtrl,
          'Bank name *',
          icon: Icons.account_balance_outlined,
        ),
        const SizedBox(height: 12),
        _field(
          _bankHolderCtrl,
          'Account holder name *',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 12),
        _field(
          _bankAccountCtrl,
          'Account number *',
          keyboardType: TextInputType.number,
          icon: Icons.credit_card_outlined,
        ),
        const SizedBox(height: 12),
        _field(
          _bankBranchCtrl,
          'Branch / routing number (optional)',
          icon: Icons.location_city_outlined,
        ),
        const SizedBox(height: 16),
        _label('Account Type'),
        const SizedBox(height: 8),
        Row(
          children: ['checking', 'savings', 'business'].map((type) {
            final selected = _bankAccountType == type;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _CuisineChip(
                label: type[0].toUpperCase() + type.substring(1),
                selected: selected,
                onTap: () => setState(() => _bankAccountType = type),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 28),
        _PrimaryButton(
          label: 'Review Application',
          onPressed: _loading
              ? null
              : () { if (_validateBanking()) _saveAndNext(3); },
          isLoading: _loading,
        ),
      ],
    );
  }

  // ── Step 5: Review & Submit ───────────────────────────────────────────────

  Widget _buildReviewStep() {
    final maskedAccount = _bankAccountCtrl.text.trim();
    final maskedDisplay = maskedAccount.length > 4
        ? '••••${maskedAccount.substring(maskedAccount.length - 4)}'
        : maskedAccount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeader(
          icon: Icons.fact_check_rounded,
          title: 'Review & Submit',
          subtitle: 'Review your information before submitting your application',
        ),
        const SizedBox(height: 24),

        // Business info card
        _ReviewCard(title: 'Business Info', icon: Icons.storefront_outlined, rows: [
          ('Restaurant', _businessNameCtrl.text.trim().orDash),
          ('Cuisine', _selectedCuisine ?? '—'),
          if (_descriptionCtrl.text.trim().isNotEmpty)
            ('Description', _descriptionCtrl.text.trim()),
          ('Phone', _businessPhoneCtrl.text.trim().orDash),
          if (_businessEmailCtrl.text.trim().isNotEmpty)
            ('Email', _businessEmailCtrl.text.trim()),
        ]),

        // Location card
        _ReviewCard(title: 'Location & Hours', icon: Icons.place_outlined, rows: [
          ('Address', _addressCtrl.text.trim().orDash),
          ('Hours', '${_fmt(_openingTime)} – ${_fmt(_closingTime)}'),
          ('Store Type', _storeType == 'both'
              ? 'Food & Grocery'
              : _storeType[0].toUpperCase() + _storeType.substring(1)),
        ]),

        // Banking card
        _ReviewCard(title: 'Banking Details', icon: Icons.account_balance_outlined, rows: [
          ('Bank', _bankNameCtrl.text.trim().orDash),
          ('Holder', _bankHolderCtrl.text.trim().orDash),
          ('Account', maskedDisplay.isEmpty ? '—' : maskedDisplay),
          ('Type', _bankAccountType[0].toUpperCase() + _bankAccountType.substring(1)),
        ]),

        // Terms
        GestureDetector(
          onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _agreedToTerms,
                onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                activeColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text.rich(
                    TextSpan(
                      text:
                          'I confirm all information is accurate and I agree to the ',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(
                          text: 'Terms & Conditions',
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Restaurant Partner Agreement.',
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Review note
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: Colors.amber[800]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your application will be reviewed by our team within 24–48 hours. You will be notified once approved.',
                  style: TextStyle(fontSize: 12, color: Colors.amber[900]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Submit button
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          decoration: BoxDecoration(
            gradient: (_loading || !_agreedToTerms)
                ? const LinearGradient(
                    colors: [Color(0xFFD1D5DB), Color(0xFFD1D5DB)],
                  )
                : LinearGradient(
                    colors: [AppTheme.primaryColor, const Color(0xFFFF8C42)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: (_loading || !_agreedToTerms)
                ? []
                : [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: (_loading || !_agreedToTerms)
                  ? null
                  : () => _saveAndNext(7, submit: true),
              child: Center(
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.send_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Submit Application',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading
              ? null
              : () => ref
                  .read(
                    onboardingProvider(OnboardingRole.restaurant).notifier,
                  )
                  .setStep(2),
          child: Text(
            'Go back to edit',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _field(
    TextEditingController ctrl,
    String label, {
    TextInputType? keyboardType,
    int maxLines = 1,
    String? hint,
    IconData? icon,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null
            ? Icon(icon, size: 20, color: AppTheme.primaryColor)
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _passwordField() {
    return TextFormField(
      controller: _passwordCtrl,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: Icon(
          Icons.lock_outline,
          size: 20,
          color: AppTheme.primaryColor,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      ),
    );
  }

  Widget _divider(String text) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ],
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

// ── Private sub-widgets ────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _StepIndicator({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        children: [
          Row(
            children: List.generate(totalSteps * 2 - 1, (i) {
              if (i.isOdd) {
                final stepNum = (i ~/ 2) + 1;
                return Expanded(
                  child: Container(
                    height: 2,
                    color: stepNum < currentStep
                        ? AppTheme.primaryColor
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                );
              }
              final stepNum = (i ~/ 2) + 1;
              final done = stepNum < currentStep;
              final active = stepNum == currentStep;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (done || active)
                      ? AppTheme.primaryColor
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: (done || active)
                        ? AppTheme.primaryColor
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text(
                          '$stepNum',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? Colors.white
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            'Step $currentStep of $totalSteps',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _StepHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 26),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52,
      decoration: BoxDecoration(
        gradient: onPressed == null
            ? const LinearGradient(
                colors: [Color(0xFFD1D5DB), Color(0xFFD1D5DB)],
              )
            : LinearGradient(
                colors: [AppTheme.primaryColor, const Color(0xFFFF8C42)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: onPressed == null
            ? []
            : [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _CuisineChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CuisineChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor
              : Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _TimePickerTile extends StatelessWidget {
  final String label;
  final String displayTime;
  final VoidCallback onTap;
  const _TimePickerTile({
    required this.label,
    required this.displayTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 18, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  displayTime,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreTypeChip extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _StoreTypeChip({
    required this.value,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? AppTheme.primaryColor
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected
                    ? AppTheme.primaryColor
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<(String, String)> rows;
  const _ReviewCard({
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      r.$1,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.$2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String get orDash => trim().isEmpty ? '—' : trim();
}
