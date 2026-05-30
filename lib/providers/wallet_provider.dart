import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wallet_model.dart';
import '../services/payment/wallet_service.dart';
import '../utils/app_logger.dart';
import 'auth_provider.dart';

final walletServiceProvider = Provider<WalletService>((ref) {
  return WalletService(Supabase.instance.client);
});

// ─── Real-time wallet balance ─────────────────────────────────────────────────
// Streams the wallets row directly from Supabase Realtime.
// This is the single source of truth for balance across the whole app.

final walletBalanceStreamProvider = StreamProvider.autoDispose<Wallet?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(null);
  return Supabase.instance.client
      .from('wallets')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .map((rows) => rows.isEmpty ? null : Wallet.fromJson(rows.first));
});

// ─── Real-time transaction list ───────────────────────────────────────────────
// Re-fetches the full transaction history every time the wallet row changes.
// This avoids needing wallet_transactions in Supabase Realtime — the wallets
// table stream (above) is the trigger, and we always get a fresh ordered list.

final walletTransactionsStreamProvider =
    StreamProvider.autoDispose<List<WalletTransaction>>((ref) async* {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    yield [];
    return;
  }

  final service = ref.read(walletServiceProvider);

  // Fetch immediately so the list appears without waiting for the first
  // wallet-change event.
  try {
    yield await service.getTransactions(userId);
  } catch (e) {
    AppLogger.error('walletTransactions initial fetch: $e');
    yield [];
  }

  // Subscribe to wallet row changes. Every INSERT/UPDATE/DELETE on wallets
  // (balance top-up, reservation, settlement, refund) fires this stream, which
  // triggers a fresh transaction fetch so the history is always in sync.
  final walletStream = Supabase.instance.client
      .from('wallets')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId);

  await for (final _ in walletStream) {
    try {
      final txns = await service.getTransactions(userId);
      yield txns;
    } catch (e) {
      AppLogger.error('walletTransactions wallet-trigger fetch: $e');
    }
  }
});

// ─── Legacy one-shot providers (kept for screens that still use them) ─────────

final walletProvider = FutureProvider.autoDispose<Wallet?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(walletServiceProvider).getWallet(userId);
});

final walletTransactionsProvider =
    FutureProvider.autoDispose<List<WalletTransaction>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];
  return ref.watch(walletServiceProvider).getTransactions(userId);
});

// ─── Wallet action notifier ───────────────────────────────────────────────────
// Used for mutations (deposit, pay, transfer). After each action the underlying
// DB row changes, which fires walletBalanceStreamProvider automatically — so
// callers only need to await the action; they don't need to manually refresh.

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
      state = AsyncValue.data(await _service.getWallet(_userId));
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
    await _load();
    return result;
  }
}

final walletNotifierProvider =
    StateNotifierProvider<WalletNotifier, AsyncValue<Wallet?>>((ref) {
  final service = ref.watch(walletServiceProvider);
  final userId = ref.watch(currentUserIdProvider);
  return WalletNotifier(service, userId);
});
