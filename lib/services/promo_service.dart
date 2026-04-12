import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/promo_model.dart';
import '../utils/app_logger.dart';

class PromoService {
  final SupabaseClient _client;
  PromoService(this._client);

  Future<PromoCode?> validateCode(String code, double subtotal) async {
    try {
      final res = await _client
          .from('promo_codes')
          .select()
          .eq('code', code.toUpperCase())
          .eq('is_active', true)
          .maybeSingle();
      if (res == null) return null;
      final promo = PromoCode.fromJson(res);
      return promo.isValid(subtotal) ? promo : null;
    } catch (e) {
      AppLogger.error('Error validating promo code: $e');
      return null;
    }
  }

  Future<void> markUsed(String promoId) async {
    try {
      await _client.rpc('increment_promo_usage', params: {'promo_id': promoId});
    } catch (e) {
      AppLogger.error('Error marking promo used: $e');
    }
  }

  Future<List<PromoCode>> listAll() async {
    final res = await _client
        .from('promo_codes')
        .select()
        .order('created_at', ascending: false);
    return (res as List).map((e) => PromoCode.fromJson(e)).toList();
  }

  Future<void> createPromo({
    required String code,
    required String discountType,
    required double discountValue,
    double? minOrderAmount,
    int? maxUses,
    DateTime? expiresAt,
  }) async {
    await _client.from('promo_codes').insert({
      'code': code.toUpperCase(),
      'discount_type': discountType,
      'discount_value': discountValue,
      'min_order_amount': ?minOrderAmount,
      'max_uses': ?maxUses,
      if (expiresAt != null) 'expires_at': expiresAt.toIso8601String(),
      'is_active': true,
    });
  }

  Future<void> toggleActive(String promoId, bool isActive) async {
    await _client
        .from('promo_codes')
        .update({'is_active': isActive})
        .eq('id', promoId);
  }

  Future<void> deletePromo(String promoId) async {
    await _client.from('promo_codes').delete().eq('id', promoId);
  }
}
