import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../../services/payout_service.dart'
    show StripePayoutService, DriverPayoutMethod;
import '../../providers/driver_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../config/app_constants.dart';

final _methodsProvider = FutureProvider.autoDispose<List<DriverPayoutMethod>>((
  ref,
) {
  return StripePayoutService.instance.getPayoutMethods();
});

class DriverPayoutMethodsScreen extends ConsumerStatefulWidget {
  const DriverPayoutMethodsScreen({super.key});
  @override
  ConsumerState<DriverPayoutMethodsScreen> createState() => _State();
}

class _State extends ConsumerState<DriverPayoutMethodsScreen> {
  static const _bg = Color(0xFF0F1117);
  static const _cardBg = Color(0xFF1C1F2E);
  static const _green = Color(0xFF00C896);

  bool _loading = false;
  String? _error;
  String? _success;

  // ── Add bank account ─────────────────────────────────────────────────

  Future<void> _addBank() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddBankSheet(),
    );
    if (result == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      await StripePayoutService.instance.addBankAccount(
        accountNumber: result['account']!,
        routingNumber: result['routing']!,
        accountHolderName: result['name']!,
      );
      ref.invalidate(_methodsProvider);
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) ref.invalidate(driverProfileProvider(userId));
      setState(
        () => _success =
            'Bank account added! Standard payouts (2–5 days) are now available.',
      );
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Add debit card ────────────────────────────────────────────────────

  Future<void> _addCard() async {
    final pubKey = AppConstants.stripePublishableKey;
    if (pubKey.isEmpty) {
      setState(() => _error = 'Stripe is not configured.');
      return;
    }
    Stripe.publishableKey = pubKey;
    await Stripe.instance.applySettings();
    if (!mounted) return;

    final tokenId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddCardSheet(),
    );
    if (tokenId == null || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      final r = await StripePayoutService.instance.addDebitCard(tokenId);
      final last4 = r['last4'] as String?;
      ref.invalidate(_methodsProvider);
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) ref.invalidate(driverProfileProvider(userId));
      setState(
        () => _success = last4 != null
            ? 'Debit card •••• $last4 added!'
            : 'Debit card added!',
      );
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final methodsAsync = ref.watch(_methodsProvider);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text(
          'Payout Methods',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_success != null)
              _Banner(
                message: _success!,
                color: _green,
                icon: Icons.check_circle,
              ),
            if (_error != null)
              _Banner(
                message: _error!,
                color: Colors.redAccent,
                icon: Icons.error_outline,
              ),

            const Text(
              'Current Methods',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            methodsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => _Banner(
                message: friendlyError(e),
                color: Colors.orange,
                icon: Icons.warning_amber,
              ),
              data: (methods) => methods.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.white38,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No payout methods yet. Add a bank account or debit card.',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: methods
                          .map((m) => _MethodTile(method: m))
                          .toList(),
                    ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Add New Method',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _AddMethodCard(
              title: 'Bank Account (ACH)',
              subtitle: 'Standard payouts · 2–5 business days · Free',
              icon: Icons.account_balance,
              loading: _loading,
              onTap: _addBank,
            ),
            const SizedBox(height: 10),
            _AddMethodCard(
              title: 'Debit Card',
              subtitle: 'Instant payouts · Arrives in minutes · 1% fee',
              icon: Icons.credit_card,
              loading: _loading,
              onTap: _addCard,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.security, color: Colors.white38, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Secure & Encrypted',
                        style: TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Your payment details are processed by Stripe and never stored on our servers.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final DriverPayoutMethod method;
  const _MethodTile({required this.method});
  static const _cardBg = Color(0xFF1C1F2E);
  static const _accent = Color(0xFF6C63FF);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _cardBg,
      borderRadius: BorderRadius.circular(12),
      border: method.isDefault
          ? Border.all(color: _accent.withValues(alpha: 0.4))
          : null,
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _accent.withValues(alpha: 0.15),
          ),
          child: Icon(
            method.isCard ? Icons.credit_card : Icons.account_balance,
            color: _accent,
            size: 20,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                method.isCard
                    ? '${method.brand ?? 'Card'} •••• ${method.last4}'
                    : '${method.bankName ?? 'Bank'} •••• ${method.last4}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                method.isCard
                    ? 'Debit · Instant payouts'
                    : 'Bank Account · Standard payouts',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
        if (method.isDefault)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Default',
              style: TextStyle(
                color: Color(0xFF6C63FF),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    ),
  );
}

class _AddMethodCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;
  const _AddMethodCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.loading,
    required this.onTap,
  });
  static const _cardBg = Color(0xFF1C1F2E);
  static const _accent = Color(0xFF6C63FF);

  @override
  Widget build(BuildContext context) => Material(
    color: _cardBg,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: loading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: _accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.add, color: Color(0xFF6C63FF), size: 22),
          ],
        ),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;
  const _Banner({
    required this.message,
    required this.color,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      border: Border.all(color: color.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: TextStyle(color: color, fontSize: 13)),
        ),
      ],
    ),
  );
}

// ── Add Bank Bottom Sheet ───────────────────────────────────────────────────

class _AddBankSheet extends StatefulWidget {
  const _AddBankSheet();
  @override
  State<_AddBankSheet> createState() => _AddBankSheetState();
}

class _AddBankSheetState extends State<_AddBankSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _routing = TextEditingController();
  final _account = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _routing.dispose();
    _account.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1F2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Add Bank Account',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'US bank accounts only (ACH).',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _BField(
              label: 'Account Holder Name',
              ctrl: _name,
              validator: (v) => v!.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            _BField(
              label: 'Routing Number (9 digits)',
              ctrl: _routing,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              validator: (v) => v!.length != 9 ? 'Must be 9 digits' : null,
            ),
            const SizedBox(height: 12),
            _BField(
              label: 'Account Number',
              ctrl: _account,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(17),
              ],
              validator: (v) =>
                  v!.length < 4 ? 'Enter valid account number' : null,
            ),
            const SizedBox(height: 12),
            _BField(
              label: 'Confirm Account Number',
              ctrl: _confirm,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(17),
              ],
              validator: (v) =>
                  v != _account.text ? 'Account numbers do not match' : null,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  if (_formKey.currentState!.validate())
                    Navigator.pop(context, {
                      'name': _name.text.trim(),
                      'routing': _routing.text.trim(),
                      'account': _account.text.trim(),
                    });
                },
                child: const Text(
                  'Add Bank Account',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  const _BField({
    required this.label,
    required this.ctrl,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: ctrl,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    validator: validator,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF0F1117),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF6C63FF)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    ),
  );
}

// ── Add Card Bottom Sheet ───────────────────────────────────────────────────

class _AddCardSheet extends StatefulWidget {
  const _AddCardSheet();
  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  bool _cardComplete = false, _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tokenData = await Stripe.instance.createToken(
        const CreateTokenParams.card(
          params: CardTokenParams(type: TokenType.Card),
        ),
      );
      if (tokenData.id.isEmpty)
        throw Exception('No token returned from Stripe.');
      if (mounted) Navigator.pop(context, tokenData.id);
    } catch (e) {
      setState(() {
        _error = e
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('StripeException: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1F2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Add Debit Card',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'Visa or Mastercard debit only. Used for instant payouts.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),
          CardField(
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              fillColor: Color(0xFF0F1117),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Color(0xFF2E3147)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Color(0xFF2E3147)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Color(0xFF6C63FF)),
              ),
            ),
            onCardChanged: (d) =>
                setState(() => _cardComplete = d?.complete == true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_cardComplete && !_loading) ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                disabledBackgroundColor: const Color(
                  0xFF6C63FF,
                ).withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save Card',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
