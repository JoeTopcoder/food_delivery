import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_logger.dart';

/// Server-verified order breakdown returned by the `calculate-order-total` edge function.
class OrderBreakdown {
  final double subtotal;
  final double taxRate;
  final double taxAmount;
  final double deliveryFee;
  final double? deliveryDistanceKm;
  final double promoDiscount;
  final String? promoId;
  final String? promoDetail;
  final double loyaltyDiscount;
  final int loyaltyPointsUsed;
  final String paymentMethod;
  final double paymentFeePercent;
  final double paymentFee;
  final double driverTip;
  final double commissionRate;
  final double commissionAmount;
  final double orderTotal;
  final double grandTotal;
  final bool subscriptionDeliveryFree;
  final String? subscriptionId;

  const OrderBreakdown({
    required this.subtotal,
    required this.taxRate,
    required this.taxAmount,
    required this.deliveryFee,
    this.deliveryDistanceKm,
    required this.promoDiscount,
    this.promoId,
    this.promoDetail,
    required this.loyaltyDiscount,
    required this.loyaltyPointsUsed,
    required this.paymentMethod,
    required this.paymentFeePercent,
    required this.paymentFee,
    required this.driverTip,
    required this.commissionRate,
    required this.commissionAmount,
    required this.orderTotal,
    required this.grandTotal,
    required this.subscriptionDeliveryFree,
    this.subscriptionId,
  });

  factory OrderBreakdown.fromJson(Map<String, dynamic> json) {
    return OrderBreakdown(
      subtotal: (json['subtotal'] as num).toDouble(),
      taxRate: (json['tax_rate'] as num).toDouble(),
      taxAmount: (json['tax_amount'] as num).toDouble(),
      deliveryFee: (json['delivery_fee'] as num).toDouble(),
      deliveryDistanceKm: (json['delivery_distance_km'] as num?)?.toDouble(),
      promoDiscount: (json['promo_discount'] as num).toDouble(),
      promoId: json['promo_id'] as String?,
      promoDetail: json['promo_detail'] as String?,
      loyaltyDiscount: (json['loyalty_discount'] as num).toDouble(),
      loyaltyPointsUsed: (json['loyalty_points_used'] as num).toInt(),
      paymentMethod: json['payment_method'] as String,
      paymentFeePercent: (json['payment_fee_percent'] as num).toDouble(),
      paymentFee: (json['payment_fee'] as num).toDouble(),
      driverTip: (json['driver_tip'] as num).toDouble(),
      commissionRate: (json['commission_rate'] as num).toDouble(),
      commissionAmount: (json['commission_amount'] as num).toDouble(),
      orderTotal: (json['order_total'] as num).toDouble(),
      grandTotal: (json['grand_total'] as num).toDouble(),
      subscriptionDeliveryFree:
          json['subscription_delivery_free'] as bool? ?? false,
      subscriptionId: json['subscription_id'] as String?,
    );
  }
}

/// Calls the `calculate-order-total` edge function for a server-authoritative
/// price breakdown. Falls back to `null` on network error so the caller can
/// decide whether to proceed with client-side math.
class OrderCalculationService {
  final SupabaseClient _client;
  OrderCalculationService(this._client);

  Future<OrderBreakdown?> calculate({
    required String restaurantId,
    required String userId,
    required List<Map<String, dynamic>> items,
    String? promoCode,
    int redeemPoints = 0,
    double driverTip = 0,
    String paymentMethod = 'cash',
    bool isPickup = false,
    double? deliveryLatitude,
    double? deliveryLongitude,
  }) async {
    try {
      // Supabase client throws FunctionException for non-2xx — catch JWT
      // errors, refresh the session, and retry once.
      late FunctionResponse response;
      try {
        response = await _client.functions.invoke(
          'calculate-order-total',
          body: {
            'restaurant_id': restaurantId,
            'user_id': userId,
            'items': items,
            'promo_code': ?promoCode,
            'redeem_points': redeemPoints,
            'driver_tip': driverTip,
            'payment_method': paymentMethod,
            'is_pickup': isPickup,
            'delivery_latitude': ?deliveryLatitude,
            'delivery_longitude': ?deliveryLongitude,
          },
        );
      } on FunctionException catch (fe) {
        final raw = fe.details?.toString() ?? '';
        if (fe.status == 401 ||
            fe.status == 403 ||
            raw.contains('LEGACY_JWT') ||
            raw.contains('ES256') ||
            raw.contains('JWT')) {
          await _client.auth.refreshSession();
          response = await _client.functions.invoke(
            'calculate-order-total',
            body: {
              'restaurant_id': restaurantId,
              'user_id': userId,
              'items': items,
              'promo_code': ?promoCode,
              'redeem_points': redeemPoints,
              'driver_tip': driverTip,
              'payment_method': paymentMethod,
              'is_pickup': isPickup,
              'delivery_latitude': ?deliveryLatitude,
              'delivery_longitude': ?deliveryLongitude,
            },
          );
        } else {
          rethrow;
        }
      }

      final body = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      if (body['error'] != null) {
        throw Exception(body['error']);
      }
      if (body['verified'] != true) {
        throw Exception('Server did not verify order total');
      }

      return OrderBreakdown.fromJson(
        Map<String, dynamic>.from(body['breakdown'] as Map),
      );
    } catch (e) {
      AppLogger.error('OrderCalculationService.calculate error: $e');
      return null;
    }
  }
}
