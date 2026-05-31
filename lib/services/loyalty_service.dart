import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../models/loyalty_model.dart';
import '../utils/app_logger.dart';

class LoyaltyService {
  final SupabaseClient _client;
  LoyaltyService(this._client);

  /// Points earned per \$100 spent (DB-driven via AppConstants)
  static int computeEarnedPoints(double orderTotal) =>
      (orderTotal / 100 * AppConstants.loyaltyPointsPer100).floor();

  Future<LoyaltyAccount?> getAccount(String userId) async {
    try {
      final res = await _client
          .from('loyalty_accounts')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      return res != null ? LoyaltyAccount.fromJson(res) : null;
    } catch (e) {
      AppLogger.error('Error getting loyalty account: $e');
      return null;
    }
  }

  Future<LoyaltyAccount> getOrCreateAccount(String userId) async {
    try {
      final existing = await getAccount(userId);
      if (existing != null) return existing;
      final res = await _client
          .from('loyalty_accounts')
          .insert({'user_id': userId, 'points': 0})
          .select()
          .single();
      return LoyaltyAccount.fromJson(res);
    } catch (e) {
      AppLogger.error('Error getting/creating loyalty account: $e');
      return LoyaltyAccount(
        id: '',
        userId: userId,
        points: 0,
        totalEarned: 0,
        totalRedeemed: 0,
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<void> earnPoints({
    required String userId,
    required String orderId,
    required double orderTotal,
    String description = 'Earned from order',
  }) async {
    try {
      final pts = computeEarnedPoints(orderTotal);
      if (pts <= 0) return;
      await _client.rpc(
        'add_loyalty_points',
        params: {
          'p_user_id': userId,
          'p_points': pts,
          'p_order_id': orderId,
          'p_type': 'earn',
          'p_description': description,
        },
      );
    } catch (e) {
      AppLogger.error('Error earning loyalty points: $e');
    }
  }

  Future<void> redeemPoints({
    required String userId,
    required String orderId,
    required int points,
  }) async {
    try {
      await _client.rpc(
        'add_loyalty_points',
        params: {
          'p_user_id': userId,
          'p_points': -points,
          'p_order_id': orderId,
          'p_type': 'redeem',
          'p_description': 'Redeemed at checkout',
        },
      );
    } catch (e) {
      AppLogger.error('Error redeeming loyalty points: $e');
      rethrow;
    }
  }

  Future<List<LoyaltyTransaction>> getTransactions(String userId) async {
    try {
      final res = await _client
          .from('loyalty_transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      return (res as List).map((e) => LoyaltyTransaction.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error getting loyalty transactions: $e');
      return [];
    }
  }
}
