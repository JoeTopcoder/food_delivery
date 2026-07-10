import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/stripe/earnings_summary_model.dart';
import '../../models/stripe/payout_request_model.dart';
import '../../services/stripe/earnings_service.dart';
import '../../services/stripe/payout_service.dart';

// ----------------------------------------------------------------
// Service providers
// ----------------------------------------------------------------

final earningsServiceProvider = Provider<EarningsService>(
  (ref) => EarningsService(Supabase.instance.client),
);

final stripePayoutServiceProvider = Provider<StripePayoutService>(
  (ref) => StripePayoutService(Supabase.instance.client),
);

// ----------------------------------------------------------------
// State class
// ----------------------------------------------------------------

class EarningsState {
  final EarningsSummary summary;
  final PayoutSettings? settings;
  final List<PayoutRequest> recentPayouts;
  final bool isLoading;
  final String? error;
  final String? successMessage;

  const EarningsState({
    required this.summary,
    this.settings,
    required this.recentPayouts,
    this.isLoading = false,
    this.error,
    this.successMessage,
  });

  factory EarningsState.initial() => EarningsState(
        summary: EarningsSummary.zero(),
        recentPayouts: [],
        isLoading: true,
      );

  bool get canRequestPayout =>
      settings != null &&
      summary.availableBalanceCents >= settings!.minPayoutCents;

  EarningsState copyWith({
    EarningsSummary? summary,
    PayoutSettings? settings,
    List<PayoutRequest>? recentPayouts,
    bool? isLoading,
    String? error,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
  }) =>
      EarningsState(
        summary: summary ?? this.summary,
        settings: settings ?? this.settings,
        recentPayouts: recentPayouts ?? this.recentPayouts,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        successMessage:
            clearSuccess ? null : (successMessage ?? this.successMessage),
      );
}

// ----------------------------------------------------------------
// Notifier
// ----------------------------------------------------------------

class EarningsNotifier extends StateNotifier<EarningsState> {
  EarningsNotifier(
      this._earningsService, this._payoutService, this._role)
      : super(EarningsState.initial()) {
    load();
  }

  final EarningsService _earningsService;
  final StripePayoutService _payoutService;
  final String _role;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _earningsService.getEarningsSummary(role: _role);

      final summaryJson = data['summary'] as Map<String, dynamic>?;
      final summary = summaryJson != null
          ? EarningsSummary.fromJson(summaryJson)
          : EarningsSummary.zero();

      final settingsJson = data['settings'] as Map<String, dynamic>?;
      final settings =
          settingsJson != null ? PayoutSettings.fromJson(settingsJson) : null;

      final payouts = (data['recent_payouts'] as List? ?? [])
          .map((p) => PayoutRequest.fromJson(p as Map<String, dynamic>))
          .toList();

      state = EarningsState(
        summary: summary,
        settings: settings,
        recentPayouts: payouts,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Request a payout. Returns the payout request on success, null on error.
  Future<PayoutRequest?> requestPayout({
    required int amountCents,
    String payoutMethod = 'standard',
  }) async {
    state = state.copyWith(clearError: true, clearSuccess: true);
    try {
      final pr = await _payoutService.requestPayout(
        role: _role,
        amountCents: amountCents,
        payoutMethod: payoutMethod,
      );
      // Reload to reflect locked balance
      await load();
      return pr;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
  void clearSuccess() => state = state.copyWith(clearSuccess: true);
}

// ----------------------------------------------------------------
// Provider — keyed by role ('driver' or 'restaurant')
// ----------------------------------------------------------------

final earningsProvider =
    StateNotifierProvider.family<EarningsNotifier, EarningsState, String>(
  (ref, role) => EarningsNotifier(
    ref.watch(earningsServiceProvider),
    ref.watch(stripePayoutServiceProvider),
    role,
  ),
);
