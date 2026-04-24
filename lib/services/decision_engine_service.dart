import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class UserPromo {
  final String id; // user_promotions.id
  final String promoId;
  final String type; // 'discount' | 'free_delivery' | 'fixed'
  final double value;
  final double minOrder;
  final String targetSegment;
  final String? label;

  const UserPromo({
    required this.id,
    required this.promoId,
    required this.type,
    required this.value,
    required this.minOrder,
    required this.targetSegment,
    this.label,
  });

  factory UserPromo.fromJson(Map<String, dynamic> j) {
    final p = j['promotions'] as Map<String, dynamic>? ?? {};
    return UserPromo(
      id: j['id'] as String,
      promoId: j['promotion_id'] as String,
      type: p['type'] as String? ?? 'discount',
      value: (p['value'] as num?)?.toDouble() ?? 0.0,
      minOrder: (p['min_order'] as num?)?.toDouble() ?? 0.0,
      targetSegment: p['target_segment'] as String? ?? '',
      label: p['label'] as String?,
    );
  }

  /// Discount amount applied to [subtotal].
  double computeDiscount(double subtotal) {
    if (subtotal < minOrder) return 0.0;
    switch (type) {
      case 'discount':
        return subtotal * (value / 100);
      case 'fixed':
        return value;
      default:
        return 0.0;
    }
  }

  bool get isFreeDelivery => type == 'free_delivery';
}

class SegmentRow {
  final String segment;
  final int userCount;
  final double pct;

  const SegmentRow({
    required this.segment,
    required this.userCount,
    required this.pct,
  });

  factory SegmentRow.fromJson(Map<String, dynamic> j) => SegmentRow(
    segment: j['segment'] as String,
    userCount: (j['user_count'] as num).toInt(),
    pct: (j['pct'] as num).toDouble(),
  );
}

class PromoStat {
  final String promotionId;
  final String? label;
  final String type;
  final double value;
  final String targetSegment;
  final int sent;
  final int used;
  final double conversionRate;
  final double revenueGenerated;

  const PromoStat({
    required this.promotionId,
    this.label,
    required this.type,
    required this.value,
    required this.targetSegment,
    required this.sent,
    required this.used,
    required this.conversionRate,
    required this.revenueGenerated,
  });

  factory PromoStat.fromJson(Map<String, dynamic> j) => PromoStat(
    promotionId: j['promotion_id'] as String,
    label: j['label'] as String?,
    type: j['type'] as String? ?? 'discount',
    value: (j['value'] as num?)?.toDouble() ?? 0.0,
    targetSegment: j['target_segment'] as String? ?? '',
    sent: (j['sent'] as num?)?.toInt() ?? 0,
    used: (j['used'] as num?)?.toInt() ?? 0,
    conversionRate: (j['conversion_rate'] as num?)?.toDouble() ?? 0.0,
    revenueGenerated: (j['revenue_generated'] as num?)?.toDouble() ?? 0.0,
  );
}

// ── Service ───────────────────────────────────────────────────────────────────

class DecisionEngineService {
  final SupabaseClient _client;
  DecisionEngineService(this._client);

  /// First unused AI-assigned promo for current user, or null.
  Future<UserPromo?> getUserPromo(String userId) async {
    try {
      final res = await _client
          .from('user_promotions')
          .select('*, promotions(*)')
          .eq('user_id', userId)
          .eq('used', false)
          .limit(1);
      if (res.isEmpty) return null;
      return UserPromo.fromJson(Map<String, dynamic>.from(res.first as Map));
    } catch (e) {
      AppLogger.error('[DecisionEngine] getUserPromo error: $e');
      return null; // non-fatal
    }
  }

  /// Mark a user_promotions row as used.
  Future<void> markPromoUsed(String userPromoId) async {
    try {
      await _client
          .from('user_promotions')
          .update({'used': true, 'used_at': DateTime.now().toIso8601String()})
          .eq('id', userPromoId);
    } catch (e) {
      AppLogger.error('[DecisionEngine] markPromoUsed error: $e');
    }
  }

  /// Dynamic delivery fee from supply/demand RPC. Falls back to [baseFee].
  Future<double> getDynamicDeliveryFee(double baseFee) async {
    try {
      final result = await _client.rpc(
        'get_dynamic_delivery_fee',
        params: {'base_fee': baseFee},
      );
      return (result as num?)?.toDouble() ?? baseFee;
    } catch (e) {
      AppLogger.error('[DecisionEngine] getDynamicDeliveryFee error: $e');
      return baseFee;
    }
  }

  /// Segment distribution — admin panel.
  Future<List<SegmentRow>> getSegmentDistribution() async {
    try {
      final data = await _client.rpc('get_segment_distribution') as List;
      return data
          .map((e) => SegmentRow.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      AppLogger.error('[DecisionEngine] getSegmentDistribution error: $e');
      rethrow;
    }
  }

  /// Promo performance — admin panel.
  Future<List<PromoStat>> getPromotionStats() async {
    try {
      final data = await _client.rpc('get_promotion_stats') as List;
      return data
          .map((e) => PromoStat.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      AppLogger.error('[DecisionEngine] getPromotionStats error: $e');
      rethrow;
    }
  }

  /// Trigger a full engine refresh (admin, calls service-role RPC).
  Future<void> runDecisionEngine() async {
    try {
      await _client.rpc('run_decision_engine');
    } catch (e) {
      AppLogger.error('[DecisionEngine] runDecisionEngine error: $e');
      rethrow;
    }
  }

  /// Rule-based recommendation string for the admin AI panel.
  static String buildRecommendation({
    required List<SegmentRow> segments,
    required List<PromoStat> promos,
  }) {
    final total = segments.fold<int>(0, (s, r) => s + r.userCount);
    if (total == 0)
      return 'No user data yet — run the engine to generate segments.';

    final atRisk = segments
        .where((s) => s.segment == 'at_risk')
        .fold<int>(0, (s, r) => s + r.userCount);
    final atRiskPct = atRisk * 100.0 / total;

    final loyal = segments
        .where((s) => s.segment == 'loyal')
        .fold<int>(0, (s, r) => s + r.userCount);

    // Kill underperforming promos first
    final badPromos = promos
        .where((p) => p.sent > 10 && p.conversionRate < 0.05)
        .toList();
    if (badPromos.isNotEmpty) {
      return '${badPromos.length} promo(s) under 5% conversion — pause them and test new offers.';
    }

    if (atRiskPct > 30) {
      return '$atRisk users (${atRiskPct.toStringAsFixed(0)}%) haven\'t ordered in 14+ days — activate comeback offers now.';
    }

    if (loyal > 50) {
      return '$loyal loyal users identified — push free delivery or upsell promos to them.';
    }

    final bestPromo = promos.isEmpty
        ? null
        : promos.reduce(
            (a, b) => a.revenueGenerated > b.revenueGenerated ? a : b,
          );
    if (bestPromo != null && bestPromo.conversionRate > 0.2) {
      return '"${bestPromo.label ?? bestPromo.targetSegment}" converting at ${(bestPromo.conversionRate * 100).toStringAsFixed(0)}% — scale it.';
    }

    return 'Engine healthy. Monitor retention weekly; adjust promo values as conversion data accumulates.';
  }
}
