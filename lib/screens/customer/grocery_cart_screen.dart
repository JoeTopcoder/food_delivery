import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_constants.dart';
import '../../models/restaurant_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/feature_providers.dart';
import '../../utils/app_theme.dart';

class GroceryCartScreen extends ConsumerStatefulWidget {
  const GroceryCartScreen({super.key});

  @override
  ConsumerState<GroceryCartScreen> createState() => _GroceryCartScreenState();
}

class _GroceryCartScreenState extends ConsumerState<GroceryCartScreen> {
  double _lastSurge = 1.0;

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(groceryCartProvider);
    final subtotal = ref.watch(groceryCartSubtotalProvider);
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final isPickup = ref.watch(groceryIsPickupProvider);
    final defaultAddrAsync = currentUserId != null
        ? ref.watch(defaultAddressProvider(currentUserId))
        : null;
    final deliveryAddress =
        defaultAddrAsync?.valueOrNull?.address ??
        currentUser?.address ??
        'No address saved';

    // Group cart items by store
    final Map<String, List<CartItem>> grouped = {};
    for (final item in cartItems) {
      final sid = item.menuItem.restaurantId;
      grouped.putIfAbsent(sid, () => []).add(item);
    }
    final storeIds = grouped.keys.toList();

    // Surge multiplier
    final defaultAddr = defaultAddrAsync?.valueOrNull;
    final delLat = defaultAddr?.latitude ?? currentUser?.latitude ?? 0.0;
    final delLng = defaultAddr?.longitude ?? currentUser?.longitude ?? 0.0;
    final surgeKey =
        '${delLat.toStringAsFixed(6)},${delLng.toStringAsFixed(6)}';
    final surgeAsync = ref.watch(surgeMultiplierProvider(surgeKey));
    if (surgeAsync.hasValue) _lastSurge = surgeAsync.value!;
    final surgeMultiplier = surgeAsync.valueOrNull ?? _lastSurge;

    // Accumulate delivery / service fee across all stores
    double totalActiveFee = 0;
    final storeData = <String, Restaurant?>{};
    for (final sid in storeIds) {
      final sAsync = ref.watch(restaurantByIdProvider(sid));
      final s = sAsync.valueOrNull;
      storeData[sid] = s;
      if (isPickup) {
        totalActiveFee += s?.serviceFee ?? AppConstants.pickupServiceFee;
      } else {
        final base = s?.deliveryFee ?? AppConstants.defaultDeliveryFee;
        totalActiveFee += double.parse(
          (base * surgeMultiplier).toStringAsFixed(2),
        );
      }
    }

    final tax = subtotal * AppConstants.taxRate;
    final total = subtotal + totalActiveFee + tax;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Grocery Cart',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (cartItems.isNotEmpty)
            TextButton(
              onPressed: () {
                ref.read(groceryCartProvider.notifier).clearCart();
              },
              child: const Text(
                'Clear',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      backgroundColor: Colors.white,
      body: cartItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_grocery_store_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your grocery cart is empty',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Browse Groceries',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                SingleChildScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  child: Column(
                    children: [
                      // ── Delivery / Pickup Toggle ──────────────────────
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    ref
                                            .read(
                                              groceryIsPickupProvider.notifier,
                                            )
                                            .state =
                                        false,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !isPickup
                                        ? AppTheme.primaryColor
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.delivery_dining_rounded,
                                        size: 18,
                                        color: !isPickup
                                            ? Colors.white
                                            : AppTheme.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Delivery',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: !isPickup
                                              ? Colors.white
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    ref
                                            .read(
                                              groceryIsPickupProvider.notifier,
                                            )
                                            .state =
                                        true,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPickup
                                        ? AppTheme.primaryColor
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.store_rounded,
                                        size: 18,
                                        color: isPickup
                                            ? Colors.white
                                            : AppTheme.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Pickup',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: isPickup
                                              ? Colors.white
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ── Address / Pickup Location ─────────────────────
                      if (isPickup)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(
                                    Icons.store_rounded,
                                    color: Color(0xFF10B981),
                                    size: 20,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Pick up from',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              for (final sid in storeIds)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 30,
                                    bottom: 2,
                                  ),
                                  child: Text(
                                    storeData[sid]?.name ?? 'Store',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: () =>
                              Navigator.pushNamed(context, '/address-book'),
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.07,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on_rounded,
                                  color: AppTheme.primaryColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Deliver to',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      Text(
                                        deliveryAddress,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppTheme.textSecondary,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),

                      // ── Cart Items grouped by store ───────────────────
                      for (final sid in storeIds) ...[
                        // Store header
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(
                              alpha: 0.06,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.storefront_rounded,
                                color: AppTheme.primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  storeData[sid]?.name ?? 'Store',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${grouped[sid]!.length} item${grouped[sid]!.length == 1 ? '' : 's'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Items for this store
                        for (final cartItem in grouped[sid]!)
                          _GroceryCartItemWidget(
                            name: cartItem.menuItem.name,
                            brand: cartItem.menuItem.brand,
                            weight: cartItem.menuItem.weight,
                            quantity: cartItem.quantity,
                            maxQuantity: cartItem.menuItem.maxQuantity,
                            price: cartItem.menuItem.discountedPrice,
                            imageUrl: cartItem.menuItem.imageUrl,
                            onRemove: () {
                              ref
                                  .read(groceryCartProvider.notifier)
                                  .removeItem(cartItem.menuItem.id);
                            },
                            onQuantityChanged: (newQuantity) {
                              ref
                                  .read(groceryCartProvider.notifier)
                                  .updateQuantity(
                                    cartItem.menuItem.id,
                                    newQuantity,
                                  );
                            },
                          ),
                        const SizedBox(height: 4),
                      ],

                      // ── Price Breakdown ───────────────────────────────
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.shade200,
                            width: 0.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            _PriceRow(
                              'Subtotal',
                              '${AppConstants.currencySymbol}${subtotal.toStringAsFixed(2)}',
                            ),
                            const SizedBox(height: 8),
                            if (isPickup)
                              _PriceRow(
                                'Service Fee${storeIds.length > 1 ? ' (${storeIds.length} stores)' : ''}',
                                '${AppConstants.currencySymbol}${totalActiveFee.toStringAsFixed(2)}',
                                valueColor: const Color(0xFF10B981),
                              )
                            else
                              _PriceRow(
                                surgeMultiplier > 1.0
                                    ? 'Delivery (${((surgeMultiplier - 1) * 100).toStringAsFixed(0)}% surge)'
                                    : 'Delivery Fee${storeIds.length > 1 ? ' (${storeIds.length} stores)' : ''}',
                                '${AppConstants.currencySymbol}${totalActiveFee.toStringAsFixed(2)}',
                                valueColor: surgeMultiplier > 1.0
                                    ? const Color(0xFFFFA630)
                                    : null,
                              ),
                            const SizedBox(height: 8),
                            _PriceRow('Tax', '${AppConstants.currencySymbol}${tax.toStringAsFixed(2)}'),
                            Divider(color: Colors.grey[300], height: 16),
                            _PriceRow(
                              'Total',
                              '${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
                              isBold: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),

                // ── Checkout Button ─────────────────────────────────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: SafeArea(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/grocery-checkout');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Proceed to Checkout - \$${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Cart item widget (grocery-specific with brand/weight) ───────────────────

class _GroceryCartItemWidget extends StatelessWidget {
  final String name;
  final String? brand;
  final String? weight;
  final int quantity;
  final int maxQuantity;
  final double price;
  final String? imageUrl;
  final VoidCallback onRemove;
  final Function(int) onQuantityChanged;

  const _GroceryCartItemWidget({
    required this.name,
    this.brand,
    this.weight,
    required this.quantity,
    this.maxQuantity = 99,
    required this.price,
    this.imageUrl,
    required this.onRemove,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      child: Row(
        children: [
          // Product image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl != null && imageUrl!.isNotEmpty
                ? Image.network(
                    imageUrl!,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _imgPlaceholder(),
                  )
                : _imgPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (brand != null)
                  Text(
                    brand!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (weight != null)
                  Text(
                    weight!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${AppConstants.currencySymbol}${(price * quantity).toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppTheme.priceColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 16),
                  onPressed: () => onQuantityChanged(quantity - 1),
                  constraints: const BoxConstraints(
                    minHeight: 30,
                    minWidth: 30,
                  ),
                  padding: EdgeInsets.zero,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('$quantity'),
                ),
                IconButton(
                  icon: Icon(
                    Icons.add,
                    size: 16,
                    color: quantity >= maxQuantity ? Colors.grey[300] : null,
                  ),
                  onPressed: quantity >= maxQuantity
                      ? null
                      : () => onQuantityChanged(quantity + 1),
                  constraints: const BoxConstraints(
                    minHeight: 30,
                    minWidth: 30,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          if (quantity >= maxQuantity)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Tooltip(
                message: 'Max $maxQuantity',
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.orange[400],
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: Colors.red),
            onPressed: onRemove,
            constraints: const BoxConstraints(minHeight: 40, minWidth: 40),
          ),
        ],
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
    width: 64,
    height: 64,
    color: Colors.grey[100],
    child: Icon(Icons.shopping_bag_outlined, color: Colors.grey[300], size: 28),
  );
}

// ── Price row ─────────────────────────────────────────────────────────────────

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _PriceRow(
    this.label,
    this.value, {
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? Colors.black : Colors.grey[600],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: valueColor ?? Colors.black,
          ),
        ),
      ],
    );
  }
}
