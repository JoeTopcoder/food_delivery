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
}
