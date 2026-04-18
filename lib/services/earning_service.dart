import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/earning_model.dart';
import '../utils/app_logger.dart';

class EarningService {
  final SupabaseClient _client;
  EarningService(this._client);

  // ── Account ──────────────────────────────────────────────────

  /// Get or auto-create a user's earning account
  Future<EarningAccount?> getAccount(String userId) async {
    try {
      final res = await _client
          .from('earning_accounts')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (res != null) return EarningAccount.fromJson(res);

      // Auto-create
      final created = await _client
          .from('earning_accounts')
          .insert({'user_id': userId})
          .select()
          .single();
      return EarningAccount.fromJson(created);
    } catch (e) {
      AppLogger.error('Error getting earning account: $e');
      return null;
    }
  }

  // ── Transactions ──────────────────────────────────────────────

  /// Get earning transactions for a user (recent first)
  Future<List<EarningTransaction>> getTransactions(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final res = await _client
          .from('earning_transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return (res as List).map((e) => EarningTransaction.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error getting earning transactions: $e');
      return [];
    }
  }

  // ── Process referral earnings (called after order delivered) ──

  /// Process earnings for an order from a referred customer
  Future<Map<String, dynamic>> processOrderEarnings({
    required String orderId,
    required String customerId,
  }) async {
    try {
      final result = await _client.rpc(
        'process_order_referral_earnings',
        params: {'p_order_id': orderId, 'p_customer_id': customerId},
      );
      AppLogger.info('Order earning processed: $result');
      return result is Map<String, dynamic> ? result : {};
    } catch (e) {
      AppLogger.error('Error processing order earnings: $e');
      return {};
    }
  }

  /// Process signup referral bonus (called after first order)
  Future<Map<String, dynamic>> processSignupBonus(String userId) async {
    try {
      final result = await _client.rpc(
        'process_signup_referral_bonus',
        params: {'p_referred_user_id': userId},
      );
      AppLogger.info('Signup bonus processed: $result');
      return result is Map<String, dynamic> ? result : {};
    } catch (e) {
      AppLogger.error('Error processing signup bonus: $e');
      return {};
    }
  }

  /// Check and award volume bonuses
  Future<Map<String, dynamic>> checkVolumeBonus(String userId) async {
    try {
      final result = await _client.rpc(
        'process_volume_bonus',
        params: {'p_user_id': userId},
      );
      return result is Map<String, dynamic> ? result : {};
    } catch (e) {
      AppLogger.error('Error checking volume bonus: $e');
      return {};
    }
  }

  /// Expire old credits (admin action or cron)
  Future<int> expireOldCredits() async {
    try {
      final result = await _client.rpc('expire_old_credits');
      return result is int ? result : 0;
    } catch (e) {
      AppLogger.error('Error expiring credits: $e');
      return 0;
    }
  }

  // ── Referred users with earning context ──────────────────────

  /// Get direct referrals with their order counts
  Future<List<Map<String, dynamic>>> getDirectReferrals(String userId) async {
    try {
      final referrals = await _client
          .from('referrals')
          .select('referred_id, status, reward_given, completed_at')
          .eq('referrer_id', userId)
          .eq('status', 'completed');

      final results = <Map<String, dynamic>>[];
      for (final ref in (referrals as List)) {
        final refId = ref['referred_id'] as String?;
        if (refId == null) continue;

        // Get user info
        final user = await _client
            .from('users')
            .select('name, email, profile_image_url')
            .eq('id', refId)
            .maybeSingle();

        // Count their completed orders
        final orderCount = await _client
            .from('orders')
            .select('id')
            .eq('user_id', refId)
            .eq('status', 'delivered')
            .count();

        results.add({
          'user_id': refId,
          'name': user?['name'] ?? 'User',
          'email': user?['email'] ?? '',
          'profile_image_url': user?['profile_image_url'],
          'order_count': orderCount.count,
          'reward_given': ref['reward_given'] ?? false,
          'joined_at': ref['completed_at'],
        });
      }
      return results;
    } catch (e) {
      AppLogger.error('Error getting direct referrals: $e');
      return [];
    }
  }

  // ── Admin: get all earning accounts ──────────────────────────

  Future<List<EarningAccount>> getAllAccounts({
    int offset = 0,
    int limit = 50,
  }) async {
    try {
      final res = await _client
          .from('earning_accounts')
          .select('*, users:user_id(name)')
          .order('total_earned', ascending: false)
          .range(offset, offset + limit - 1);
      return (res as List).map((e) => EarningAccount.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error getting all earning accounts: $e');
      return [];
    }
  }

  /// Admin: manual credit adjustment
  Future<void> adminAdjustCredit({
    required String userId,
    required double amount,
    required String description,
  }) async {
    try {
      await _client.rpc(
        'credit_earning',
        params: {
          'p_user_id': userId,
          'p_amount': amount,
          'p_type': 'adjustment',
          'p_description': description,
          'p_expiry_days': EarningConfig.creditExpiryDays,
        },
      );
    } catch (e) {
      AppLogger.error('Error adjusting credits: $e');
      rethrow;
    }
  }
}
