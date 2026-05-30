import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/restaurant_model.dart';
import '../models/menu_model.dart';
import '../models/order_model.dart';
import '../models/master_order_model.dart';
import '../models/cart_recommendation_model.dart';
import '../services/food/restaurant_service.dart';
import '../services/food/menu_service.dart';
import '../services/food/menu_category_service.dart';
import '../services/food/order_service.dart';
import '../services/food/order_calculation_service.dart';
import '../services/notification_service.dart';
import '../config/supabase_config.dart';
import '../utils/app_logger.dart';

// Tracks the currently selected bottom-nav tab index so any screen can gate
// behaviour (e.g. popup banners) on which tab is visible.
final currentTabIndexProvider = StateProvider<int>((ref) => 0);

// Service Providers
final restaurantServiceProvider = Provider<RestaurantService>((ref) {
  return RestaurantService(SupabaseConfig.client);
});

final menuServiceProvider = Provider<MenuService>((ref) {
  return MenuService(SupabaseConfig.client);
});

final menuCategoryServiceProvider = Provider<MenuCategoryService>((ref) {
  return MenuCategoryService(SupabaseConfig.client);
});

// Meals across open restaurants for a specific category, fetched via the
// `menu-by-category` Supabase edge function.
final mealsByCategoryProvider = FutureProvider.family
    .autoDispose<List<MenuItemWithRestaurant>, String>((ref, category) async {
      ref.keepAlive();
      final service = ref.watch(menuCategoryServiceProvider);
      return service.getMealsByCategory(category);
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
  ref.keepAlive();
  final restaurantService = ref.watch(restaurantServiceProvider);
  return restaurantService.getAllRestaurants();
});

final topRatedRestaurantsProvider =
    FutureProvider.autoDispose<List<Restaurant>>((ref) async {
      ref.keepAlive();
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
      ref.keepAlive();
      final restaurantService = ref.watch(restaurantServiceProvider);

      // Real-time: refresh when this restaurant row changes
      // Stable channel name — avoids churn from microsecond-suffix unique names
      final channel = Supabase.instance.client.realtime.channel(
        'rest_$restaurantId',
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
      ref.keepAlive();
      return ref.watch(restaurantServiceProvider).getNewlyAddedRestaurants();
    });

final breakfastRestaurantsProvider =
    FutureProvider.autoDispose<List<Restaurant>>((ref) async {
      ref.keepAlive();
      return ref.watch(restaurantServiceProvider).getBreakfastRestaurants();
    });

final mustTryRestaurantsProvider = FutureProvider.autoDispose<List<Restaurant>>(
  (ref) async {
    ref.keepAlive();
    return ref.watch(restaurantServiceProvider).getMustTryRestaurants();
  },
);

// Menu Providers — no autoDispose so data stays cached across screen visits
final restaurantMenuProvider = FutureProvider.family
    .autoDispose<List<MenuItem>, String>((ref, restaurantId) async {
      ref.keepAlive();
      final menuService = ref.watch(menuServiceProvider);
      return menuService.getMenuByRestaurant(restaurantId);
    });

// Used by the restaurant owner's management screen — returns ALL menu items
// (including ones marked unavailable) so they can manage everything.
final restaurantMenuManagementProvider = FutureProvider.family
    .autoDispose<List<MenuItem>, String>((ref, restaurantId) async {
      ref.keepAlive();
      final menuService = ref.watch(menuServiceProvider);
      return menuService.getAllMenuByRestaurant(restaurantId);
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

/// Like [orderByIdProvider] but also falls back to looking up by order_group_id.
/// Used by the tracking screen so multi-restaurant orders (which pass an
/// order_group_id instead of an orders.id) resolve to a trackable sub-order.
final orderByIdOrGroupIdProvider = FutureProvider.family.autoDispose<Order?, String>((
  ref,
  orderId,
) async {
  final orderService = ref.watch(orderServiceProvider);
  final order = await orderService.getOrderById(orderId);
  if (order != null) return order;

  // Fallback: treat orderId as an order_group_id. Fetch all sub-orders,
  // merge their items, and override with group-level receipt number + grand total.
  try {
    final rows = await SupabaseConfig.client
        .from('orders')
        .select(
          '*, order_items(*, order_item_sides(*)), order_groups(receipt_number, total_amount)',
        )
        .eq('order_group_id', orderId)
        .order('sequence_in_group', ascending: true);
    if (rows.isEmpty) return null;

    // Use the first sub-order as the base
    final base = Map<String, dynamic>.from(rows[0] as Map);
    final groupData = base.remove('order_groups') as Map<String, dynamic>?;

    // Combine items from all sub-orders
    final allItems = <dynamic>[];
    for (final row in rows) {
      allItems.addAll((row['order_items'] as List? ?? []));
    }
    base['order_items'] = allItems;

    // Override with group-level receipt number and grand total
    if (groupData != null) {
      if (groupData['receipt_number'] != null) {
        base['receipt_number'] = groupData['receipt_number'];
      }
      if (groupData['total_amount'] != null) {
        base['total_amount'] = groupData['total_amount'];
      }
    }

    final items = (base['order_items'] as List).map((itemJson) {
      final sides = (itemJson['order_item_sides'] as List? ?? [])
          .map((s) => OrderItemSide.fromJson(s as Map<String, dynamic>))
          .toList();
      return OrderItem.fromJson({
        ...itemJson as Map<String, dynamic>,
        'sides': sides.map((s) => s.toJson()).toList(),
      });
    }).toList();
    return Order.fromJson({
      ...base,
      'items': items.map((item) => item.toJson()).toList(),
    });
  } catch (e) {
    AppLogger.error('Error fetching order by group id: $e');
    return null;
  }
});

// ─── Master Order Providers (new multi-restaurant schema) ─────────────────────

/// Full detail for one master order.
/// Uses separate flat queries (avoids PostgREST nested-join schema-cache issues).
/// Falls back to legacy order_groups + orders schema for pre-migration orders.
final masterOrderDetailProvider = FutureProvider.family
    .autoDispose<MasterOrder?, String>((ref, masterOrderId) async {
      // ── 1. New schema: master_orders ───────────────────────────────────────────
      final moRow = await SupabaseConfig.client
          .from('master_orders')
          .select('*')
          .eq('id', masterOrderId)
          .maybeSingle();

      if (moRow != null) {
        // Flat query for restaurant_orders (no nested join)
        final roRows = await SupabaseConfig.client
            .from('restaurant_orders')
            .select('*')
            .eq('master_order_id', masterOrderId)
            .order('sequence_in_group', ascending: true);

        final restaurantOrders = <RestaurantOrder>[];
        for (final ro in roRows as List) {
          final roId = ro['id'] as String;
          final restaurantId = ro['restaurant_id'] as String;

          // Restaurant name
          final restRow = await SupabaseConfig.client
              .from('restaurants')
              .select('name')
              .eq('id', restaurantId)
              .maybeSingle();
          final restaurantName = restRow?['name'] as String?;

          // Items for this restaurant_order
          final itemRows = await SupabaseConfig.client
              .from('restaurant_order_items')
              .select('*')
              .eq('restaurant_order_id', roId);

          final items = <RestaurantOrderItem>[];
          for (final it in itemRows as List) {
            final itemId = it['id'] as String;
            final sideRows = await SupabaseConfig.client
                .from('restaurant_order_item_sides')
                .select('*')
                .eq('restaurant_order_item_id', itemId);

            items.add(
              RestaurantOrderItem(
                id: itemId,
                restaurantOrderId: roId,
                menuItemId: it['menu_item_id'] as String?,
                itemName: it['item_name'] as String? ?? '',
                price: (it['price'] as num?)?.toDouble() ?? 0,
                quantity: (it['quantity'] as num?)?.toInt() ?? 1,
                notes: it['notes'] as String?,
                sides: (sideRows as List)
                    .map(
                      (s) => RestaurantOrderItemSide(
                        id: s['id'] as String? ?? '',
                        restaurantOrderItemId: itemId,
                        sideName: s['side_name'] as String? ?? '',
                        sidePrice: (s['side_price'] as num?)?.toDouble() ?? 0,
                      ),
                    )
                    .toList(),
              ),
            );
          }

          restaurantOrders.add(
            RestaurantOrder(
              id: roId,
              masterOrderId: masterOrderId,
              restaurantId: restaurantId,
              restaurantName: restaurantName,
              restaurantOrderNumber: ro['restaurant_order_number'] as String?,
              status: ro['status'] as String? ?? 'pending',
              subtotal: (ro['subtotal'] as num?)?.toDouble() ?? 0,
              deliveryFee: (ro['delivery_fee'] as num?)?.toDouble() ?? 0,
              commissionRate: (ro['commission_rate'] as num?)?.toDouble(),
              commissionAmount: (ro['commission_amount'] as num?)?.toDouble(),
              distanceKm: (ro['distance_km'] as num?)?.toDouble(),
              sequenceInGroup: (ro['sequence_in_group'] as num?)?.toInt() ?? 1,
              deliveryOtp: ro['delivery_otp'] as String?,
              pickupStatus: ro['pickup_status'] as String? ?? 'pending',
              notes: ro['notes'] as String?,
              createdAt: DateTime.parse(ro['created_at'] as String),
              items: items,
              deliveryAddress: moRow['delivery_address'] as String?,
              contactlessDelivery:
                  moRow['contactless_delivery'] as bool? ?? false,
              paymentMethod: moRow['payment_method'] as String?,
            ),
          );
        }

        final m = moRow;
        return MasterOrder(
          id: masterOrderId,
          customerId: m['customer_id'] as String? ?? '',
          masterOrderNumber: m['master_order_number'] as String?,
          status: m['status'] as String? ?? 'pending',
          deliveryAddress: m['delivery_address'] as String? ?? '',
          deliveryLatitude: (m['delivery_latitude'] as num?)?.toDouble(),
          deliveryLongitude: (m['delivery_longitude'] as num?)?.toDouble(),
          paymentMethod: m['payment_method'] as String? ?? 'stripe',
          paymentStatus: m['payment_status'] as String? ?? 'pending',
          subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
          deliveryFee: (m['delivery_fee'] as num?)?.toDouble() ?? 0,
          extraStopFee: (m['extra_stop_fee'] as num?)?.toDouble() ?? 0,
          platformFee: (m['platform_fee'] as num?)?.toDouble() ?? 0,
          taxAmount: (m['tax_amount'] as num?)?.toDouble() ?? 0,
          discount: (m['discount'] as num?)?.toDouble() ?? 0,
          totalAmount: (m['total_amount'] as num?)?.toDouble() ?? 0,
          driverId: m['driver_id'] as String?,
          notes: m['notes'] as String?,
          isPickup: m['is_pickup'] as bool? ?? false,
          contactlessDelivery: m['contactless_delivery'] as bool? ?? false,
          driverTip: (m['driver_tip'] as num?)?.toDouble(),
          postDeliveryTip: (m['post_delivery_tip'] as num?)?.toDouble(),
          deliveryOtp: m['delivery_otp'] as String?,
          deliveryOtpVerified: m['delivery_otp_verified'] as bool?,
          deliveryPhotoUrl: m['delivery_photo_url'] as String?,
          estimatedDeliveryAt: m['estimated_delivery_at'] == null
              ? null
              : DateTime.parse(m['estimated_delivery_at'] as String),
          deliveredAt: m['delivered_at'] == null
              ? null
              : DateTime.parse(m['delivered_at'] as String),
          cancelledAt: m['cancelled_at'] == null
              ? null
              : DateTime.parse(m['cancelled_at'] as String),
          createdAt: DateTime.parse(m['created_at'] as String),
          restaurantOrders: restaurantOrders,
        );
      }

      // ── 2. Legacy fallback: order_groups + orders (pre-migration data) ─────────
      final subRows = await SupabaseConfig.client
          .from('orders')
          .select('*, order_items(*, order_item_sides(*)), restaurants(name)')
          .eq('order_group_id', masterOrderId)
          .order('sequence_in_group', ascending: true);

      if ((subRows as List).isEmpty) return null;

      final groupRow = await SupabaseConfig.client
          .from('order_groups')
          .select(
            'id, receipt_number, total_amount, customer_id, created_at, '
            'delivery_address, payment_method, payment_status, status',
          )
          .eq('id', masterOrderId)
          .maybeSingle();

      final now = DateTime.now();
      final legacyOrders =
          subRows.map((row) {
              final r = Map<String, dynamic>.from(row as Map);
              final restData = r.remove('restaurants') as Map<String, dynamic>?;
              final itemsList = (r.remove('order_items') as List?) ?? [];

              final items = itemsList.map((it) {
                final item = Map<String, dynamic>.from(it as Map);
                final sides = (item.remove('order_item_sides') as List? ?? [])
                    .map((s) {
                      final sm = s as Map<String, dynamic>;
                      return RestaurantOrderItemSide(
                        id: sm['id'] as String? ?? '',
                        restaurantOrderItemId: '',
                        sideName: sm['side_name'] as String? ?? '',
                        sidePrice: (sm['side_price'] as num?)?.toDouble() ?? 0,
                      );
                    })
                    .toList();
                return RestaurantOrderItem(
                  id: item['id'] as String? ?? '',
                  restaurantOrderId: r['id'] as String? ?? '',
                  menuItemId: item['menu_item_id'] as String?,
                  itemName: item['item_name'] as String? ?? '',
                  price: (item['price'] as num?)?.toDouble() ?? 0,
                  quantity: (item['quantity'] as num?)?.toInt() ?? 1,
                  notes: item['notes'] as String?,
                  sides: sides,
                );
              }).toList();

              return RestaurantOrder(
                id: r['id'] as String,
                masterOrderId: masterOrderId,
                restaurantId: r['restaurant_id'] as String,
                restaurantName: restData?['name'] as String?,
                restaurantOrderNumber: r['restaurant_order_number'] as String?,
                status: r['status'] as String? ?? 'pending',
                subtotal: (r['subtotal'] as num?)?.toDouble() ?? 0,
                deliveryFee: (r['delivery_fee'] as num?)?.toDouble() ?? 0,
                sequenceInGroup: (r['sequence_in_group'] as num?)?.toInt() ?? 1,
                deliveryOtp: r['delivery_otp'] as String?,
                createdAt:
                    DateTime.tryParse(r['ordered_at'] as String? ?? '') ?? now,
                items: items,
                deliveryAddress: r['delivery_address'] as String?,
              );
            }).toList()
            ..sort((a, b) => a.sequenceInGroup.compareTo(b.sequenceInGroup));

      return MasterOrder(
        id: masterOrderId,
        customerId: groupRow?['customer_id'] as String? ?? '',
        masterOrderNumber: groupRow?['receipt_number'] as String?,
        status:
            groupRow?['status'] as String? ??
            (subRows.first['status'] as String? ?? 'pending'),
        deliveryAddress:
            groupRow?['delivery_address'] as String? ??
            (subRows.first['delivery_address'] as String? ?? ''),
        paymentMethod: groupRow?['payment_method'] as String? ?? 'stripe',
        paymentStatus: groupRow?['payment_status'] as String? ?? 'pending',
        subtotal: legacyOrders.fold(0.0, (s, r) => s + r.subtotal),
        deliveryFee: legacyOrders.fold(0.0, (s, r) => s + r.deliveryFee),
        totalAmount:
            (groupRow?['total_amount'] as num?)?.toDouble() ??
            legacyOrders.fold(0.0, (s, r) => s + r.subtotal + r.deliveryFee),
        createdAt:
            DateTime.tryParse(groupRow?['created_at'] as String? ?? '') ??
            DateTime.tryParse(subRows.first['ordered_at'] as String? ?? '') ??
            now,
        restaurantOrders: legacyOrders,
      );
    });

/// All master orders for a customer — used by history screen.
/// Uses three flat batch queries instead of nested PostgREST joins to avoid
/// schema-cache issues on newly created tables.
final customerMasterOrdersProvider = FutureProvider.family
    .autoDispose<List<MasterOrder>, String>((ref, customerId) async {
      try {
        // 1. Fetch master orders
        final moRows = await SupabaseConfig.client
            .from('master_orders')
            .select('*')
            .eq('customer_id', customerId)
            .order('created_at', ascending: false)
            .limit(500);

        if ((moRows as List).isEmpty) return [];

        final masterOrderIds = moRows
            .map((r) => (r as Map)['id'] as String)
            .toList();

        // 2. Fetch all restaurant_orders for these master orders in one query
        final roRows = await SupabaseConfig.client
            .from('restaurant_orders')
            .select(
              'id, master_order_id, restaurant_id, restaurant_order_number, '
              'status, subtotal, delivery_fee, sequence_in_group, '
              'delivery_otp, pickup_status, notes, created_at',
            )
            .inFilter('master_order_id', masterOrderIds)
            .order('sequence_in_group', ascending: true);

        // 3. Fetch restaurant names for all referenced restaurants in one query
        final restaurantIds = (roRows as List)
            .map((r) => (r as Map)['restaurant_id'] as String)
            .toSet()
            .toList();
        final restNameMap = <String, String>{};
        if (restaurantIds.isNotEmpty) {
          final restRows = await SupabaseConfig.client
              .from('restaurants')
              .select('id, name')
              .inFilter('id', restaurantIds);
          for (final r in (restRows as List)) {
            restNameMap[(r as Map)['id'] as String] =
                r['name'] as String? ?? '';
          }
        }

        // Group restaurant_orders by master_order_id
        final roByMaster = <String, List<RestaurantOrder>>{};
        for (final ro in roRows) {
          final r = ro;
          final mid = r['master_order_id'] as String;
          roByMaster
              .putIfAbsent(mid, () => [])
              .add(
                RestaurantOrder(
                  id: r['id'] as String,
                  masterOrderId: mid,
                  restaurantId: r['restaurant_id'] as String,
                  restaurantName: restNameMap[r['restaurant_id'] as String],
                  restaurantOrderNumber:
                      r['restaurant_order_number'] as String?,
                  status: r['status'] as String? ?? 'pending',
                  subtotal: (r['subtotal'] as num?)?.toDouble() ?? 0,
                  deliveryFee: (r['delivery_fee'] as num?)?.toDouble() ?? 0,
                  sequenceInGroup:
                      (r['sequence_in_group'] as num?)?.toInt() ?? 1,
                  deliveryOtp: r['delivery_otp'] as String?,
                  pickupStatus: r['pickup_status'] as String? ?? 'pending',
                  notes: r['notes'] as String?,
                  createdAt: DateTime.parse(r['created_at'] as String),
                ),
              );
        }

        // Build MasterOrder list — skip rows that fail to parse
        final result = <MasterOrder>[];
        for (final mo in moRows) {
          try {
            final m = mo;
            final mid = m['id'] as String;
            final orders = (roByMaster[mid] ?? [])
              ..sort((a, b) => a.sequenceInGroup.compareTo(b.sequenceInGroup));
            result.add(
              MasterOrder(
                id: mid,
                customerId: m['customer_id'] as String? ?? '',
                masterOrderNumber: m['master_order_number'] as String?,
                status: m['status'] as String? ?? 'pending',
                deliveryAddress: m['delivery_address'] as String? ?? '',
                deliveryLatitude: (m['delivery_latitude'] as num?)?.toDouble(),
                deliveryLongitude: (m['delivery_longitude'] as num?)
                    ?.toDouble(),
                paymentMethod: m['payment_method'] as String? ?? 'stripe',
                paymentStatus: m['payment_status'] as String? ?? 'pending',
                subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
                deliveryFee: (m['delivery_fee'] as num?)?.toDouble() ?? 0,
                extraStopFee: (m['extra_stop_fee'] as num?)?.toDouble() ?? 0,
                platformFee: (m['platform_fee'] as num?)?.toDouble() ?? 0,
                taxAmount: (m['tax_amount'] as num?)?.toDouble() ?? 0,
                discount: (m['discount'] as num?)?.toDouble() ?? 0,
                totalAmount: (m['total_amount'] as num?)?.toDouble() ?? 0,
                driverId: m['driver_id'] as String?,
                notes: m['notes'] as String?,
                isPickup: m['is_pickup'] as bool? ?? false,
                contactlessDelivery:
                    m['contactless_delivery'] as bool? ?? false,
                driverTip: (m['driver_tip'] as num?)?.toDouble(),
                postDeliveryTip: (m['post_delivery_tip'] as num?)?.toDouble(),
                deliveryOtp: m['delivery_otp'] as String?,
                deliveryOtpVerified: m['delivery_otp_verified'] as bool?,
                estimatedDeliveryAt: m['estimated_delivery_at'] == null
                    ? null
                    : DateTime.parse(m['estimated_delivery_at'] as String),
                deliveredAt: m['delivered_at'] == null
                    ? null
                    : DateTime.parse(m['delivered_at'] as String),
                cancelledAt: m['cancelled_at'] == null
                    ? null
                    : DateTime.parse(m['cancelled_at'] as String),
                createdAt: DateTime.parse(
                  m['created_at'] as String? ??
                      DateTime.now().toIso8601String(),
                ),
                restaurantOrders: orders,
              ),
            );
          } catch (e) {
            AppLogger.error('customerMasterOrdersProvider: skipping row: $e');
          }
        }
        return result;
      } catch (e) {
        AppLogger.error('customerMasterOrdersProvider: $e');
        return [];
      }
    });

/// Real-time subscription — invalidates [customerMasterOrdersProvider] on any change.
final masterOrderRealtimeProvider = StreamProvider.family
    .autoDispose<void, String>((ref, customerId) {
      final channel = SupabaseConfig.client
          .channel('master_orders_rt_$customerId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'master_orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'customer_id',
              value: customerId,
            ),
            callback: (_) =>
                ref.invalidate(customerMasterOrdersProvider(customerId)),
          )
          .subscribe();
      ref.onDispose(() => channel.unsubscribe());
      return const Stream.empty();
    });

/// Restaurant-side: all restaurant_orders for a given restaurant_id (group orders tab).
final restaurantOrdersForRestaurantProvider = FutureProvider.family
    .autoDispose<List<RestaurantOrder>, String>((ref, restaurantId) async {
      try {
        final rows = await SupabaseConfig.client
            .from('restaurant_orders')
            .select(
              '*,'
              'restaurant_order_items(*,restaurant_order_item_sides(*)),'
              'master_orders(delivery_address,notes,contactless_delivery,payment_method)',
            )
            .eq('restaurant_id', restaurantId)
            .order('created_at', ascending: false)
            .limit(100);
        return (rows as List)
            .map((r) => RestaurantOrder.fromJson(r as Map<String, dynamic>))
            .toList();
      } catch (e) {
        AppLogger.error('restaurantOrdersForRestaurantProvider: $e');
        return [];
      }
    });

/// All restaurant_orders visible to the current restaurant owner (uses RLS).
/// The owner_id parameter is used only as a cache key; RLS filters rows automatically.
final ownerGroupOrdersProvider = FutureProvider.family
    .autoDispose<List<RestaurantOrder>, String>((ref, ownerId) async {
      try {
        final rows = await SupabaseConfig.client
            .from('restaurant_orders')
            .select(
              '*,'
              'restaurants(name),'
              'restaurant_order_items(*,restaurant_order_item_sides(*)),'
              'master_orders(delivery_address,notes,contactless_delivery,payment_method)',
            )
            .order('created_at', ascending: false)
            .limit(100);
        return (rows as List)
            .map((r) => RestaurantOrder.fromJson(r as Map<String, dynamic>))
            .toList();
      } catch (e) {
        AppLogger.error('ownerGroupOrdersProvider: $e');
        return [];
      }
    });

/// Real-time subscription for restaurant_orders — used by restaurant dashboard.
final restaurantOrdersRealtimeProvider = StreamProvider.family
    .autoDispose<void, String>((ref, restaurantId) {
      final channel = SupabaseConfig.client
          .channel('restaurant_orders_rt_$restaurantId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'restaurant_orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'restaurant_id',
              value: restaurantId,
            ),
            callback: (_) => ref.invalidate(
              restaurantOrdersForRestaurantProvider(restaurantId),
            ),
          )
          .subscribe();
      ref.onDispose(() => channel.unsubscribe());
      return const Stream.empty();
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
  /// When multi-restaurant mode is active this is the first restaurant's id.
  String? get currentRestaurantId =>
      state.isNotEmpty ? state.first.menuItem.restaurantId : null;

  /// All distinct restaurant IDs currently in the cart.
  Set<String> get restaurantIds =>
      state.map((i) => i.menuItem.restaurantId).toSet();

  /// Number of distinct restaurants in the cart.
  int get restaurantCount => restaurantIds.length;

  /// Returns true if the item belongs to a restaurant NOT yet in the cart.
  bool isDifferentRestaurant(MenuItem menuItem) {
    final rid = currentRestaurantId;
    return rid != null && rid != menuItem.restaurantId;
  }

  /// Returns true if adding this item would exceed the max restaurant limit.
  bool wouldExceedRestaurantLimit(MenuItem menuItem, int maxRestaurants) {
    if (restaurantIds.contains(menuItem.restaurantId)) return false;
    return restaurantCount >= maxRestaurants;
  }

  /// Add item from a second (or Nth) restaurant — multi-restaurant mode.
  void addItemFromNewRestaurant(
    MenuItem menuItem, {
    List<MenuItemSide>? sides,
    Map<String, List<OptionChoice>>? options,
  }) {
    state = [
      ...state,
      CartItem(
        menuItem: menuItem,
        selectedSides: sides,
        selectedOptions: options,
      ),
    ];
    _persist();
  }

  /// Remove all items belonging to a specific restaurant.
  void removeRestaurantGroup(String restaurantId) {
    state = state
        .where((i) => i.menuItem.restaurantId != restaurantId)
        .toList();
    _persist();
  }

  /// Items grouped by restaurant id — used by multi-restaurant cart/checkout.
  Map<String, List<CartItem>> get itemsByRestaurant {
    final map = <String, List<CartItem>>{};
    for (final item in state) {
      map.putIfAbsent(item.menuItem.restaurantId, () => []).add(item);
    }
    return map;
  }

  /// Subtotal for a single restaurant group.
  double subtotalForRestaurant(String restaurantId) {
    return state
        .where((i) => i.menuItem.restaurantId == restaurantId)
        .fold(0.0, (s, i) => s + i.subtotal);
  }

  /// Clear the cart and add the item from the new restaurant (single-restaurant replace).
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
      final updated = state[existingIndex].copyWith(
        quantity: state[existingIndex].quantity + 1,
      );
      final newList = [...state];
      newList[existingIndex] = updated;
      state = newList;
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
        final newList = [...state];
        newList[index] = state[index].copyWith(quantity: quantity);
        state = newList;
        _persist();
      }
    }
  }

  void updateNotes(String menuItemId, String notes) {
    final index = state.indexWhere((item) => item.menuItem.id == menuItemId);
    if (index != -1) {
      final newList = [...state];
      newList[index] = state[index].copyWith(notes: notes);
      state = newList;
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

/// When > 0, the current cart checkout is for a group order with this many
/// participants. The delivery fee should be discounted to 60% of regular.
/// Set before navigating to /cart from a group order lock, cleared on return.
final groupOrderParticipantCountProvider = StateProvider<int>((ref) => 0);

/// Holds the groupOrderId that should be marked as 'ordered' once the
/// checkout flow completes successfully. Null when not a group order checkout.
final groupOrderIdForCheckoutProvider = StateProvider<String?>((ref) => null);

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
      final newList = [...state];
      newList[existingIndex] = state[existingIndex].copyWith(
        quantity: current + 1,
      );
      state = newList;
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
        final newList = [...state];
        newList[index] = state[index].copyWith(quantity: quantity);
        state = newList;
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
        'rest_owner_$ownerId',
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

// ── Cart AI Recommendations ───────────────────────────────────────────────────

/// Calls the cart-recommendations edge function to suggest nearby restaurants
/// the user frequently pairs with whatever is already in their cart.
final cartRecommendationsProvider = FutureProvider.family
    .autoDispose<
      List<CartRecommendation>,
      ({
        String userId,
        List<String> cartRestaurantIds,
        double? lat,
        double? lng,
      })
    >((ref, params) async {
      if (params.cartRestaurantIds.isEmpty) return [];
      try {
        // Calls the get_cart_recommendations PostgreSQL function directly —
        // same pattern as get_smart_recommendations in the brain engine.
        final result = await SupabaseConfig.client.rpc(
          'get_cart_recommendations',
          params: {
            'p_user_id': params.userId,
            'p_cart_restaurant_ids': params.cartRestaurantIds,
            if (params.lat != null) 'p_delivery_lat': params.lat,
            if (params.lng != null) 'p_delivery_lng': params.lng,
          },
        );
        if (result is! List) return [];
        return result
            .map((e) => CartRecommendation.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        AppLogger.error('cartRecommendationsProvider: $e');
        return [];
      }
    });
