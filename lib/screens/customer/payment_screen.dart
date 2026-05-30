// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_constants.dart';
import '../../providers/payment_provider.dart';
import '../../utils/app_logger.dart';
import '../../utils/friendly_error.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _kNavy = Color(0xFF004E89);
const _kBlue = Color(0xFF0077C8);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kBg = Color(0xFFF4F6F9);
const _kText = Color(0xFF1A1A2E);

enum _PayState { loading, ready, processing, success, failed }

// ─── Screen ───────────────────────────────────────────────────────────────────
class PaymentScreen extends ConsumerStatefulWidget {
  final String orderId;
  final double amount;
  final String currency;
  final String? customerEmail;
  final String? customerName;
  final String? restaurantName;
  final int? itemCount;
  final String type;
  /// If provided the screen skips the server createStripeCheckout call and
  /// uses this secret directly (e.g. subscription flow which already has one).
  final String? preloadedClientSecret;

  const PaymentScreen({
    super.key,
    required this.orderId,
    required this.amount,
    required this.currency,
    this.customerEmail,
    this.customerName,
    this.restaurantName,
    this.itemCount,
    this.type = 'order',
    this.preloadedClientSecret,
  });

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen>
    with TickerProviderStateMixin {
  _PayState _state = _PayState.loading;
  String? _clientSecret;
  String? _paymentIntentId;
  bool _cardComplete = false;
  String? _errorMessage;
  bool _tapping = false;

  late final AnimationController _checkCtrl;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _checkScale = CurvedAnimation(parent: _checkCtrl, curve: Curves.elasticOut);
    _initStripeAndCreateIntent();
  }

  @override
  void dispose() {
    _checkCtrl.dispose();
    super.dispose();
  }

  // ── Init ────────────────────────────────────────────────────────────────────

  /// Extracts the payment intent ID from a client secret
  /// (format: pi_xxxxx_secret_yyy → pi_xxxxx).
  String? _extractPaymentIntentId(String clientSecret) {
    final idx = clientSecret.indexOf('_secret_');
    return idx < 0 ? null : clientSecret.substring(0, idx);
  }

  Future<void> _initStripeAndCreateIntent() async {
    try {
      if (Stripe.publishableKey.isEmpty) {
        Stripe.publishableKey = AppConstants.stripePublishableKey;
        Stripe.merchantIdentifier = AppConstants.stripeMerchantId;
        await Stripe.instance.applySettings();
      }

      // Subscription (and similar) flows supply the client secret directly.
      if (widget.preloadedClientSecret != null) {
        if (!mounted) return;
        setState(() {
          _clientSecret = widget.preloadedClientSecret;
          _paymentIntentId =
              _extractPaymentIntentId(widget.preloadedClientSecret!);
          _state = _PayState.ready;
        });
        return;
      }

      final paymentService = ref.read(paymentServiceProvider);

      final alreadyPaid = await _checkAlreadyPaid();
      if (alreadyPaid) {
        _handleSuccess(skipServerConfirm: true);
        return;
      }

      final session = await paymentService.createStripeCheckout(
        orderId: widget.orderId,
        amount: widget.amount,
        customerEmail: widget.customerEmail ?? '',
        customerName: widget.customerName ?? '',
        type: widget.type,
      );

      if (!mounted) return;
      setState(() {
        _clientSecret = session.clientSecret;
        _paymentIntentId = session.paymentIntentId;
        _state = _PayState.ready;
      });
    } catch (e) {
      AppLogger.error('PaymentScreen init: $e');
      if (!mounted) return;
      setState(() {
        _state = _PayState.failed;
        _errorMessage = _sanitiseInitError(e.toString());
      });
    }
  }

  String _sanitiseInitError(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('api key') ||
        s.contains('pk_test') ||
        s.contains('pk_live') ||
        s.contains('sk_test') ||
        s.contains('sk_live')) {
      return 'Payment service is temporarily unavailable. Please try again later.';
    }
    if (s.contains('already paid')) return 'This order has already been paid.';
    if (s.contains('network') ||
        s.contains('timeout') ||
        s.contains('socket')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (s.contains('unauthorized') || s.contains('unauthenticated')) {
      return 'Session expired. Please log in again and retry.';
    }
    return 'Unable to start payment. Please try again.';
  }

  Future<bool> _checkAlreadyPaid() async {
    if (widget.preloadedClientSecret != null || widget.orderId.isEmpty) {
      return false;
    }
    try {
      final row = await Supabase.instance.client
          .from('orders')
          .select('payment_status')
          .eq('id', widget.orderId)
          .maybeSingle();
      return row?['payment_status'] == 'completed';
    } catch (_) {
      return false;
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _onPay() async {
    if (_tapping || _state != _PayState.ready || !_cardComplete) return;
    _tapping = true;
    setState(() => _state = _PayState.processing);

    try {
      await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: _clientSecret!,
        data: const PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );

      if (_paymentIntentId != null) {
        try {
          await ref
              .read(paymentServiceProvider)
              .confirmStripePayment(
                paymentIntentId: _paymentIntentId!,
                orderId: widget.orderId,
                type: widget.type,
              );
        } catch (e) {
          AppLogger.error('Server confirm (non-fatal): $e');
        }
      }

      _handleSuccess();
    } on StripeException catch (e) {
      _tapping = false;
      if (e.error.code == FailureCode.Canceled) {
        if (mounted) setState(() => _state = _PayState.ready);
        return;
      }
      if (mounted) {
        setState(() {
          _state = _PayState.failed;
          _errorMessage = _friendlyStripeError(e.error.localizedMessage ?? '');
        });
      }
    } catch (e) {
      _tapping = false;
      if (mounted) {
        setState(() {
          _state = _PayState.failed;
          _errorMessage = friendlyError(e);
        });
      }
    }
  }

  void _handleSuccess({bool skipServerConfirm = false}) {
    if (!mounted) return;
    setState(() => _state = _PayState.success);
    _checkCtrl.forward();
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) Navigator.of(context).pop({'status': 'paid', 'payment_intent_id': _paymentIntentId});
    });
  }

  Future<void> _onRetry() async {
    setState(() {
      _state = _PayState.loading;
      _clientSecret = null;
      _paymentIntentId = null;
      _errorMessage = null;
      _cardComplete = false;
    });
    _tapping = false;
    await _initStripeAndCreateIntent();
  }

  String _friendlyStripeError(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('declined') || s.contains('card_declined'))
      return 'Your card was declined. Please try a different card.';
    if (s.contains('expired') || s.contains('exp'))
      return 'Your card has expired. Please try a different card.';
    if (s.contains('cvc') || s.contains('security code'))
      return 'Incorrect security code. Please check and try again.';
    if (s.contains('funds') || s.contains('insufficient'))
      return 'Insufficient funds. Please try a different card.';
    if (s.contains('authentication') || s.contains('3d secure'))
      return 'Card authentication failed. Please try again.';
    if (s.contains('network') || s.contains('timeout'))
      return 'Network error. Please check your connection.';
    if (s.contains('blocked') || s.contains('fraudulent'))
      return 'This transaction was blocked. Please contact your bank.';
    if (s.isEmpty) return 'Payment failed. Please try again.';
    return raw;
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: _buildAppBar(),
      resizeToAvoidBottomInset: false,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _buildBody(),
      ),
    );
  }

  AppBar _buildAppBar() {
    final canPop = _state == _PayState.ready || _state == _PayState.failed;
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: canPop
          ? IconButton(
              icon: const Icon(Icons.close_rounded, color: _kText),
              onPressed: () => Navigator.of(context).pop(null),
            )
          : const SizedBox.shrink(),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Secure Checkout',
            style: TextStyle(
              color: _kText,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              letterSpacing: -0.3,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 10, color: _kGreen),
              const SizedBox(width: 3),
              Text(
                'SSL Encrypted',
                style: TextStyle(
                  color: _kGreen,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(color: Colors.grey.shade100, height: 1),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _PayState.loading:
        return const _LoadingView(key: ValueKey('loading'));
      case _PayState.ready:
      case _PayState.processing:
        return _CardFormView(
          key: const ValueKey('form'),
          amount: widget.amount,
          restaurantName: widget.restaurantName,
          itemCount: widget.itemCount,
          processing: _state == _PayState.processing,
          cardComplete: _cardComplete,
          onCompletionChanged: (complete) =>
              setState(() => _cardComplete = complete),
          onPay: _onPay,
        );
      case _PayState.success:
        return _SuccessView(
          key: const ValueKey('success'),
          amount: widget.amount,
          scaleAnim: _checkScale,
        );
      case _PayState.failed:
        return _FailedView(
          key: const ValueKey('failed'),
          errorMessage: _errorMessage ?? 'Payment failed. Please try again.',
          onRetry: _onRetry,
          onCancel: () => Navigator.of(context).pop(null),
        );
    }
  }
}

// ─── Loading view ─────────────────────────────────────────────────────────────

class _LoadingView extends StatefulWidget {
  const _LoadingView({super.key});

  @override
  State<_LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<_LoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) =>
                  Opacity(opacity: 0.4 + _pulse.value * 0.6, child: child),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _kNavy.withAlpha(15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_rounded, color: _kNavy, size: 36),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Setting up secure payment',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: _kText,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Please wait…',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.grey.shade200,
                  color: _kNavy,
                  minHeight: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Card form view ───────────────────────────────────────────────────────────

class _CardFormView extends StatefulWidget {
  final double amount;
  final String? restaurantName;
  final int? itemCount;
  final bool processing;
  final bool cardComplete;
  final void Function(bool complete) onCompletionChanged;
  final VoidCallback onPay;

  const _CardFormView({
    super.key,
    required this.amount,
    this.restaurantName,
    this.itemCount,
    required this.processing,
    required this.cardComplete,
    required this.onCompletionChanged,
    required this.onPay,
  });

  @override
  State<_CardFormView> createState() => _CardFormViewState();
}

class _CardFormViewState extends State<_CardFormView> {
  @override
  Widget build(BuildContext context) {
    final sym = AppConstants.currencySymbol;
    final amtStr = '$sym${widget.amount.toStringAsFixed(2)}';
    final enabled = widget.cardComplete && !widget.processing;
    // viewInsets.bottom = keyboard height; padding.bottom = system nav bar.
    // Both must be added since resizeToAvoidBottomInset is false.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final navBarHeight = MediaQuery.of(context).padding.bottom;

    return Column(
      children: [
        // ── Scrollable receipt area ─────────────────────────────────────────
        // Only the order summary scrolls. The card form is always visible.
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: _ReceiptCard(
              amount: widget.amount,
              sym: sym,
              restaurantName: widget.restaurantName,
              itemCount: widget.itemCount,
            ),
          ),
        ),

        // ── Sticky card form + pay button ───────────────────────────────────
        // AnimatedContainer slides up smoothly when the keyboard opens so the
        // card number field and pay button are never hidden behind the keyboard.
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset + navBarHeight),
          decoration: BoxDecoration(
            color: _kBg,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(14),
                blurRadius: 18,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Card details ─────────────────────────────────────────────
              _WhiteCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _kNavy.withAlpha(15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.credit_card_rounded,
                            color: _kNavy,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Card Details',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: _kText,
                                ),
                              ),
                              Text(
                                'Enter your card information below',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // CardFormField — card number row 1, MM/YY + CVV row 2.
                    CardFormField(
                      onCardChanged: (details) =>
                          widget.onCompletionChanged(details?.complete == true),
                      enablePostalCode: false,
                      style: CardFormStyle(
                        backgroundColor: Colors.white,
                        textColor: _kText,
                        placeholderColor: const Color(0xFFAAAAAA),
                        borderColor: const Color(0xFFDDDDDD),
                        borderRadius: 12,
                        borderWidth: 1,
                        fontSize: 16,
                        cursorColor: _kNavy,
                      ),
                    ),

                    Row(
                      children: [
                        const Icon(
                          Icons.verified_user_rounded,
                          size: 13,
                          color: _kGreen,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Secured by Stripe encryption',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Wrap(
                      spacing: 6,
                      children: [
                        _BrandChip('VISA', Color(0xFF1A1F71), Colors.white),
                        _BrandChip('MC', Color(0xFFEB001B), Colors.white),
                        _BrandChip('AMEX', Color(0xFF007DC5), Colors.white),
                        _BrandChip('DISC', Color(0xFFFF6000), Colors.white),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Pay button ───────────────────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 58,
                decoration: BoxDecoration(
                  gradient: enabled
                      ? const LinearGradient(colors: [_kNavy, _kBlue])
                      : null,
                  color: enabled ? null : const Color(0xFFCDD5E0),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: enabled
                      ? [
                          BoxShadow(
                            color: _kNavy.withAlpha(90),
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
                    onTap: enabled ? widget.onPay : null,
                    borderRadius: BorderRadius.circular(14),
                    child: Center(
                      child: widget.processing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.lock_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Pay $amtStr',
                                  style: const TextStyle(
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

              const SizedBox(height: 8),

              Center(
                child: Text(
                  'By paying you agree to our Terms & Privacy Policy',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Gradient receipt card ────────────────────────────────────────────────────

class _ReceiptCard extends StatelessWidget {
  final double amount;
  final String sym;
  final String? restaurantName;
  final int? itemCount;

  const _ReceiptCard({
    required this.amount,
    required this.sym,
    this.restaurantName,
    this.itemCount,
  });

  @override
  Widget build(BuildContext context) {
    final name = restaurantName ?? AppConstants.appName;
    final cnt = itemCount ?? 0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _kNavy.withAlpha(55),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Gradient header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kNavy, _kBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$cnt item${cnt == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$sym${amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 28,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // White footer strip
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_rounded,
                    size: 14,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Order Summary',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      'Pending Payment',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF856404),
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
}

// ─── Success view ─────────────────────────────────────────────────────────────

class _SuccessView extends StatefulWidget {
  final double amount;
  final Animation<double> scaleAnim;

  const _SuccessView({
    super.key,
    required this.amount,
    required this.scaleAnim,
  });

  @override
  State<_SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends State<_SuccessView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringCtrl;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    super.dispose();
  }

  Widget _ring(double offset) {
    return AnimatedBuilder(
      animation: _ringCtrl,
      builder: (_, __) {
        final p = ((_ringCtrl.value - offset + 1.0) % 1.0);
        final scale = 0.55 + p * 0.75;
        final opacity = ((1.0 - p) * 0.55).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _kGreen, width: 2),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sym = AppConstants.currencySymbol;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ripple rings + checkmark
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _ring(0.0),
                  _ring(0.33),
                  _ring(0.66),
                  ScaleTransition(
                    scale: widget.scaleAnim,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: _kGreen,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _kGreen.withAlpha(100),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 52,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            const Text(
              'Payment Successful!',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: _kText,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$sym${widget.amount.toStringAsFixed(2)} charged to your card',
              style: const TextStyle(
                fontSize: 15,
                color: _kGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your order is being prepared',
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              'Redirecting you now…',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Failed view ──────────────────────────────────────────────────────────────

class _FailedView extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const _FailedView({
    super.key,
    required this.errorMessage,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: _kRed.withAlpha(15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.credit_card_off_rounded,
                color: _kRed,
                size: 44,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Payment Failed',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: _kText,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your order was not placed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _kRed,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kRed.withAlpha(10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kRed.withAlpha(40)),
              ),
              child: Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.grey.shade700,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 28),
            // Gradient retry button
            Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_kNavy, _kBlue]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _kNavy.withAlpha(90),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: onRetry,
                  borderRadius: BorderRadius.circular(14),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Try Again',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onCancel,
              child: Text(
                'Go back',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _WhiteCard extends StatelessWidget {
  final Widget child;
  const _WhiteCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha(8),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );
}

class _BrandChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _BrandChip(this.label, this.bg, this.fg);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        color: fg,
      ),
    ),
  );
}
