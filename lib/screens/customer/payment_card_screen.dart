import 'package:flutter/material.dart';
import 'package:flutter_credit_card/flutter_credit_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/payment_provider.dart';
import '../../utils/app_logger.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import 'payment_screen.dart';

class PaymentCardScreen extends ConsumerStatefulWidget {
  final String? orderId; // null for add-card mode
  final double amount;
  final bool isAddCardMode;

  const PaymentCardScreen({
    super.key,
    this.orderId,
    required this.amount,
    this.isAddCardMode = false,
  });

  @override
  ConsumerState<PaymentCardScreen> createState() => _PaymentCardScreenState();
}

class _PaymentCardScreenState extends ConsumerState<PaymentCardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cardHolderKey = GlobalKey<FormFieldState<String>>();
  final _cardNumberKey = GlobalKey<FormFieldState<String>>();
  final _expiryDateKey = GlobalKey<FormFieldState<String>>();
  final _cvvKey = GlobalKey<FormFieldState<String>>();
  final _cvvFocusNode = FocusNode();
  final _cvvController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cardHolderController = TextEditingController();

  String cardNumber = '';
  String expiryDate = '';
  String cardHolderName = '';
  String cvvCode = '';
  bool isCvvFocused = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _cvvFocusNode.addListener(() {
      setState(() {
        isCvvFocused = _cvvFocusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _cvvFocusNode.dispose();
    _cvvController.dispose();
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cardHolderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAddCardMode ? 'Add Card' : 'Pay with Card'),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Credit card visual display ──────────────────────────────
            CreditCardWidget(
              cardNumber: cardNumber,
              expiryDate: expiryDate,
              cardHolderName: cardHolderName,
              cvvCode: cvvCode,
              cardBgColor: const Color(0xFF7C3AED),
              showBackView: isCvvFocused,
              obscureCardNumber: true,
              onCreditCardWidgetChange: (CreditCardBrand brand) {},
              isHolderNameVisible: true,
            ),
            const SizedBox(height: 20),

            // ── Card Input Form ─────────────────────────────────────────
            Form(
              key: _formKey,
              child: Column(
                children: [
                  // Cardholder Name
                  FormField<String>(
                    key: _cardHolderKey,
                    builder: (state) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _cardHolderController,
                            decoration: InputDecoration(
                              labelText: 'Cardholder Name',
                              hintText: 'Name on card',
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              errorText: state.errorText,
                            ),
                            onChanged: (value) {
                              setState(() => cardHolderName = value);
                              state.didChange(value);
                            },
                          ),
                        ],
                      );
                    },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Cardholder name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Card Number
                  FormField<String>(
                    key: _cardNumberKey,
                    builder: (state) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _cardNumberController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Card Number',
                              hintText: 'XXXX XXXX XXXX XXXX',
                              prefixIcon: const Icon(Icons.credit_card),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              errorText: state.errorText,
                            ),
                            onChanged: (value) {
                              String cleaned = value.replaceAll(
                                RegExp(r'\D'),
                                '',
                              );
                              if (cleaned.length > 19)
                                cleaned = cleaned.substring(0, 19);

                              String formatted = '';
                              for (int i = 0; i < cleaned.length; i++) {
                                if (i > 0 && i % 4 == 0) formatted += ' ';
                                formatted += cleaned[i];
                              }

                              if (formatted != _cardNumberController.text) {
                                _cardNumberController.text = formatted;
                                _cardNumberController
                                    .selection = TextSelection.fromPosition(
                                  TextPosition(
                                    offset: _cardNumberController.text.length,
                                  ),
                                );
                              }

                              setState(() => cardNumber = formatted);
                              state.didChange(formatted);
                            },
                          ),
                        ],
                      );
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Card number is required';
                      }
                      final cleaned = value.replaceAll(' ', '');
                      if (cleaned.length < 13 || cleaned.length > 19) {
                        return 'Invalid card number';
                      }
                      if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
                        return 'Card number must be digits only';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Expiry Date & CVV
                  Row(
                    children: [
                      Expanded(
                        child: FormField<String>(
                          key: _expiryDateKey,
                          builder: (state) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: _expiryController,
                                  keyboardType: TextInputType.datetime,
                                  decoration: InputDecoration(
                                    labelText: 'MM/YY',
                                    hintText: 'MM/YY',
                                    prefixIcon: const Icon(Icons.event),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    errorText: state.errorText,
                                  ),
                                  onChanged: (value) {
                                    String cleaned = value.replaceAll(
                                      RegExp(r'\D'),
                                      '',
                                    );
                                    if (cleaned.length > 4)
                                      cleaned = cleaned.substring(0, 4);

                                    String formatted = '';
                                    if (cleaned.length >= 2) {
                                      int month = int.parse(
                                        cleaned.substring(0, 2),
                                      );
                                      if (month > 12) month = 12;
                                      formatted = month.toString().padLeft(
                                        2,
                                        '0',
                                      );
                                      if (cleaned.length > 2) {
                                        formatted += '/${cleaned.substring(2)}';
                                      }
                                    } else {
                                      formatted = cleaned;
                                    }

                                    if (formatted != _expiryController.text) {
                                      _expiryController.text = formatted;
                                      _expiryController.selection =
                                          TextSelection.fromPosition(
                                            TextPosition(
                                              offset:
                                                  _expiryController.text.length,
                                            ),
                                          );
                                    }

                                    setState(() => expiryDate = formatted);
                                    state.didChange(formatted);
                                  },
                                ),
                              ],
                            );
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Required';
                            }
                            if (!RegExp(
                              r'^(0[1-9]|1[0-2])\/([0-9]{2})$',
                            ).hasMatch(value)) {
                              return 'Invalid (MM/YY)';
                            }
                            final parts = value.split('/');
                            final month = int.parse(parts[0]);
                            final year = int.parse('20${parts[1]}');
                            final now = DateTime.now();
                            if (year < now.year ||
                                (year == now.year && month < now.month)) {
                              return 'Card expired';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FormField<String>(
                          key: _cvvKey,
                          builder: (state) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: _cvvController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'CVV',
                                    hintText: 'XXX',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    errorText: state.errorText,
                                  ),
                                  focusNode: _cvvFocusNode,
                                  onChanged: (value) {
                                    String cleaned = value.replaceAll(
                                      RegExp(r'\D'),
                                      '',
                                    );
                                    if (cleaned.length > 4)
                                      cleaned = cleaned.substring(0, 4);

                                    if (cleaned != _cvvController.text) {
                                      _cvvController.text = cleaned;
                                      _cvvController.selection =
                                          TextSelection.fromPosition(
                                            TextPosition(
                                              offset:
                                                  _cvvController.text.length,
                                            ),
                                          );
                                    }

                                    setState(() => cvvCode = cleaned);
                                    state.didChange(cleaned);
                                  },
                                ),
                              ],
                            );
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Required';
                            }
                            if (!RegExp(r'^\d{3,4}$').hasMatch(value)) {
                              return '3-4 digits';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Amount display
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Total Amount',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$${widget.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF7C3AED),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _loading ? null : _submitPayment,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Pay \$${widget.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
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
    );
  }

  Future<void> _submitPayment() async {
    // Validate all fields
    final cardHolderField = _cardHolderKey.currentState;
    final cardNumberField = _cardNumberKey.currentState;
    final expiryDateField = _expiryDateKey.currentState;
    final cvvField = _cvvKey.currentState;

    bool isValid = true;
    if (cardHolderField == null || !cardHolderField.validate()) isValid = false;
    if (cardNumberField == null || !cardNumberField.validate()) isValid = false;
    if (expiryDateField == null || !expiryDateField.validate()) isValid = false;
    if (cvvField == null || !cvvField.validate()) isValid = false;

    if (!isValid) return;

    setState(() => _loading = true);

    try {
      // Parse expiry date
      final parts = expiryDate.split('/');
      if (parts.length != 2) throw Exception('Invalid expiry date');
      final month = parts[0].trim();
      final year = parts[1].trim();

      // Get clean card number (remove spaces)
      final cleanCardNumber = cardNumber.replaceAll(' ', '');

      // Handle add-card mode vs payment mode
      if (widget.isAddCardMode) {
        await _addCard(
          cardNumber: cleanCardNumber,
          expiryMonth: month,
          expiryYear: year,
          cvv: cvvCode,
          cardholderName: cardHolderName,
        );
      } else {
        // Payment mode - requires orderId
        final orderId = widget.orderId;
        if (orderId == null || orderId.isEmpty) {
          throw Exception('Order ID is required for payment');
        }

        AppLogger.info(
          'Processing Stripe payment: order=$orderId, amount=\$${widget.amount.toStringAsFixed(2)}',
        );

        final authUser = Supabase.instance.client.auth.currentUser;
        final email = authUser?.email ?? '';

        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentScreen(
              orderId: orderId,
              amount: widget.amount,
              currency: AppConstants.currencyCode,
              customerEmail: email,
              customerName: cardHolderName,
            ),
          ),
        );

        if (!mounted) return;

        if (result != null && result['status'] == 'paid') {
          AppLogger.info('Stripe payment successful');
          Navigator.of(context).pop({'success': true, 'result': result});
        } else {
          AppLogger.info('Stripe payment cancelled or failed');
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment was cancelled')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  /// Add card to user's wallet via Stripe SetupIntent
  Future<void> _addCard({
    required String cardNumber,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
    required String cardholderName,
  }) async {
    try {
      AppLogger.info('Adding card to wallet via Stripe...');

      // Get current user email for Stripe customer
      final authState = ref.read(authProvider);
      final userEmail = authState.user?.email ?? '';

      // Create Stripe SetupIntent
      final setupIntent = await ref
          .read(paymentServiceProvider)
          .createSetupIntent(customerEmail: userEmail);

      if (!mounted) return;

      final clientSecret = setupIntent['clientSecret'] as String?;
      if (clientSecret == null) {
        throw Exception('Failed to create setup intent');
      }

      // Present Stripe setup sheet to save the card
      final success = await ref
          .read(paymentServiceProvider)
          .presentSetupSheet(
            clientSecret: clientSecret,
            customerName: cardholderName,
            customerEmail: userEmail,
          );

      if (!mounted) return;

      if (success) {
        AppLogger.info('Card added successfully to wallet');
        // Invalidate saved cards to refresh the list
        final userId = ref.read(currentUserIdProvider);
        if (userId != null) {
          ref.invalidate(savedCardsProvider(userId));
        }
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Card added successfully!')),
          );
          Navigator.of(context).pop({'success': true});
        }
      } else {
        AppLogger.info('Card addition cancelled');
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Card addition was cancelled')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }
}
