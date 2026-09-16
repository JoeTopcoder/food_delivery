import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../config/supabase_config.dart';
import '../models/restaurant_model.dart';
import '../models/menu_model.dart';
import '../models/grocery_category_model.dart';
import '../models/inventory_model.dart';
import '../services/grocery_service.dart';
import 'address_provider.dart';
import 'auth_provider.dart';

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
    'grocery_stores',
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

  return _groceryStoresSortedByDistance(ref);
});

/// The customer's location used to rank grocery stores: their selected delivery
/// address, falling back to their saved profile location. Either coordinate may
/// be null when the customer has no known location.
final groceryCustomerOriginProvider = Provider<({double? lat, double? lng})>((
  ref,
) {
  final address = ref.watch(selectedAddressProvider);
  final user = ref.watch(currentUserProvider);
  return (
    lat: address?.latitude ?? user?.latitude,
    lng: address?.longitude ?? user?.longitude,
  );
});

/// A short "nearest to you" label for a store (e.g. "2.3 km", "800 m"), or null
/// when the customer's location or the store's coordinates are unknown.
String? groceryStoreDistanceLabel({
  required double? originLat,
  required double? originLng,
  required double? storeLat,
  required double? storeLng,
}) {
  if (originLat == null ||
      originLng == null ||
      storeLat == null ||
      storeLng == null) {
    return null;
  }
  final meters = Geolocator.distanceBetween(
    originLat,
    originLng,
    storeLat,
    storeLng,
  );
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// Fetch grocery stores and sort them nearest-first relative to the customer's
/// selected delivery address (falling back to their saved profile location).
/// Stores without coordinates, and the case where we have no customer location,
/// fall back to the default order (rating). Distance is straight-line metres.
Future<List<Restaurant>> _groceryStoresSortedByDistance(Ref ref) async {
  final stores = await ref.watch(groceryServiceProvider).getGroceryStores();

  final origin = ref.watch(groceryCustomerOriginProvider);
  final oLat = origin.lat;
  final oLng = origin.lng;
  if (oLat == null || oLng == null) return stores;

  double distanceMeters(Restaurant s) {
    if (s.latitude == null || s.longitude == null) return double.infinity;
    return Geolocator.distanceBetween(oLat, oLng, s.latitude!, s.longitude!);
  }

  final sorted = [...stores]
    ..sort((a, b) => distanceMeters(a).compareTo(distanceMeters(b)));
  return sorted;
}

final groceryStoreSearchProvider = FutureProvider.family
    .autoDispose<List<Restaurant>, String>((ref, query) {
      if (query.isEmpty) {
        return ref.watch(groceryServiceProvider).getGroceryStores();
      }
      return ref.watch(groceryServiceProvider).searchGroceryStores(query);
    });

/// Fetch a single grocery store by ID (used by banner tap).
final groceryStoreByIdProvider = FutureProvider.family
    .autoDispose<Restaurant?, String>((ref, storeId) async {
      final data = await SupabaseConfig.client
          .from('restaurants')
          .select()
          .eq('id', storeId)
          .maybeSingle();
      if (data == null) return null;
      // Customer-facing: anonymise the real partner store behind the brand.
      return GroceryService.maskGroceryStore(data);
    });

// ── Product Providers (real-time) ───────────────────────────────────────────

final groceryProductsProvider = FutureProvider.family
    .autoDispose<List<MenuItem>, String>((ref, storeId) {
      // Keep products alive while browsing
      ref.keepAlive();
      // Real-time: refresh when products for this store change
      final channel = Supabase.instance.client.realtime.channel(
        'grocery_products_$storeId',
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
        'grocery_categories',
      );
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'grocery_categories',
            callback: (_) => ref.invalidateSelf(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'menus',
            callback: (payload) {
              // Only refresh when a new product is inserted — a new category
              // name may have appeared. Ignore UPDATE/DELETE events (stock
              // toggles, price edits) which cannot add new category names.
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
        'all_grocery_cat_${category.hashCode}',
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
        'owner_grocery_$ownerId',
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
        'owner_grocery_prods_$storeId',
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

// ── Inventory Providers (real-time) ─────────────────────────────────────────

/// Inventory snapshot for a store's grocery products, keyed by product id.
/// Refreshes in real time when any of the store's menus rows change — so a
/// sale placed through the order flow (which decrements stock server-side)
/// reflects here without a manual refresh.
final storeInventoryProvider = FutureProvider.family
    .autoDispose<Map<String, ProductInventory>, String>((ref, storeId) {
      final channel = Supabase.instance.client.realtime.channel(
        'store_inventory_$storeId',
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

      return ref.watch(groceryServiceProvider).getStoreInventory(storeId);
    });

/// Recent movement-ledger rows for a single product (newest first).
final productMovementsProvider = FutureProvider.family
    .autoDispose<List<InventoryMovement>, String>((ref, productId) {
      return ref.watch(groceryServiceProvider).getProductMovements(productId);
    });
