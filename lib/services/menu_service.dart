import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../models/menu_model.dart';
import '../utils/app_logger.dart';

class MenuService {
  final SupabaseClient _supabaseClient;

  MenuService(this._supabaseClient);

  static String _sanitizeQuery(String q) =>
      q.replaceAll(RegExp(r'[%_(),.\\]'), '');

  // Get menu items for a restaurant
  Future<List<MenuItem>> getMenuByRestaurant(String restaurantId) async {
    return _fetchMenuByRestaurant(restaurantId, includeUnavailable: false);
  }

  // Get every menu item for a restaurant (including unavailable) — used by the
  // restaurant management screen so owners can still see and edit hidden items.
  Future<List<MenuItem>> getAllMenuByRestaurant(String restaurantId) async {
    return _fetchMenuByRestaurant(restaurantId, includeUnavailable: true);
  }

  Future<List<MenuItem>> _fetchMenuByRestaurant(
    String restaurantId, {
    required bool includeUnavailable,
  }) async {
    try {
      AppLogger.info(
        'Fetching menu for restaurant: $restaurantId (includeUnavailable=$includeUnavailable)',
      );

      // Single query with embedded sides + option groups (with nested choices)
      var query = _supabaseClient
          .from(AppConstants.tableMenus)
          .select(
            '*, ${AppConstants.tableMenuItemSides}(*), menu_option_groups(*, menu_option_choices(*))',
          )
          .eq('restaurant_id', restaurantId);
      if (!includeUnavailable) {
        query = query.eq('is_available', true);
      }
      final response = await query.order('category');

      final items = (response as List).map((row) {
        final sidesJson = row[AppConstants.tableMenuItemSides] as List? ?? [];
        return MenuItem.fromJson({...row, 'sides': sidesJson});
      }).toList();

      AppLogger.info('Fetched ${items.length} menu items');
      return items;
    } catch (e) {
      AppLogger.error('Error fetching menu: $e');
      rethrow;
    }
  }

  // Get menu item by ID
  Future<MenuItem?> getMenuItemById(String menuItemId) async {
    try {
      AppLogger.info('Fetching menu item: $menuItemId');

      final response = await _supabaseClient
          .from(AppConstants.tableMenus)
          .select()
          .eq('id', menuItemId)
          .single();

      final item = MenuItem.fromJson(response);
      AppLogger.info('Menu item fetched successfully');
      return item;
    } catch (e) {
      AppLogger.error('Error fetching menu item: $e');
      return null;
    }
  }

  // Search menu items
  Future<List<MenuItem>> searchMenuItems(String query) async {
    try {
      AppLogger.info('Searching menu items: $query');

      final response = await _supabaseClient
          .from(AppConstants.tableMenus)
          .select()
          .or(
            'name.ilike.%${_sanitizeQuery(query)}%,description.ilike.%${_sanitizeQuery(query)}%',
          )
          .eq('is_available', true);

      final items = (response as List)
          .map((item) => MenuItem.fromJson(item))
          .toList();

      AppLogger.info('Found ${items.length} menu items');
      return items;
    } catch (e) {
      AppLogger.error('Error searching menu items: $e');
      rethrow;
    }
  }

  // Get menu items by category
  Future<List<MenuItem>> getMenuItemsByCategory(
    String restaurantId,
    String category,
  ) async {
    try {
      AppLogger.info('Fetching menu items by category: $category');

      final response = await _supabaseClient
          .from(AppConstants.tableMenus)
          .select()
          .eq('restaurant_id', restaurantId)
          .eq('category', category)
          .eq('is_available', true);

      final items = (response as List)
          .map((item) => MenuItem.fromJson(item))
          .toList();

      AppLogger.info('Fetched ${items.length} items in category: $category');
      return items;
    } catch (e) {
      AppLogger.error('Error fetching menu items by category: $e');
      rethrow;
    }
  }

  // Add menu item (for restaurant owners)
  Future<MenuItem?> addMenuItem({
    required String restaurantId,
    required String name,
    required double price,
    required String category,
    String? description,
    String? imageUrl,
    double? discount,
    List<String>? tags,
    int? preparationTime,
  }) async {
    try {
      AppLogger.info('Adding menu item: $name');

      final response = await _supabaseClient
          .from(AppConstants.tableMenus)
          .insert({
            'restaurant_id': restaurantId,
            'name': name,
            'price': price,
            'category': category,
            'description': description,
            'image_url': imageUrl,
            'is_available': true,
            'discount': discount,
            'tags': tags,
            'preparation_time': preparationTime,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final item = MenuItem.fromJson(response);
      AppLogger.info('Menu item added successfully');
      return item;
    } catch (e) {
      AppLogger.error('Error adding menu item: $e');
      rethrow;
    }
  }

  // Update menu item
  Future<MenuItem?> updateMenuItem({
    required String menuItemId,
    String? name,
    double? price,
    String? description,
    String? imageUrl,
    bool? isAvailable,
    double? discount,
    int? preparationTime,
  }) async {
    try {
      AppLogger.info('Updating menu item: $menuItemId');

      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (name != null) updateData['name'] = name;
      if (price != null) updateData['price'] = price;
      if (description != null) updateData['description'] = description;
      if (imageUrl != null) updateData['image_url'] = imageUrl;
      if (isAvailable != null) updateData['is_available'] = isAvailable;
      if (discount != null) updateData['discount'] = discount;
      if (preparationTime != null) {
        updateData['preparation_time'] = preparationTime;
      }

      final response = await _supabaseClient
          .from(AppConstants.tableMenus)
          .update(updateData)
          .eq('id', menuItemId)
          .select()
          .single();

      final item = MenuItem.fromJson(response);
      AppLogger.info('Menu item updated successfully');
      return item;
    } catch (e) {
      AppLogger.error('Error updating menu item: $e');
      rethrow;
    }
  }

  // Delete menu item
  Future<void> deleteMenuItem(String menuItemId) async {
    try {
      AppLogger.info('Deleting menu item: $menuItemId');

      await _supabaseClient
          .from(AppConstants.tableMenus)
          .delete()
          .eq('id', menuItemId);

      AppLogger.info('Menu item deleted successfully');
    } catch (e) {
      AppLogger.error('Error deleting menu item: $e');
      rethrow;
    }
  }

  // --- Side / Add-on management ---

  // Get sides for a menu item
  Future<List<MenuItemSide>> getSidesForMenuItem(String menuItemId) async {
    try {
      final response = await _supabaseClient
          .from(AppConstants.tableMenuItemSides)
          .select()
          .eq('menu_item_id', menuItemId)
          .order('name');
      return (response as List).map((s) => MenuItemSide.fromJson(s)).toList();
    } catch (e) {
      AppLogger.error('Error fetching sides: $e');
      rethrow;
    }
  }

  // Add a side to a menu item
  Future<MenuItemSide> addSide({
    required String menuItemId,
    required String name,
    required double price,
    String sideType = 'side',
  }) async {
    try {
      final response = await _supabaseClient
          .from(AppConstants.tableMenuItemSides)
          .insert({
            'menu_item_id': menuItemId,
            'name': name,
            'price': price,
            'is_available': true,
            'side_type': sideType,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();
      return MenuItemSide.fromJson(response);
    } catch (e) {
      AppLogger.error('Error adding side: $e');
      rethrow;
    }
  }

  // Delete a side
  Future<void> deleteSide(String sideId) async {
    try {
      await _supabaseClient
          .from(AppConstants.tableMenuItemSides)
          .delete()
          .eq('id', sideId);
    } catch (e) {
      AppLogger.error('Error deleting side: $e');
      rethrow;
    }
  }

  // Update an existing side (name, price, availability, type)
  Future<MenuItemSide> updateSide({
    required String sideId,
    String? name,
    double? price,
    bool? isAvailable,
    String? sideType,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (price != null) updates['price'] = price;
      if (isAvailable != null) updates['is_available'] = isAvailable;
      if (sideType != null) updates['side_type'] = sideType;
      if (updates.isEmpty) {
        throw ArgumentError('updateSide called with no fields to update');
      }
      final response = await _supabaseClient
          .from(AppConstants.tableMenuItemSides)
          .update(updates)
          .eq('id', sideId)
          .select()
          .single();
      return MenuItemSide.fromJson(response);
    } catch (e) {
      AppLogger.error('Error updating side: $e');
      rethrow;
    }
  }
}
