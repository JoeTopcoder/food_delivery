import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/stripe/connected_account_model.dart';
import '../../services/stripe/stripe_connect_service.dart';

// ----------------------------------------------------------------
// Service provider
// ----------------------------------------------------------------

final stripeConnectServiceProvider = Provider<StripeConnectService>(
  (ref) => StripeConnectService(Supabase.instance.client),
);

// ----------------------------------------------------------------
// State class
// ----------------------------------------------------------------

class ConnectedAccountState {
  final ConnectedAccount? account;
  final Map<String, dynamic>? refreshStatus;
  final bool isLoading;
  final String? error;

  const ConnectedAccountState({
    this.account,
    this.refreshStatus,
    this.isLoading = false,
    this.error,
  });

  bool get hasAccount => account != null;
  bool get isComplete => account?.isComplete ?? false;

  ConnectedAccountState copyWith({
    ConnectedAccount? account,
    Map<String, dynamic>? refreshStatus,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      ConnectedAccountState(
        account: account ?? this.account,
        refreshStatus: refreshStatus ?? this.refreshStatus,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

// ----------------------------------------------------------------
// Notifier
// ----------------------------------------------------------------

class ConnectedAccountNotifier
    extends StateNotifier<ConnectedAccountState> {
  ConnectedAccountNotifier(this._service, this._userId)
      : super(const ConnectedAccountState(isLoading: true)) {
    _load();
  }

  final StripeConnectService _service;
  final String _userId;

  Future<void> _load({String role = 'driver'}) async {
    try {
      final account =
          await _service.getConnectedAccount(userId: _userId, role: role);
      state = ConnectedAccountState(account: account);
    } catch (e) {
      state = ConnectedAccountState(error: e.toString());
    }
  }

  /// Create a new Stripe Express account for the user.
  Future<void> setupAccount({
    required String role,
    String country = 'US',
    String currency = 'usd',
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final account = await _service.createConnectAccount(
        role: role,
        country: country,
        currency: currency,
      );
      state = ConnectedAccountState(account: account);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Generate an onboarding URL for Stripe Connect Express.
  Future<String?> getOnboardingUrl({required String role}) async {
    try {
      return await _service.createAccountLink(role: role);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Refresh account status from Stripe (call after returning from onboarding URL).
  Future<void> refreshStatus({required String role}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final status = await _service.refreshConnectAccount(role: role);
      final account =
          await _service.getConnectedAccount(userId: _userId, role: role);
      state = ConnectedAccountState(account: account, refreshStatus: status);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Reload the account from Supabase (no Stripe API call).
  Future<void> reload({required String role}) => _load(role: role);

  void clearError() => state = state.copyWith(clearError: true);
}

// ----------------------------------------------------------------
// Provider — keyed by userId so different users get isolated state
// ----------------------------------------------------------------

final connectedAccountProvider = StateNotifierProvider.family<
    ConnectedAccountNotifier,
    ConnectedAccountState,
    String>(
  (ref, userId) => ConnectedAccountNotifier(
    ref.watch(stripeConnectServiceProvider),
    userId,
  ),
);
