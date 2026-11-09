import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/supabase_config.dart';
import '../../models/finance/driver_pay_tier.dart';

/// All driver-pay tiers, range tiers first (by min_km), the default row last.
final driverPayTiersProvider =
    FutureProvider.autoDispose<List<DriverPayTier>>((ref) async {
  final rows = await SupabaseConfig.client
      .from('driver_pay_tiers')
      .select()
      .order('is_default') // false (ranges) before true (default)
      .order('min_km', nullsFirst: false)
      .order('sort_order');
  return (rows as List)
      .map((r) => DriverPayTier.fromJson(r as Map<String, dynamic>))
      .toList();
});

class DriverPayService {
  static Future<void> addTier({
    required double minKm,
    required double maxKm,
    required String payType,
    required double amount,
    String? label,
  }) async {
    await SupabaseConfig.client.from('driver_pay_tiers').insert({
      'label': label,
      'min_km': minKm,
      'max_km': maxKm,
      'pay_type': payType,
      'amount': amount,
      'is_default': false,
      'is_active': true,
    });
  }

  static Future<void> updateTier(
    String id, {
    double? minKm,
    double? maxKm,
    String? payType,
    double? amount,
    bool? isActive,
  }) async {
    final data = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (minKm != null) data['min_km'] = minKm;
    if (maxKm != null) data['max_km'] = maxKm;
    if (payType != null) data['pay_type'] = payType;
    if (amount != null) data['amount'] = amount;
    if (isActive != null) data['is_active'] = isActive;
    await SupabaseConfig.client
        .from('driver_pay_tiers')
        .update(data)
        .eq('id', id);
  }

  static Future<void> deleteTier(String id) async {
    await SupabaseConfig.client.from('driver_pay_tiers').delete().eq('id', id);
  }

  /// Preview what a delivery of [distanceKm] and [deliveryFee] would pay the
  /// driver under the current tiers (uses the same DB resolver as payouts).
  static Future<double> preview(double? distanceKm, double deliveryFee) async {
    final res = await SupabaseConfig.client.rpc('resolve_driver_pay', params: {
      'p_distance_km': distanceKm,
      'p_delivery_fee': deliveryFee,
    });
    return (res as num).toDouble();
  }
}
