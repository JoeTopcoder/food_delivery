import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/subscription_model.dart';
import '../utils/app_logger.dart';

class SubscriptionService {
  final SupabaseClient _client;
  SubscriptionService(this._client);

  // Get all active meal plans
  Future<List<MealPlan>> getAvailablePlans() async {
    try {
      final response = await _client
          .from('meal_plans')
          .select()
          .eq('is_active', true)
          .order('price');
      return (response as List).map((e) => MealPlan.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error fetching meal plans: $e');
      return [];
    }
  }

  // Get plans by restaurant
  Future<List<MealPlan>> getRestaurantPlans(String restaurantId) async {
    try {
      final response = await _client
          .from('meal_plans')
          .select()
          .eq('restaurant_id', restaurantId)
          .eq('is_active', true);
      return (response as List).map((e) => MealPlan.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error fetching restaurant plans: $e');
      return [];
    }
  }

  // Subscribe to a plan
  Future<UserSubscription?> subscribe({
    required String userId,
    required String mealPlanId,
    required String deliveryAddress,
    double? deliveryLatitude,
    double? deliveryLongitude,
  }) async {
    try {
      // Get plan details for meals_remaining
      final plan = await _client
          .from('meal_plans')
          .select()
          .eq('id', mealPlanId)
          .single();
      final mealsPerPeriod = plan['meals_per_period'] as int? ?? 1;

      final now = DateTime.now();
      final response = await _client
          .from('user_subscriptions')
          .insert({
            'user_id': userId,
            'meal_plan_id': mealPlanId,
            'start_date': now.toIso8601String().split('T')[0],
            'next_delivery': now
                .add(const Duration(days: 1))
                .toIso8601String()
                .split('T')[0],
            'delivery_address': deliveryAddress,
            'delivery_latitude': deliveryLatitude,
            'delivery_longitude': deliveryLongitude,
            'meals_remaining': mealsPerPeriod,
          })
          .select('*, meal_plans(*)')
          .single();
      return UserSubscription.fromJson(response);
    } catch (e) {
      AppLogger.error('Error subscribing: $e');
      return null;
    }
  }

  // Get user's subscriptions
  Future<List<UserSubscription>> getUserSubscriptions(String userId) async {
    try {
      final response = await _client
          .from('user_subscriptions')
          .select('*, meal_plans(*)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => UserSubscription.fromJson(e))
          .toList();
    } catch (e) {
      AppLogger.error('Error fetching subscriptions: $e');
      return [];
    }
  }

  // Pause subscription
  Future<bool> pauseSubscription(String subscriptionId) async {
    try {
      await _client
          .from('user_subscriptions')
          .update({
            'status': 'paused',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', subscriptionId);
      return true;
    } catch (e) {
      AppLogger.error('Error pausing subscription: $e');
      return false;
    }
  }

  // Resume subscription
  Future<bool> resumeSubscription(String subscriptionId) async {
    try {
      await _client
          .from('user_subscriptions')
          .update({
            'status': 'active',
            'next_delivery': DateTime.now()
                .add(const Duration(days: 1))
                .toIso8601String()
                .split('T')[0],
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', subscriptionId);
      return true;
    } catch (e) {
      AppLogger.error('Error resuming subscription: $e');
      return false;
    }
  }

  // Cancel subscription
  Future<bool> cancelSubscription(String subscriptionId) async {
    try {
      await _client
          .from('user_subscriptions')
          .update({
            'status': 'cancelled',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', subscriptionId);
      return true;
    } catch (e) {
      AppLogger.error('Error cancelling subscription: $e');
      return false;
    }
  }

  // Create a meal plan (restaurant owner / admin)
  Future<MealPlan?> createPlan({
    required String name,
    String? description,
    String? restaurantId,
    required double price,
    required String frequency,
    required int mealsPerPeriod,
    List<Map<String, dynamic>>? items,
  }) async {
    try {
      final response = await _client
          .from('meal_plans')
          .insert({
            'name': name,
            'description': description,
            'restaurant_id': restaurantId,
            'price': price,
            'frequency': frequency,
            'meals_per_period': mealsPerPeriod,
            'items': items ?? [],
          })
          .select()
          .single();
      return MealPlan.fromJson(response);
    } catch (e) {
      AppLogger.error('Error creating meal plan: $e');
      return null;
    }
  }

  // ── Uber One-style subscription methods ───────────────────────────────────

  /// Create a subscription via edge function. Returns clientSecret + subscription info.
  Future<Map<String, dynamic>?> createDeliverySubscription({
    required String plan, // 'basic' or 'pro'
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-subscription',
        body: {'action': 'subscribe', 'plan': plan},
      );

      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      if (data['error'] != null) {
        throw Exception(data['error']);
      }

      return data;
    } catch (e) {
      AppLogger.error('Error creating delivery subscription: $e');
      rethrow;
    }
  }

  /// Cancel a subscription via edge function.
  Future<bool> cancelDeliverySubscription(String subscriptionId) async {
    try {
      final response = await _client.functions.invoke(
        'create-subscription',
        body: {'action': 'cancel', 'subscription_id': subscriptionId},
      );

      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      return data['success'] == true;
    } catch (e) {
      AppLogger.error('Error cancelling delivery subscription: $e');
      return false;
    }
  }

  /// Get the user's active delivery subscription (Uber One-style).
  Future<UserSubscription?> getActiveDeliverySubscription(String userId) async {
    try {
      final response = await _client
          .from('user_subscriptions')
          .select()
          .eq('user_id', userId)
          .eq('status', 'active')
          .not('plan_type', 'is', null)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return UserSubscription.fromJson(response);
    } catch (e) {
      AppLogger.error('Error fetching active delivery subscription: $e');
      return null;
    }
  }

  /// Check if a restaurant is eligible for subscription delivery.
  Future<bool> isRestaurantEligible(String restaurantId) async {
    try {
      final response = await _client
          .from('restaurants')
          .select('eligible_for_subscription')
          .eq('id', restaurantId)
          .single();
      return response['eligible_for_subscription'] as bool? ?? true;
    } catch (e) {
      return true; // Default to eligible
    }
  }

  /// Use a subscription delivery atomically via the DB function.
  Future<bool> useSubscriptionDelivery({
    required String subscriptionId,
    required String orderId,
  }) async {
    try {
      final response = await _client.rpc(
        'use_subscription_delivery',
        params: {'p_subscription_id': subscriptionId, 'p_order_id': orderId},
      );
      return response == true;
    } catch (e) {
      AppLogger.error('Error using subscription delivery: $e');
      return false;
    }
  }
}
