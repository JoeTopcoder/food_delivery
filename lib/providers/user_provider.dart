import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/restaurant_model.dart';
import '../models/menu_model.dart';
import '../models/order_model.dart';
import '../services/restaurant_service.dart';
import '../services/menu_service.dart';
import '../services/order_service.dart';
import '../services/order_calculation_service.dart';
import '../services/notification_service.dart';
import '../config/supabase_config.dart';
import '../utils/app_logger.dart';

// Service Providers
final restaurantServiceProvider = Provider<RestaurantService>((ref) {
  return RestaurantService(SupabaseConfig.client);
});

final menuServiceProvider = Provider<MenuService>((ref) {
  return MenuService(SupabaseConfig.client);
});

final orderServiceProvider = Provider<OrderService>((ref) {
  return OrderService(SupabaseConfig.client);
});

final orderCalculationServiceProvider = Provider<OrderCalculationService>((
  ref,
) {
  return OrderCalculationService(SupabaseConfig.client);
});

// Restaurant Providers
final allRestaurantsProvider = FutureProvider.autoDispose<List<Restaurant>>((
  ref,
) async {
  final link = ref.keepAlive();
  final restaurantService = ref.watch(restaurantServiceProvider);
  return restaurantService.getAllRestaurants();
});

final topRatedRestaurantsProvider =
    FutureProvider.autoDispose<List<Restaurant>>((ref) async {
      final link = ref.keepAlive();
      final restaurantService = ref.watch(restaurantServiceProvider);
      return restaurantService.getTopRatedRestaurants();
    });

final restaurantSearchProvider = FutureProvider.family
    .autoDispose<List<Restaurant>, String>((ref, query) async {
      final restaurantService = ref.watch(restaurantServiceProvider);
      if (query.isEmpty) {
        return restaurantService.getAllRestaurants();
      }
      return restaurantService.searchRestaurants(query);
    });

final restaurantByIdProvider = FutureProvider.family
    .autoDispose<Restaurant?, String>((ref, restaurantId) async {
      final link = ref.keepAlive();
      final restaurantService = ref.watch(restaurantServiceProvider);

      // Real-time: refresh when this restaurant row changes
      final channel = Supabase.instance.client.realtime.channel(
        'rest_${restaurantId}_${DateTime.now().microsecondsSinceEpoch}',
      );
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'restaurants',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: restaurantId,
            ),
            callback: (_) => ref.invalidateSelf(),
          )
          .subscribe();
      ref.onDispose(
        () => Supabase.instance.client.realtime.removeChannel(channel),
      );

      return restaurantService.getRestaurantById(restaurantId);
    });

final restaurantsByCuisineProvider = FutureProvider.family
    .autoDispose<List<Restaurant>, String>((ref, cuisineType) async {
      final restaurantService = ref.watch(restaurantServiceProvider);
      return restaurantService.getRestaurantsByCuisine(cuisineType);
    });

final newlyAddedRestaurantsProvider =
    FutureProvider.autoDispose<List<Restaurant>>((ref) async {
      final link = ref.keepAlive();
      return ref.watch(restaurantServiceProvider).getNewlyAddedRestaurants();
    });

final breakfastRestaurantsProvider =
    FutureProvider.autoDispose<List<Restaurant>>((ref) async {
      final link = ref.keepAlive();
      return ref.watch(restaurantServiceProvider).getBreakfastRestaurants();
    });

final mustTryRestaurantsProvider = FutureProvider.autoDispose<List<Restaurant>>(
  (ref) async {
    final link = ref.keepAlive();
    return ref.watch(restaurantServiceProvider).getMustTryRestaurants();
  },
);

// Menu Providers — no autoDispose so data stays cached across screen visits
final restaurantMenuProvider = FutureProvider.family
    .autoDispose<List<MenuItem>, String>((ref, restaurantId) async {
      final link = ref.keepAlive();
      final menuService = ref.watch(menuServiceProvider);
      return menuService.getMenuByRestaurant(restaurantId);
    });

final menuItemByIdProvider = FutureProvider.family
    .autoDispose<MenuItem?, String>((ref, menuItemId) async {
      final menuService = ref.watch(menuServiceProvider);
      return menuService.getMenuItemById(menuItemId);
    });

final menuSearchProvider = FutureProvider.family
    .autoDispose<List<MenuItem>, String>((ref, query) async {
      final menuService = ref.watch(menuServiceProvider);
      if (query.isEmpty) {
        return [];
      }
      return menuService.searchMenuItems(query);
    });

final menuByCategoryProvider = FutureProvider.family
    .autoDispose<List<MenuItem>, ({String restaurantId, String category})>((
      ref,
      params,
    ) async {
      final menuService = ref.watch(menuServiceProvider);
      return menuService.getMenuItemsByCategory(
        params.restaurantId,
        params.category,
      );
    });

// Order Providers
final userOrdersProvider = FutureProvider.family
    .autoDispose<List<Order>, String>((ref, userId) async {
      ref.keepAlive();
      final orderService = ref.watch(orderServiceProvider);
      return orderService.getUserOrders(userId);
    });

/// Real-time watcher for customer orders — invalidates userOrdersProvider on
/// any INSERT, UPDATE, or DELETE so the orders list stays fresh instantly.
final customerOrderRealtimeProvider = Provider.family.autoDispose<void, String>((
  ref,
  userId,
) {
  final channel = SupabaseConfig.client.realtime.channel(
    'customer_orders_$userId',
  );

  channel.onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: 'orders',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: userId,
    ),
    callback: (payload) {
      final newStatus = payload.newRecord['status'] as String?;
      AppLogger.info(
        'Customer Realtime: order update (status=$newStatus) for user $userId',
      );
      ref.invalidate(userOrdersProvider(userId));
    },
  );

  channel.subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
    AppLogger.info(
      'Customer Realtime: customer_orders_$userId channel disposed',
    );
  });
});

final orderByIdProvider = FutureProvider.family.autoDispose<Order?, String>((
  ref,
  orderId,
) async {
  final orderService = ref.watch(orderServiceProvider);
  return orderService.getOrderById(orderId);
});

// Cart State Notifier
class CartItem {
  final MenuItem menuItem;
  int quantity;
  String? notes;
  List<MenuItemSide> selectedSides;

  /// Map of groupId -> list of selected OptionChoice
  Map<String, List<OptionChoice>> selectedOptions;

  CartItem({
    required this.menuItem,
    this.quantity = 1,
    this.notes,
    List<MenuItemSide>? selectedSides,
    Map<String, List<OptionChoice>>? selectedOptions,
  }) : selectedSides = selectedSides ?? [],
       selectedOptions = selectedOptions ?? {};

  double get sidesTotal => selectedSides.fold(0.0, (sum, s) => sum + s.price);

  double get optionsTotal => selectedOptions.values
      .expand((choices) => choices)
      .fold(0.0, (sum, c) => sum + c.price);

  double get subtotal =>
      (menuItem.discountedPrice + sidesTotal + optionsTotal) * quantity;

  /// Readable summary of all selected options for display.
  String get optionsSummary {
    final parts = <String>[];
    for (final choices in selectedOptions.values) {
      for (final c in choices) {
        parts.add(c.name);
      }
    }
    return parts.join(', ');
  }

  CartItem copyWith({
    MenuItem? menuItem,
    int? quantity,
    String? notes,
    List<MenuItemSide>? selectedSides,
    Map<String, List<OptionChoice>>? selectedOptions,
  }) {
    return CartItem(
      menuItem: menuItem ?? this.menuItem,
      quantity: quantity ?? this.quantity,
      notes: notes ?? this.notes,
      selectedSides: selectedSides ?? this.selectedSides,
      selectedOptions: selectedOptions ?? this.selectedOptions,
    );
  }

  Map<String, dynamic> toJson() => {
    'menuItem': menuItem.toJson(),
    'quantity': quantity,
    'notes': notes,
    'selectedSides': selectedSides.map((s) => s.toJson()).toList(),
    'selectedOptions': selectedOptions.map(
      (groupId, choices) =>
          MapEntry(groupId, choices.map((c) => c.toJson()).toList()),
    ),
  };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      menuItem: MenuItem.fromJson(json['menuItem'] as Map<String, dynamic>),
      quantity: json['quantity'] as int? ?? 1,
      notes: json['notes'] as String?,
      selectedSides:
          (json['selectedSides'] as List?)
              ?.map((s) => MenuItemSide.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      selectedOptions:
          (json['selectedOptions'] as Map<String, dynamic>?)?.map(
            (groupId, choices) => MapEntry(
              groupId,
              (choices as List)
                  .map((c) => OptionChoice.fromJson(c as Map<String, dynamic>))
                  .toList(),
            ),
          ) ??
          {},
    );
  }
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  static const _storageKey = 'persisted_cart';

  CartNotifier() : super([]) {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List)
            .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
            .toList();
        state = list;
      }
    } catch (e) {
      AppLogger.error('Cart load error: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(state.map((c) => c.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      AppLogger.error('Cart save error: $e');
    }
  }

  /// Returns the restaurantId currently in the cart, or null if empty.
  String? get currentRestaurantId =>
      state.isNotEmpty ? state.first.menuItem.restaurantId : null;

  /// Returns true if the item belongs to a different restaurant than what's in
  /// the cart already.
  bool isDifferentRestaurant(MenuItem menuItem) {
    final rid = currentRestaurantId;
    return rid != null && rid != menuItem.restaurantId;
  }

  /// Clear the cart and add the item from the new restaurant.
  void replaceWithItem(
    MenuItem menuItem, {
    List<MenuItemSide>? sides,
    Map<String, List<OptionChoice>>? options,
  }) {
    state = [
      CartItem(
        menuItem: menuItem,
        selectedSides: sides,
        selectedOptions: options,
      ),
    ];
    _persist();
  }

  void addItem(
    MenuItem menuItem, {
    List<MenuItemSide>? sides,
    Map<String, List<OptionChoice>>? options,
  }) {
    // If sides/options differ, treat as a separate line item
    final existingIndex = state.indexWhere(
      (item) =>
          item.menuItem.id == menuItem.id &&
          _sameSides(item.selectedSides, sides ?? []) &&
          _sameOptions(item.selectedOptions, options ?? {}),
    );

    if (existingIndex != -1) {
      state[existingIndex].quantity++;
      state = [...state];
    } else {
      state = [
        ...state,
        CartItem(
          menuItem: menuItem,
          selectedSides: sides,
          selectedOptions: options,
        ),
      ];
    }
    _persist();
  }

  bool _sameSides(List<MenuItemSide> a, List<MenuItemSide> b) {
    if (a.length != b.length) return false;
    final aIds = a.map((s) => s.id).toSet();
    final bIds = b.map((s) => s.id).toSet();
    return aIds.length == bIds.length && aIds.containsAll(bIds);
  }

  bool _sameOptions(
    Map<String, List<OptionChoice>> a,
    Map<String, List<OptionChoice>> b,
  ) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      final aIds = a[key]!.map((c) => c.id).toSet();
      final bIds = b[key]!.map((c) => c.id).toSet();
      if (!aIds.containsAll(bIds) || aIds.length != bIds.length) return false;
    }
    return true;
  }

  void removeItem(String menuItemId) {
    state = state.where((item) => item.menuItem.id != menuItemId).toList();
    _persist();
  }

  void updateQuantity(String menuItemId, int quantity) {
    final index = state.indexWhere((item) => item.menuItem.id == menuItemId);
    if (index != -1) {
      if (quantity <= 0) {
        removeItem(menuItemId);
      } else {
        state[index].quantity = quantity;
        state = [...state];
        _persist();
      }
    }
  }

  void updateNotes(String menuItemId, String notes) {
    final index = state.indexWhere((item) => item.menuItem.id == menuItemId);
    if (index != -1) {
      state[index].notes = notes;
      state = [...state];
      _persist();
    }
  }

  void clearCart() {
    state = [];
    _persist();
  }

  double getSubtotal() {
    return state.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  int getItemCount() {
    return state.fold(0, (sum, item) => sum + item.quantity);
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});

// Calculated cart totals
final cartSubtotalProvider = Provider.autoDispose<double>((ref) {
  final cart = ref.watch(cartProvider);
  return cart.fold(0.0, (sum, item) => sum + item.subtotal);
});

final cartItemCountProvider = Provider.autoDispose<int>((ref) {
  final cart = ref.watch(cartProvider);
  return cart.fold(0, (sum, item) => sum + item.quantity);
});

// ── Grocery Cart (separate from restaurant cart) ──────────────────────────

class GroceryCartNotifier extends StateNotifier<List<CartItem>> {
  static const _storageKey = 'persisted_grocery_cart';

  GroceryCartNotifier() : super([]) {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List)
            .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
            .toList();
        state = list;
      }
    } catch (e) {
      AppLogger.error('Grocery cart load error: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(state.map((c) => c.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      AppLogger.error('Grocery cart save error: $e');
    }
  }

  /// Returns all distinct store IDs currently in the cart.
  Set<String> get storeIds => state.map((c) => c.menuItem.restaurantId).toSet();

  void addItem(MenuItem menuItem) {
    final existingIndex = state.indexWhere(
      (item) => item.menuItem.id == menuItem.id,
    );
    if (existingIndex != -1) {
      final current = state[existingIndex].quantity;
      if (current >= menuItem.maxQuantity) return;
      state[existingIndex].quantity++;
      state = [...state];
    } else {
      if (menuItem.maxQuantity <= 0) return;
      state = [...state, CartItem(menuItem: menuItem)];
    }
    _persist();
  }

  void removeItem(String menuItemId) {
    state = state.where((item) => item.menuItem.id != menuItemId).toList();
    _persist();
  }

  void updateQuantity(String menuItemId, int quantity) {
    final index = state.indexWhere((item) => item.menuItem.id == menuItemId);
    if (index != -1) {
      if (quantity <= 0) {
        removeItem(menuItemId);
      } else {
        state[index].quantity = quantity;
        state = [...state];
        _persist();
      }
    }
  }

  void clearCart() {
    state = [];
    _persist();
  }

  double getSubtotal() {
    return state.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  int getItemCount() {
    return state.fold(0, (sum, item) => sum + item.quantity);
  }
}

final groceryCartProvider =
    StateNotifierProvider<GroceryCartNotifier, List<CartItem>>((ref) {
      return GroceryCartNotifier();
    });

final groceryCartSubtotalProvider = Provider.autoDispose<double>((ref) {
  final cart = ref.watch(groceryCartProvider);
  return cart.fold(0.0, (sum, item) => sum + item.subtotal);
});

final groceryCartItemCountProvider = Provider.autoDispose<int>((ref) {
  final cart = ref.watch(groceryCartProvider);
  return cart.fold(0, (sum, item) => sum + item.quantity);
});

/// Whether the customer chose pickup for grocery orders.
final groceryIsPickupProvider = StateProvider<bool>((ref) => false);

/// Whether the customer chose pickup instead of delivery.
final isPickupProvider = StateProvider<bool>((ref) => false);

// Restaurant Owner Providers
final restaurantByOwnerProvider = FutureProvider.family
    .autoDispose<Restaurant?, String>((ref, ownerId) async {
      final restaurantService = ref.watch(restaurantServiceProvider);

      // Real-time: refresh when any restaurant owned by this user changes
      final channel = Supabase.instance.client.realtime.channel(
        'rest_owner_${ownerId}_${DateTime.now().microsecondsSinceEpoch}',
      );
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'restaurants',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'owner_id',
              value: ownerId,
            ),
            callback: (_) => ref.invalidateSelf(),
          )
          .subscribe();
      ref.onDispose(
        () => Supabase.instance.client.realtime.removeChannel(channel),
      );

      return restaurantService.getRestaurantByOwnerId(ownerId);
    });

// All restaurants for an owner (multi-restaurant support)
final restaurantsByOwnerProvider = FutureProvider.family
    .autoDispose<List<Restaurant>, String>((ref, ownerId) async {
      final restaurantService = ref.watch(restaurantServiceProvider);
      return restaurantService.getRestaurantsByOwnerId(ownerId);
    });

// Orders across ALL restaurants for an owner
final ownerAllOrdersProvider = FutureProvider.family
    .autoDispose<List<Order>, String>((ref, ownerId) async {
      final restaurants = await ref.watch(
        restaurantsByOwnerProvider(ownerId).future,
      );
      if (restaurants.isEmpty) return [];
      final restaurantIds = restaurants.map((r) => r.id).toList();
      final orderService = ref.watch(orderServiceProvider);
      return orderService.getOrdersForRestaurants(restaurantIds);
    });

final restaurantOrdersProvider = FutureProvider.family
    .autoDispose<List<Order>, String>((ref, restaurantId) async {
      ref.keepAlive();
      final orderService = ref.watch(orderServiceProvider);
      return orderService.getRestaurantOrders(restaurantId);
    });

// ==================== RESTAURANT REALTIME NOTIFICATIONS ====================

/// Owner-level realtime: watches ALL restaurants for a given owner.
/// Invalidates ownerAllOrdersProvider when new orders come in to any restaurant.
final ownerOrderRealtimeProvider = Provider.family.autoDispose<void, String>((
  ref,
  ownerId,
) {
  final restaurantsAsync = ref.watch(restaurantsByOwnerProvider(ownerId));

  restaurantsAsync.whenData((restaurants) {
    for (final restaurant in restaurants) {
      final channel = SupabaseConfig.client.realtime.channel(
        'owner_orders_${restaurant.id}',
      );

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'restaurant_id',
          value: restaurant.id,
        ),
        callback: (payload) {
          final record = payload.newRecord;
          final orderId = record['id'] ?? '';
          final eventType = payload.eventType;

          if (eventType == PostgresChangeEvent.insert) {
            AppLogger.info(
              'Owner Realtime: new order #$orderId at ${restaurant.name}',
            );
            NotificationService().showNotification(
              title: 'New Order Received! 🔔',
              body: 'New order #$orderId at ${restaurant.name}.',
              data: {
                'type': 'new_restaurant_order',
                'order_id': orderId.toString(),
                'restaurant_id': restaurant.id,
              },
            );
            NotificationService.onNewOrderForRestaurant?.call();
          } else {
            AppLogger.info(
              'Owner Realtime: order #$orderId updated at ${restaurant.name}',
            );
          }
          ref.invalidate(ownerAllOrdersProvider(ownerId));
        },
      );

      channel.subscribe();

      ref.onDispose(() {
        channel.unsubscribe();
        AppLogger.info(
          'Owner Realtime: owner_orders_${restaurant.id} channel disposed',
        );
      });
    }
  });
});

/// Watches the orders table via Supabase Realtime for new orders targeting
/// a specific restaurant. Shows in-app notification and refreshes orders list.
final restaurantNewOrderRealtimeProvider = Provider.family
    .autoDispose<void, String>((ref, restaurantId) {
      final channel = SupabaseConfig.client.realtime.channel(
        'restaurant_orders_$restaurantId',
      );

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'restaurant_id',
          value: restaurantId,
        ),
        callback: (payload) {
          final record = payload.newRecord;
          final orderId = record['id'] ?? '';
          final eventType = payload.eventType;

          if (eventType == PostgresChangeEvent.insert) {
            AppLogger.info('Restaurant Realtime: new order #$orderId received');
            NotificationService().showNotification(
              title: 'New Order Received! 🔔',
              body: 'You have a new order #$orderId to prepare.',
              data: {
                'type': 'new_restaurant_order',
                'order_id': orderId.toString(),
                'restaurant_id': restaurantId,
              },
            );
            NotificationService.onNewOrderForRestaurant?.call();
          } else {
            final status = record['status'] as String? ?? '';
            AppLogger.info(
              'Restaurant Realtime: order #$orderId updated (status=$status)',
            );
          }

          ref.invalidate(restaurantOrdersProvider(restaurantId));
        },
      );

      channel.subscribe();

      ref.onDispose(() {
        channel.unsubscribe();
        AppLogger.info(
          'Restaurant Realtime: restaurant_orders_$restaurantId channel disposed',
        );
      });
    });
