import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../utils/app_logger.dart';

/// Service that loads app_config from the database and updates AppConstants.
/// Call [load] once at startup (e.g. in main.dart after Supabase init).
class AppConfigService {
  final SupabaseClient _client;
  AppConfigService(this._client);

  /// Fetches all config from `get-app-config` edge function and hydrates
  /// [AppConstants] with the DB values. Falls back to compiled defaults on error.
  Future<void> load() async {
    try {
      final response = await _client.functions.invoke(
        'get-app-config',
        method: HttpMethod.get,
      );
      final body = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      if (body == null || body['config'] == null) {
        AppLogger.warning('AppConfigService: empty response, using defaults');
        return;
      }
      final Map<String, dynamic> config = Map<String, dynamic>.from(
        body['config'] as Map,
      );
      _applyConfig(config);
      AppLogger.info(
        'AppConfigService: loaded ${config.length} settings from DB',
      );
    } catch (e) {
      // Non-fatal: app works with compiled defaults
      AppLogger.warning(
        'AppConfigService: could not load remote config ($e), using defaults',
      );
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

    // Delivery
    AppConstants.deliveryBaseFee = _double(
      c,
      'delivery_base_fee',
      AppConstants.deliveryBaseFee,
    );
    AppConstants.deliveryPerKmFee = _double(
      c,
      'delivery_per_km_fee',
      AppConstants.deliveryPerKmFee,
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
