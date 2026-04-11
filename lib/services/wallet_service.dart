import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wallet_model.dart';
import '../utils/app_logger.dart';

class WalletService {
  final SupabaseClient _client;
  WalletService(this._client);

  /// Get user's wallet (creates one if it doesn't exist)
  Future<Wallet> getWallet(String userId) async {
    try {
      final row = await _client
          .from('wallets')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (row != null) return Wallet.fromJson(row);

      // Create wallet if it doesn't exist
      final newRow = await _client
          .from('wallets')
          .insert({'user_id': userId})
          .select()
          .single();
      return Wallet.fromJson(newRow);
    } catch (e) {
      AppLogger.error('Error getting wallet: $e');
      return Wallet.empty(userId);
    }
  }

  /// Add funds to wallet via RPC
  Future<Wallet?> deposit(
    String userId,
    double amount, {
    String method = 'card',
  }) async {
    try {
      final result = await _client.rpc(
        'wallet_deposit',
        params: {'p_user_id': userId, 'p_amount': amount, 'p_method': method},
      );
      final data = result as Map<String, dynamic>;
      return Wallet(
        userId: userId,
        balance: (data['balance'] as num).toDouble(),
        cashbackBalance: (data['cashback_balance'] as num).toDouble(),
      );
    } catch (e) {
      AppLogger.error('Error depositing to wallet: $e');
      rethrow;
    }
  }

  /// Pay from wallet
  Future<Wallet?> payWithWallet(
    String userId,
    double amount,
    String orderId,
  ) async {
    try {
      final result = await _client.rpc(
        'wallet_pay',
        params: {
          'p_user_id': userId,
          'p_amount': amount,
          'p_order_id': orderId,
        },
      );
      final data = result as Map<String, dynamic>;
      return Wallet(
        userId: userId,
        balance: (data['balance'] as num).toDouble(),
        cashbackBalance: (data['cashback_balance'] as num).toDouble(),
      );
    } catch (e) {
      AppLogger.error('Error paying with wallet: $e');
      rethrow;
    }
  }

  /// Get transaction history
  Future<List<WalletTransaction>> getTransactions(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final rows = await _client
          .from('wallet_transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error getting transactions: $e');
      return [];
    }
  }

  /// Cancel order with penalty
  Future<Map<String, dynamic>> cancelOrderWithPenalty(
    String orderId,
    String userId,
  ) async {
    try {
      final result = await _client.rpc(
        'cancel_order_with_penalty',
        params: {'p_order_id': orderId, 'p_user_id': userId},
      );
      return result as Map<String, dynamic>;
    } catch (e) {
      AppLogger.error('Error cancelling with penalty: $e');
      rethrow;
    }
  }
}
