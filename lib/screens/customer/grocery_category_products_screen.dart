import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/menu_model.dart';
import '../../providers/grocery_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import 'package:food_driver/config/app_constants.dart';

class GroceryCategoryProductsScreen extends ConsumerStatefulWidget {
  final String categoryName;
  final String? categoryIcon;

  const GroceryCategoryProductsScreen({
    super.key,
    required this.categoryName,
    this.categoryIcon,
  });

  @override
  ConsumerState<GroceryCategoryProductsScreen> createState() =>
      _GroceryCategoryProductsScreenState();
}

class _GroceryCategoryProductsScreenState
    extends ConsumerState<GroceryCategoryProductsScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(
      allGroceryProductsByCategoryProvider(widget.categoryName),
    );

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            if (widget.categoryIcon != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  widget.categoryIcon!,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            Text(
              widget.categoryName,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: [_CartBadge(), const SizedBox(width: 8)],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search ${widget.categoryName.toLowerCase()}...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          // Products grid
          Expanded(
            child: productsAsync.when(
              data: (products) {
                var filtered = products;
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  filtered = filtered
                      .where(
                        (p) =>
                            p.name.toLowerCase().contains(q) ||
                            (p.brand?.toLowerCase().contains(q) ?? false),
                      )
                      .toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No products in this category yet'
                              : 'No products found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  cacheExtent: 500,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                  ).copyWith(bottom: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.62,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => RepaintBoundary(
                    child: _CategoryProductCard(product: filtered[index]),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text(friendlyError(err))),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomCartBar(),
    );
  }
}

// ── Product card with store name ──────────────────────────────────────────────

class _CategoryProductCard extends ConsumerWidget {
  final MenuItem product;
  const _CategoryProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inStock = product.inStock;
    final storeAsync = ref.watch(restaurantByIdProvider(product.restaurantId));
    final storeName = storeAsync.valueOrNull?.name;

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
                  // Store name
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
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (product.weight != null)
                    Text(
                      product.weight!,
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: product.discount != null && product.discount! > 0
                            ? Row(
                                children: [
                                  Text(
                                    '${AppConstants.currencySymbol}${product.discountedPrice.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${AppConstants.currencySymbol}${product.price.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[700],
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                '${AppConstants.currencySymbol}${product.price.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                      ),
                      // Add button / quantity stepper
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
                                _StepperBtn(
                                  icon: Icons.remove,
                                  onTap: () => ref
                                      .read(groceryCartProvider.notifier)
                                      .updateQuantity(
                                        product.id,
                                        inCartQty - 1,
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
                                _StepperBtn(
                                  icon: Icons.add,
                                  filled: true,
                                  disabled: atMax,
                                  onTap: atMax
                                      ? null
                                      : () => _addToCart(ref, context),
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

// ── Small stepper button ─────────────────────────────────────────────────────

class _StepperBtn extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final bool disabled;
  final VoidCallback? onTap;

  const _StepperBtn({
    required this.icon,
    this.filled = false,
    this.disabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: disabled
              ? Colors.grey[300]
              : filled
              ? AppTheme.primaryColor
              : Colors.grey[200],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 14,
          color: filled || disabled
              ? Colors.white
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

// ── Cart badge in app bar ────────────────────────────────────────────────────

class _CartBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(groceryCartItemCountProvider);

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/grocery-cart'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              color: Theme.of(context).colorScheme.onSurface,
              size: 24,
            ),
            if (count > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
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

// ── Bottom cart bar ──────────────────────────────────────────────────────────

class _BottomCartBar extends ConsumerWidget {
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
                  '${AppConstants.currencySymbol}${subtotal.toStringAsFixed(2)}',
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
