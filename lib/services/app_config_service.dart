import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../models/earning_model.dart';
import '../utils/app_logger.dart';

/// Service that loads app_config from the database and updates AppConstants.
/// Call [load] once at startup (e.g. in main.dart after Supabase init).
class AppConfigService {
  final SupabaseClient _client;
  AppConfigService(this._client);

  /// Fetches all config from the `app_config` table and hydrates
  /// [AppConstants] with the DB values. Falls back to compiled defaults on error.
  Future<void> load() async {
    try {
      AppLogger.info('[AppConfig] fetching app_config table...');
      final rows = await _client
          .from('app_config')
          .select('key, value, value_type')
          .timeout(const Duration(seconds: 5));

      AppLogger.info('[AppConfig] got ${rows.length} rows');

      if (rows.isEmpty) {
        AppLogger.info('[AppConfig] EMPTY - using defaults');
        return;
      }

      final config = <String, dynamic>{};
      for (final row in rows) {
        final key = row['key'] as String;
        final rawValue = row['value'] as String? ?? '';
        final valueType = row['value_type'] as String? ?? 'string';
        config[key] = _parseValue(rawValue, valueType);
      }

      _applyConfig(config);
      AppLogger.info(
        '[AppConfig] LOADED ${config.length} settings — '
        'deliveryBaseFee=${AppConstants.deliveryBaseFee}, '
        'deliveryPerKmFee=${AppConstants.deliveryPerKmFee}, '
        'defaultDeliveryFee=${AppConstants.defaultDeliveryFee}, '
        'minDeliveryFee=${AppConstants.minDeliveryFee}, '
        'surgeMult=${AppConstants.deliverySurgeMultiplier}',
      );
    } catch (e, st) {
      AppLogger.error('[AppConfig] FAILED: $e');
      AppLogger.error('[AppConfig] stack: $st');
    }
  }

  /// Parse a raw string value from the DB into its typed form.
  dynamic _parseValue(String raw, String valueType) {
    switch (valueType) {
      case 'number':
        return num.tryParse(raw) ?? 0;
      case 'boolean':
        return raw == 'true';
      case 'json':
        try {
          return jsonDecode(raw);
        } catch (_) {
          return raw;
        }
      default:
        return raw;
    }
  }

  void _applyConfig(Map<String, dynamic> c) {
    // Fees
    AppConstants.taxRate = _double(c, 'tax_rate', AppConstants.taxRate);
    AppConstants.defaultDeliveryFee = _double(
      c,
      'default_delivery_fee',
      AppConstants.defaultDeliveryFee,
    );
    AppConstants.driverFeePerDelivery = _double(
      c,
      'driver_fee_per_delivery',
      AppConstants.driverFeePerDelivery,
    );
    AppConstants.cardFeePercent = _double(
      c,
      'card_fee_percent',
      AppConstants.cardFeePercent,
    );
    AppConstants.bankTransferFeePercent = _double(
      c,
      'bank_transfer_fee_percent',
      AppConstants.bankTransferFeePercent,
    );
    AppConstants.cashFeePercent = _double(
      c,
      'cash_fee_percent',
      AppConstants.cashFeePercent,
    );

    // Delivery ($2–$2.50/mile pricing)
    AppConstants.deliveryBaseFee = _double(
      c,
      'delivery_base_fee',
      AppConstants.deliveryBaseFee,
    );
    AppConstants.deliveryPerMileFee = _double(
      c,
      'delivery_per_mile_fee',
      AppConstants.deliveryPerMileFee,
    );
    AppConstants.deliveryPerMileFeePeak = _double(
      c,
      'delivery_per_mile_fee_peak',
      AppConstants.deliveryPerMileFeePeak,
    );
    AppConstants.deliveryPerKmFee = _double(
      c,
      'delivery_per_km_fee',
      AppConstants.deliveryPerKmFee,
    );
    AppConstants.deliveryBaseMiles = _double(
      c,
      'delivery_base_miles',
      AppConstants.deliveryBaseMiles,
    );
    AppConstants.deliveryBaseKm = _double(
      c,
      'delivery_base_km',
      AppConstants.deliveryBaseKm,
    );
    AppConstants.deliveryMaxKm = _double(
      c,
      'delivery_max_km',
      AppConstants.deliveryMaxKm,
    );
    AppConstants.deliverySurgeMultiplier = _double(
      c,
      'delivery_surge_multiplier',
      AppConstants.deliverySurgeMultiplier,
    );
    AppConstants.driverPayPercent = _double(
      c,
      'driver_pay_percent',
      AppConstants.driverPayPercent,
    );
    AppConstants.minDeliveryFee = _double(
      c,
      'min_delivery_fee',
      AppConstants.minDeliveryFee,
    );
    AppConstants.driverBonusPerOrder = _double(
      c,
      'driver_bonus_per_order',
      AppConstants.driverBonusPerOrder,
    );

    // Driver pay rates ($1.50/mile compliance)
    AppConstants.driverRatePerMile = _double(
      c,
      'driver_rate_per_mile',
      AppConstants.driverRatePerMile,
    );
    AppConstants.driverRatePerKm = _double(
      c,
      'driver_rate_per_km',
      AppConstants.driverRatePerKm,
    );
    AppConstants.driverMinBasePay = _double(
      c,
      'driver_base_pay_minimum',
      AppConstants.driverMinBasePay,
    );

    // Peak hour pricing
    AppConstants.peakAddonFee = _double(
      c,
      'peak_addon_fee',
      AppConstants.peakAddonFee,
    );
    AppConstants.peakHoursStart = _int(
      c,
      'peak_hours_start',
      AppConstants.peakHoursStart,
    );
    AppConstants.peakHoursEnd = _int(
      c,
      'peak_hours_end',
      AppConstants.peakHoursEnd,
    );
    AppConstants.peakHoursStart2 = _int(
      c,
      'peak_hours_start_2',
      AppConstants.peakHoursStart2,
    );
    AppConstants.peakHoursEnd2 = _int(
      c,
      'peak_hours_end_2',
      AppConstants.peakHoursEnd2,
    );

    // Loyalty
    AppConstants.loyaltyPointValue = _double(
      c,
      'loyalty_point_value',
      AppConstants.loyaltyPointValue,
    );
    AppConstants.loyaltyMaxRedemptionPercent = _double(
      c,
      'loyalty_max_redemption_percent',
      AppConstants.loyaltyMaxRedemptionPercent,
    );
    AppConstants.loyaltyPointsPer100 = _int(
      c,
      'loyalty_points_per_100',
      AppConstants.loyaltyPointsPer100,
    );
    AppConstants.loyaltyTierSilverThreshold = _int(
      c,
      'loyalty_tier_silver_threshold',
      AppConstants.loyaltyTierSilverThreshold,
    );
    AppConstants.loyaltyTierGoldThreshold = _int(
      c,
      'loyalty_tier_gold_threshold',
      AppConstants.loyaltyTierGoldThreshold,
    );
    AppConstants.loyaltyTierPlatinumThreshold = _int(
      c,
      'loyalty_tier_platinum_threshold',
      AppConstants.loyaltyTierPlatinumThreshold,
    );
    AppConstants.loyaltyMultiplierBronze = _double(
      c,
      'loyalty_multiplier_bronze',
      AppConstants.loyaltyMultiplierBronze,
    );
    AppConstants.loyaltyMultiplierSilver = _double(
      c,
      'loyalty_multiplier_silver',
      AppConstants.loyaltyMultiplierSilver,
    );
    AppConstants.loyaltyMultiplierGold = _double(
      c,
      'loyalty_multiplier_gold',
      AppConstants.loyaltyMultiplierGold,
    );
    AppConstants.loyaltyMultiplierPlatinum = _double(
      c,
      'loyalty_multiplier_platinum',
      AppConstants.loyaltyMultiplierPlatinum,
    );

    // Commission
    AppConstants.defaultCommissionRate = _double(
      c,
      'default_commission_rate',
      AppConstants.defaultCommissionRate,
    );

    // ── Earning system ──────────────────────────────────────────────
    EarningConfig.referrerSignupBonus = _double(
      c,
      'earning_referrer_signup_bonus',
      EarningConfig.referrerSignupBonus,
    );
    EarningConfig.referredFirstOrderBonus = _double(
      c,
      'earning_referred_first_order',
      EarningConfig.referredFirstOrderBonus,
    );
    EarningConfig.directOrderRate = _double(
      c,
      'earning_direct_order_rate',
      EarningConfig.directOrderRate,
    );
    EarningConfig.indirectOrderRate = _double(
      c,
      'earning_indirect_order_rate',
      EarningConfig.indirectOrderRate,
    );
    EarningConfig.builderMinRefs = _int(
      c,
      'earning_builder_min_refs',
      EarningConfig.builderMinRefs,
    );
    EarningConfig.builderMinOrders = _int(
      c,
      'earning_builder_min_orders',
      EarningConfig.builderMinOrders,
    );
    EarningConfig.leaderMinRefs = _int(
      c,
      'earning_leader_min_refs',
      EarningConfig.leaderMinRefs,
    );
    EarningConfig.leaderMinOrders = _int(
      c,
      'earning_leader_min_orders',
      EarningConfig.leaderMinOrders,
    );
    EarningConfig.volumeBonus300 = _double(
      c,
      'earning_volume_bonus_300',
      EarningConfig.volumeBonus300,
    );
    EarningConfig.volumeBonus1000 = _double(
      c,
      'earning_volume_bonus_1000',
      EarningConfig.volumeBonus1000,
    );
    EarningConfig.volumeBonus3000 = _double(
      c,
      'earning_volume_bonus_3000',
      EarningConfig.volumeBonus3000,
    );
    EarningConfig.monthlyCap = _double(
      c,
      'earning_monthly_cap',
      EarningConfig.monthlyCap,
    );
    EarningConfig.creditExpiryDays = _int(
      c,
      'earning_credit_expiry_days',
      EarningConfig.creditExpiryDays,
    );
    EarningConfig.minOrderToUse = _double(
      c,
      'earning_min_order_to_use',
      EarningConfig.minOrderToUse,
    );
    EarningConfig.maxCreditPct = _double(
      c,
      'earning_max_credit_pct',
      EarningConfig.maxCreditPct,
    );
    EarningConfig.restaurantRefCredits = _double(
      c,
      'earning_restaurant_ref_credits',
      EarningConfig.restaurantRefCredits,
    );
    EarningConfig.restaurantRefCommissionDiscount = _double(
      c,
      'earning_restaurant_ref_commission_discount',
      EarningConfig.restaurantRefCommissionDiscount,
    );

    // Stripe
    if (c.containsKey('stripe_publishable_key')) {
      final v = c['stripe_publishable_key'];
      if (v is String && v.isNotEmpty) {
        AppConstants.stripePublishableKey = v;
      }
    }

    // Subscription (MealHub+)
    AppConstants.subscriptionBasicPrice = _double(
      c,
      'subscription_basic_price',
      AppConstants.subscriptionBasicPrice,
    );
    AppConstants.subscriptionBasicDeliveries = _int(
      c,
      'subscription_basic_deliveries',
      AppConstants.subscriptionBasicDeliveries,
    );
    AppConstants.subscriptionProPrice = _double(
      c,
      'subscription_pro_price',
      AppConstants.subscriptionProPrice,
    );
    AppConstants.subscriptionProDeliveries = _int(
      c,
      'subscription_pro_deliveries',
      AppConstants.subscriptionProDeliveries,
    );
    AppConstants.subscriptionMinCart = _double(
      c,
      'subscription_min_cart',
      AppConstants.subscriptionMinCart,
    );
    AppConstants.subscriptionServiceFeeDiscount = _double(
      c,
      'subscription_service_fee_discount',
      AppConstants.subscriptionServiceFeeDiscount,
    );

    // Tips
    if (c.containsKey('preset_tips')) {
      final raw = c['preset_tips'];
      if (raw is List) {
        AppConstants.presetTips = raw
            .map((e) => (e as num).toDouble())
            .toList();
      }
    }

    // System
    AppConstants.apiTimeout = _int(c, 'api_timeout', AppConstants.apiTimeout);
    AppConstants.connectionTimeout = _int(
      c,
      'connection_timeout',
      AppConstants.connectionTimeout,
    );
    AppConstants.pageSize = _int(c, 'page_size', AppConstants.pageSize);
    AppConstants.orderAssignmentCutoffMinutes = _int(
      c,
      'order_assignment_cutoff_minutes',
      AppConstants.orderAssignmentCutoffMinutes,
    );
  }

  double _double(Map<String, dynamic> c, String key, double fallback) {
    final v = c[key];
    if (v is num) return v.toDouble();
    return fallback;
  }

  int _int(Map<String, dynamic> c, String key, int fallback) {
    final v = c[key];
    if (v is num) return v.toInt();
    return fallback;
  }
}
