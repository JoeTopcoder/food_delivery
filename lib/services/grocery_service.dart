import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/restaurant_model.dart';
import '../models/menu_model.dart';
import '../models/grocery_category_model.dart';
import '../config/app_constants.dart';
import '../utils/app_logger.dart';

class GroceryService {
  final SupabaseClient _client;

  GroceryService(this._client);

  static String _sanitize(String q) => q.replaceAll(RegExp(r'[%_(),.\\]'), '');

  /// Fetch the grocery store owned by a specific user.
  Future<Restaurant?> getGroceryStoreByOwnerId(String ownerId) async {
    try {
      AppLogger.info('Fetching grocery store for owner: $ownerId');
      final response = await _client
          .from(AppConstants.tableRestaurants)
          .select()
          .eq('owner_id', ownerId)
          .or('store_type.eq.grocery,store_type.eq.both')
          .limit(1);
      if (response.isEmpty) return null;
      return Restaurant.fromJson(response.first);
    } catch (e) {
      AppLogger.error('Error fetching grocery store by owner: $e');
      rethrow;
    }
  }

  /// Create a new grocery store for an owner.
  Future<Restaurant> createGroceryStore({
    required String ownerId,
    required String name,
    String? description,
    String? phone,
    String? address,
  }) async {
    try {
      AppLogger.info('Creating grocery store for owner: $ownerId');
      final response = await _client
          .from(AppConstants.tableRestaurants)
          .insert({
            'owner_id': ownerId,
            'name': name,
            'description': description,
            'phone': phone,
            'address': address,
            'store_type': 'grocery',
            'is_open': true,
            'is_verified': true,
          })
          .select()
          .single();
      return Restaurant.fromJson(response);
    } catch (e) {
      AppLogger.error('Error creating grocery store: $e');
      rethrow;
    }
  }

  /// Fetch all verified grocery stores (store_type = 'grocery' or 'both').
  Future<List<Restaurant>> getGroceryStores({int? limit}) async {
    try {
      AppLogger.info('Fetching grocery stores');
      var query = _client
          .from(AppConstants.tableRestaurants)
          .select()
          .or('store_type.eq.grocery,store_type.eq.both')
          .eq('is_verified', true)
          .order('rating', ascending: false);

      if (limit != null) {
        query = query.limit(limit);
      }

      final response = await query;
      return (response as List).map((r) => Restaurant.fromJson(r)).toList();
    } catch (e) {
      AppLogger.error('Error fetching grocery stores: $e');
      rethrow;
    }
  }

  /// Search grocery stores by name.
  Future<List<Restaurant>> searchGroceryStores(String query) async {
    try {
      final response = await _client
          .from(AppConstants.tableRestaurants)
          .select()
          .or('store_type.eq.grocery,store_type.eq.both')
          .eq('is_verified', true)
          .ilike('name', '%${_sanitize(query)}%')
          .order('rating', ascending: false);

      return (response as List).map((r) => Restaurant.fromJson(r)).toList();
    } catch (e) {
      AppLogger.error('Error searching grocery stores: $e');
      rethrow;
    }
  }

  /// Fetch all grocery products for a given store.
  Future<List<MenuItem>> getGroceryProducts(String storeId) async {
    try {
      AppLogger.info('Fetching grocery products for store: $storeId');
      final response = await _client
          .from(AppConstants.tableMenus)
          .select(
            '*, menu_item_sides(*), menu_option_groups(*, menu_option_choices(*))',
          )
          .eq('restaurant_id', storeId)
          .eq('product_type', 'grocery')
          .eq('is_available', true)
          .order('category');

      return (response as List).map((row) {
        final sidesJson = row['menu_item_sides'] as List? ?? [];
        return MenuItem.fromJson({...row, 'sides': sidesJson});
      }).toList();
    } catch (e) {
      AppLogger.error('Error fetching grocery products: $e');
      rethrow;
    }
  }

  /// Search grocery products across all stores.
  Future<List<MenuItem>> searchGroceryProducts(String query) async {
    try {
      final response = await _client
          .from(AppConstants.tableMenus)
          .select()
          .eq('product_type', 'grocery')
          .eq('is_available', true)
          .or(
            'name.ilike.%${_sanitize(query)}%,brand.ilike.%${_sanitize(query)}%,description.ilike.%${_sanitize(query)}%',
          );

      return (response as List).map((r) => MenuItem.fromJson(r)).toList();
    } catch (e) {
      AppLogger.error('Error searching grocery products: $e');
      rethrow;
    }
  }

  /// Fetch all grocery categories (from grocery_categories table + any custom
  /// categories that exist on products in the menus table).
  Future<List<GroceryCategory>> getCategories() async {
    try {
      // 1. Fetch the curated categories
      final catResponse = await _client
          .from('grocery_categories')
          .select()
          .eq('is_active', true)
          .order('sort_order');

      final categories = (catResponse as List)
          .map((r) => GroceryCategory.fromJson(r))
          .toList();

      final knownNames = categories.map((c) => c.name).toSet();

      // 2. Fetch distinct category names from actual grocery products
      final menuResponse = await _client
          .from(AppConstants.tableMenus)
          .select('category')
          .eq('product_type', 'grocery')
          .eq('is_available', true);

      final productCategories = <String>{};
      for (final row in (menuResponse as List)) {
        final cat = row['category'] as String?;
        if (cat != null && cat.isNotEmpty) {
          productCategories.add(cat);
        }
      }

      // 3. Merge: add any product categories not already in the curated list
      for (final name in productCategories) {
        if (!knownNames.contains(name)) {
          categories.add(
            GroceryCategory(
              id: 'custom_$name',
              name: name,
              icon: '📦',
              sortOrder: 999,
              isActive: true,
              createdAt: DateTime.now(),
            ),
          );
        }
      }

      // Sort: curated first (by sort_order), custom at end alphabetically
      categories.sort((a, b) {
        if (a.sortOrder != b.sortOrder)
          return a.sortOrder.compareTo(b.sortOrder);
        return a.name.compareTo(b.name);
      });

      return categories;
    } catch (e) {
      AppLogger.error('Error fetching grocery categories: $e');
      rethrow;
    }
  }

  /// Fetch grocery products by category for a given store.
  Future<List<MenuItem>> getProductsByCategory(
    String storeId,
    String category,
  ) async {
    try {
      final response = await _client
          .from(AppConstants.tableMenus)
          .select(
            '*, menu_item_sides(*), menu_option_groups(*, menu_option_choices(*))',
          )
          .eq('restaurant_id', storeId)
          .eq('product_type', 'grocery')
          .eq('category', category)
          .eq('is_available', true)
          .order('name');

      return (response as List).map((row) {
        final sidesJson = row['menu_item_sides'] as List? ?? [];
        return MenuItem.fromJson({...row, 'sides': sidesJson});
      }).toList();
    } catch (e) {
      AppLogger.error('Error fetching products by category: $e');
      rethrow;
    }
  }

  /// Fetch grocery products by category across ALL stores.
  Future<List<MenuItem>> getAllProductsByCategory(String category) async {
    try {
      AppLogger.info('Fetching all grocery products for category: $category');
      final response = await _client
          .from(AppConstants.tableMenus)
          .select(
            '*, menu_item_sides(*), menu_option_groups(*, menu_option_choices(*))',
          )
          .eq('product_type', 'grocery')
          .eq('category', category)
          .eq('is_available', true)
          .eq('in_stock', true)
          .order('name');

      return (response as List).map((row) {
        final sidesJson = row['menu_item_sides'] as List? ?? [];
        return MenuItem.fromJson({...row, 'sides': sidesJson});
      }).toList();
    } catch (e) {
      AppLogger.error('Error fetching all products by category: $e');
      rethrow;
    }
  }

  /// Add a grocery product (for store owners).
  Future<MenuItem?> addGroceryProduct({
    required String storeId,
    required String name,
    required double price,
    required String category,
    String? description,
    String? imageUrl,
    String? unit,
    String? brand,
    String? weight,
    int maxQuantity = 99,
  }) async {
    try {
      final response = await _client
          .from(AppConstants.tableMenus)
          .insert({
            'restaurant_id': storeId,
            'name': name,
            'price': price,
            'category': category,
            'description': description,
            'image_url': imageUrl,
            'is_available': true,
            'product_type': 'grocery',
            'unit': unit,
            'brand': brand,
            'weight': weight,
            'in_stock': true,
            'max_quantity': maxQuantity,
          })
          .select()
          .single();

      return MenuItem.fromJson(response);
    } catch (e) {
      AppLogger.error('Error adding grocery product: $e');
      rethrow;
    }
  }

  /// Update stock status of a grocery product.
  Future<void> updateStockStatus(String productId, bool inStock) async {
    try {
      await _client
          .from(AppConstants.tableMenus)
          .update({'in_stock': inStock})
          .eq('id', productId);
    } catch (e) {
      AppLogger.error('Error updating stock status: $e');
      rethrow;
    }
  }

  /// Fetch ALL grocery products for a store (including unavailable — for owner management).
  Future<List<MenuItem>> getOwnerGroceryProducts(String storeId) async {
    try {
      final response = await _client
          .from(AppConstants.tableMenus)
          .select(
            '*, menu_item_sides(*), menu_option_groups(*, menu_option_choices(*))',
          )
          .eq('restaurant_id', storeId)
          .eq('product_type', 'grocery')
          .order('category');

      return (response as List).map((row) {
        final sidesJson = row['menu_item_sides'] as List? ?? [];
        return MenuItem.fromJson({...row, 'sides': sidesJson});
      }).toList();
    } catch (e) {
      AppLogger.error('Error fetching owner grocery products: $e');
      rethrow;
    }
  }

  /// Delete a grocery product.
  Future<void> deleteGroceryProduct(String productId) async {
    try {
      await _client.from(AppConstants.tableMenus).delete().eq('id', productId);
    } catch (e) {
      AppLogger.error('Error deleting grocery product: $e');
      rethrow;
    }
  }

  /// Toggle availability of a grocery product.
  Future<void> toggleAvailability(String productId, bool available) async {
    try {
      await _client
          .from(AppConstants.tableMenus)
          .update({'is_available': available})
          .eq('id', productId);
    } catch (e) {
      AppLogger.error('Error toggling product availability: $e');
      rethrow;
    }
  }

  /// Place a grocery order via edge function (server-side validated).
  Future<Map<String, dynamic>> placeGroceryOrder({
    required String storeId,
    required String userId,
    required List<Map<String, dynamic>> items,
    bool isPickup = false,
    String paymentMethod = 'cash',
    String? deliveryAddress,
    double? deliveryLatitude,
    double? deliveryLongitude,
    double driverTip = 0,
    String? specialInstructions,
    String? promoCode,
    // Payment gate: pass one so the edge function charges/verifies before insert.
    String? savedCardPaymentMethodId,
    String? paymentIntentId,
  }) async {
    try {
      AppLogger.info('Placing grocery order via edge function');

      final invokeBody = {
        'store_id': storeId,
        'user_id': userId,
        'items': items,
        'is_pickup': isPickup,
        'payment_method': paymentMethod,
        if (deliveryAddress != null) 'delivery_address': deliveryAddress,
        if (deliveryLatitude != null) 'delivery_latitude': deliveryLatitude,
        if (deliveryLongitude != null) 'delivery_longitude': deliveryLongitude,
        'driver_tip': driverTip,
        if (specialInstructions != null) 'special_instructions': specialInstructions,
        if (promoCode != null) 'promo_code': promoCode,
        if (savedCardPaymentMethodId != null && savedCardPaymentMethodId.isNotEmpty)
          'saved_card_payment_method_id': savedCardPaymentMethodId,
        if (paymentIntentId != null && paymentIntentId.isNotEmpty)
          'payment_intent_id': paymentIntentId,
      };

      // Build a fresh Authorization header to avoid UNAUTHORIZED_LEGACY_JWT.
      // Uses the token from the refresh response directly — more reliable than
      // reading currentSession which may still hold the old legacy token.
      Future<Map<String, String>> freshHeader() async {
        String? token;
        try {
          final res = await _client.auth.refreshSession();
          token = res.session?.accessToken;
        } catch (_) {}
        token ??= _client.auth.currentSession?.accessToken;
        return (token != null && token.isNotEmpty)
            ? {'Authorization': 'Bearer $token'}
            : {};
      }

      String? extractFunctionError(dynamic details) {
        if (details == null) return null;
        if (details is Map) {
          final e = details['error'] ?? details['message'];
          if (e != null) return e.toString();
        }
        final str = details.toString();
        try {
          final parsed = jsonDecode(str);
          if (parsed is Map) {
            final e = parsed['error'] ?? parsed['message'];
            if (e != null) return e.toString();
          }
        } catch (_) {}
        return null;
      }

      FunctionResponse response;
      try {
        response = await _client.functions.invoke('grocery-order',
            body: invokeBody, headers: await freshHeader());
      } on FunctionException catch (fe) {
        final raw = fe.details?.toString() ?? '';
        final isJwtError = fe.status == 401 ||
            fe.status == 403 ||
            raw.contains('LEGACY_JWT') ||
            raw.contains('ES256') ||
            raw.contains('JWT');
        if (isJwtError) {
          try {
            response = await _client.functions.invoke('grocery-order',
                body: invokeBody, headers: await freshHeader());
          } on FunctionException catch (fe2) {
            if (fe2.status == 401 || fe2.status == 403) {
              throw Exception(
                'Your session has expired. Please sign out and sign in again to place your order.',
              );
            }
            final msg = extractFunctionError(fe2.details) ??
                'Order placement failed (${fe2.status}). Please try again.';
            throw Exception(msg);
          }
        } else {
          final msg = extractFunctionError(fe.details);
          if (msg != null) throw Exception(msg);
          rethrow;
        }
      }

      final body = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      if (body['error'] != null) {
        throw Exception(body['error']);
      }

      return body;
    } catch (e) {
      AppLogger.error('Error placing grocery order: $e');
      rethrow;
    }
  }
}
