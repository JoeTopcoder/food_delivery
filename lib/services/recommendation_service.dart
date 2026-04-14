import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/recommendation_model.dart';
import '../models/user_intelligence_model.dart';
import '../utils/app_logger.dart';

/// Core recommendation service — calls Supabase RPCs and assembles the
/// [BrainEngineResponse] that powers the smart home screen.
class RecommendationService {
  final SupabaseClient _client;

  RecommendationService(this._client);

  /// Run the full brain engine pipeline for a user:
  ///  1. Compute / refresh user intelligence profile
  ///  2. Fetch smart recommendations (scored & ranked)
  ///  3. Generate targeted coupon if applicable
  ///  4. Return assembled [BrainEngineResponse]
  Future<BrainEngineResponse> runBrainEngine({
    required String userId,
    double? latitude,
    double? longitude,
  }) async {
    try {
      // 1. Compute profile (updates DB and returns summary)
      final profileResult = await _client.rpc(
        'compute_user_profile',
        params: {'p_user_id': userId},
      );

      final profileJson = profileResult is Map<String, dynamic>
          ? profileResult
          : {};
      final segment = profileJson['segment'] as String? ?? 'new_user';
      final churnRisk = (profileJson['churn_risk'] as num?)?.toDouble() ?? 0;
      final cuisineScores = profileJson['cuisine_scores'];
      String? topCuisine;
      if (cuisineScores is Map && cuisineScores.isNotEmpty) {
        final sorted = cuisineScores.entries.toList()
          ..sort(
            (a, b) => (double.tryParse(b.value.toString()) ?? 0).compareTo(
              double.tryParse(a.value.toString()) ?? 0,
            ),
          );
        topCuisine = sorted.first.key.toString();
      }

      // 2. Get scored recommendations
      final recResults = await _client.rpc(
        'get_smart_recommendations',
        params: {
          'p_user_id': userId,
          if (latitude != null) 'p_latitude': latitude,
          if (longitude != null) 'p_longitude': longitude,
          'p_limit': 30,
        },
      );

      final allRecs = <SmartRecommendation>[];
      if (recResults is List) {
        for (final r in recResults) {
          if (r is Map<String, dynamic>) {
            allRecs.add(SmartRecommendation.fromJson(r));
          }
        }
      }

      // 3. Sort into sections
      final forYou = <SmartRecommendation>[];
      final becauseYouLove = <SmartRecommendation>[];
      final dealsForYou = <SmartRecommendation>[];
      final quickDelivery = <SmartRecommendation>[];

      for (final rec in allRecs) {
        switch (rec.section) {
          case 'because_you_love':
            becauseYouLove.add(rec);
            break;
          case 'deals_for_you':
            dealsForYou.add(rec);
            break;
          case 'quick_delivery':
            quickDelivery.add(rec);
            break;
          default:
            forYou.add(rec);
        }
      }

      // 4. Generate targeted coupon — always attempt for any user
      SmartCoupon? coupon;
      try {
        final couponResult = await _client.rpc(
          'generate_targeted_coupon',
          params: {'p_user_id': userId},
        );
        if (couponResult is Map<String, dynamic> &&
            couponResult['generated'] == true) {
          coupon = SmartCoupon.fromJson(couponResult);
        }
      } catch (e) {
        AppLogger.error('Coupon generation failed: $e');
      }

      return BrainEngineResponse(
        forYou: forYou,
        becauseYouLove: becauseYouLove,
        dealsForYou: dealsForYou,
        quickDelivery: quickDelivery,
        activeCoupon: coupon,
        userSegment: segment,
        churnRisk: churnRisk,
        topCuisine: topCuisine,
      );
    } catch (e) {
      AppLogger.error('BrainEngine.run failed: $e');
      // Return empty response so UI can still render fallback content
      return const BrainEngineResponse();
    }
  }

  /// Fetch the current intelligence profile without recomputing.
  Future<UserIntelligenceProfile?> getProfile(String userId) async {
    try {
      final result = await _client
          .from('user_intelligence_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (result == null) return null;
      return UserIntelligenceProfile.fromJson(result);
    } catch (e) {
      AppLogger.error('RecommendationService.getProfile failed: $e');
      return null;
    }
  }

  /// Fetch active (unused, unexpired) coupons for a user.
  Future<List<SmartCoupon>> getActiveCoupons(String userId) async {
    try {
      final results = await _client
          .from('user_coupons')
          .select()
          .eq('user_id', userId)
          .eq('is_used', false)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);
      return (results as List).map((r) {
        final json = r as Map<String, dynamic>;
        return SmartCoupon(
          id: json['id'] as String?,
          code: json['code'] as String? ?? '',
          discountPercent: (json['discount_percent'] as num?)?.toInt() ?? 0,
          minOrder: (json['min_order'] as num?)?.toDouble() ?? 0,
          reason: json['reason'] as String? ?? '',
        );
      }).toList();
    } catch (e) {
      AppLogger.error('RecommendationService.getActiveCoupons failed: $e');
      return [];
    }
  }

  /// Mark a coupon as used.
  Future<void> redeemCoupon(String couponId) async {
    try {
      await _client
          .from('user_coupons')
          .update({'is_used': true})
          .eq('id', couponId);
    } catch (e) {
      AppLogger.error('RecommendationService.redeemCoupon failed: $e');
    }
  }
}
