import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../models/order_model.dart';
import '../../models/saved_card_model.dart';
import '../../utils/app_logger.dart';

/// Payment method enum
enum PaymentMethod { card, cash }

/// Result from creating a Stripe PaymentIntent via the edge function
class StripePaymentSession {
  final String orderId;
  final String paymentIntentId;
  final String clientSecret;
  final double amount;
  final String currency;
  final String? customerId;
  final String? ephemeralKey;

  const StripePaymentSession({
    required this.orderId,
    required this.paymentIntentId,
    required this.clientSecret,
    required this.amount,
    required this.currency,
    this.customerId,
    this.ephemeralKey,
  });
}

/// Payment response model
class PaymentResponse {
  final bool success;
  final String transactionId;
  final String status; // pending, processing, completed, failed
  final double amount;
  final String paymentMethod;
  final String? errorMessage;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  PaymentResponse({
    required this.success,
    required this.transactionId,
    required this.status,
    required this.amount,
    required this.paymentMethod,
    this.errorMessage,
    required this.timestamp,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    'transactionId': transactionId,
    'status': status,
    'amount': amount,
    'paymentMethod': paymentMethod,
    'errorMessage': errorMessage,
    'timestamp': timestamp.toIso8601String(),
    'metadata': metadata,
  };
}

/// Handles payment processing via Stripe
class PaymentService {
  final SupabaseClient _supabaseClient;

  PaymentService({required SupabaseClient supabaseClient})
    : _supabaseClient = supabaseClient;

  Future<Map<String, String>> _buildFunctionHeaders() async {
    try {
      await _supabaseClient.auth.refreshSession();
    } catch (_) {
      // Ignore refresh errors; use existing session if available.
    }

    final session = _supabaseClient.auth.currentSession;
    if (session?.accessToken != null && session!.accessToken.isNotEmpty) {
      return {'Authorization': 'Bearer ${session.accessToken}'};
    }
    return <String, String>{};
  }

  Future<FunctionResponse> _invokeStripeFunction(
    String functionName, {
    required Map<String, dynamic> body,
    int retryCount = 1,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await _supabaseClient.functions.invoke(
          functionName,
          body: body,
          headers: await _buildFunctionHeaders(),
        );
      } on FunctionException catch (fe) {
        final raw = fe.details?.toString() ?? '';
        if (attempt < retryCount &&
            (fe.status == 401 ||
                fe.status == 403 ||
                raw.contains('LEGACY_JWT') ||
                raw.contains('JWT') ||
                raw.contains('Unauthorized'))) {
          attempt++;
          try {
            await _supabaseClient.auth.refreshSession();
          } catch (_) {}
          continue;
        }
        rethrow;
      }
    }
  }

  /// Create a Stripe PaymentIntent via the edge function and present
  /// the Stripe Payment Sheet to the user.
  ///
  /// Returns a [StripePaymentSession] containing the clientSecret needed
  /// for the Payment Sheet. The actual payment sheet presentation is
  /// handled by the calling screen.
  Future<StripePaymentSession> createStripeCheckout({
    required String orderId,
    required double amount,
    required String customerEmail,
    required String customerName,
    String type = 'order',
  }) async {
    try {
      final response = await _invokeStripeFunction(
        AppConstants.stripePaymentFunction,
        body: {
          'action': 'create_payment_intent',
          'orderId': orderId,
          'amount': amount,
          'email': customerEmail,
          'name': customerName,
          'type': type,
          'currency': AppConstants.currencyCode.toLowerCase(),
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected Stripe session response.');
      }
      if (data['error'] != null) {
        // Retry once with fresh token if auth error
        final errMsg = data['error'].toString();
        if (errMsg.contains('Unauthorized') || errMsg.contains('401')) {
          AppLogger.info(
            'Auth error on payment intent, retrying with fresh token...',
          );
          await _supabaseClient.auth.refreshSession();
          final retryResponse = await _supabaseClient.functions.invoke(
            AppConstants.stripePaymentFunction,
            body: {
              'action': 'create_payment_intent',
              'orderId': orderId,
              'amount': amount,
              'email': customerEmail,
              'name': customerName,
              'type': type,
              'currency': AppConstants.currencyCode.toLowerCase(),
            },
            headers: await _buildFunctionHeaders(),
          );
          final retryData = retryResponse.data;
          if (retryData is Map<String, dynamic> && retryData['error'] == null) {
            final clientSecret = retryData['clientSecret'] as String?;
            final paymentIntentId = retryData['paymentIntentId'] as String?;
            if (clientSecret != null && paymentIntentId != null) {
              return StripePaymentSession(
                orderId: orderId,
                paymentIntentId: paymentIntentId,
                clientSecret: clientSecret,
                amount: amount,
                currency: (retryData['currency'] as String?) ?? 'usd',
                customerId: retryData['customerId'] as String?,
                ephemeralKey: retryData['ephemeralKey'] as String?,
              );
            }
          }
        }
        throw Exception(_stripeErrorMessage(data['error']));
      }
      final clientSecret = data['clientSecret'] as String?;
      final paymentIntentId = data['paymentIntentId'] as String?;
      if (clientSecret == null || paymentIntentId == null) {
        throw Exception('Stripe session is incomplete.');
      }
      return StripePaymentSession(
        orderId: orderId,
        paymentIntentId: paymentIntentId,
        clientSecret: clientSecret,
        amount: amount,
        currency: (data['currency'] as String?) ?? 'usd',
        customerId: data['customerId'] as String?,
        ephemeralKey: data['ephemeralKey'] as String?,
      );
    } catch (e) {
      AppLogger.error('Stripe checkout creation error: $e');
      rethrow;
    }
  }

  String _stripeErrorMessage(dynamic error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('api key'))
      return 'Invalid Stripe API key. Contact support.';
    if (msg.contains('card was declined')) return 'Your card was declined.';
    if (msg.contains('expired card')) return 'Your card is expired.';
    if (msg.contains('authentication'))
      return 'Authentication failed. Try another card.';
    if (msg.contains('network')) return 'Network error. Please try again.';
    if (msg.contains('paymentintent'))
      return 'Payment could not be created. Try again.';
    return 'Payment failed: $error';
  }

  /// Create a Stripe PaymentIntent and present the Payment Sheet in one go.
  /// This is the primary method for card payments when NO saved card is selected.
  /// Returns a map with 'status' = 'paid' if successful, null on cancellation.
  Future<Map<String, dynamic>?> presentStripePaymentSheet({
    required String orderId,
    required double amount,
    String? customerEmail,
    String? customerName,
    String type = 'order',
  }) async {
    try {
      final session = await createStripeCheckout(
        orderId: orderId,
        amount: amount,
        customerEmail: customerEmail ?? '',
        customerName: customerName ?? '',
        type: type,
      );
      if (Stripe.publishableKey.isEmpty) {
        final key = AppConstants.stripePublishableKey;
        if (key.isNotEmpty) {
          Stripe.publishableKey = key;
          Stripe.merchantIdentifier = AppConstants.stripeMerchantId;
          await Stripe.instance.applySettings();
        }
      }
      // Match the same minimal setup as the working add-card (presentSetupSheet):
      // no Apple Pay / Google Pay params to avoid currency-compatibility failures.
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: session.clientSecret,
          customerId: session.customerId,
          customerEphemeralKeySecret: session.ephemeralKey,
          merchantDisplayName: AppConstants.appName,
          style: ThemeMode.system,
          billingDetails: BillingDetails(
            email: customerEmail,
            name: customerName,
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return {'status': 'paid', 'orderId': orderId};
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        AppLogger.info('Stripe payment cancelled by user');
        return null;
      }
      AppLogger.error('Stripe payment error: ${e.error.localizedMessage}');
      throw Exception(_stripeErrorMessage(e.error.localizedMessage));
    } catch (e) {
      AppLogger.error('Stripe payment sheet error: $e');
      throw Exception(_stripeErrorMessage(e));
    }
  }

  /// Create an unconfirmed PaymentIntent for a saved card so the Flutter SDK
  /// can confirm it client-side with CVC re-collection.
  /// Pass [type] = 'wallet_topup' to skip the order-table lookup.
  Future<StripePaymentSession> prepareSavedCardPayment({
    required String orderId,
    required double amount,
    required String paymentMethodId,
    String type = 'order',
  }) async {
    try {
      final response = await _invokeStripeFunction(
        AppConstants.stripePaymentFunction,
        body: {
          'action': 'prepare_saved_card_payment',
          'orderId': orderId,
          'amount': amount,
          'paymentMethodId': paymentMethodId,
          'type': type,
          'currency': AppConstants.currencyCode.toLowerCase(),
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected response from payment function.');
      }
      if (data['error'] != null) {
        throw Exception(_stripeErrorMessage(data['error']));
      }
      final clientSecret = data['clientSecret'] as String?;
      final paymentIntentId = data['paymentIntentId'] as String?;
      if (clientSecret == null || paymentIntentId == null) {
        throw Exception('Incomplete payment session response.');
      }
      return StripePaymentSession(
        orderId: orderId,
        paymentIntentId: paymentIntentId,
        clientSecret: clientSecret,
        amount: amount,
        currency: (data['currency'] as String?) ??
            AppConstants.currencyCode.toLowerCase(),
        customerId: data['customerId'] as String?,
      );
    } catch (e) {
      AppLogger.error('Prepare saved card payment error: $e');
      rethrow;
    }
  }

  /// Charge a verified saved card off-session (no Stripe UI shown).
  /// Uses the same server-side approach as the card verification charge.
  /// Pass [type] = 'wallet_topup' for wallet deposits so the edge function
  /// skips the order-table lookup. Returns true on success.
  Future<bool> chargeWithSavedCard({
    required String orderId,
    required double amount,
    required String paymentMethodId,
    String type = 'order',
  }) async {
    try {
      final response = await _invokeStripeFunction(
        AppConstants.stripePaymentFunction,
        body: {
          'action': 'charge_saved_card',
          'orderId': orderId,
          'amount': amount,
          'paymentMethodId': paymentMethodId,
          'type': type,
          'currency': AppConstants.currencyCode.toLowerCase(),
        },
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return false;
      if (data['error'] != null) {
        throw Exception(_stripeErrorMessage(data['error']));
      }
      return data['success'] == true;
    } catch (e) {
      AppLogger.error('Saved card charge error: $e');
      rethrow;
    }
  }

  /// Present the Stripe Payment Sheet for a ride fare.
  /// Reuses the deployed `stripe-payment` function with type='ride' so the
  /// order lookup is skipped. [amountCents] is converted to dollars internally
  /// since the function multiplies by 100 itself.
  /// Returns {'status': 'paid'} on success, null if user cancels.
  Future<Map<String, dynamic>?> presentStripePaymentSheetForRide({
    required int amountCents,
    String currency = 'jmd',
    String? customerEmail,
    String? customerName,
  }) async {
    try {
      final rideRef = 'ride_${DateTime.now().millisecondsSinceEpoch}';
      final session = await createStripeCheckout(
        orderId: rideRef,
        amount: amountCents / 100.0,
        customerEmail: customerEmail ?? '',
        customerName: customerName ?? '',
        type: 'ride',
      );

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
          paymentIntentClientSecret: session.clientSecret,
          customerId: session.customerId,
          customerEphemeralKeySecret: session.ephemeralKey,
          merchantDisplayName: AppConstants.appName,
          style: ThemeMode.system,
          billingDetails: BillingDetails(
            email: customerEmail,
            name: customerName,
          ),
          applePay: const PaymentSheetApplePay(merchantCountryCode: 'US'),
          googlePay: const PaymentSheetGooglePay(merchantCountryCode: 'US'),
          allowsDelayedPaymentMethods: true,
        ),
      );

      await Stripe.instance.presentPaymentSheet();
      return {'status': 'paid'};
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        AppLogger.info('Stripe ride payment cancelled by user');
        return null;
      }
      AppLogger.error('Stripe ride payment error: ${e.error.localizedMessage}');
      throw Exception(_stripeErrorMessage(e.error.localizedMessage));
    } catch (e) {
      AppLogger.error('Stripe ride payment sheet error: $e');
      throw Exception(_stripeErrorMessage(e));
    }
  }

  /// Confirm payment status server-side after the payment sheet completes
  Future<bool> confirmStripePayment({
    required String paymentIntentId,
    required String orderId,
    String type = 'order',
  }) async {
    try {
      final response = await _invokeStripeFunction(
        AppConstants.stripePaymentFunction,
        body: {
          'action': 'confirm_payment',
          'paymentIntentId': paymentIntentId,
          'orderId': orderId,
          'type': type,
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) return false;
      return data['success'] == true;
    } catch (e) {
      AppLogger.error('Stripe payment confirmation error: $e');
      return false;
    }
  }

  /// Cleanup an unpaid order server-side so cancelled/failed card attempts
  /// never leave orphan pending orders in the database.
  Future<bool> cleanupUnpaidOrder(String orderId) async {
    try {
      final response = await _invokeStripeFunction(
        AppConstants.stripePaymentFunction,
        body: {'action': 'cleanup_unpaid_order', 'orderId': orderId},
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) return false;
      return data['success'] == true;
    } catch (e) {
      AppLogger.error('Stripe unpaid order cleanup error: $e');
      return false;
    }
  }

  /// Create a Stripe SetupIntent for saving a card without charging it
  Future<Map<String, dynamic>> createSetupIntent({
    required String customerEmail,
  }) async {
    try {
      final response = await _invokeStripeFunction(
        AppConstants.stripePaymentFunction,
        body: {'action': 'create_setup_intent', 'email': customerEmail},
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected setup intent response.');
      }

      if (data['error'] != null) {
        // Retry once with fresh token if auth error
        final errMsg = data['error'].toString();
        if (errMsg.contains('Unauthorized') || errMsg.contains('401')) {
          AppLogger.info(
            'Auth error on setup intent, retrying with fresh token...',
          );
          await _supabaseClient.auth.refreshSession();
          final retryResponse = await _supabaseClient.functions.invoke(
            AppConstants.stripePaymentFunction,
            body: {'action': 'create_setup_intent', 'email': customerEmail},
            headers: await _buildFunctionHeaders(),
          );
          final retryData = retryResponse.data;
          if (retryData is Map<String, dynamic> && retryData['error'] == null) {
            return retryData;
          }
        }
        throw Exception(_stripeErrorMessage(data['error']));
      }

      return data;
    } catch (e) {
      AppLogger.error('Setup intent creation error: $e');
      rethrow;
    }
  }

  /// Create a card verification setup flow and return the Stripe SetupIntent info.
  Future<Map<String, dynamic>> createVerificationCharge({
    required String customerEmail,
    required String customerName,
    String? cardBrand,
    String? lastFour,
    String? cardholderName,
    String? phone,
  }) async {
    try {
      final response = await _invokeStripeFunction(
        AppConstants.stripePaymentFunction,
        body: {
          'action': 'create_verification_charge',
          'email': customerEmail,
          'name': customerName,
          if (cardBrand != null) 'card_brand': cardBrand,
          if (lastFour != null) 'last_four': lastFour,
          if (cardholderName != null) 'cardholder_name': cardholderName,
          if (phone != null) 'phone': phone,
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected verification setup response.');
      }

      if (data['error'] != null) {
        final errMsg = data['error'].toString();
        if (errMsg.contains('Unauthorized') || errMsg.contains('401')) {
          AppLogger.info(
            'Auth error on verification setup, retrying with fresh token...',
          );
          await _supabaseClient.auth.refreshSession();
          final retryResponse = await _supabaseClient.functions.invoke(
            AppConstants.stripePaymentFunction,
            body: {
              'action': 'create_verification_charge',
              'email': customerEmail,
              'name': customerName,
              if (cardBrand != null) 'card_brand': cardBrand,
              if (lastFour != null) 'last_four': lastFour,
              if (cardholderName != null) 'cardholder_name': cardholderName,
              if (phone != null) 'phone': phone,
            },
            headers: await _buildFunctionHeaders(),
          );
          final retryData = retryResponse.data;
          if (retryData is Map<String, dynamic> && retryData['error'] == null) {
            return retryData;
          }
        }
        throw Exception(_stripeErrorMessage(data['error']));
      }

      return data;
    } catch (e) {
      AppLogger.error('Verification setup creation error: $e');
      rethrow;
    }
  }

  /// Complete the verification flow and charge the saved card.
  Future<Map<String, dynamic>> completeVerificationCharge({
    required String setupIntentId,
    String? cardBrand,
    String? lastFour,
    String? cardholderName,
    String? email,
    String? phone,
  }) async {
    try {
      final response = await _invokeStripeFunction(
        AppConstants.stripePaymentFunction,
        body: {
          'action': 'complete_verification_charge',
          'setup_intent_id': setupIntentId,
          if (cardBrand != null) 'card_brand': cardBrand,
          if (lastFour != null) 'last_four': lastFour,
          if (cardholderName != null) 'cardholder_name': cardholderName,
          if (email != null) 'email': email,
          if (phone != null) 'phone': phone,
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected verification completion response.');
      }

      if (data['error'] != null) {
        final errMsg = data['error'].toString();
        if (errMsg.contains('Unauthorized') || errMsg.contains('401')) {
          AppLogger.info(
            'Auth error on verification completion, retrying with fresh token...',
          );
          await _supabaseClient.auth.refreshSession();
          final retryResponse = await _supabaseClient.functions.invoke(
            AppConstants.stripePaymentFunction,
            body: {
              'action': 'complete_verification_charge',
              'setup_intent_id': setupIntentId,
              if (cardBrand != null) 'card_brand': cardBrand,
              if (lastFour != null) 'last_four': lastFour,
              if (cardholderName != null) 'cardholder_name': cardholderName,
              if (email != null) 'email': email,
              if (phone != null) 'phone': phone,
            },
            headers: await _buildFunctionHeaders(),
          );
          final retryData = retryResponse.data;
          if (retryData is Map<String, dynamic> && retryData['error'] == null) {
            return retryData;
          }
        }
        throw Exception(_stripeErrorMessage(data['error']));
      }

      return data;
    } catch (e) {
      AppLogger.error('Verification completion error: $e');
      rethrow;
    }
  }

  /// Present the Stripe Payment Sheet in setup mode to save a card
  Future<bool> presentSetupSheet({
    required String clientSecret,
    required String customerName,
    required String customerEmail,
  }) async {
    try {
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
          setupIntentClientSecret: clientSecret,
          merchantDisplayName: AppConstants.appName,
          style: ThemeMode.system,
          billingDetails: BillingDetails(
            email: customerEmail,
            name: customerName,
          ),
        ),
      );

      await Stripe.instance.presentPaymentSheet();
      return true;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        return false;
      }
      rethrow;
    }
  }

  Future<String> waitForOrderPaymentStatus(
    String orderId, {
    int attempts = 8,
    Duration interval = const Duration(milliseconds: 750),
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      final status = await getOrderPaymentStatus(orderId);
      if (status != AppConstants.paymentPending) {
        return status;
      }
      await Future.delayed(interval);
    }

    return AppConstants.paymentPending;
  }

  Future<String> getOrderPaymentStatus(String orderId) async {
    final response = await _supabaseClient
        .from(AppConstants.tableOrders)
        .select('payment_status')
        .eq('id', orderId)
        .maybeSingle();

    if (response == null) {
      return AppConstants.paymentFailed;
    }

    return (response['payment_status'] as String?) ??
        AppConstants.paymentPending;
  }

  /// Process payment for order
  Future<PaymentResponse> processPayment({
    required String orderId,
    required double amount,
    required PaymentMethod paymentMethod,
    required String userEmail,
    required String userPhone,
    String? cardToken, // For card payments
    String? cardLast4,
  }) async {
    try {
      AppLogger.info(
        'Processing payment: Order=$orderId, Amount=$amount, Method=$paymentMethod',
      );

      // Route to appropriate payment method processor
      switch (paymentMethod) {
        case PaymentMethod.card:
          // Card payments are handled via Stripe Payment Sheet
          // Use createStripeCheckout() + presentStripePaymentSheet()
          return _createFailedResponse(
            orderId: orderId,
            amount: amount,
            paymentMethod: 'card',
            errorMessage:
                'Card payments use Stripe Payment Sheet. Use createStripeCheckout() flow instead.',
          );

        case PaymentMethod.cash:
          return await _processCashPayment(orderId: orderId, amount: amount);
      }
    } catch (e) {
      AppLogger.error('Payment processing error: $e');
      return _createFailedResponse(
        orderId: orderId,
        amount: amount,
        paymentMethod: paymentMethod.toString(),
        errorMessage: 'Payment failed: $e',
      );
    }
  }

  /// Process cash payment (COD - Cash on Delivery)
  Future<PaymentResponse> _processCashPayment({
    required String orderId,
    required double amount,
  }) async {
    try {
      AppLogger.info(
        'Processing cash payment: $orderId - ${AppConstants.currencySymbol}$amount',
      );

      // Cash payments are recorded but not processed
      // Driver will collect payment on delivery
      final transactionId = 'TXN_CASH_${DateTime.now().millisecondsSinceEpoch}';

      return PaymentResponse(
        success: true,
        transactionId: transactionId,
        status: 'pending_collection',
        amount: amount,
        paymentMethod: 'cash',
        timestamp: DateTime.now(),
        metadata: {'collection_method': 'driver_on_delivery'},
      );
    } catch (e) {
      AppLogger.error('Cash payment error: $e');
      return _createFailedResponse(
        orderId: orderId,
        amount: amount,
        paymentMethod: 'cash',
        errorMessage: 'Cash payment setup failed: $e',
      );
    }
  }

  // No mobile money for NCB

  /// Verify payment status via Stripe API (through Edge Function).
  Future<String> verifyPaymentStatus(String transactionId) async {
    try {
      AppLogger.info('Verifying payment status: $transactionId');
      final response = await _invokeStripeFunction(
        'stripe-payment',
        body: {'action': 'verify', 'transaction_id': transactionId},
      );
      final data = response.data as Map<String, dynamic>?;
      return data?['status'] as String? ?? AppConstants.paymentFailed;
    } catch (e) {
      AppLogger.error('Payment verification error: $e');
      return AppConstants.paymentFailed;
    }
  }

  /// Refund payment via Stripe API (through Edge Function).
  Future<bool> refundPayment({
    required String transactionId,
    required double amount,
    String? reason,
  }) async {
    try {
      AppLogger.info(
        'Processing refund: $transactionId - ${AppConstants.currencySymbol}$amount',
      );
      final response = await _invokeStripeFunction(
        'stripe-payment',
        body: {
          'action': 'refund',
          'transaction_id': transactionId,
          'amount': (amount * 100).round(), // cents
          if (reason != null) 'reason': reason,
        },
      );
      final data = response.data as Map<String, dynamic>?;
      if (data?['error'] != null) {
        AppLogger.error('Refund error: ${data!['error']}');
        return false;
      }
      AppLogger.info('Refund processed successfully');
      return true;
    } catch (e) {
      AppLogger.error('Refund error: $e');
      return false;
    }
  }

  /// Generate payment summary for receipt
  String generatePaymentSummary({
    required Order order,
    required PaymentResponse paymentResponse,
  }) {
    return '''
        ═══════════════════════════════════
        PAYMENT RECEIPT
        ═══════════════════════════════════
        Order ID: ${order.id}
        Transaction ID: ${paymentResponse.transactionId}
        
        Amount Breakdown:
        ─────────────────────────────────
        Subtotal:       ${AppConstants.currencySymbol}${order.subtotal.toStringAsFixed(2)}
        Tax:            ${AppConstants.currencySymbol}${order.taxAmount?.toStringAsFixed(2) ?? '0.00'}
        Delivery Fee:   ${AppConstants.currencySymbol}${order.deliveryFee.toStringAsFixed(2)}
        Discount:       -${AppConstants.currencySymbol}${order.discount?.toStringAsFixed(2) ?? '0.00'}
        ─────────────────────────────────
        TOTAL:          ${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(2)}
        
        Payment Method: ${paymentResponse.paymentMethod}
        Status: ${paymentResponse.status.toUpperCase()}
        Time: ${paymentResponse.timestamp}
        ═══════════════════════════════════
        ''';
  }

  /// Helper to create failed response
  PaymentResponse _createFailedResponse({
    required String orderId,
    required double amount,
    required String paymentMethod,
    required String errorMessage,
  }) {
    return PaymentResponse(
      success: false,
      transactionId: 'FAILED_${DateTime.now().millisecondsSinceEpoch}',
      status: AppConstants.paymentFailed,
      amount: amount,
      paymentMethod: paymentMethod,
      errorMessage: errorMessage,
      timestamp: DateTime.now(),
    );
  }

  /// Calculate payment fees (uses DB-driven rates from AppConstants)
  double calculatePaymentFee({
    required double amount,
    required PaymentMethod paymentMethod,
  }) {
    double feePercent = paymentMethod == PaymentMethod.card
        ? AppConstants.cardFeePercent
        : AppConstants.cashFeePercent;

    return (amount * feePercent) / 100;
  }

  // ── Saved Cards ──────────────────────────────────────────────

  /// Fetch saved cards from Stripe and sync to local DB.
  Future<List<SavedCard>> getSavedCards(String userId) async {
    try {
      // Try fetching live from Stripe
      final response = await _invokeStripeFunction(
        AppConstants.stripePaymentFunction,
        body: {'action': 'list_payment_methods'},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['cards'] != null) {
        final stripeCards = (data['cards'] as List)
            .cast<Map<String, dynamic>>();
        final customerId = data['customer_id'] as String?;
        // Sync to DB
        await _syncStripeCardsToDb(userId, customerId, stripeCards);
      }
    } catch (e) {
      AppLogger.error('Error fetching Stripe cards (falling back to DB): $e');
    }

    // Read from local DB (always the source of truth after sync)
    try {
      final rows = await _supabaseClient
          .from('saved_cards')
          .select()
          .eq('user_id', userId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);
      return (rows as List).map((e) => SavedCard.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error reading saved cards from DB: $e');
      return [];
    }
  }

  /// Sync Stripe payment methods into the saved_cards table.
  Future<void> _syncStripeCardsToDb(
    String userId,
    String? customerId,
    List<Map<String, dynamic>> stripeCards,
  ) async {
    try {
      // Get existing saved cards
      final existing = await _supabaseClient
          .from('saved_cards')
          .select('id, stripe_payment_method_id, last_four, card_brand')
          .eq('user_id', userId);
      final existingPmIds = (existing as List)
          .map((e) => e['stripe_payment_method_id'] as String?)
          .where((id) => id != null)
          .toSet();

      for (final sc in stripeCards) {
        final pmId = sc['payment_method_id'] as String;
        if (existingPmIds.contains(pmId)) continue; // already synced

        // Check for a legacy row matching last4 + brand but missing PM id
        final last4 = sc['last4'] as String? ?? '';
        final brand = sc['brand'] as String? ?? '';
        final matchRows = await _supabaseClient
            .from('saved_cards')
            .select('id')
            .eq('user_id', userId)
            .eq('last_four', last4)
            .eq('card_brand', brand)
            .isFilter('stripe_payment_method_id', null)
            .limit(1);
        if ((matchRows as List).isNotEmpty) {
          // Update existing row with Stripe ids
          await _supabaseClient
              .from('saved_cards')
              .update({
                'stripe_payment_method_id': pmId,
                'stripe_customer_id': customerId,
                'exp_month': sc['exp_month'],
                'exp_year': sc['exp_year'],
                'status': 'verified',
              })
              .eq('id', matchRows[0]['id']);
        } else {
          // Insert new
          await _supabaseClient.from('saved_cards').insert({
            'user_id': userId,
            'card_brand': brand,
            'last_four': last4,
            'exp_month': sc['exp_month'],
            'exp_year': sc['exp_year'],
            'stripe_payment_method_id': pmId,
            'stripe_customer_id': customerId,
            'status': 'verified',
            'is_default': false,
          });
        }
      }

      // Remove DB rows that no longer exist in Stripe
      final stripePmIds = stripeCards
          .map((c) => c['payment_method_id'] as String)
          .toSet();
      for (final row in (existing as List)) {
        final rowPmId = row['stripe_payment_method_id'] as String?;
        if (rowPmId != null && !stripePmIds.contains(rowPmId)) {
          await _supabaseClient
              .from('saved_cards')
              .delete()
              .eq('id', row['id']);
        }
      }
    } catch (e) {
      AppLogger.error('Error syncing Stripe cards to DB: $e');
    }
  }

  /// Delete a saved card from both Stripe and local DB.
  Future<bool> deleteSavedCard(String cardId) async {
    try {
      // Get the card to check for Stripe payment method ID
      final row = await _supabaseClient
          .from('saved_cards')
          .select('stripe_payment_method_id')
          .eq('id', cardId)
          .single();
      final pmId = row['stripe_payment_method_id'] as String?;

      // Detach from Stripe if we have a PM ID
      if (pmId != null && pmId.isNotEmpty) {
        try {
          await _invokeStripeFunction(
            AppConstants.stripePaymentFunction,
            body: {
              'action': 'detach_payment_method',
              'payment_method_id': pmId,
            },
          );
        } catch (e) {
          AppLogger.error('Error detaching from Stripe: $e');
          // Continue to delete from DB even if Stripe detach fails
        }
      }

      await _supabaseClient.from('saved_cards').delete().eq('id', cardId);
      return true;
    } catch (e) {
      AppLogger.error('Error deleting saved card: $e');
      return false;
    }
  }

  /// Save a card in 'pending' status after the verification charge succeeds.
  /// The user has until [expiresAt] to enter the correct amount.
  Future<SavedCard?> savePendingCard({
    required String userId,
    required String cardBrand,
    required String lastFour,
    required String cardholderName,
    required String email,
    required String phone,
    required String verificationId,
    required DateTime expiresAt,
    String? stripePaymentMethodId,
    String? stripeCustomerId,
  }) async {
    try {
      final count = await _supabaseClient
          .from('saved_cards')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'verified');
      final isFirst = (count as List).isEmpty;

      final inserted = await _supabaseClient
          .from('saved_cards')
          .insert({
            'user_id': userId,
            'card_brand': cardBrand.toLowerCase(),
            'last_four': lastFour,
            'cardholder_name': cardholderName,
            'email': email,
            'phone': phone,
            'is_default': isFirst,
            'status': 'pending',
            'verification_id': verificationId,
            'verification_expires_at': expiresAt.toUtc().toIso8601String(),
            'verification_attempts': 0,
            if (stripePaymentMethodId != null)
              'stripe_payment_method_id': stripePaymentMethodId,
            if (stripeCustomerId != null)
              'stripe_customer_id': stripeCustomerId,
          })
          .select()
          .single();
      return SavedCard.fromJson(inserted);
    } catch (e) {
      AppLogger.error('Error saving pending card: $e');
      return null;
    }
  }

  /// Attempt to verify a pending card by matching the charged amount.
  /// Returns true if verified, false if wrong. Increments attempt count.
  Future<bool> verifyPendingCard(String cardId, double enteredAmount) async {
    try {
      // Get the card and its verification record
      final cardRow = await _supabaseClient
          .from('saved_cards')
          .select(
            'user_id, card_brand, verification_id, verification_attempts, verification_expires_at',
          )
          .eq('id', cardId)
          .single();

      final verificationId = cardRow['verification_id'] as String?;
      if (verificationId == null) return false;
      final ownerUserId = cardRow['user_id'] as String?;
      final cardBrand = (cardRow['card_brand'] as String? ?? '').toLowerCase();

      // Check if expired
      final expiresAt = cardRow['verification_expires_at'] as String?;
      if (expiresAt != null &&
          DateTime.now().toUtc().isAfter(DateTime.parse(expiresAt).toUtc())) {
        await _supabaseClient
            .from('saved_cards')
            .update({'status': 'failed'})
            .eq('id', cardId);
        return false;
      }

      final currentAttempts = cardRow['verification_attempts'] as int? ?? 0;

      // Already exhausted all attempts
      if (currentAttempts >= 3) {
        await _supabaseClient
            .from('saved_cards')
            .update({'status': 'failed'})
            .eq('id', cardId);
        return false;
      }

      final attempts = currentAttempts + 1;

      // Check amount against card_verifications
      var row = await _supabaseClient
          .from('card_verifications')
          .select('amount, status')
          .eq('id', verificationId)
          .maybeSingle();

      // Lazy-backfill for Lunipay cards saved before complete_setup_session
      // existed: if no row, try to create it from the Lunipay session.
      // We treat any non-real-brand value (lunipay/card/empty) as a Lunipay
      // card, since the verification_id IS the Lunipay session id for those.
      final realBrands = {
        'visa',
        'mastercard',
        'amex',
        'american_express',
        'discover',
        'keycard',
      };
      final isLunipayCard = !realBrands.contains(cardBrand);
      // Stripe-only: Legacy Lunipay setup session logic removed
      if (row == null && isLunipayCard && ownerUserId != null) {
        try {
          row = await _supabaseClient
              .from('card_verifications')
              .select('amount, status')
              .eq('id', verificationId)
              .maybeSingle();
        } catch (e) {
          AppLogger.error('Card verification lookup error: $e');
        }
      }

      bool matched = false;
      if (row != null) {
        final chargedAmount = (row['amount'] as num).toDouble();
        final cvStatus = row['status'] as String?;
        matched = cvStatus == 'completed' && chargedAmount == enteredAmount;
      }

      if (matched) {
        // Verify the card
        await _supabaseClient
            .from('saved_cards')
            .update({'status': 'verified', 'verification_attempts': attempts})
            .eq('id', cardId);

        // Refund the verification charge back to the card via Stripe
        try {
          await _supabaseClient.functions.invoke(
            AppConstants.stripePaymentFunction,
            body: {
              'action': 'refund_verification_charge',
              'payment_intent_id': verificationId,
            },
          );
        } catch (e) {
          AppLogger.error('Verification refund failed (non-blocking): $e');
        }

        // Mark verification charge as refunded in DB
        await _supabaseClient
            .from('card_verifications')
            .update({
              'refund_status': 'refunded',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', verificationId);
        return true;
      }

      // Wrong amount — increment attempts, fail after 3
      if (attempts >= 3) {
        await _supabaseClient
            .from('saved_cards')
            .update({'status': 'failed', 'verification_attempts': attempts})
            .eq('id', cardId);
      } else {
        await _supabaseClient
            .from('saved_cards')
            .update({'verification_attempts': attempts})
            .eq('id', cardId);
      }
      return false;
    } catch (e) {
      AppLogger.error('Error verifying pending card: $e');
      return false;
    }
  }

  /// Get the remaining attempts for a pending card.
  Future<int> getCardVerificationAttempts(String cardId) async {
    try {
      final row = await _supabaseClient
          .from('saved_cards')
          .select('verification_attempts')
          .eq('id', cardId)
          .single();
      return row['verification_attempts'] as int? ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<SavedCard?> saveCard({
    required String userId,
    required String cardBrand,
    required String lastFour,
    required String cardholderName,
    required String email,
    required String phone,
  }) async {
    try {
      // Check if this card already exists for the user
      final existing = await _supabaseClient
          .from('saved_cards')
          .select()
          .eq('user_id', userId)
          .eq('last_four', lastFour)
          .eq('card_brand', cardBrand.toLowerCase())
          .maybeSingle();

      if (existing != null) {
        // Update existing card's contact info
        final updated = await _supabaseClient
            .from('saved_cards')
            .update({
              'cardholder_name': cardholderName,
              'email': email,
              'phone': phone,
            })
            .eq('id', existing['id'])
            .select()
            .single();
        return SavedCard.fromJson(updated);
      }

      // Check if this is the first card (make it default)
      final count = await _supabaseClient
          .from('saved_cards')
          .select('id')
          .eq('user_id', userId);
      final isFirst = (count as List).isEmpty;

      final card = SavedCard(
        id: '',
        userId: userId,
        cardBrand: cardBrand.toLowerCase(),
        lastFour: lastFour,
        cardholderName: cardholderName,
        email: email,
        phone: phone,
        isDefault: isFirst,
        createdAt: DateTime.now(),
      );

      final inserted = await _supabaseClient
          .from('saved_cards')
          .insert(card.toJson())
          .select()
          .single();
      return SavedCard.fromJson(inserted);
    } catch (e) {
      AppLogger.error('Error saving card: $e');
      return null;
    }
  }

  Future<void> setDefaultCard(String userId, String cardId) async {
    try {
      // Unset all defaults for user
      await _supabaseClient
          .from('saved_cards')
          .update({'is_default': false})
          .eq('user_id', userId);
      // Set the chosen card as default
      await _supabaseClient
          .from('saved_cards')
          .update({'is_default': true})
          .eq('id', cardId);
    } catch (e) {
      AppLogger.error('Error setting default card: $e');
    }
  }

  // ── Stripe Payout Processing ────────────────────────────────────

  /// Process payout to a bank account via Stripe
  Future<Map<String, dynamic>> processStripePayout({
    required String payoutId,
    required double amount,
    required String recipientName,
    required String bankAccount,
    required String bankName,
    String? description,
  }) async {
    try {
      AppLogger.info('Processing Stripe payout: $payoutId, amount=$amount');

      final response = await _supabaseClient.functions.invoke(
        'stripe-payment',
        body: {
          'action': 'create_payout',
          'payoutId': payoutId,
          'amount': amount,
          'currency': 'usd',
          'recipientName': recipientName,
          'bankAccount': bankAccount,
          'bankName': bankName,
          'description': description ?? 'Payout $payoutId',
        },
        headers: await _buildFunctionHeaders(),
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected Stripe payout response');
      }

      final status = data['status'] as String?;
      if (status != 'success') {
        throw Exception(data['error'] ?? 'Stripe payout failed');
      }

      AppLogger.info('Stripe payout successful: ${data['payout_reference']}');
      return data;
    } catch (e) {
      AppLogger.error('Stripe payout error: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stripe is the sole payment gateway — all card payments route through Stripe
  // ─────────────────────────────────────────────────────────────────────────
  // Legacy Lunipay and WiPay methods are deprecated and no longer used.
  // Use presentStripePaymentSheet() for all card payments instead.
}
