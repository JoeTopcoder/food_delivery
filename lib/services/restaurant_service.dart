import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../models/restaurant_model.dart';
import '../utils/app_logger.dart';

class RestaurantService {
  final SupabaseClient _supabaseClient;

  RestaurantService(this._supabaseClient);

  // Get all restaurants
  Future<List<Restaurant>> getAllRestaurants({
    int? limit,
    int offset = 0,
  }) async {
    limit ??= AppConstants.pageSize;
    try {
      AppLogger.info('Fetching all restaurants');

      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .eq('is_open', true)
          .eq('is_verified', true)
          .range(offset, offset + limit - 1)
          .order('rating', ascending: false);

      final restaurants = (response as List)
          .map((restaurant) => Restaurant.fromJson(restaurant))
          .toList();

      AppLogger.info('Fetched ${restaurants.length} restaurants');
      return restaurants;
    } catch (e) {
      AppLogger.error('Error fetching restaurants: $e');
      rethrow;
    }
  }

  // Search restaurants by name or cuisine
  Future<List<Restaurant>> searchRestaurants(String query) async {
    try {
      AppLogger.info('Searching restaurants: $query');

      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .or('name.ilike.%$query%,cuisine_type.ilike.%$query%')
          .eq('is_open', true)
          .eq('is_verified', true);

      final restaurants = (response as List)
          .map((restaurant) => Restaurant.fromJson(restaurant))
          .toList();

      AppLogger.info('Found ${restaurants.length} restaurants');
      return restaurants;
    } catch (e) {
      AppLogger.error('Error searching restaurants: $e');
      rethrow;
    }
  }

  // Get restaurant by owner ID (no is_open filter)
  Future<Restaurant?> getRestaurantByOwnerId(String ownerId) async {
    try {
      AppLogger.info('Fetching restaurant for owner: $ownerId');
      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .eq('owner_id', ownerId)
          .limit(1);
      if (response.isEmpty) return null;
      return Restaurant.fromJson(response.first);
    } catch (e) {
      AppLogger.error('Error fetching restaurant by owner: $e');
      rethrow;
    }
  }

  // Get restaurant by ID
  Future<Restaurant?> getRestaurantById(String restaurantId) async {
    try {
      AppLogger.info('Fetching restaurant: $restaurantId');

      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .eq('id', restaurantId)
          .single();

      final restaurant = Restaurant.fromJson(response);
      AppLogger.info('Restaurant fetched successfully');
      return restaurant;
    } catch (e) {
      AppLogger.error('Error fetching restaurant: $e');
      return null;
    }
  }

  // Get restaurants by cuisine type
  Future<List<Restaurant>> getRestaurantsByCuisine(String cuisineType) async {
    try {
      AppLogger.info('Fetching restaurants by cuisine: $cuisineType');

      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .eq('cuisine_type', cuisineType)
          .eq('is_open', true);

      final restaurants = (response as List)
          .map((restaurant) => Restaurant.fromJson(restaurant))
          .toList();

      AppLogger.info('Fetched ${restaurants.length} restaurants');
      return restaurants;
    } catch (e) {
      AppLogger.error('Error fetching restaurants by cuisine: $e');
      rethrow;
    }
  }

  // Get top rated restaurants
  Future<List<Restaurant>> getTopRatedRestaurants({int limit = 10}) async {
    try {
      AppLogger.info('Fetching top rated restaurants');

      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .eq('is_open', true)
          .eq('is_verified', true)
          .order('rating', ascending: false)
          .limit(limit);

      final restaurants = (response as List)
          .map((restaurant) => Restaurant.fromJson(restaurant))
          .toList();

      AppLogger.info('Fetched ${restaurants.length} top rated restaurants');
      return restaurants;
    } catch (e) {
      AppLogger.error('Error fetching top rated restaurants: $e');
      rethrow;
    }
  }

  // Get newly added restaurants (most recent first)
  Future<List<Restaurant>> getNewlyAddedRestaurants({int limit = 10}) async {
    try {
      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .eq('is_open', true)
          .eq('is_verified', true)
          .order('created_at', ascending: false)
          .limit(limit);

      return (response as List).map((r) => Restaurant.fromJson(r)).toList();
    } catch (e) {
      AppLogger.error('Error fetching newly added restaurants: $e');
      rethrow;
    }
  }

  // Get restaurants tagged/typed as breakfast
  Future<List<Restaurant>> getBreakfastRestaurants({int limit = 10}) async {
    try {
      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .eq('is_open', true)
          .or('cuisine_type.ilike.%breakfast%,tags.cs.{breakfast}')
          .limit(limit);

      return (response as List).map((r) => Restaurant.fromJson(r)).toList();
    } catch (e) {
      AppLogger.error('Error fetching breakfast restaurants: $e');
      rethrow;
    }
  }

  // Get "must try" restaurants — highest rated with most reviews
  Future<List<Restaurant>> getMustTryRestaurants({int limit = 10}) async {
    try {
      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .eq('is_open', true)
          .gte('rating', 4.0)
          .order('review_count', ascending: false)
          .limit(limit);

      return (response as List).map((r) => Restaurant.fromJson(r)).toList();
    } catch (e) {
      AppLogger.error('Error fetching must-try restaurants: $e');
      rethrow;
    }
  }

  // Create restaurant (for restaurant owners)
  Future<Restaurant?> createRestaurant({
    required String ownerId,
    required String name,
    String? description,
    String? phone,
    String? address,
    double? latitude,
    double? longitude,
    String? cuisineType,
    double? deliveryFee,
    int? estimatedDeliveryTime,
  }) async {
    try {
      AppLogger.info('Creating restaurant: $name');

      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .insert({
            'owner_id': ownerId,
            'name': name,
            'description': description,
            'phone': phone,
            'address': address,
            'latitude': latitude,
            'longitude': longitude,
            'cuisine_type': cuisineType,
            'delivery_fee': deliveryFee ?? 50.0,
            'estimated_delivery_time': estimatedDeliveryTime ?? 30,
            'is_open': true,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final restaurant = Restaurant.fromJson(response);
      AppLogger.info('Restaurant created successfully');
      return restaurant;
    } catch (e) {
      AppLogger.error('Error creating restaurant: $e');
      rethrow;
    }
  }

  // Update restaurant
  Future<Restaurant?> updateRestaurant({
    required String restaurantId,
    String? name,
    String? description,
    String? phone,
    String? address,
    double? latitude,
    double? longitude,
    String? cuisineType,
    double? deliveryFee,
    int? estimatedDeliveryTime,
    bool? isOpen,
    String? imageUrl,
    double? commissionRate,
    Map<String, dynamic>? operatingHours,
  }) async {
    try {
      AppLogger.info('Updating restaurant: $restaurantId');

      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (name != null) updateData['name'] = name;
      if (description != null) updateData['description'] = description;
      if (phone != null) updateData['phone'] = phone;
      if (address != null) updateData['address'] = address;
      if (latitude != null) updateData['latitude'] = latitude;
      if (longitude != null) updateData['longitude'] = longitude;
      if (cuisineType != null) updateData['cuisine_type'] = cuisineType;
      if (deliveryFee != null) updateData['delivery_fee'] = deliveryFee;
      if (estimatedDeliveryTime != null) {
        updateData['estimated_delivery_time'] = estimatedDeliveryTime;
      }
      if (isOpen != null) updateData['is_open'] = isOpen;
      if (imageUrl != null) updateData['image_url'] = imageUrl;
      if (commissionRate != null) {
        updateData['commission_rate'] = commissionRate;
      }
      if (operatingHours != null) {
        updateData['operating_hours'] = operatingHours;
      }

      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .update(updateData)
          .eq('id', restaurantId)
          .select()
          .single();

      final restaurant = Restaurant.fromJson(response);
      AppLogger.info('Restaurant updated successfully');
      return restaurant;
    } catch (e) {
      AppLogger.error('Error updating restaurant: $e');
      rethrow;
    }
  }

  /// Get reviews for a restaurant
  Future<List<Map<String, dynamic>>> getRestaurantReviews(
    String restaurantId,
  ) async {
    try {
      final res = await _supabaseClient
          .from('reviews')
          .select()
          .eq('restaurant_id', restaurantId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      AppLogger.error('Error fetching reviews: $e');
      return [];
    }
  }

  /// Restaurant owner responds to a review
  Future<void> respondToReview({
    required String reviewId,
    required String responseText,
    required String responderId,
  }) async {
    try {
      await _supabaseClient
          .from('reviews')
          .update({
            'response_text': responseText,
            'responded_at': DateTime.now().toIso8601String(),
            'response_by': responderId,
          })
          .eq('id', reviewId);
    } catch (e) {
      AppLogger.error('Error responding to review: $e');
      rethrow;
    }
  }
}
