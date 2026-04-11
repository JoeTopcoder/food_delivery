import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../models/order_model.dart';
import '../models/saved_card_model.dart';
import '../utils/app_logger.dart';

/// Payment method enum
enum PaymentMethod { card, bankTransfer, cash }

class NcbPaymentSession {
  final String orderId;
  final String transactionId;
  final String paymentUrl;
  final String callbackUrl;

  const NcbPaymentSession({
    required this.orderId,
    required this.transactionId,
    required this.paymentUrl,
    required this.callbackUrl,
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

/// Handles payment processing via NCB
class PaymentService {
  final SupabaseClient _supabaseClient;

  PaymentService({required SupabaseClient supabaseClient})
    : _supabaseClient = supabaseClient;

  bool get isNcbConfigured => AppConstants.ncbApiKey.isNotEmpty;

  Future<NcbPaymentSession> createCardCheckout({
    required String orderId,
    required double amount,
    required String customerEmail,
    required String customerPhone,
    required String customerName,
    String? billingAddress,
  }) async {
    if (!isNcbConfigured) {
      throw Exception(
        'NCB is not configured. Set NCB_API_KEY in your Flutter build and deploy the Supabase payment functions with NCB secrets.',
      );
    }

    try {
      final response = await _supabaseClient.functions.invoke(
        AppConstants.ncbInitiatePaymentFunction.replaceAll('/', ''),
        body: {
          'orderId': orderId,
          'amount': _formatAmount(amount),
          'email': customerEmail,
          'phone': customerPhone,
          'name': customerName,
          if (billingAddress != null && billingAddress.trim().isNotEmpty)
            'billingAddress': billingAddress.trim(),
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected NCB session response.');
      }

      final paymentUrl = data['payment_url'] as String?;
      final transactionId = data['reference'] as String?;
      final callbackUrl = AppConstants.ncbCallbackUrl;

      if (paymentUrl == null || transactionId == null) {
        throw Exception(data['error'] ?? 'NCB session is incomplete.');
      }

      return NcbPaymentSession(
        orderId: orderId,
        transactionId: transactionId,
        paymentUrl: paymentUrl,
        callbackUrl: callbackUrl,
      );
    } catch (e) {
      AppLogger.error('NCB checkout creation error: $e');
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
          // Card payments require createCardCheckout()
          return _createFailedResponse(
            orderId: orderId,
            amount: amount,
            paymentMethod: 'card',
            errorMessage:
                'Card payments require createCardCheckout() so NCB can securely host card entry.',
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
      AppLogger.info('Processing cash payment: $orderId - JMD\$$amount');

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

  /// Verify payment status
  Future<String> verifyPaymentStatus(String transactionId) async {
    try {
      AppLogger.info('Verifying payment status: $transactionId');

      // TODO: Call NCB API to verify payment status
      // For now, return mock status
      return AppConstants.paymentCompleted;
    } catch (e) {
      AppLogger.error('Payment verification error: $e');
      return AppConstants.paymentFailed;
    }
  }

  /// Refund payment
  Future<bool> refundPayment({
    required String transactionId,
    required double amount,
    String? reason,
  }) async {
    try {
      AppLogger.info('Processing refund: $transactionId - JMD\$$amount');

      if (reason != null) {
        AppLogger.info('Refund reason: $reason');
      }

      // TODO: Call NCB refund API
      // For now, mock successful refund
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
        Subtotal:       JMD\$${order.subtotal.toStringAsFixed(2)}
        Tax:            JMD\$${order.taxAmount?.toStringAsFixed(2) ?? '0.00'}
        Delivery Fee:   JMD\$${order.deliveryFee.toStringAsFixed(2)}
        Discount:       -JMD\$${order.discount?.toStringAsFixed(2) ?? '0.00'}
        ─────────────────────────────────
        TOTAL:          JMD\$${order.totalAmount.toStringAsFixed(2)}
        
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

  String _formatAmount(double amount) => amount.toStringAsFixed(2);

  // ── Saved Cards ──────────────────────────────────────────────

  Future<List<SavedCard>> getSavedCards(String userId) async {
    try {
      final data = await _supabaseClient
          .from('saved_cards')
          .select()
          .eq('user_id', userId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);
      return (data as List).map((e) => SavedCard.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error fetching saved cards: $e');
      return [];
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

  Future<void> deleteSavedCard(String cardId) async {
    try {
      await _supabaseClient.from('saved_cards').delete().eq('id', cardId);
    } catch (e) {
      AppLogger.error('Error deleting saved card: $e');
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

  // ── NCB Payout Processing ────────────────────────────────────

  /// Process payout to a bank account via NCB gateway
  Future<Map<String, dynamic>> processNcbPayout({
    required String payoutId,
    required double amount,
    required String recipientName,
    required String bankAccount,
    required String bankName,
    String? description,
  }) async {
    try {
      AppLogger.info('Processing NCB payout: $payoutId, amount=$amount');

      final response = await _supabaseClient.functions.invoke(
        'ncb-process-payout',
        body: {
          'amount': amount,
          'currency': 'JMD',
          'name': recipientName,
          'bank_account': bankAccount,
          'bank_name': bankName,
          'description': description ?? 'Payout $payoutId',
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected NCB payout response');
      }

      final status = data['status'] as String?;
      if (status != 'success') {
        throw Exception(data['error'] ?? 'NCB payout failed');
      }

      AppLogger.info('NCB payout successful: ${data['payout_reference']}');
      return data;
    } catch (e) {
      AppLogger.error('NCB payout error: $e');
      rethrow;
    }
  }
}
