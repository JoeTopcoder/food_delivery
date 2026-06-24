import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../models/restaurant_model.dart';
import '../../utils/app_logger.dart';
import '../../utils/api_retry.dart';

// Columns needed by Restaurant.fromJson — explicit list avoids pulling large
// unused fields (description, operating_hours JSON, etc.) on list requests.
// Detail screen uses getRestaurantById() which fetches all columns.
const _kRestaurantListCols = 'id, name, image_url, cuisine_type, rating, '
    'review_count, delivery_fee, estimated_delivery_time, is_open, '
    'is_verified, address, latitude, longitude, store_type, tags, '
    'opening_time, closing_time, commission_rate, owner_id, created_at, updated_at';

class RestaurantService {
  final SupabaseClient _supabaseClient;

  RestaurantService(this._supabaseClient);

  static String _sanitizeQuery(String q) =>
      q.replaceAll(RegExp(r'[%_(),.\\]'), '');

  // Get all restaurants — narrowed columns + retry on transient failures
  Future<List<Restaurant>> getAllRestaurants({
    int? limit,
    int offset = 0,
  }) async {
    limit ??= AppConstants.pageSize;
    return withRetry(() async {
      AppLogger.info('Fetching all restaurants (offset=$offset, limit=$limit)');

      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select(_kRestaurantListCols)
          .eq('is_open', true)
          .eq('is_verified', true)
          .neq('store_type', 'grocery')
          .range(offset, offset + limit! - 1)
          .order('rating', ascending: false);

      final restaurants = (response as List)
          .map((r) => Restaurant.fromJson(r))
          .toList();
      AppLogger.info('Fetched ${restaurants.length} restaurants');
      return restaurants;
    }, label: 'getAllRestaurants');
  }

  // Search restaurants — narrowed columns + retry
  Future<List<Restaurant>> searchRestaurants(String query) async {
    final safe = _sanitizeQuery(query);
    return withRetry(() async {
      AppLogger.info('Searching restaurants: $query');

      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select(_kRestaurantListCols)
          .or('name.ilike.%$safe%,cuisine_type.ilike.%$safe%')
          .eq('is_open', true)
          .eq('is_verified', true)
          .neq('store_type', 'grocery')
          .limit(50);

      final restaurants = (response as List)
          .map((r) => Restaurant.fromJson(r))
          .toList();
      AppLogger.info('Found ${restaurants.length} restaurants');
      return restaurants;
    }, label: 'searchRestaurants');
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

  // Get ALL restaurants by owner ID
  Future<List<Restaurant>> getRestaurantsByOwnerId(String ownerId) async {
    try {
      AppLogger.info('Fetching all restaurants for owner: $ownerId');
      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select()
          .eq('owner_id', ownerId);
      return (response as List).map((r) => Restaurant.fromJson(r)).toList();
    } catch (e) {
      AppLogger.error('Error fetching restaurants by owner: $e');
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
          .eq('is_open', true)
          .neq('store_type', 'grocery')
          .limit(50);

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
    return withRetry(() async {
      AppLogger.info('Fetching top rated restaurants');
      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select(_kRestaurantListCols)
          .eq('is_open', true)
          .eq('is_verified', true)
          .neq('store_type', 'grocery')
          .order('rating', ascending: false)
          .limit(limit);
      return (response as List).map((r) => Restaurant.fromJson(r)).toList();
    }, label: 'getTopRatedRestaurants');
  }

  // Get newly added restaurants (most recent first)
  Future<List<Restaurant>> getNewlyAddedRestaurants({int limit = 10}) async {
    return withRetry(() async {
      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select(_kRestaurantListCols)
          .eq('is_open', true)
          .eq('is_verified', true)
          .neq('store_type', 'grocery')
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List).map((r) => Restaurant.fromJson(r)).toList();
    }, label: 'getNewlyAddedRestaurants');
  }

  // Get restaurants tagged/typed as breakfast
  Future<List<Restaurant>> getBreakfastRestaurants({int limit = 10}) async {
    return withRetry(() async {
      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select(_kRestaurantListCols)
          .eq('is_open', true)
          .neq('store_type', 'grocery')
          .or('cuisine_type.ilike.%breakfast%,tags.cs.{breakfast}')
          .limit(limit);
      return (response as List).map((r) => Restaurant.fromJson(r)).toList();
    }, label: 'getBreakfastRestaurants');
  }

  // Get "must try" restaurants — highest rated with most reviews
  Future<List<Restaurant>> getMustTryRestaurants({int limit = 10}) async {
    return withRetry(() async {
      final response = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .select(_kRestaurantListCols)
          .eq('is_open', true)
          .neq('store_type', 'grocery')
          .gte('rating', 4.0)
          .order('review_count', ascending: false)
          .limit(limit);
      return (response as List).map((r) => Restaurant.fromJson(r)).toList();
    }, label: 'getMustTryRestaurants');
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

  // ── Onboarding helpers ────────────────────────────────────────────────────

  Future<Restaurant?> updateOnboardingStep({
    required String restaurantId,
    required int step,
    String? name,
    String? description,
    String? cuisineType,
    String? phone,
    String? email,
    String? address,
    double? latitude,
    double? longitude,
    String? storeType,
    String? imageUrl,
    Map<String, dynamic>? operatingHours,
    double? deliveryFee,
    int? estimatedDeliveryTime,
  }) async {
    try {
      final data = <String, dynamic>{
        'onboarding_step': step,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (name != null) data['name'] = name;
      if (description != null) data['description'] = description;
      if (cuisineType != null) data['cuisine_type'] = cuisineType;
      if (phone != null) data['phone'] = phone;
      if (email != null) data['email'] = email;
      if (address != null) data['address'] = address;
      if (latitude != null) data['latitude'] = latitude;
      if (longitude != null) data['longitude'] = longitude;
      if (storeType != null) data['store_type'] = storeType;
      if (imageUrl != null) data['image_url'] = imageUrl;
      if (operatingHours != null) data['operating_hours'] = operatingHours;
      if (deliveryFee != null) data['delivery_fee'] = deliveryFee;
      if (estimatedDeliveryTime != null) data['estimated_delivery_time'] = estimatedDeliveryTime;

      final row = await _supabaseClient
          .from(AppConstants.tableRestaurants)
          .update(data)
          .eq('id', restaurantId)
          .select()
          .single();
      return Restaurant.fromJson(row);
    } catch (e) {
      AppLogger.error('Error updating onboarding step: $e');
      rethrow;
    }
  }

  Future<void> saveRestaurantDocument({
    required String restaurantId,
    required String documentType,
    String? documentNumber,
    String? photoUrl,
    DateTime? expiryDate,
  }) async {
    try {
      final existing = await _supabaseClient
          .from('restaurant_documents')
          .select('id')
          .eq('restaurant_id', restaurantId)
          .eq('document_type', documentType)
          .maybeSingle();
      final data = <String, dynamic>{
        'restaurant_id': restaurantId,
        'document_type': documentType,
        if (documentNumber != null) 'document_number': documentNumber,
        if (photoUrl != null) 'photo_url': photoUrl,
        if (expiryDate != null) 'expiry_date': expiryDate.toIso8601String().substring(0, 10),
        'verification_status': 'pending',
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (existing != null) {
        await _supabaseClient
            .from('restaurant_documents')
            .update(data)
            .eq('id', existing['id'] as String);
      } else {
        await _supabaseClient.from('restaurant_documents').insert(data);
      }
    } catch (e) {
      // Documents are optional — RLS / missing-table errors must not block submission.
      AppLogger.warning('saveRestaurantDocument non-fatal: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getRestaurantDocuments(String restaurantId) async {
    try {
      final response = await _supabaseClient
          .from('restaurant_documents')
          .select()
          .eq('restaurant_id', restaurantId)
          .order('created_at');
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      AppLogger.error('Error fetching restaurant documents: $e');
      return [];
    }
  }

  Future<Restaurant?> submitApplication(String restaurantId) async {
    try {
      final now = DateTime.now().toIso8601String();
      // Keep status as 'draft' — DB check constraint only allows 'draft'/'active'.
      // Admin promotes to 'active' after review. submitted_at signals it was sent.
      final data = <String, dynamic>{
        'onboarding_step': 7,
        'updated_at': now,
      };
      // submitted_at column may not exist in all deployments — try with it first.
      Map<String, dynamic>? row;
      try {
        row = await _supabaseClient
            .from(AppConstants.tableRestaurants)
            .update({...data, 'submitted_at': now, 'rejection_reason': null})
            .eq('id', restaurantId)
            .select()
            .single();
      } catch (_) {
        // Retry without optional columns if they don't exist yet.
        row = await _supabaseClient
            .from(AppConstants.tableRestaurants)
            .update(data)
            .eq('id', restaurantId)
            .select()
            .single();
      }
      return Restaurant.fromJson(row);
    } catch (e) {
      AppLogger.error('Error submitting restaurant application: $e');
      rethrow;
    }
  }
}
