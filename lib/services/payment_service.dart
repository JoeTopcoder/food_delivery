import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../models/order_model.dart';
import '../models/saved_card_model.dart';
import '../utils/app_logger.dart';

/// Payment method enum
enum PaymentMethod { card, bankTransfer, cash }

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

/// Legacy NCB session kept for backward compat references (unused in new flow)
class NcbPaymentSession {
  final String orderId;
  final String transactionId;
  final String paymentUrl;
  final String callbackUrl;
  final double? verificationAmount;

  const NcbPaymentSession({
    required this.orderId,
    required this.transactionId,
    required this.paymentUrl,
    required this.callbackUrl,
    this.verificationAmount,
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

  bool get isNcbConfigured => AppConstants.ncbApiKey.isNotEmpty;

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
      final response = await _supabaseClient.functions.invoke(
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

      final clientSecret = data['clientSecret'] as String?;
      final paymentIntentId = data['paymentIntentId'] as String?;

      if (clientSecret == null || paymentIntentId == null) {
        throw Exception(data['error'] ?? 'Stripe session is incomplete.');
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

  /// Present the Stripe Payment Sheet and wait for the user to complete payment.
  /// Returns true if payment succeeded, false otherwise.
  Future<bool> presentStripePaymentSheet({
    required StripePaymentSession session,
    required String customerEmail,
    required String customerName,
  }) async {
    try {
      // Ensure Stripe native SDK is initialized
      if (Stripe.publishableKey.isEmpty) {
        final key = AppConstants.stripePublishableKey;
        if (key.isNotEmpty) {
          Stripe.publishableKey = key;
          Stripe.merchantIdentifier = AppConstants.stripeMerchantId;
          await Stripe.instance.applySettings();
        }
      }

      // Initialize the Payment Sheet
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

      // Present the Payment Sheet
      await Stripe.instance.presentPaymentSheet();

      // If we reach here, payment was successful
      return true;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        AppLogger.info('Stripe payment cancelled by user');
        return false;
      }
      AppLogger.error('Stripe payment error: ${e.error.localizedMessage}');
      rethrow;
    } catch (e) {
      AppLogger.error('Stripe payment sheet error: $e');
      rethrow;
    }
  }

  /// Confirm payment status server-side after the payment sheet completes
  Future<bool> confirmStripePayment({
    required String paymentIntentId,
    required String orderId,
    String type = 'order',
  }) async {
    try {
      final response = await _supabaseClient.functions.invoke(
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

  /// Create a Stripe SetupIntent for saving a card without charging it
  Future<Map<String, dynamic>> createSetupIntent({
    required String customerEmail,
  }) async {
    try {
      final response = await _supabaseClient.functions.invoke(
        AppConstants.stripePaymentFunction,
        body: {'action': 'create_setup_intent', 'email': customerEmail},
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected setup intent response.');
      }

      if (data['error'] != null) {
        throw Exception(data['error']);
      }

      return data;
    } catch (e) {
      AppLogger.error('Setup intent creation error: $e');
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

  /// Legacy: Create NCB card checkout (kept for any residual reference)
  Future<NcbPaymentSession> createCardCheckout({
    required String orderId,
    required double amount,
    required String customerEmail,
    required String customerPhone,
    required String customerName,
    String? billingAddress,
    String? type,
    String? savedCardId,
    String? cvv,
  }) async {
    throw Exception(
      'NCB payments have been replaced by Stripe. Use createStripeCheckout() instead.',
    );
  }

  /// Legacy: Create card verification checkout (no longer needed with Stripe)
  Future<NcbPaymentSession> createCardVerificationCheckout({
    required String customerEmail,
    required String customerPhone,
    required String customerName,
    String? cardNumber,
    String? cardExpiry,
    String? cardCvv,
  }) async {
    throw Exception(
      'Card verification is no longer needed with Stripe. Use createSetupIntent() instead.',
    );
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

        case PaymentMethod.bankTransfer:
          return await _processBankTransferPayment(
            orderId: orderId,
            amount: amount,
            userEmail: userEmail,
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

  /// Process bank transfer payment (stub for NCB)
  Future<PaymentResponse> _processBankTransferPayment({
    required String orderId,
    required double amount,
    required String userEmail,
  }) async {
    try {
      AppLogger.info(
        'Processing NCB bank transfer: $orderId - $amount to $userEmail',
      );

      // Simulate NCB bank transfer (replace with real API call)
      final transactionId = 'NCB_BANK_${DateTime.now().millisecondsSinceEpoch}';

      return PaymentResponse(
        success: true,
        transactionId: transactionId,
        status: AppConstants.paymentCompleted,
        amount: amount,
        paymentMethod: 'bank_transfer',
        timestamp: DateTime.now(),
        metadata: {'email': userEmail, 'processor': 'ncb'},
      );
    } catch (e) {
      AppLogger.error('NCB bank transfer error: $e');
      return _createFailedResponse(
        orderId: orderId,
        amount: amount,
        paymentMethod: 'bank_transfer',
        errorMessage: 'NCB bank transfer failed: $e',
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
      final response = await _supabaseClient.functions.invoke(
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
      final response = await _supabaseClient.functions.invoke(
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
        : paymentMethod == PaymentMethod.bankTransfer
        ? AppConstants.bankTransferFeePercent
        : AppConstants.cashFeePercent;

    return (amount * feePercent) / 100;
  }

  // ── Saved Cards ──────────────────────────────────────────────

  /// Fetch saved cards from Stripe and sync to local DB.
  Future<List<SavedCard>> getSavedCards(String userId) async {
    try {
      // Try fetching live from Stripe
      final response = await _supabaseClient.functions.invoke(
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
          await _supabaseClient.functions.invoke(
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
            'verification_id, verification_attempts, verification_expires_at',
          )
          .eq('id', cardId)
          .single();

      final verificationId = cardRow['verification_id'] as String?;
      if (verificationId == null) return false;

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
      final row = await _supabaseClient
          .from('card_verifications')
          .select('amount, status')
          .eq('id', verificationId)
          .maybeSingle();

      if (row == null) return false;
      final chargedAmount = (row['amount'] as num).toDouble();
      final cvStatus = row['status'] as String?;
      final matched = cvStatus == 'completed' && chargedAmount == enteredAmount;

      if (matched) {
        // Verify the card
        await _supabaseClient
            .from('saved_cards')
            .update({'status': 'verified', 'verification_attempts': attempts})
            .eq('id', cardId);
        // Mark verification charge for refund
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
}
