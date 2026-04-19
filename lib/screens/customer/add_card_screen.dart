import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/payment_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_logger.dart';

class AddCardScreen extends ConsumerStatefulWidget {
  const AddCardScreen({super.key});

  @override
  ConsumerState<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends ConsumerState<AddCardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _cardNumberCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  String _selectedCurrency = 'USD';
  bool _isSaving = false;

  // Live preview state
  String _previewName = 'YOUR NAME';
  String _previewNumber = '**** **** **** ****';
  String _previewExpiry = 'MM/YY';
  String _cardBrand = '';

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

      // Detect card brand
      if (digits.startsWith('4')) {
        _cardBrand = 'visa';
      } else if (digits.startsWith('5') || digits.startsWith('2')) {
        _cardBrand = 'mastercard';
      } else if (digits.startsWith('3')) {
        _cardBrand = 'keycard';
      } else {
        _cardBrand = '';
      }
    });
  }

  Future<void> _saveCard() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) throw Exception('Not signed in');

      final paymentService = ref.read(paymentServiceProvider);
      final authUser = Supabase.instance.client.auth.currentUser;
      final email = authUser?.email ?? '';
      final firstName = _firstNameCtrl.text.trim();
      final lastName = _lastNameCtrl.text.trim();
      final fullName = '$firstName $lastName'.trim();
      final digits = _cardNumberCtrl.text.replaceAll(RegExp(r'\D'), '');
      final lastFour = digits.length >= 4 ? digits.substring(digits.length - 4) : digits;

      // Step 1: Create a small verification charge via Stripe
      final response = await Supabase.instance.client.functions.invoke(
        AppConstants.stripePaymentFunction,
        body: {
          'action': 'create_verification_charge',
          'email': email,
          'name': fullName,
          'card_brand': _cardBrand,
          'last_four': lastFour,
          'cardholder_name': fullName,
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected response from server.');
      }
      if (data['error'] != null) {
        throw Exception(data['error']);
      }

      final clientSecret = data['clientSecret'] as String?;
      final paymentIntentId = data['paymentIntentId'] as String?;
      final customerId = data['customerId'] as String?;
      final ephemeralKey = data['ephemeralKey'] as String?;

      if (clientSecret == null || paymentIntentId == null) {
        throw Exception('Failed to create verification charge.');
      }

      if (!mounted) return;

      // Step 2: Present the Stripe Payment Sheet to pay the small charge
      if (Stripe.publishableKey.isEmpty) {
        final key = AppConstants.stripePublishableKey;
        if (key.isNotEmpty) {
          Stripe.publishableKey = key;
          Stripe.merchantIdentifier = AppConstants.stripeMerchantId;
          await Stripe.instance.applySettings();
        }
      }

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          customerId: customerId,
          customerEphemeralKeySecret: ephemeralKey,
          merchantDisplayName: AppConstants.appName,
          style: ThemeMode.system,
          billingDetails: BillingDetails(email: email, name: fullName),
        ),
      );

      await Stripe.instance.presentPaymentSheet();

      if (!mounted) return;

      // Step 3: Confirm the charge went through
      final confirmResp = await Supabase.instance.client.functions.invoke(
        AppConstants.stripePaymentFunction,
        body: {
          'action': 'confirm_verification_charge',
          'payment_intent_id': paymentIntentId,
        },
      );
      final confirmData = confirmResp.data as Map<String, dynamic>?;
      if (confirmData == null || confirmData['success'] != true) {
        throw Exception('Verification charge was not completed.');
      }

      // Step 4: Save card as 'pending' verification in DB
      final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 24));
      await paymentService.savePendingCard(
        userId: userId,
        cardBrand: _cardBrand.isNotEmpty ? _cardBrand : 'unknown',
        lastFour: lastFour,
        cardholderName: fullName,
        email: email,
        phone: '',
        verificationId: paymentIntentId,
        expiresAt: expiresAt,
      );

      if (!mounted) return;

      ref.invalidate(savedCardsProvider(userId));
      AppSnackbar.success(
        context,
        'A small charge was placed on your card. '
        'Check your bank statement and enter the exact amount '
        'in your Wallet to verify the card.',
      );
      Navigator.of(context).pop(true);
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        if (mounted) AppSnackbar.warning(context, 'Card setup was cancelled');
      } else {
        if (mounted) AppSnackbar.error(context, friendlyError(e));
      }
    } catch (e) {
      AppLogger.error('Add card error: $e');
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBorder = isDark
        ? const Color(0xFF374151)
        : const Color(0xFF9CA3AF);
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
        child: Form(
          key: _formKey,
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
              const SizedBox(height: 28),

              // Card Information header
              Text(
                'Card Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 16),

              // First Name / Last Name row
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _firstNameCtrl,
                      hint: 'First Name',
                      icon: Icons.person_outline,
                      isDark: isDark,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _lastNameCtrl,
                      hint: 'Last Name',
                      icon: Icons.person_outline,
                      isDark: isDark,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Card Number
              _buildField(
                controller: _cardNumberCtrl,
                hint: 'Card Number',
                icon: Icons.credit_card,
                isDark: isDark,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(16),
                  _CardNumberFormatter(),
                ],
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 13) return 'Enter a valid card number';
                  return null;
                },
                suffixIcon: _cardBrand.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(
                          Icons.account_balance_wallet_outlined,
                          color: AppTheme.successColor,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 14),

              // Expiry / CVV row
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _expiryCtrl,
                      hint: 'Expiry Date',
                      icon: Icons.calendar_today_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                        _ExpiryFormatter(),
                      ],
                      validator: (v) {
                        if (v == null || v.length < 5) return 'MM/YY';
                        final parts = v.split('/');
                        final month = int.tryParse(parts[0]) ?? 0;
                        if (month < 1 || month > 12) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _cvvCtrl,
                      hint: 'CVV',
                      icon: Icons.shield_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      validator: (v) {
                        if (v == null || v.length < 3) return 'Invalid CVV';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Currency selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: fieldBorder),
                  color: isDark ? const Color(0xFF1F2937) : Colors.white,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCurrency,
                    isExpanded: true,
                    dropdownColor: isDark
                        ? const Color(0xFF1F2937)
                        : Colors.white,
                    style: TextStyle(fontSize: 16, color: textColor),
                    hint: Text(
                      'Select Currency',
                      style: TextStyle(color: hintColor),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'KYD',
                        child: Text('KYD - Cayman Islands Dollar'),
                      ),
                      DropdownMenuItem(
                        value: 'USD',
                        child: Text('USD - US Dollar'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedCurrency = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Save Card button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveCard,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.white
                        : const Color(0xFF1F2937),
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? AppLoadingIndicator(
                          fullScreen: false,
                          color: isDark ? Colors.black : Colors.white,
                        )
                      : const Text(
                          'Save Card',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
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

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool obscureText = false,
    Widget? suffixIcon,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    final borderColor = isDark
        ? const Color(0xFF374151)
        : const Color(0xFF9CA3AF);
    final textColor = isDark ? Colors.white : Colors.black;
    final hintColor = isDark ? Colors.grey.shade500 : Colors.grey.shade400;

    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      textCapitalization: textCapitalization,
      style: TextStyle(fontSize: 16, color: textColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: hintColor),
        prefixIcon: Icon(icon, color: hintColor, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: isDark ? const Color(0xFF1F2937) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppTheme.successColor,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.errorColor),
        ),
      ),
    );
  }
}

/// Formats card number input as "1234 5678 9012 3456"
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Formats expiry input as "MM/YY"
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    String formatted = digits;
    if (digits.length >= 3) {
      formatted = '${digits.substring(0, 2)}/${digits.substring(2)}';
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
