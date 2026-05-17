import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';
import '../models/saved_card_model.dart';
import '../services/payment/payment_service.dart';

/// Payment processing state
class PaymentState {
  final bool isProcessing;
  final PaymentResponse? lastPayment;
  final String? error;
  final String selectedMethod; // 'card', 'mobile_money', 'cash'

  PaymentState({
    this.isProcessing = false,
    this.lastPayment,
    this.error,
    this.selectedMethod = 'card',
  });

  PaymentState copyWith({
    bool? isProcessing,
    PaymentResponse? lastPayment,
    String? error,
    String? selectedMethod,
  }) {
    return PaymentState(
      isProcessing: isProcessing ?? this.isProcessing,
      lastPayment: lastPayment ?? this.lastPayment,
      error: error ?? this.error,
      selectedMethod: selectedMethod ?? this.selectedMethod,
    );
  }
}

/// Payment notifier for managing payment flow
class PaymentNotifier extends StateNotifier<PaymentState> {
  final PaymentService _paymentService;

  PaymentNotifier(this._paymentService) : super(PaymentState());

  /// Process payment
  Future<bool> processPayment({
    required String orderId,
    required double amount,
    required String userEmail,
    required String userPhone,
    String? cardToken,
    String? cardLast4,
  }) async {
    try {
      state = state.copyWith(isProcessing: true, error: null);

      PaymentMethod method = _getPaymentMethod(state.selectedMethod);

      final response = await _paymentService.processPayment(
        orderId: orderId,
        amount: amount,
        paymentMethod: method,
        userEmail: userEmail,
        userPhone: userPhone,
        cardToken: cardToken,
        cardLast4: cardLast4,
      );

      state = state.copyWith(
        isProcessing: false,
        lastPayment: response,
        error: response.success ? null : response.errorMessage,
      );

      return response.success;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return false;
    }
  }

  /// Select payment method
  void selectPaymentMethod(String method) {
    state = state.copyWith(selectedMethod: method);
  }

  /// Refund payment
  Future<bool> refundPayment({
    required String transactionId,
    required double amount,
    String? reason,
  }) async {
    try {
      state = state.copyWith(isProcessing: true);

      final success = await _paymentService.refundPayment(
        transactionId: transactionId,
        amount: amount,
        reason: reason,
      );

      state = state.copyWith(isProcessing: false);
      return success;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return false;
    }
  }

  /// Verify payment
  Future<String> verifyPayment(String transactionId) async {
    try {
      return await _paymentService.verifyPaymentStatus(transactionId);
    } catch (e) {
      return 'failed';
    }
  }

  /// Calculate total with fees
  double calculateTotalWithFees({required double amount}) {
    PaymentMethod method = _getPaymentMethod(state.selectedMethod);
    double fee = _paymentService.calculatePaymentFee(
      amount: amount,
      paymentMethod: method,
    );
    return amount + fee;
  }

  /// Get payment method enum
  PaymentMethod _getPaymentMethod(String method) {
    switch (method) {
      case 'card':
        return PaymentMethod.card;
      case 'cash':
        return PaymentMethod.cash;
      default:
        return PaymentMethod.card;
    }
  }

  /// Reset payment state
  void reset() {
    state = PaymentState();
  }
}

/// Payment service provider
final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService(supabaseClient: SupabaseConfig.client);
});

/// Payment state notifier provider
final paymentNotifierProvider =
    StateNotifierProvider<PaymentNotifier, PaymentState>((ref) {
      final paymentService = ref.watch(paymentServiceProvider);
      return PaymentNotifier(paymentService);
    });

/// Saved cards provider – fetches cards for a given user id
final savedCardsProvider = FutureProvider.family<List<SavedCard>, String>((
  ref,
  userId,
) async {
  final paymentService = ref.watch(paymentServiceProvider);
  return paymentService.getSavedCards(userId);
});

/// Last payment response provider
final lastPaymentProvider = Provider<PaymentResponse?>((ref) {
  final paymentState = ref.watch(paymentNotifierProvider);
  return paymentState.lastPayment;
});

/// Payment processing status provider
final isPaymentProcessingProvider = Provider<bool>((ref) {
  final paymentState = ref.watch(paymentNotifierProvider);
  return paymentState.isProcessing;
});

/// Payment error provider
final paymentErrorProvider = Provider<String?>((ref) {
  final paymentState = ref.watch(paymentNotifierProvider);
  return paymentState.error;
});

/// Selected payment method provider
final selectedPaymentMethodProvider = Provider<String>((ref) {
  final paymentState = ref.watch(paymentNotifierProvider);
  return paymentState.selectedMethod;
});
