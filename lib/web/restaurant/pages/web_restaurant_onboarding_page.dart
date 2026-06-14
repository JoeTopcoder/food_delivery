import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/models/onboarding_role.dart';
import '../../../features/auth/providers/onboarding_provider.dart';
import '../../../features/auth/providers/role_provider.dart';
import '../../../features/auth/services/onboarding_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/friendly_error.dart';

// ── Palette (matches landing page) ───────────────────────────────────────────
const _navy    = Color(0xFF0F172A);
const _navyMid = Color(0xFF1E293B);
const _gold    = Color(0xFFF59E0B);
const _goldL   = Color(0xFFFCD34D);
const _slate   = Color(0xFF64748B);
const _border  = Color(0xFFE2E8F0);
const _surface = Color(0xFFF8FAFC);

const _kCuisineTypes = [
  'Caribbean', 'Jamaican', 'American', 'Chinese', 'Indian', 'Italian',
  'Mexican', 'Japanese', 'Thai', 'Mediterranean', 'Fast Food', 'Seafood',
  'Vegetarian', 'Vegan', 'Bakery', 'Café', 'Desserts', 'Other',
];

// ── Left-panel config per step ───────────────────────────────────────────────
const _stepConfig = [
  (
    heading: 'Join 500+\nRestaurant Partners',
    sub: 'Create your account and start growing your restaurant today.',
    icon: Icons.storefront_rounded,
    bullets: [
      (Icons.percent_rounded,        '0% commission your first 30 days'),
      (Icons.bolt_rounded,           'Fast, weekly bank payouts'),
      (Icons.support_agent_rounded,  '24/7 dedicated partner support'),
      (Icons.bar_chart_rounded,      'Real-time sales & analytics'),
    ],
  ),
  (
    heading: 'Tell Us About\nYour Restaurant',
    sub: 'A great profile helps customers discover and love your food.',
    icon: Icons.restaurant_menu_rounded,
    bullets: [
      (Icons.visibility_rounded,     'More detail = more visibility in search'),
      (Icons.local_offer_rounded,    'Cuisine type matches customer preferences'),
      (Icons.photo_camera_rounded,   'Descriptions drive up to 35% more orders'),
      (Icons.star_rounded,           'Start with a 5-star setup from day one'),
    ],
  ),
  (
    heading: 'Reach Customers\nNear You',
    sub: 'Your location and hours help us match you with hungry locals.',
    icon: Icons.location_on_rounded,
    bullets: [
      (Icons.people_rounded,         'Connect with thousands of nearby customers'),
      (Icons.schedule_rounded,       'Set hours that fit your kitchen schedule'),
      (Icons.delivery_dining_rounded,'We handle all delivery logistics for you'),
      (Icons.notifications_rounded,  'Get notified the moment orders come in'),
    ],
  ),
  (
    heading: 'Fast, Secure\nPayouts',
    sub: 'Your earnings deposited directly to your bank account.',
    icon: Icons.account_balance_rounded,
    bullets: [
      (Icons.lock_rounded,           'Bank-level 256-bit encryption'),
      (Icons.payments_rounded,       'Weekly automatic payout schedule'),
      (Icons.receipt_long_rounded,   'Full transaction history & reporting'),
      (Icons.shield_rounded,         'No hidden fees or surprise deductions'),
    ],
  ),
  (
    heading: 'Almost There!',
    sub: 'Review your application and submit — we\'ll take it from here.',
    icon: Icons.fact_check_rounded,
    bullets: [
      (Icons.hourglass_top_rounded,  'Admin review within 24–48 hours'),
      (Icons.verified_rounded,       'Account activated once approved'),
      (Icons.restaurant_rounded,     'Menu setup assistance included'),
      (Icons.rocket_launch_rounded,  'Start receiving orders immediately'),
    ],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────

class WebRestaurantOnboardingPage extends ConsumerStatefulWidget {
  const WebRestaurantOnboardingPage({super.key});

  @override
  ConsumerState<WebRestaurantOnboardingPage> createState() =>
      _WebRestaurantOnboardingPageState();
}

class _WebRestaurantOnboardingPageState
    extends ConsumerState<WebRestaurantOnboardingPage> {
  // ── Form controllers ───────────────────────────────────────────────────────
  final _nameCtrl         = TextEditingController();
  final _emailCtrl        = TextEditingController();
  final _passwordCtrl     = TextEditingController();
  final _businessNameCtrl = TextEditingController();
  final _descriptionCtrl  = TextEditingController();
  final _businessPhoneCtrl= TextEditingController();
  final _businessEmailCtrl= TextEditingController();
  final _addressCtrl      = TextEditingController();
  final _bankNameCtrl     = TextEditingController();
  final _bankHolderCtrl   = TextEditingController();
  final _bankAccountCtrl  = TextEditingController();
  final _bankBranchCtrl   = TextEditingController();

  final _scrollCtrl = ScrollController();

  bool _obscurePassword  = true;
  String? _selectedCuisine;
  String _openingTime    = '08:00';
  String _closingTime    = '22:00';
  String _storeType      = 'food';
  String _bankAccountType= 'checking';
  bool   _agreedToTerms  = false;
  bool   _loading        = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _passwordCtrl.dispose();
    _businessNameCtrl.dispose(); _descriptionCtrl.dispose();
    _businessPhoneCtrl.dispose(); _businessEmailCtrl.dispose();
    _addressCtrl.dispose(); _bankNameCtrl.dispose(); _bankHolderCtrl.dispose();
    _bankAccountCtrl.dispose(); _bankBranchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  Future<void> _signUpWithEmail() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass  = _passwordCtrl.text;
    if (name.isEmpty)  { _err('Enter your full name.');            return; }
    if (email.isEmpty) { _err('Enter your email address.');        return; }
    if (pass.length < 6){ _err('Password must be at least 6 characters.'); return; }
    setState(() => _loading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signUp(
        email: email, password: pass, name: name, role: 'restaurant',
      );
      await _afterAuth();
    } catch (e) {
      if (mounted) _err(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _afterAuth() async {
    final user = ref.read(authNotifierProvider).user;
    if (user == null) throw Exception('Sign-in did not return a user.');
    if (user.role == 'admin') {
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/admin-dashboard', (_) => false);
      return;
    }
    await ref.read(roleProvider.notifier).setRole(OnboardingRole.restaurant);
    try {
      await ref.read(onboardingServiceProvider).ensureUserRecord(
        userId: user.id, role: OnboardingRole.restaurant,
        email: user.email, name: user.name,
      );
    } catch (e) { AppLogger.error('ensureUserRecord: $e'); }
    await ref.read(authNotifierProvider.notifier).refreshUser();
    await ref.read(onboardingProvider(OnboardingRole.restaurant).notifier).setStep(0);
    if (mounted) _ok('Account created! Fill in your restaurant details.');
  }

  // ── Step save ──────────────────────────────────────────────────────────────

  Future<void> _saveAndNext(int nextStep, {bool submit = false}) async {
    setState(() => _loading = true);
    try {
      final userId = ref.read(onboardingServiceProvider).currentUserId;
      if (userId != null) {
        try {
          await ref.read(onboardingServiceProvider).saveRestaurantDraft(
            userId: userId,
            businessName:      _businessNameCtrl.text.trim(),
            description:       _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
            cuisineType:       _selectedCuisine,
            phone:             _businessPhoneCtrl.text.trim(),
            email:             _businessEmailCtrl.text.trim().isEmpty ? null : _businessEmailCtrl.text.trim(),
            address:           _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
            openingTime:       _openingTime,
            closingTime:       _closingTime,
            storeType:         _storeType,
            bankName:          _bankNameCtrl.text.trim().isEmpty ? null : _bankNameCtrl.text.trim(),
            bankAccountHolder: _bankHolderCtrl.text.trim().isEmpty ? null : _bankHolderCtrl.text.trim(),
            bankAccountNumber: _bankAccountCtrl.text.trim().isEmpty ? null : _bankAccountCtrl.text.trim(),
            bankAccountType:   _bankAccountType,
            bankBranch:        _bankBranchCtrl.text.trim().isEmpty ? null : _bankBranchCtrl.text.trim(),
            onboardingStep:    nextStep,
            goLive:            submit,
          );
        } catch (e, st) {
          AppLogger.error('saveRestaurantDraft: $e\n$st');
          if (submit) { _err('Failed to submit. ${friendlyError(e)}'); return; }
        }
      }
      await ref.read(onboardingProvider(OnboardingRole.restaurant).notifier).setStep(nextStep);
      if (submit && mounted) {
        if (userId == null) {
          _ok('Confirm your email, then sign in to complete your application.');
          Navigator.of(context).pushReplacementNamed('/signin/restaurant');
          return;
        }
        if (kIsWeb) {
          ref.invalidate(restaurantByOwnerProvider(userId));
          _ok('Application submitted! We will review your restaurant shortly.');
          return;
        }
        Navigator.of(context).pushNamedAndRemoveUntil('/restaurant-dashboard', (_) => false);
      }
      _scrollToTop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToTop() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  bool _validateBusiness() {
    if (_businessNameCtrl.text.trim().isEmpty) { _err('Enter your restaurant name.');    return false; }
    if (_selectedCuisine == null)              { _err('Select a cuisine type.');          return false; }
    if (_businessPhoneCtrl.text.trim().isEmpty){ _err('Enter a business phone number.');  return false; }
    return true;
  }
  bool _validateLocation() {
    if (_addressCtrl.text.trim().isEmpty) { _err('Enter your restaurant address.'); return false; }
    return true;
  }
  bool _validateBanking() {
    if (_bankNameCtrl.text.trim().isEmpty)   { _err('Enter your bank name.');            return false; }
    if (_bankHolderCtrl.text.trim().isEmpty) { _err('Enter the account holder name.');   return false; }
    if (_bankAccountCtrl.text.trim().isEmpty){ _err('Enter your account number.');        return false; }
    return true;
  }

  // ── Time picker ────────────────────────────────────────────────────────────

  Future<void> _pickTime(bool isOpening) async {
    final parts = (isOpening ? _openingTime : _closingTime).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked != null && mounted) {
      final fmt = '${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}';
      setState(() { if (isOpening) _openingTime = fmt; else _closingTime = fmt; });
    }
  }

  String _fmtTime(String hhmm) {
    final p = hhmm.split(':');
    final h = int.parse(p[0]); final m = int.parse(p[1]);
    final period = h >= 12 ? 'PM' : 'AM';
    final dh = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$dh:${m.toString().padLeft(2,'0')} $period';
  }

  void _err(String msg) => AppSnackbar.error(context, msg);
  void _ok(String msg)  => AppSnackbar.success(context, msg);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final step = ref.watch(onboardingProvider(OnboardingRole.restaurant)).valueOrNull ?? 0;
    final isAuthStep = !authState.isAuthenticated && !authState.emailConfirmationPending;
    final displayStep = isAuthStep ? 0 : step.clamp(0, 4);
    final cfg = _stepConfig[displayStep];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (authState.isAuthenticated) {
          // Signed in mid-application → sign out so the auth gate shows the landing page
          await ref.read(authNotifierProvider.notifier).signOut();
        } else {
          // Not signed in → was pushed from the landing page, just pop back
          if (context.mounted) Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // ── LEFT PANEL ────────────────────────────────────────────────
          _LeftPanel(
            stepIndex: displayStep,
            isAuthStep: isAuthStep,
            config: cfg,
          ),
          // ── RIGHT PANEL ───────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Step dots
                        if (!isAuthStep) ...[
                          _StepDots(current: displayStep, total: 4),
                          const SizedBox(height: 36),
                        ],
                        // Form for current step
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey(displayStep),
                            child: isAuthStep
                                ? _buildAccountStep()
                                : switch (displayStep) {
                                    0 => _buildBusinessStep(),
                                    1 => _buildLocationStep(),
                                    2 => _buildBankingStep(),
                                    _ => _buildReviewStep(),
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),   // Scaffold
    );   // PopScope
  }

  // ── Step 1: Account ────────────────────────────────────────────────────────

  Widget _buildAccountStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepBadge('Step 1 of 5'),
        const SizedBox(height: 8),
        const Text('Create Your Account', style: _titleStyle),
        const SizedBox(height: 6),
        const Text('Get started with your restaurant partner application.', style: _subStyle),
        const SizedBox(height: 32),

        // Social buttons
        _SocialButton(
          icon: Icons.g_mobiledata_rounded,
          label: 'Continue with Google',
          onPressed: _loading ? null : () async {
            setState(() => _loading = true);
            try {
              await ref.read(authNotifierProvider.notifier).signInWithGoogle();
              await _afterAuth();
            } catch (e) { if (mounted) _err(friendlyError(e)); }
            finally { if (mounted) setState(() => _loading = false); }
          },
        ),
        const SizedBox(height: 10),
        _divider('or sign up with email'),
        const SizedBox(height: 20),

        _WebField(ctrl: _nameCtrl,  label: 'Full name',      icon: Icons.person_outline_rounded),
        const SizedBox(height: 14),
        _WebField(ctrl: _emailCtrl, label: 'Email address',  icon: Icons.email_outlined, inputType: TextInputType.emailAddress),
        const SizedBox(height: 14),
        _PasswordField(ctrl: _passwordCtrl, obscure: _obscurePassword, onToggle: () => setState(() => _obscurePassword = !_obscurePassword)),
        const SizedBox(height: 28),

        _PrimaryBtn(label: 'Create Account & Continue', loading: _loading, onPressed: _loading ? null : _signUpWithEmail),
        const SizedBox(height: 20),
        _centeredLink(
          prefix: 'Already have an account? ',
          label: 'Sign in',
          onTap: () => Navigator.of(context).pushNamed('/signin/restaurant'),
        ),
      ],
    );
  }

  // ── Step 2: Business ───────────────────────────────────────────────────────

  Widget _buildBusinessStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepBadge('Step 2 of 5'),
        const SizedBox(height: 8),
        const Text('Business Details', style: _titleStyle),
        const SizedBox(height: 6),
        const Text('Tell us about your restaurant so customers can find you.', style: _subStyle),
        const SizedBox(height: 32),

        _WebField(ctrl: _businessNameCtrl, label: 'Restaurant name *', icon: Icons.storefront_outlined),
        const SizedBox(height: 14),
        _WebField(ctrl: _descriptionCtrl,  label: 'Description (optional)', icon: Icons.description_outlined, maxLines: 3, hint: 'Tell customers what makes your food special…'),
        const SizedBox(height: 20),

        _sectionLabel('Cuisine Type *'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _kCuisineTypes.map((c) => _CuisineChip(
            label: c, selected: _selectedCuisine == c,
            onTap: () => setState(() => _selectedCuisine = c),
          )).toList(),
        ),
        const SizedBox(height: 20),

        Row(children: [
          Expanded(child: _WebField(ctrl: _businessPhoneCtrl, label: 'Business phone *', icon: Icons.phone_outlined, inputType: TextInputType.phone)),
          const SizedBox(width: 14),
          Expanded(child: _WebField(ctrl: _businessEmailCtrl, label: 'Business email', icon: Icons.alternate_email, inputType: TextInputType.emailAddress)),
        ]),
        const SizedBox(height: 32),

        _PrimaryBtn(label: 'Save & Continue', loading: _loading, onPressed: _loading ? null : () { if (_validateBusiness()) _saveAndNext(1); }),
      ],
    );
  }

  // ── Step 3: Location & Hours ───────────────────────────────────────────────

  Widget _buildLocationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepBadge('Step 3 of 5'),
        const SizedBox(height: 8),
        const Text('Location & Hours', style: _titleStyle),
        const SizedBox(height: 6),
        const Text('Where are you located and when are you open?', style: _subStyle),
        const SizedBox(height: 32),

        _WebField(ctrl: _addressCtrl, label: 'Full address *', icon: Icons.place_outlined, hint: '123 Main St, Kingston, Jamaica'),
        const SizedBox(height: 24),

        _sectionLabel('Operating Hours'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _TimeTile(label: 'Opening', time: _fmtTime(_openingTime), onTap: () => _pickTime(true))),
          const SizedBox(width: 14),
          Expanded(child: _TimeTile(label: 'Closing',  time: _fmtTime(_closingTime), onTap: () => _pickTime(false))),
        ]),
        const SizedBox(height: 24),

        _sectionLabel('Store Type'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _StoreTypeBtn(value: 'food',    label: 'Food Only', icon: Icons.restaurant_rounded,     selected: _storeType == 'food',    onTap: () => setState(() => _storeType = 'food'))),
          const SizedBox(width: 10),
          Expanded(child: _StoreTypeBtn(value: 'grocery', label: 'Grocery',   icon: Icons.local_grocery_store_rounded, selected: _storeType == 'grocery', onTap: () => setState(() => _storeType = 'grocery'))),
          const SizedBox(width: 10),
          Expanded(child: _StoreTypeBtn(value: 'both',    label: 'Both',      icon: Icons.store_rounded,          selected: _storeType == 'both',    onTap: () => setState(() => _storeType = 'both'))),
        ]),
        const SizedBox(height: 32),

        Row(children: [
          Expanded(child: _SecondaryBtn(label: 'Back', onPressed: _loading ? null : () => ref.read(onboardingProvider(OnboardingRole.restaurant).notifier).setStep(0))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _PrimaryBtn(label: 'Save & Continue', loading: _loading, onPressed: _loading ? null : () { if (_validateLocation()) _saveAndNext(2); })),
        ]),
      ],
    );
  }

  // ── Step 4: Banking ────────────────────────────────────────────────────────

  Widget _buildBankingStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepBadge('Step 4 of 5'),
        const SizedBox(height: 8),
        const Text('Banking Details', style: _titleStyle),
        const SizedBox(height: 6),
        const Text('Required to receive your restaurant payouts securely.', style: _subStyle),
        const SizedBox(height: 24),

        // Security notice
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: const Row(children: [
            Icon(Icons.lock_rounded, size: 16, color: Color(0xFF16A34A)),
            SizedBox(width: 10),
            Expanded(child: Text('Your banking details are encrypted with 256-bit SSL and only used for secure payout processing.', style: TextStyle(fontSize: 12, color: Color(0xFF166534), height: 1.5))),
          ]),
        ),
        const SizedBox(height: 24),

        Row(children: [
          Expanded(child: _WebField(ctrl: _bankNameCtrl,   label: 'Bank name *',          icon: Icons.account_balance_outlined)),
          const SizedBox(width: 14),
          Expanded(child: _WebField(ctrl: _bankHolderCtrl, label: 'Account holder name *', icon: Icons.person_outline_rounded)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _WebField(ctrl: _bankAccountCtrl, label: 'Account number *',         icon: Icons.credit_card_outlined, inputType: TextInputType.number)),
          const SizedBox(width: 14),
          Expanded(child: _WebField(ctrl: _bankBranchCtrl,  label: 'Branch / routing (optional)', icon: Icons.location_city_outlined)),
        ]),
        const SizedBox(height: 20),

        _sectionLabel('Account Type'),
        const SizedBox(height: 10),
        Row(children: ['Checking', 'Savings', 'Business'].map((t) {
          final v = t.toLowerCase();
          final sel = _bankAccountType == v;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _CuisineChip(label: t, selected: sel, onTap: () => setState(() => _bankAccountType = v)),
          );
        }).toList()),
        const SizedBox(height: 32),

        Row(children: [
          Expanded(child: _SecondaryBtn(label: 'Back', onPressed: _loading ? null : () => ref.read(onboardingProvider(OnboardingRole.restaurant).notifier).setStep(1))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _PrimaryBtn(label: 'Review Application', loading: _loading, onPressed: _loading ? null : () { if (_validateBanking()) _saveAndNext(3); })),
        ]),
      ],
    );
  }

  // ── Step 5: Review & Submit ────────────────────────────────────────────────

  Widget _buildReviewStep() {
    final masked = _bankAccountCtrl.text.trim();
    final maskedDisplay = masked.length > 4 ? '••••${masked.substring(masked.length - 4)}' : masked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepBadge('Step 5 of 5 — Final Step'),
        const SizedBox(height: 8),
        const Text('Review & Submit', style: _titleStyle),
        const SizedBox(height: 6),
        const Text('Review your information before submitting your application.', style: _subStyle),
        const SizedBox(height: 28),

        _ReviewCard(title: 'Business Info', icon: Icons.storefront_outlined, rows: [
          ('Restaurant',  _businessNameCtrl.text.trim().orDash),
          ('Cuisine',     _selectedCuisine ?? '—'),
          if (_descriptionCtrl.text.trim().isNotEmpty) ('Description', _descriptionCtrl.text.trim()),
          ('Phone',       _businessPhoneCtrl.text.trim().orDash),
          if (_businessEmailCtrl.text.trim().isNotEmpty) ('Email', _businessEmailCtrl.text.trim()),
        ]),
        _ReviewCard(title: 'Location & Hours', icon: Icons.place_outlined, rows: [
          ('Address', _addressCtrl.text.trim().orDash),
          ('Hours',   '${_fmtTime(_openingTime)} – ${_fmtTime(_closingTime)}'),
          ('Type',    _storeType == 'both' ? 'Food & Grocery' : _storeType[0].toUpperCase() + _storeType.substring(1)),
        ]),
        _ReviewCard(title: 'Banking Details', icon: Icons.account_balance_outlined, rows: [
          ('Bank',    _bankNameCtrl.text.trim().orDash),
          ('Holder',  _bankHolderCtrl.text.trim().orDash),
          ('Account', maskedDisplay.isEmpty ? '—' : maskedDisplay),
          ('Type',    _bankAccountType[0].toUpperCase() + _bankAccountType.substring(1)),
        ]),

        const SizedBox(height: 8),

        // Terms
        GestureDetector(
          onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _agreedToTerms,
                onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                activeColor: _gold,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text.rich(TextSpan(
                    text: 'I confirm all information is accurate and I agree to the ',
                    style: const TextStyle(fontSize: 13, color: _slate, height: 1.5),
                    children: const [
                      TextSpan(text: 'Terms & Conditions', style: TextStyle(color: _gold, fontWeight: FontWeight.w700)),
                      TextSpan(text: ' and the '),
                      TextSpan(text: 'Restaurant Partner Agreement.', style: TextStyle(color: _gold, fontWeight: FontWeight.w700)),
                    ],
                  )),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Review timeline notice
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _gold.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.schedule_rounded, size: 16, color: _gold),
            const SizedBox(width: 10),
            Expanded(child: Text('Your application will be reviewed within 24–48 hours. You\'ll be notified once approved.', style: TextStyle(fontSize: 12, color: Colors.brown.shade700, height: 1.5))),
          ]),
        ),
        const SizedBox(height: 24),

        Row(children: [
          Expanded(child: _SecondaryBtn(label: 'Back', onPressed: _loading ? null : () => ref.read(onboardingProvider(OnboardingRole.restaurant).notifier).setStep(2))),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _SubmitBtn(
              loading: _loading,
              enabled: _agreedToTerms && !_loading,
              onPressed: () => _saveAndNext(7, submit: true),
            ),
          ),
        ]),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _stepBadge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: _gold.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _gold.withValues(alpha: 0.3)),
    ),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _gold)),
  );

  Widget _sectionLabel(String t) => Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _navyMid));

  Widget _divider(String text) => Row(children: [
    const Expanded(child: Divider(color: _border)),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(text, style: const TextStyle(fontSize: 12, color: _slate))),
    const Expanded(child: Divider(color: _border)),
  ]);

  Widget _centeredLink({required String prefix, required String label, required VoidCallback onTap}) =>
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(prefix, style: const TextStyle(color: _slate, fontSize: 13)),
        GestureDetector(onTap: onTap, child: Text(label, style: const TextStyle(color: _gold, fontWeight: FontWeight.w700, fontSize: 13))),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Left Panel
// ─────────────────────────────────────────────────────────────────────────────

class _LeftPanel extends StatelessWidget {
  final int stepIndex;
  final bool isAuthStep;
  final ({String heading, String sub, IconData icon, List<(IconData, String)> bullets}) config;

  const _LeftPanel({required this.stepIndex, required this.isAuthStep, required this.config});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 380,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A0F1A), _navy, _navyMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(36, 48, 36, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo
            Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_gold, _goldL]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bolt_rounded, color: _navy, size: 22),
              ),
              const SizedBox(width: 10),
              const Text('MealHub', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5)),
            ]),
            const SizedBox(height: 48),

            // Step icon
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _gold.withValues(alpha: 0.3)),
              ),
              child: Icon(config.icon, color: _gold, size: 30),
            ),
            const SizedBox(height: 20),

            // Heading
            Text(config.heading, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1.2, letterSpacing: -0.5)),
            const SizedBox(height: 12),
            Text(config.sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14, height: 1.6)),
            const SizedBox(height: 36),

            // Bullet list
            ...config.bullets.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(b.$1, color: _gold, size: 16),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(b.$2, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, height: 1.4)),
                  )),
                ],
              ),
            )),

            const SizedBox(height: 40),

            // Step progress
            if (!isAuthStep) _VerticalStepProgress(current: stepIndex),

            const SizedBox(height: 40),

            // Trust badges
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(children: [
                _trustRow(Icons.shield_rounded, 'Your data is secure & encrypted'),
                const SizedBox(height: 10),
                _trustRow(Icons.no_encryption_gmailerrorred_rounded, 'No credit card required to apply'),
                const SizedBox(height: 10),
                _trustRow(Icons.cancel_outlined, 'No long-term contracts'),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trustRow(IconData icon, String text) => Row(children: [
    Icon(icon, size: 14, color: _gold.withValues(alpha: 0.7)),
    const SizedBox(width: 10),
    Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Vertical step progress (shown in left panel after account step)
// ─────────────────────────────────────────────────────────────────────────────

class _VerticalStepProgress extends StatelessWidget {
  final int current;
  const _VerticalStepProgress({required this.current});

  static const _steps = ['Business Details', 'Location & Hours', 'Banking Details', 'Review & Submit'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your Progress', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        ..._steps.asMap().entries.map((e) {
          final idx = e.key;
          final done = idx < current;
          final active = idx == current;
          final isLast = idx == _steps.length - 1;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? _gold : active ? _gold.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
                    border: Border.all(
                      color: (done || active) ? _gold : Colors.white.withValues(alpha: 0.15),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: done
                        ? const Icon(Icons.check, size: 12, color: _navy)
                        : active
                            ? Container(width: 8, height: 8, decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle))
                            : null,
                  ),
                ),
                if (!isLast) Container(width: 1.5, height: 28, color: (done ? _gold : Colors.white.withValues(alpha: 0.1))),
              ]),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 28),
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: done ? _gold : active ? Colors.white : Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step dots (right panel top)
// ─────────────────────────────────────────────────────────────────────────────

class _StepDots extends StatelessWidget {
  final int current;
  final int total;
  const _StepDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(children: List.generate(total, (i) {
      final done = i < current;
      final active = i == current;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 4,
            decoration: BoxDecoration(
              color: done || active ? _gold : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared form widgets
// ─────────────────────────────────────────────────────────────────────────────

class _WebField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType? inputType;
  final int maxLines;
  final String? hint;
  const _WebField({required this.ctrl, required this.label, required this.icon, this.inputType, this.maxLines = 1, this.hint});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      keyboardType: inputType,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 14, color: _navy),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _slate, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: _slate),
        filled: true,
        fillColor: _surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _gold, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController ctrl;
  final bool obscure;
  final VoidCallback onToggle;
  const _PasswordField({required this.ctrl, required this.obscure, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(fontSize: 14, color: _navy),
      decoration: InputDecoration(
        labelText: 'Password',
        labelStyle: const TextStyle(color: _slate, fontSize: 13),
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: _slate),
        suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: _slate), onPressed: onToggle),
        filled: true,
        fillColor: _surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _gold, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _SocialButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 22, color: _navy),
      label: Text(label, style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 14)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: _border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: Colors.white,
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  const _PrimaryBtn({required this.label, required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: _navy,
          disabledBackgroundColor: const Color(0xFFD1D5DB),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: _navy))
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ),
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _SecondaryBtn({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: _slate,
          side: const BorderSide(color: _border, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    );
  }
}

class _SubmitBtn extends StatelessWidget {
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;
  const _SubmitBtn({required this.loading, required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFF97316)], begin: Alignment.centerLeft, end: Alignment.centerRight)
              : const LinearGradient(colors: [Color(0xFFD1D5DB), Color(0xFFD1D5DB)]),
          borderRadius: BorderRadius.circular(10),
          boxShadow: enabled ? [BoxShadow(color: _gold.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 6))] : [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: _navy))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.send_rounded, size: 16, color: _navy),
                      SizedBox(width: 8),
                      Text('Submit Application', style: TextStyle(color: _navy, fontWeight: FontWeight.w800, fontSize: 15)),
                    ]),
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
  const _CuisineChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _gold : _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _gold : _border),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? _navy : _slate)),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;
  const _TimeTile({required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
        child: Row(children: [
          const Icon(Icons.access_time_rounded, size: 16, color: _gold),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 10, color: _slate, fontWeight: FontWeight.w600)),
            Text(time,  style: const TextStyle(fontSize: 14, color: _navy,  fontWeight: FontWeight.w700)),
          ]),
          const Spacer(),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _slate),
        ]),
      ),
    );
  }
}

class _StoreTypeBtn extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _StoreTypeBtn({required this.value, required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _gold.withValues(alpha: 0.08) : _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _gold : _border, width: selected ? 2 : 1),
        ),
        child: Column(children: [
          Icon(icon, size: 20, color: selected ? _gold : _slate),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? _gold : _slate)),
        ]),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<(String, String)> rows;
  const _ReviewCard({required this.title, required this.icon, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: _gold),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _navy)),
        ]),
        const SizedBox(height: 12),
        ...rows.map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 90, child: Text(r.$1, style: const TextStyle(fontSize: 12, color: _slate))),
            Expanded(child: Text(r.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navy))),
          ]),
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

const _titleStyle = TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _navy, letterSpacing: -0.5, height: 1.2);
const _subStyle   = TextStyle(fontSize: 14, color: _slate, height: 1.6);

extension on String {
  String get orDash => trim().isEmpty ? '—' : trim();
}
