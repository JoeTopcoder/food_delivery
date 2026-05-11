import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/payment_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_logger.dart';

class AddCardScreen extends ConsumerStatefulWidget {
  const AddCardScreen({super.key});

  @override
  ConsumerState<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends ConsumerState<AddCardScreen> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _cardNumberCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  bool _isSaving = false;

  // Live preview state
  String _previewName = 'YOUR NAME';
  String _previewNumber = '**** **** **** ****';
  String _previewExpiry = 'MM/YY';

  @override
  void initState() {
    super.initState();
    _firstNameCtrl.addListener(_updatePreview);
    _lastNameCtrl.addListener(_updatePreview);
    _cardNumberCtrl.addListener(_updatePreview);
    _expiryCtrl.addListener(_updatePreview);
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _cardNumberCtrl.dispose();
    _expiryCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  void _updatePreview() {
    setState(() {
      final first = _firstNameCtrl.text.trim();
      final last = _lastNameCtrl.text.trim();
      _previewName = (first.isEmpty && last.isEmpty)
          ? 'YOUR NAME'
          : '$first $last'.trim();

      final digits = _cardNumberCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) {
        _previewNumber = '**** **** **** ****';
      } else {
        final padded = digits.padRight(16, '*');
        _previewNumber =
            '${padded.substring(0, 4)} ${padded.substring(4, 8)} '
            '${padded.substring(8, 12)} ${padded.substring(12, 16)}';
      }

      _previewExpiry = _expiryCtrl.text.isEmpty ? 'MM/YY' : _expiryCtrl.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final hintColor = isDark ? Colors.grey.shade500 : Colors.grey.shade400;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0D1117)
          : AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Add New Card'),
        backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.credit_card, color: hintColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Payment Method',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      Text(
                        'Securely add your credit or debit card',
                        style: TextStyle(fontSize: 13, color: hintColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Card Preview
            _buildCardPreview(isDark),
            const SizedBox(height: 16),

            // ── Add card via Stripe ──────────────────────────
            _StripeAddCardButton(
              isLoading: _isSaving,
              onTap: _addCardWithStripe,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1F2937)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 18, color: hintColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Card details are entered securely via Stripe. '
                      'Your card is tokenized for secure future payments. '
                      'A small verification charge will be made and refunded after verification.',
                      style: TextStyle(fontSize: 12, color: hintColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _detectCardBrand(String cardNumber) {
    final digits = cardNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('4')) {
      return 'visa';
    }
    if (RegExp(r'^(5[1-5]|2(2[2-9]|[3-6]\d|7[0-1]|720))').hasMatch(digits)) {
      return 'mastercard';
    }
    if (digits.startsWith('34') || digits.startsWith('37')) {
      return 'american_express';
    }
    if (digits.startsWith('6') ||
        digits.startsWith('6011') ||
        digits.startsWith('65')) {
      return 'discover';
    }
    return 'card';
  }

  Widget _buildCardPreview(bool isDark) {
    return Container(
      width: double.infinity,
      height: 200,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF374151), const Color(0xFF1F2937)]
              : [const Color(0xFFE5E7EB), const Color(0xFFF9FAFB)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: wallet icon + card chip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: isDark ? Colors.white70 : Colors.black54,
                size: 28,
              ),
              Icon(
                Icons.credit_card,
                color: isDark ? Colors.white70 : Colors.black54,
                size: 24,
              ),
            ],
          ),
          const Spacer(),
          // Card number
          Text(
            _previewNumber,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          // Bottom row: name + expiry
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CARD HOLDER',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white54 : Colors.black45,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _previewName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'EXPIRES',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white54 : Colors.black45,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _previewExpiry,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Stripe "save card" + verification flow ───────────────────────────
  Future<void> _addCardWithStripe() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) throw Exception('Not signed in');

      final authUser = Supabase.instance.client.auth.currentUser;
      final email = authUser?.email ?? '';
      final name = authUser?.userMetadata?['name'] as String? ?? 'Customer';
      final cardholderName =
          ('${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'
              .trim()
              .isNotEmpty
          ? '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim()
          : name);
      final phone = authUser?.phone ?? '';

      if (!mounted) return;

      final paymentService = ref.read(paymentServiceProvider);
      final verificationSetup = await paymentService.createVerificationCharge(
        customerEmail: email,
        customerName: name,
        cardholderName: cardholderName.isNotEmpty ? cardholderName : null,
        phone: phone.isNotEmpty ? phone : null,
      );

      if (!mounted) return;

      final clientSecret =
          verificationSetup['clientSecret'] as String? ??
          verificationSetup['client_secret'] as String?;
      final setupIntentId =
          verificationSetup['setupIntentId'] as String? ??
          verificationSetup['setup_intent_id'] as String?;

      if (clientSecret == null ||
          clientSecret.isEmpty ||
          setupIntentId == null) {
        throw Exception('Unable to start card verification flow.');
      }

      final success = await paymentService.presentSetupSheet(
        clientSecret: clientSecret,
        customerName: name,
        customerEmail: email,
      );

      if (!mounted) return;

      if (!success) {
        AppSnackbar.warning(context, 'Card verification was cancelled');
        return;
      }

      final verificationResult = await paymentService
          .completeVerificationCharge(
            setupIntentId: setupIntentId,
            cardholderName: cardholderName.isNotEmpty ? cardholderName : null,
            email: email.isNotEmpty ? email : null,
            phone: phone.isNotEmpty ? phone : null,
          );

      if (!mounted) return;

      final verificationId =
          verificationResult['verificationId'] as String? ??
          verificationResult['verification_id'] as String?;
      final paymentMethodId =
          verificationResult['paymentMethodId'] as String? ??
          verificationResult['payment_method_id'] as String?;
      final cardBrand =
          verificationResult['cardBrand'] as String? ??
          verificationResult['card_brand'] as String? ??
          _detectCardBrand(_cardNumberCtrl.text);
      final lastFour =
          verificationResult['lastFour'] as String? ??
          verificationResult['last_four'] as String? ??
          _cardNumberCtrl.text
              .replaceAll(RegExp(r'\D'), '')
              .padRight(4, '*')
              .substring(0, 4);
      final customerId =
          verificationResult['stripeCustomerId'] as String? ??
          verificationResult['customerId'] as String?;

      if (verificationId == null || verificationId.isEmpty) {
        throw Exception('Unable to verify card setup.');
      }

      final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 30));
      final savedCard = await paymentService.savePendingCard(
        userId: userId,
        cardBrand: cardBrand,
        lastFour: lastFour,
        cardholderName: cardholderName.isNotEmpty ? cardholderName : 'Unknown',
        email: email,
        phone: phone,
        verificationId: verificationId,
        expiresAt: expiresAt,
        stripePaymentMethodId: paymentMethodId,
        stripeCustomerId: customerId,
      );

      if (!mounted) return;

      if (savedCard == null) {
        throw Exception('Failed to save pending card data.');
      }

      ref.invalidate(savedCardsProvider(userId));
      AppSnackbar.success(
        context,
        'Card added. Enter the small verification amount in your wallet to complete setup.',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      AppLogger.error('Stripe add card error: $e');
      if (mounted) {
        AppSnackbar.error(context, 'Add card failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

/// Stripe "Save card" tappable button.
class _StripeAddCardButton extends StatelessWidget {
  const _StripeAddCardButton({required this.isLoading, required this.onTap});

  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF635BFF), Color(0xFF4C47E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF635BFF).withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.credit_card,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add card with Stripe',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Fast and secure card tokenization',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              else
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 14,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
