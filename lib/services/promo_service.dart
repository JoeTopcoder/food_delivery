import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/promo_model.dart';
import '../utils/app_logger.dart';

class PromoService {
  final SupabaseClient _client;
  PromoService(this._client);

  Future<PromoCode?> validateCode(
    String code,
    double subtotal, {
    String? restaurantId,
    double deliveryFee = 0,
    double taxAmount = 0,
  }) async {
    try {
      // Proactively refresh JWT to avoid UNAUTHORIZED_LEGACY_JWT errors.
      try { await _client.auth.refreshSession(); } catch (_) {}

      final invokeBody = {
        'code': code.trim().toUpperCase(),
        'subtotal': subtotal,
        if (restaurantId != null) 'restaurant_id': restaurantId,
        'delivery_fee': deliveryFee,
        'tax_amount': taxAmount,
      };
      FunctionResponse res;
      try {
        res = await _client.functions.invoke('validate-promo', body: invokeBody);
      } on FunctionException catch (fe) {
        final raw = fe.details?.toString() ?? '';
        if (fe.status == 401 || fe.status == 403 ||
            raw.contains('LEGACY_JWT') || raw.contains('JWT')) {
          await _client.auth.refreshSession();
          res = await _client.functions.invoke('validate-promo', body: invokeBody);
        } else {
          rethrow;
        }
      }
      if (res.status >= 400) {
        AppLogger.error('validate-promo HTTP ${res.status}: ${res.data}');
        return null;
      }
      final raw = res.data;
      final data = raw is Map<String, dynamic>
          ? raw
          : raw is String
          ? (jsonDecode(raw) as Map<String, dynamic>?)
          : null;
      if (data == null || data['valid'] != true) {
        final serverMsg = data?['error'] as String?;
        AppLogger.error('validate-promo invalid: $serverMsg');
        // Throw so checkout screen can show the server's specific error message.
        throw Exception(serverMsg ?? 'Invalid or expired code');
      }
      final promoData = data['promo'] as Map<String, dynamic>;
      // All validation was done server-side.
      return PromoCode(
        id: promoData['id'] as String,
        code: promoData['code'] as String,
        discountType: promoData['discount_type'] as String,
        discountValue: (promoData['discount_value'] as num).toDouble(),
        appliesTo: promoData['applies_to'] as String? ?? 'subtotal',
        minOrderAmount: (promoData['min_order_amount'] as num?)?.toDouble(),
        maxUses: null,
        usedCount: 0,
        expiresAt: promoData['expires_at'] != null
            ? DateTime.parse(promoData['expires_at'] as String)
            : null,
        isActive: true,
        createdAt: DateTime.now(),
      );
    } on Exception {
      rethrow; // promo-specific errors propagate to the UI
    } catch (e) {
      AppLogger.error('Error validating promo code: $e');
      throw Exception('Could not validate code. Please try again.');
    }
  }

  Future<void> markUsed(String promoId) async {
    try {
      await _client.rpc('increment_promo_usage', params: {'promo_id': promoId});
    } catch (e) {
      AppLogger.error('Error marking promo used: $e');
    }
  }

  /// Looks up a single promo code by its code string. RLS restricts this to
  /// admins plus — via `self_select_own_birthday_promo` — a customer reading
  /// their own linked birthday reward code (see 20260713000001_birthday_campaign.sql).
  /// Returns null if not found or not visible to the current session.
  Future<PromoCode?> getByCode(String code) async {
    final res = await _client
        .from('promo_codes')
        .select()
        .eq('code', code.trim().toUpperCase())
        .maybeSingle();
    if (res == null) return null;
    return PromoCode.fromJson(res);
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
