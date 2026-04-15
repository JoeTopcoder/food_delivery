import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/menu_model.dart';
import '../../models/restaurant_model.dart';
import '../../providers/grocery_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/restaurant_card.dart';
import '../../widgets/smart_home_widgets.dart';
import 'grocery_store_detail_screen.dart';
import 'grocery_category_products_screen.dart';
import 'package:food_driver/config/app_constants.dart';

class GroceryScreen extends ConsumerStatefulWidget {
  const GroceryScreen({super.key});

  @override
  ConsumerState<GroceryScreen> createState() => _GroceryScreenState();
}

class _GroceryScreenState extends ConsumerState<GroceryScreen> {
  String _searchQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _searchQuery = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(groceryCategoriesProvider);
    final storesAsync = _searchQuery.isEmpty
        ? ref.watch(groceryStoresProvider)
        : ref.watch(groceryStoreSearchProvider(_searchQuery));

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          cacheExtent: 500,
          slivers: [
            // ── Header ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Grocery',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        _GroceryCartIcon(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Fresh groceries delivered to your door',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Search bar
                    TextField(
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search groceries...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ── Categories row ──────────────────────────────────────
            SliverToBoxAdapter(
              child: categoriesAsync.when(
                data: (categories) {
                  if (categories.isEmpty) return const SizedBox.shrink();
                  return SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final cat = categories[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GroceryCategoryProductsScreen(
                                  categoryName: cat.name,
                                  categoryIcon: cat.icon,
                                ),
                              ),
                            );
                          },
                          child: Column(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: Text(
                                    cat.icon ?? '🛒',
                                    style: const TextStyle(fontSize: 28),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  cat.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
                loading: () => const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),

            // ── AI-powered grocery recommendations ──────────────────
            if (_searchQuery.isEmpty)
              SliverToBoxAdapter(
                child: GrocerySmartSections(
                  onStoreTap: (rec) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroceryStoreDetailScreen(
                          store: Restaurant(
                            id: rec.restaurantId,
                            ownerId: '',
                            name: rec.restaurantName,
                            cuisineType: rec.cuisineType,
                            rating: rec.rating,
                            imageUrl: rec.imageUrl,
                            deliveryFee: rec.deliveryFee,
                            estimatedDeliveryTime: rec.estimatedDeliveryTime,
                            isOpen: rec.isOpen,
                            storeType: 'grocery',
                            createdAt: DateTime.now(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // ── Section title ───────────────────────────────────────

            // ── Product search results (only when searching) ─────────
            if (_searchQuery.isNotEmpty) ..._buildProductSearchResults(ref),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  _searchQuery.isEmpty ? 'Grocery Stores Near You' : 'Stores',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),

            // ── Store list ──────────────────────────────────────────
            storesAsync.when(
              data: (stores) {
                if (stores.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.storefront_outlined,
                            size: 64,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'No grocery stores available yet'
                                : 'No stores found for "$_searchQuery"',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => RepaintBoundary(
                        child: RestaurantCard(
                          restaurant: stores[index],
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GroceryStoreDetailScreen(
                                  store: stores[index],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      childCount: stores.length,
                      addAutomaticKeepAlives: true,
                      addRepaintBoundaries: false,
                    ),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => SliverFillRemaining(
                child: Center(child: Text(friendlyError(err))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildProductSearchResults(WidgetRef ref) {
    final productsAsync = ref.watch(groceryProductSearchProvider(_searchQuery));

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: const Text(
            'Products',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ),
      productsAsync.when(
        data: (products) {
          if (products.isEmpty) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  'No products found for "$_searchQuery"',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.62,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => RepaintBoundary(
                  child: _SearchProductCard(product: products[index]),
                ),
                childCount: products.length > 10 ? 10 : products.length,
              ),
            ),
          );
        },
        loading: () => const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
        error: (err, _) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(friendlyError(err)),
          ),
        ),
      ),
    ];
  }
}

// ── Search product card ─────────────────────────────────────────────────────

class _SearchProductCard extends ConsumerWidget {
  final MenuItem product;
  const _SearchProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inStock = product.inStock;
    final storeAsync = ref.watch(restaurantByIdProvider(product.restaurantId));
    final storeName = storeAsync.valueOrNull?.name;
    final store = storeAsync.valueOrNull;

    return GestureDetector(
      onTap: store != null
          ? () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroceryStoreDetailScreen(store: store),
              ),
            )
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image – fixed height
            SizedBox(
              height: 130,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    product.imageUrl != null && product.imageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: product.imageUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 400,
                            placeholder: (_, __) => _placeholder(),
                            errorWidget: (_, _, _) => _placeholder(),
                          )
                        : _placeholder(),
                    if (!inStock)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: Text(
                            'Out of Stock',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    if (product.discount != null && product.discount! > 0)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '-${product.discount!.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (storeName != null)
                      Text(
                        storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.primaryColor.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (product.brand != null)
                      Text(
                        product.brand!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    Flexible(
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.discount != null && product.discount! > 0
                                ? '${AppConstants.currencySymbol}${product.discountedPrice.toStringAsFixed(2)}'
                                : '${AppConstants.currencySymbol}${product.price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final cartItems = ref.watch(groceryCartProvider);
                            final inCartItem = cartItems.where(
                              (c) => c.menuItem.id == product.id,
                            );
                            final inCartQty = inCartItem.isNotEmpty
                                ? inCartItem.first.quantity
                                : 0;
                            final atMax = inCartQty >= product.maxQuantity;

                            if (inCartQty > 0) {
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () => ref
                                        .read(groceryCartProvider.notifier)
                                        .updateQuantity(
                                          product.id,
                                          inCartQty - 1,
                                        ),
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(
                                        Icons.remove,
                                        size: 14,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Text(
                                      '$inCartQty',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: atMax
                                        ? null
                                        : () => _addToCart(ref, context),
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: atMax
                                            ? Colors.grey[300]
                                            : AppTheme.primaryColor,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Icon(
                                        Icons.add,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }

                            return GestureDetector(
                              onTap: inStock
                                  ? () => _addToCart(ref, context)
                                  : null,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: inStock
                                      ? AppTheme.primaryColor
                                      : Colors.grey[300],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addToCart(WidgetRef ref, BuildContext context) {
    final cartNotifier = ref.read(groceryCartProvider.notifier);
    final cartItems = ref.read(groceryCartProvider);
    final existing = cartItems.where((c) => c.menuItem.id == product.id);
    final currentQty = existing.isNotEmpty ? existing.first.quantity : 0;
    if (currentQty >= product.maxQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum of ${product.maxQuantity} ${product.name} allowed',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    cartNotifier.addItem(product);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} added to grocery cart'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: Colors.grey[100],
    child: Center(
      child: Icon(
        Icons.shopping_bag_outlined,
        size: 36,
        color: Colors.grey[300],
      ),
    ),
  );
}

class _GroceryCartIcon extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCount = ref.watch(groceryCartItemCountProvider);

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/grocery-cart'),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(
              Icons.shopping_cart_rounded,
              color: AppTheme.primaryColor,
              size: 26,
            ),
            if (cartCount > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    '$cartCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
