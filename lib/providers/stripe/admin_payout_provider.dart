import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/stripe/payout_request_model.dart';
import '../../services/stripe/payout_service.dart';
import 'earnings_provider.dart' show stripePayoutServiceProvider;

// ----------------------------------------------------------------
// State class
// ----------------------------------------------------------------

class AdminPayoutState {
  final List<PayoutRequest> payouts;
  final bool isLoading;
  final String? error;
  final String currentFilter;

  const AdminPayoutState({
    required this.payouts,
    this.isLoading = false,
    this.error,
    this.currentFilter = 'requested',
  });

  AdminPayoutState copyWith({
    List<PayoutRequest>? payouts,
    bool? isLoading,
    String? error,
    String? currentFilter,
    bool clearError = false,
  }) =>
      AdminPayoutState(
        payouts: payouts ?? this.payouts,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        currentFilter: currentFilter ?? this.currentFilter,
      );
}

// ----------------------------------------------------------------
// Notifier
// ----------------------------------------------------------------

class AdminPayoutNotifier extends StateNotifier<AdminPayoutState> {
  AdminPayoutNotifier(this._service)
      : super(const AdminPayoutState(
          payouts: [],
          isLoading: true,
          currentFilter: 'requested',
        )) {
    load();
  }

  final StripePayoutService _service;

  Future<void> load({String? status}) async {
    final filter = status ?? state.currentFilter;
    state = state.copyWith(isLoading: true, currentFilter: filter, clearError: true);
    try {
      final payouts = await _service.getAllPayoutRequests(status: filter);
      state = state.copyWith(payouts: payouts, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> approve(String id, {String? note}) async {
    state = state.copyWith(clearError: true);
    try {
      await _service.approvePayout(payoutRequestId: id, adminNote: note);
      await load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> reject(String id, {required String note}) async {
    state = state.copyWith(clearError: true);
    try {
      await _service.rejectPayout(payoutRequestId: id, adminNote: note);
      await load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> retry(String id) async {
    state = state.copyWith(clearError: true);
    try {
      await _service.retryPayout(payoutRequestId: id);
      await load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

// ----------------------------------------------------------------
// Provider
// ----------------------------------------------------------------

final adminPayoutProvider =
    StateNotifierProvider<AdminPayoutNotifier, AdminPayoutState>(
  (ref) => AdminPayoutNotifier(ref.watch(stripePayoutServiceProvider)),
);
