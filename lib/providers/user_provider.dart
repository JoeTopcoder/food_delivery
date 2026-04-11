import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final restaurantService = ref.watch(restaurantServiceProvider);
  return restaurantService.getAllRestaurants();
});

final topRatedRestaurantsProvider =
    FutureProvider.autoDispose<List<Restaurant>>((ref) async {
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
      final restaurantService = ref.watch(restaurantServiceProvider);
      return restaurantService.getRestaurantById(restaurantId);
    });

final restaurantsByCuisineProvider = FutureProvider.family
    .autoDispose<List<Restaurant>, String>((ref, cuisineType) async {
      final restaurantService = ref.watch(restaurantServiceProvider);
      return restaurantService.getRestaurantsByCuisine(cuisineType);
    });

final newlyAddedRestaurantsProvider =
    FutureProvider.autoDispose<List<Restaurant>>((ref) async {
      return ref.watch(restaurantServiceProvider).getNewlyAddedRestaurants();
    });

final breakfastRestaurantsProvider =
    FutureProvider.autoDispose<List<Restaurant>>((ref) async {
      return ref.watch(restaurantServiceProvider).getBreakfastRestaurants();
    });

final mustTryRestaurantsProvider = FutureProvider.autoDispose<List<Restaurant>>(
  (ref) async {
    return ref.watch(restaurantServiceProvider).getMustTryRestaurants();
  },
);

// Menu Providers
final restaurantMenuProvider = FutureProvider.family
    .autoDispose<List<MenuItem>, String>((ref, restaurantId) async {
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
      final orderService = ref.watch(orderServiceProvider);
      return orderService.getUserOrders(userId);
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

  CartItem({
    required this.menuItem,
    this.quantity = 1,
    this.notes,
    List<MenuItemSide>? selectedSides,
  }) : selectedSides = selectedSides ?? [];

  double get sidesTotal => selectedSides.fold(0.0, (sum, s) => sum + s.price);

  double get subtotal => (menuItem.discountedPrice + sidesTotal) * quantity;

  CartItem copyWith({
    MenuItem? menuItem,
    int? quantity,
    String? notes,
    List<MenuItemSide>? selectedSides,
  }) {
    return CartItem(
      menuItem: menuItem ?? this.menuItem,
      quantity: quantity ?? this.quantity,
      notes: notes ?? this.notes,
      selectedSides: selectedSides ?? this.selectedSides,
    );
  }
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

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
  void replaceWithItem(MenuItem menuItem, {List<MenuItemSide>? sides}) {
    state = [CartItem(menuItem: menuItem, selectedSides: sides)];
  }

  void addItem(MenuItem menuItem, {List<MenuItemSide>? sides}) {
    // If sides differ, treat as a separate line item
    final existingIndex = state.indexWhere(
      (item) =>
          item.menuItem.id == menuItem.id &&
          _sameSides(item.selectedSides, sides ?? []),
    );

    if (existingIndex != -1) {
      state[existingIndex].quantity++;
      state = [...state];
    } else {
      state = [...state, CartItem(menuItem: menuItem, selectedSides: sides)];
    }
  }

  bool _sameSides(List<MenuItemSide> a, List<MenuItemSide> b) {
    if (a.length != b.length) return false;
    final aIds = a.map((s) => s.id).toSet();
    final bIds = b.map((s) => s.id).toSet();
    return aIds.length == bIds.length && aIds.containsAll(bIds);
  }

  void removeItem(String menuItemId) {
    state = state.where((item) => item.menuItem.id != menuItemId).toList();
  }

  void updateQuantity(String menuItemId, int quantity) {
    final index = state.indexWhere((item) => item.menuItem.id == menuItemId);
    if (index != -1) {
      if (quantity <= 0) {
        removeItem(menuItemId);
      } else {
        state[index].quantity = quantity;
        state = [...state];
      }
    }
  }

  void updateNotes(String menuItemId, String notes) {
    final index = state.indexWhere((item) => item.menuItem.id == menuItemId);
    if (index != -1) {
      state[index].notes = notes;
      state = [...state];
    }
  }

  void clearCart() {
    state = [];
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

// Restaurant Owner Providers
final restaurantByOwnerProvider = FutureProvider.family
    .autoDispose<Restaurant?, String>((ref, ownerId) async {
      final restaurantService = ref.watch(restaurantServiceProvider);
      return restaurantService.getRestaurantByOwnerId(ownerId);
    });

final restaurantOrdersProvider = FutureProvider.family
    .autoDispose<List<Order>, String>((ref, restaurantId) async {
      final orderService = ref.watch(orderServiceProvider);
      return orderService.getRestaurantOrders(restaurantId);
    });

// ==================== RESTAURANT REALTIME NOTIFICATIONS ====================

/// Watches the orders table via Supabase Realtime for new orders targeting
/// a specific restaurant. Shows in-app notification and refreshes orders list.
final restaurantNewOrderRealtimeProvider = Provider.family
    .autoDispose<void, String>((ref, restaurantId) {
      final channel = SupabaseConfig.client.realtime.channel(
        'restaurant_orders_$restaurantId',
      );

      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
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
          ref.invalidate(restaurantOrdersProvider(restaurantId));
          NotificationService.onNewOrderForRestaurant?.call();
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
