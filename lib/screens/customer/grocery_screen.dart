import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/banner_model.dart' as app;
import '../../models/menu_model.dart';
import '../../models/restaurant_model.dart';
import '../../providers/banner_provider.dart';
import '../../providers/grocery_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/restaurant_card.dart';
import '../../widgets/smart_home_widgets.dart';
import 'grocery_store_detail_screen.dart';
import 'grocery_category_products_screen.dart';
import 'package:food_driver/config/app_constants.dart';
import '../../core/utils/responsive.dart';

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
          scrollCacheExtent: const ScrollCacheExtent.pixels(500),
          slivers: [
            // ── Header ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  Responsive.horizontalPadding(context),
                  16,
                  Responsive.horizontalPadding(context),
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Grocery',
                            style: TextStyle(
                              fontSize: Responsive.headingLarge(context),
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.onSurface,
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
                        fontSize: Responsive.bodyText(context),
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Search bar
                    TextField(
                      onChanged: _onSearchChanged,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search groceries...',
                        hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
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

            // ── Grocery Banner Carousel ─────────────────────────────
            SliverToBoxAdapter(child: _GroceryBannerCarousel()),

            // ── Categories row ──────────────────────────────────────
            SliverToBoxAdapter(
              child: categoriesAsync.when(
                data: (categories) {
                  if (categories.isEmpty) return const SizedBox.shrink();
                  return LayoutBuilder(
                    builder: (context, _) {
                      final catH = (MediaQuery.of(context).size.height * 0.13)
                          .clamp(95.0, 115.0);
                      return SizedBox(
                        height: catH,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: categories.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final cat = categories[index];
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        GroceryCategoryProductsScreen(
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
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ); // SizedBox
                    },
                  ); // LayoutBuilder
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
                padding: EdgeInsets.fromLTRB(
                  Responsive.horizontalPadding(context),
                  12,
                  Responsive.horizontalPadding(context),
                  8,
                ),
                child: Text(
                  _searchQuery.isEmpty ? 'Grocery Stores Near You' : 'Stores',
                  style: TextStyle(
                    fontSize: Responsive.headingMedium(context),
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
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
                              fontSize: Responsive.headingSmall(context),
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
                  padding: EdgeInsets.symmetric(
                    horizontal: Responsive.horizontalPadding(context),
                  ),
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
          padding: EdgeInsets.fromLTRB(
            Responsive.horizontalPadding(context),
            12,
            Responsive.horizontalPadding(context),
            8,
          ),
          child: Text(
            'Products',
            style: TextStyle(
              fontSize: Responsive.headingMedium(context),
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
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
                  style: TextStyle(
                    fontSize: Responsive.bodyText(context),
                    color: Colors.grey[700],
                  ),
                ),
              ),
            );
          }
          return SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: Responsive.gridColumns(context),
                childAspectRatio: Responsive.productCardAspectRatio(context),
                crossAxisSpacing: Responsive.gridSpacing(context),
                mainAxisSpacing: Responsive.gridSpacing(context),
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
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            width: 0.5,
          ),
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
                        ? Image.network(
                            product.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder(),
                            loadingBuilder: (_, child, progress) =>
                                progress == null ? child : _placeholder(),
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    Flexible(
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
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
                            style: TextStyle(
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
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Icon(
                                        Icons.remove,
                                        size: 14,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
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

  Widget _placeholder() => Builder(
    builder: (context) => Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          size: 36,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
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
            Icon(
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

// ─── Grocery Banner Carousel ──────────────────────────────────────────────────

class _GroceryBannerCarousel extends ConsumerStatefulWidget {
  @override
  ConsumerState<_GroceryBannerCarousel> createState() =>
      _GroceryBannerCarouselState();
}

class _GroceryBannerCarouselState
    extends ConsumerState<_GroceryBannerCarousel> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bannersAsync = ref.watch(activeGroceryBannersProvider);

    return bannersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (banners) {
        if (banners.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Column(
            children: [
              SizedBox(
                height: 140,
                child: PageView.builder(
                  controller: _pageCtrl,
                  itemCount: banners.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, index) =>
                      _GroceryBannerCard(banner: banners[index]),
                ),
              ),
              if (banners.length > 1) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    banners.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _currentPage == i ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _currentPage == i
                            ? AppTheme.primaryColor
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _GroceryBannerCard extends ConsumerWidget {
  final app.Banner banner;
  const _GroceryBannerCard({required this.banner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        try {
          final data = await ref.read(
            groceryStoreByIdProvider(banner.restaurantId).future,
          );
          if (context.mounted && data != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroceryStoreDetailScreen(store: data),
              ),
            );
          }
        } catch (_) {}
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [const Color(0xFF2E7D32), const Color(0xFF66BB6A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (banner.imageUrl != null && banner.imageUrl!.isNotEmpty)
              Image.network(
                banner.imageUrl!,
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.35),
                colorBlendMode: BlendMode.darken,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            if (banner.imageUrl == null || banner.imageUrl!.isEmpty)
              Positioned(
                right: -10,
                bottom: -10,
                child: Icon(
                  Icons.local_grocery_store_rounded,
                  size: 120,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    banner.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (banner.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      banner.subtitle!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Shop at ${banner.restaurantName ?? 'Store'}',
                      style: const TextStyle(
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
