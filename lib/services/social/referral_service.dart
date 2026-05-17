import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_logger.dart';

class ReferralService {
  final SupabaseClient _client;
  ReferralService(this._client);

  /// Generate a random 8-character alphanumeric code
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Get the current user's referral code, auto-generating one if missing
  Future<String?> getReferralCode(String userId) async {
    try {
      final res = await _client
          .from('users')
          .select('referral_code')
          .eq('id', userId)
          .maybeSingle();
      final existing = res?['referral_code'] as String?;
      if (existing != null && existing.isNotEmpty) return existing;

      // No code yet — generate one, ensuring uniqueness
      String code;
      do {
        code = _generateCode();
        final conflict = await _client
            .from('users')
            .select('id')
            .eq('referral_code', code)
            .maybeSingle();
        if (conflict == null) break;
      } while (true);

      await _client
          .from('users')
          .update({'referral_code': code})
          .eq('id', userId);

      return code;
    } catch (e) {
      AppLogger.error('Error getting referral code: $e');
      return null;
    }
  }

  /// Apply a referral code during sign-up
  Future<bool> applyReferralCode(String code, String referredUserId) async {
    try {
      // Find the referrer
      final referrer = await _client
          .from('users')
          .select('id')
          .eq('referral_code', code.toUpperCase())
          .maybeSingle();

      if (referrer == null) return false;

      final referrerId = referrer['id'] as String;
      if (referrerId == referredUserId) return false; // Can't refer yourself

      // Create referral record
      await _client.from('referrals').insert({
        'referrer_id': referrerId,
        'referred_id': referredUserId,
        'code': code.toUpperCase(),
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String(),
      });

      // Update referred user
      await _client
          .from('users')
          .update({'referred_by': referrerId})
          .eq('id', referredUserId);

      AppLogger.info('Referral applied: $code for user $referredUserId');
      return true;
    } catch (e) {
      AppLogger.error('Error applying referral: $e');
      return false;
    }
  }

  /// Get referral stats for a user
  Future<Map<String, dynamic>> getReferralStats(String userId) async {
    try {
      final referrals = await _client
          .from('referrals')
          .select()
          .eq('referrer_id', userId);

      final total = (referrals as List).length;
      final completed = referrals
          .where((r) => r['status'] == 'completed')
          .length;

      return {
        'total_referrals': total,
        'completed_referrals': completed,
        'pending_referrals': total - completed,
      };
    } catch (e) {
      AppLogger.error('Error getting referral stats: $e');
      return {
        'total_referrals': 0,
        'completed_referrals': 0,
        'pending_referrals': 0,
      };
    }
  }

  /// Get list of referred users
  Future<List<Map<String, dynamic>>> getReferredUsers(String userId) async {
    try {
      final res = await _client
          .from('referrals')
          .select(
            'id, code, status, created_at, completed_at, referred_id, users!referrals_referred_id_fkey(name, email)',
          )
          .eq('referrer_id', userId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      AppLogger.error('Error getting referred users: $e');
      return [];
    }
  }
}
