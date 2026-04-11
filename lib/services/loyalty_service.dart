import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../models/loyalty_model.dart';

class LoyaltyService {
  final SupabaseClient _client;
  LoyaltyService(this._client);

  /// Points earned per \$100 spent (DB-driven via AppConstants)
  static int computeEarnedPoints(double orderTotal) =>
      (orderTotal / 100 * AppConstants.loyaltyPointsPer100).floor();

  Future<LoyaltyAccount?> getAccount(String userId) async {
    final res = await _client
        .from('loyalty_accounts')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return res != null ? LoyaltyAccount.fromJson(res) : null;
  }

  Future<LoyaltyAccount> getOrCreateAccount(String userId) async {
    final existing = await getAccount(userId);
    if (existing != null) return existing;
    final res = await _client
        .from('loyalty_accounts')
        .insert({'user_id': userId, 'points': 0})
        .select()
        .single();
    return LoyaltyAccount.fromJson(res);
  }

  Future<void> earnPoints({
    required String userId,
    required String orderId,
    required double orderTotal,
  }) async {
    final pts = computeEarnedPoints(orderTotal);
    if (pts <= 0) return;
    await _client.rpc(
      'add_loyalty_points',
      params: {
        'p_user_id': userId,
        'p_points': pts,
        'p_order_id': orderId,
        'p_type': 'earn',
        'p_description': 'Earned from order',
      },
    );
  }

  Future<void> redeemPoints({
    required String userId,
    required String orderId,
    required int points,
  }) async {
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
  }

  Future<List<LoyaltyTransaction>> getTransactions(String userId) async {
    final res = await _client
        .from('loyalty_transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return (res as List).map((e) => LoyaltyTransaction.fromJson(e)).toList();
  }
}
