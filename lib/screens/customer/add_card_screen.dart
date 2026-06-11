// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/payment_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_logger.dart';
import '../../core/utils/responsive.dart';

class AddCardScreen extends ConsumerStatefulWidget {
  const AddCardScreen({super.key});

  @override
  ConsumerState<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends ConsumerState<AddCardScreen> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  bool _isSaving = false;
  bool _cardComplete = false;
  bool _stripeReady = false;
  CardFieldInputDetails? _cardDetails;

  // Live preview state
  String _previewName = 'YOUR NAME';
  String _previewNumber = '**** **** **** ****';
  String _previewExpiry = 'MM/YY';

  @override
  void initState() {
    super.initState();
    _firstNameCtrl.addListener(_updateNamePreview);
    _lastNameCtrl.addListener(_updateNamePreview);
    _initStripe();
  }

  Future<void> _initStripe() async {
    try {
      if (Stripe.publishableKey.isEmpty) {
        final key = AppConstants.stripePublishableKey;
        if (key.isNotEmpty) {
          Stripe.publishableKey = key;
          Stripe.merchantIdentifier = AppConstants.stripeMerchantId;
        }
      }
      Stripe.urlScheme = 'sevendash.app';
      await Stripe.instance.applySettings();
    } catch (e) {
      AppLogger.error('Stripe init error: $e');
    }
    if (mounted) setState(() => _stripeReady = true);
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  void _updateNamePreview() {
    setState(() {
      final first = _firstNameCtrl.text.trim();
      final last = _lastNameCtrl.text.trim();
      _previewName = (first.isEmpty && last.isEmpty)
          ? 'YOUR NAME'
          : '$first $last'.trim();
    });
  }

  void _onCardChanged(CardFieldInputDetails? details) {
    setState(() {
      _cardDetails = details;
      _cardComplete = details?.complete == true;
      if (details != null) {
        final last4 = details.last4;
        _previewNumber = (last4 != null && last4.isNotEmpty)
            ? '**** **** **** $last4'
            : '**** **** **** ****';
        final month = details.expiryMonth;
        final year = details.expiryYear;
        if (month != null && year != null) {
          _previewExpiry =
              '${month.toString().padLeft(2, '0')}/${year.toString().substring(2)}';
        } else {
          _previewExpiry = 'MM/YY';
        }
      } else {
        _previewNumber = '**** **** **** ****';
        _previewExpiry = 'MM/YY';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final hintColor = isDark ? Colors.grey.shade500 : Colors.grey.shade400;
    final enabled = _cardComplete && !_isSaving;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0D1117)
          : AppTheme.backgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Add New Card'),
        backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header + card preview ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                  fontSize: Responsive.headingMedium(context),
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
                    _buildCardPreview(isDark),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // ── Card form + Save button ────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111827) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                // Card form header row
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF635BFF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.credit_card_rounded,
                        color: Color(0xFF635BFF),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Card Details',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: textColor,
                            ),
                          ),
                          Text(
                            'Enter your card information below',
                            style: TextStyle(fontSize: 11.5, color: hintColor),
                          ),
                        ],
                      ),
                    ),
                    const _BrandChip('VISA', Color(0xFF1A1F71), Colors.white),
                    const SizedBox(width: 4),
                    const _BrandChip('MC', Color(0xFFEB001B), Colors.white),
                    const SizedBox(width: 4),
                    const _BrandChip('AMEX', Color(0xFF007DC5), Colors.white),
                  ],
                ),
                const SizedBox(height: 14),

                // Stripe CardFormField (custom embedded — no native sheet)
                // Only rendered after applySettings() completes to avoid
                // "stripeSdk has not been initialized" on Android.
                if (_stripeReady)
                  CardFormField(
                    onCardChanged: _onCardChanged,
                    enablePostalCode: false,
                    style: CardFormStyle(
                      backgroundColor:
                          isDark ? const Color(0xFF1F2937) : Colors.white,
                      textColor: isDark
                          ? Colors.white
                          : const Color(0xFF1A1A2E),
                      placeholderColor: isDark
                          ? const Color(0xFF6B7280)
                          : const Color(0xFFAAAAAA),
                      borderColor: isDark
                          ? const Color(0xFF374151)
                          : const Color(0xFFDDDDDD),
                      borderRadius: 12,
                      borderWidth: 1,
                      fontSize: 16,
                      cursorColor: const Color(0xFF635BFF),
                    ),
                  )
                else
                  const SizedBox(
                    height: 116,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                const SizedBox(height: 8),

                // Security note
                Row(
                  children: [
                    const Icon(
                      Icons.lock_rounded,
                      size: 12,
                      color: Color(0xFF10B981),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Secured by Stripe · A small verification charge will be refunded',
                        style: TextStyle(fontSize: 11, color: hintColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Save Card button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: enabled
                        ? const LinearGradient(
                            colors: [Color(0xFF635BFF), Color(0xFF4C47E5)],
                          )
                        : null,
                    color: enabled
                        ? null
                        : (isDark
                            ? const Color(0xFF374151)
                            : const Color(0xFFCDD5E0)),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: enabled
                        ? [
                            BoxShadow(
                              color: const Color(0xFF635BFF)
                                  .withValues(alpha: 0.3),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : [],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: enabled ? _addCardWithStripe : null,
                      borderRadius: BorderRadius.circular(14),
                      child: Center(
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.lock_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Save Card',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
    );
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
              fontSize: Responsive.headingMedium(context),
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
                      fontSize: Responsive.bodyText(context),
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
                      fontSize: Responsive.bodyText(context),
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

  String _detectCardBrand() {
    final brand = _cardDetails?.brand?.toLowerCase() ?? '';
    if (brand.contains('visa')) return 'visa';
    if (brand.contains('master')) return 'mastercard';
    if (brand.contains('amex') || brand.contains('american')) {
      return 'american_express';
    }
    if (brand.contains('discover')) return 'discover';
    return 'card';
  }

  // ── Stripe save card + verification flow ─────────────────────────────────────
  Future<void> _addCardWithStripe() async {
    if (_isSaving || !_cardComplete) return;
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

      // Confirm using the custom CardFormField data (no native Stripe sheet).
      // Billing details help satisfy SCA requirements for off-session use.
      await Stripe.instance.confirmSetupIntent(
        paymentIntentClientSecret: clientSecret,
        params: PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(
            billingDetails: BillingDetails(
              name: cardholderName.isNotEmpty ? cardholderName : name,
              email: email.isNotEmpty ? email : null,
              phone: phone.isNotEmpty ? phone : null,
            ),
          ),
        ),
      );

      if (!mounted) return;

      final verificationResult = await paymentService.completeVerificationCharge(
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
          _detectCardBrand();
      final lastFour =
          verificationResult['lastFour'] as String? ??
          verificationResult['last_four'] as String? ??
          (_cardDetails?.last4 ?? '****');
      final customerId =
          verificationResult['stripeCustomerId'] as String? ??
          verificationResult['customerId'] as String?;

      if (verificationId == null || verificationId.isEmpty) {
        throw Exception('Unable to verify card setup.');
      }

      final expiresAt =
          DateTime.now().toUtc().add(const Duration(minutes: 30));
      final savedCard = await paymentService.savePendingCard(
        userId: userId,
        cardBrand: cardBrand,
        lastFour: lastFour,
        cardholderName:
            cardholderName.isNotEmpty ? cardholderName : 'Unknown',
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
    } on StripeException catch (e) {
      AppLogger.error('Stripe add card error: ${e.error.localizedMessage}');
      if (mounted) {
        AppSnackbar.error(
          context,
          e.error.localizedMessage ?? 'Card verification failed. Please try again.',
        );
      }
    } catch (e) {
      AppLogger.error('Add card error: $e');
      if (mounted) {
        AppSnackbar.error(context, 'Add card failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _BrandChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _BrandChip(this.label, this.bg, this.fg);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        color: fg,
      ),
    ),
  );
}
