import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wallet_model.dart';
import '../services/payment/wallet_service.dart';
import 'auth_provider.dart';

final walletServiceProvider = Provider<WalletService>((ref) {
  return WalletService(Supabase.instance.client);
});

/// Current user's wallet (auto-refreshes)
final walletProvider = FutureProvider.autoDispose<Wallet?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  final service = ref.watch(walletServiceProvider);
  return service.getWallet(userId);
});

/// Wallet transaction history
final walletTransactionsProvider = FutureProvider.autoDispose<List<WalletTransaction>>((
  ref,
) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];
  final service = ref.watch(walletServiceProvider);
  return service.getTransactions(userId);
});

/// Notifier for wallet actions (deposit, pay, etc.)
class WalletNotifier extends StateNotifier<AsyncValue<Wallet?>> {
  final WalletService _service;
  final String? _userId;

  WalletNotifier(this._service, this._userId)
    : super(const AsyncValue.loading()) {
    if (_userId != null) _load();
  }

  Future<void> _load() async {
    if (_userId == null) return;
    state = const AsyncValue.loading();
    try {
      final wallet = await _service.getWallet(_userId);
      state = AsyncValue.data(wallet);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  Future<Wallet?> deposit(double amount, {String method = 'card'}) async {
    if (_userId == null) return null;
    final wallet = await _service.deposit(_userId, amount, method: method);
    if (wallet != null) state = AsyncValue.data(wallet);
    return wallet;
  }

  Future<Wallet?> payWithWallet(double amount, String orderId) async {
    if (_userId == null) return null;
    final wallet = await _service.payWithWallet(_userId, amount, orderId);
    if (wallet != null) state = AsyncValue.data(wallet);
    return wallet;
  }

  Future<Wallet> transfer({
    required String recipientWalletId,
    required double amount,
    String? note,
  }) async {
    if (_userId == null) throw Exception('Not logged in');
    final wallet = await _service.transferFunds(
      senderUserId: _userId,
      recipientWalletId: recipientWalletId,
      amount: amount,
      note: note,
    );
    state = AsyncValue.data(wallet);
    return wallet;
  }

  Future<Map<String, dynamic>> cancelOrder(
    String orderId, {
    String? refundMethod,
  }) async {
    if (_userId == null) throw Exception('Not logged in');
    final result = await _service.cancelOrderWithPenalty(
      orderId,
      _userId,
      refundMethod,
    );
    await _load(); // Refresh balance after potential penalty
    return result;
  }
}

final walletNotifierProvider =
    StateNotifierProvider<WalletNotifier, AsyncValue<Wallet?>>((ref) {
      final service = ref.watch(walletServiceProvider);
      final userId = ref.watch(currentUserIdProvider);
      return WalletNotifier(service, userId);
    });
