import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/restaurant_model.dart';
import '../models/menu_model.dart';
import '../models/grocery_category_model.dart';
import '../services/grocery_service.dart';

// Service
final groceryServiceProvider = Provider<GroceryService>((ref) {
  return GroceryService(SupabaseConfig.client);
});

// ── Store Providers (real-time) ─────────────────────────────────────────────

final groceryStoresProvider = FutureProvider.autoDispose<List<Restaurant>>((
  ref,
) {
  // Keep data alive so it's not re-fetched on every tab switch
  ref.keepAlive();
  // Real-time: refresh when any grocery store row changes
  final channel = Supabase.instance.client.realtime.channel(
    'grocery_stores_${DateTime.now().microsecondsSinceEpoch}',
  );
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'restaurants',
        callback: (payload) {
          final row = payload.newRecord;
          final st = row['store_type'] as String? ?? '';
          if (st == 'grocery' || st == 'both') {
            ref.invalidateSelf();
          }
        },
      )
      .subscribe();
  ref.onDispose(() => Supabase.instance.client.realtime.removeChannel(channel));

  return ref.watch(groceryServiceProvider).getGroceryStores();
});

final groceryStoreSearchProvider = FutureProvider.family
    .autoDispose<List<Restaurant>, String>((ref, query) {
      if (query.isEmpty) {
        return ref.watch(groceryServiceProvider).getGroceryStores();
      }
      return ref.watch(groceryServiceProvider).searchGroceryStores(query);
    });

// ── Product Providers (real-time) ───────────────────────────────────────────

final groceryProductsProvider = FutureProvider.family
    .autoDispose<List<MenuItem>, String>((ref, storeId) {
      // Keep products alive while browsing
      ref.keepAlive();
      // Real-time: refresh when products for this store change
      final channel = Supabase.instance.client.realtime.channel(
        'grocery_products_${storeId}_${DateTime.now().microsecondsSinceEpoch}',
      );
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'menus',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'restaurant_id',
              value: storeId,
            ),
            callback: (_) => ref.invalidateSelf(),
          )
          .subscribe();
      ref.onDispose(
        () => Supabase.instance.client.realtime.removeChannel(channel),
      );

      return ref.watch(groceryServiceProvider).getGroceryProducts(storeId);
    });

final groceryProductSearchProvider = FutureProvider.family
    .autoDispose<List<MenuItem>, String>((ref, query) {
      if (query.isEmpty) return Future.value([]);
      return ref.watch(groceryServiceProvider).searchGroceryProducts(query);
    });

final groceryProductsByCategoryProvider = FutureProvider.family
    .autoDispose<List<MenuItem>, ({String storeId, String category})>((
      ref,
      params,
    ) {
      return ref
          .watch(groceryServiceProvider)
          .getProductsByCategory(params.storeId, params.category);
    });

// ── Category Provider ───────────────────────────────────────────────────────

final groceryCategoriesProvider =
    FutureProvider.autoDispose<List<GroceryCategory>>((ref) {
      // Keep alive across tab switches
      ref.keepAlive();
      // Real-time: refresh when grocery_categories or menus table changes
      // so custom categories from new products appear immediately
      final channel = Supabase.instance.client.realtime.channel(
        'grocery_categories_${DateTime.now().microsecondsSinceEpoch}',
      );
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'grocery_categories',
            callback: (_) => ref.invalidateSelf(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'menus',
            callback: (payload) {
              final row = payload.newRecord;
              if (row['product_type'] == 'grocery') {
                ref.invalidateSelf();
              }
            },
          )
          .subscribe();
      ref.onDispose(
        () => Supabase.instance.client.realtime.removeChannel(channel),
      );

      return ref.watch(groceryServiceProvider).getCategories();
    });

/// All grocery products for a given category across ALL stores (real-time).
final allGroceryProductsByCategoryProvider = FutureProvider.family
    .autoDispose<List<MenuItem>, String>((ref, category) {
      // Real-time: refresh when any grocery product changes
      final channel = Supabase.instance.client.realtime.channel(
        'all_grocery_cat_${category.hashCode}_${DateTime.now().microsecondsSinceEpoch}',
      );
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'menus',
            callback: (payload) {
              final row = payload.newRecord;
              if (row['product_type'] == 'grocery' &&
                  row['category'] == category) {
                ref.invalidateSelf();
              }
            },
          )
          .subscribe();
      ref.onDispose(
        () => Supabase.instance.client.realtime.removeChannel(channel),
      );

      return ref
          .watch(groceryServiceProvider)
          .getAllProductsByCategory(category);
    });

// ── Owner (restaurant) Providers (real-time) ────────────────────────────────

/// The owner's grocery store (separate from their restaurant).
final ownerGroceryStoreProvider = FutureProvider.family
    .autoDispose<Restaurant?, String>((ref, ownerId) {
      // Real-time: refresh when this owner's store changes
      final channel = Supabase.instance.client.realtime.channel(
        'owner_grocery_${ownerId}_${DateTime.now().microsecondsSinceEpoch}',
      );
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
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

      return ref
          .watch(groceryServiceProvider)
          .getGroceryStoreByOwnerId(ownerId);
    });

/// All grocery products for a store — includes unavailable items (for management).
final ownerGroceryProductsProvider = FutureProvider.family
    .autoDispose<List<MenuItem>, String>((ref, storeId) {
      // Real-time: refresh when any product changes
      final channel = Supabase.instance.client.realtime.channel(
        'owner_grocery_prods_${storeId}_${DateTime.now().microsecondsSinceEpoch}',
      );
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'menus',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'restaurant_id',
              value: storeId,
            ),
            callback: (_) => ref.invalidateSelf(),
          )
          .subscribe();
      ref.onDispose(
        () => Supabase.instance.client.realtime.removeChannel(channel),
      );

      return ref.watch(groceryServiceProvider).getOwnerGroceryProducts(storeId);
    });
