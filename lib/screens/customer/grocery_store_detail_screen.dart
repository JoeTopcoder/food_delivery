import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/restaurant_model.dart';
import '../../models/menu_model.dart';
import '../../providers/grocery_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';

class GroceryStoreDetailScreen extends ConsumerStatefulWidget {
  final Restaurant store;

  const GroceryStoreDetailScreen({super.key, required this.store});

  @override
  ConsumerState<GroceryStoreDetailScreen> createState() =>
      _GroceryStoreDetailScreenState();
}

class _GroceryStoreDetailScreenState
    extends ConsumerState<GroceryStoreDetailScreen> {
  String? _selectedCategory;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(groceryProductsProvider(widget.store.id));

    return Scaffold(
      backgroundColor: Colors.white,
      body: productsAsync.when(
        data: (products) => _buildContent(products),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(friendlyError(err))),
      ),
      bottomNavigationBar: _GroceryCartBar(),
    );
  }

  Widget _buildContent(List<MenuItem> allProducts) {
    // Group by category
    final categories = <String>{};
    for (final p in allProducts) {
      categories.add(p.category);
    }
    final sortedCats = categories.toList()..sort();

    // Filter
    var filtered = allProducts;
    if (_selectedCategory != null) {
      filtered = filtered
          .where((p) => p.category == _selectedCategory)
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where(
            (p) =>
                p.name.toLowerCase().contains(q) ||
                (p.brand?.toLowerCase().contains(q) ?? false) ||
                (p.description?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }

    final cartItems = ref.watch(groceryCartProvider);
    final cartCount = cartItems.fold(0, (sum, c) => sum + c.quantity);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      cacheExtent: 600,
      slivers: [
        // ── App bar with store image ────────────────────────────────
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leading: IconButton(
            icon: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background:
                widget.store.imageUrl != null &&
                    widget.store.imageUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: widget.store.imageUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 800,
                    placeholder: (_, __) => _storePlaceholder(),
                    errorWidget: (_, _, _) => _storePlaceholder(),
                  )
                : _storePlaceholder(),
          ),
        ),

        // ── Store info ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.store.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (widget.store.address != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.store.address!,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (widget.store.rating != null) ...[
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        widget.store.rating!.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: widget.store.isCurrentlyOpen
                            ? const Color(0xFF10B981).withValues(alpha: 0.1)
                            : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.store.isCurrentlyOpen ? 'Open' : 'Closed',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: widget.store.isCurrentlyOpen
                              ? const Color(0xFF10B981)
                              : Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Search bar ──────────────────────────────────────
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        // ── Category chips ──────────────────────────────────────────
        if (sortedCats.length > 1)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: sortedCats.length + 1, // +1 for "All"
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final isAll = index == 0;
                  final label = isAll ? 'All' : sortedCats[index - 1];
                  final isSelected = isAll
                      ? _selectedCategory == null
                      : _selectedCategory == label;

                  return GestureDetector(
                    onTap: () => setState(() {
                      _selectedCategory = isAll ? null : label;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.grey[700],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // ── Product grid ────────────────────────────────────────────
        filtered.isEmpty
            ? SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 56,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No products found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            : SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ).copyWith(bottom: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => RepaintBoundary(
                      child: _ProductCard(
                        product: filtered[index],
                        store: widget.store,
                      ),
                    ),
                    childCount: filtered.length,
                    addAutomaticKeepAlives: true,
                    addRepaintBoundaries: false,
                  ),
                ),
              ),
      ],
    );
  }

  Widget _storePlaceholder() => Container(
    color: AppTheme.primaryColor.withValues(alpha: 0.1),
    child: Center(
      child: Icon(
        Icons.storefront_rounded,
        size: 64,
        color: AppTheme.primaryColor.withValues(alpha: 0.4),
      ),
    ),
  );
}

// ── Product Card ──────────────────────────────────────────────────────────────

class _ProductCard extends ConsumerWidget {
  final MenuItem product;
  final Restaurant store;

  const _ProductCard({required this.product, required this.store});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inStock = product.inStock;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image – fixed height for uniform sizing
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
                          placeholder: (_, __) => _productPlaceholder(),
                          errorWidget: (_, _, _) => _productPlaceholder(),
                        )
                      : _productPlaceholder(),
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
                mainAxisSize: MainAxisSize.max,
                children: [
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
                  if (product.weight != null)
                    Text(
                      product.weight!,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  const Spacer(),
                  Flexible(
                    child: Row(
                      children: [
                        // Price
                        Expanded(
                          child:
                              product.discount != null && product.discount! > 0
                              ? Row(
                                  children: [
                                    Text(
                                      '\$${product.discountedPrice.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '\$${product.price.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[400],
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  '\$${product.price.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                        ),
                        // Add button / quantity badge
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
                                        color: AppTheme.textPrimary,
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
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addToCart(WidgetRef ref, BuildContext context) {
    final cartNotifier = ref.read(groceryCartProvider.notifier);

    // Enforce stock / max quantity
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

  Widget _productPlaceholder() => Container(
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

// ── Floating Grocery Cart Bar ─────────────────────────────────────────────────

class _GroceryCartBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(groceryCartProvider);
    final cartCount = cartItems.fold(0, (sum, c) => sum + c.quantity);
    final subtotal = ref.watch(groceryCartSubtotalProvider);

    if (cartCount == 0) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        child: GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/grocery-cart'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$cartCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'View Grocery Cart',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  '\$${subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
