import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_constants.dart';
import '../../models/menu_model.dart';
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
    final scheme = Theme.of(context).colorScheme;
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
    final delLat = defaultAddr?.latitude ?? currentUser?.latitude;
    final delLng = defaultAddr?.longitude ?? currentUser?.longitude;
    final surgeKey =
        '${delLat?.toStringAsFixed(6) ?? '0'},${delLng?.toStringAsFixed(6) ?? '0'}';
    final surgeAsync = ref.watch(surgeMultiplierProvider(surgeKey));
    if (surgeAsync.hasValue) _lastSurge = surgeAsync.value!;
    final surgeMultiplier = surgeAsync.valueOrNull ?? _lastSurge;

    // Accumulate delivery / service fee across all stores
    double totalActiveFee = 0;
    final storeData = <String, Restaurant?>{};
    final feeTypes = <String>{};
    bool anyFeeLoading = false;
    final hasDeliveryCoords = delLat != null && delLng != null;
    for (final sid in storeIds) {
      final sAsync = ref.watch(restaurantByIdProvider(sid));
      final s = sAsync.valueOrNull;
      storeData[sid] = s;
      if (isPickup) {
        totalActiveFee += s?.serviceFee ?? AppConstants.pickupServiceFee;
      } else if (hasDeliveryCoords) {
        final feeKey =
            '$sid|$delLat|$delLng|${s?.latitude ?? ''}|${s?.longitude ?? ''}|${s?.deliveryFee ?? ''}';
        final feeAsync = ref.watch(deliveryFeeProvider(feeKey));
        if (feeAsync.isLoading) anyFeeLoading = true;
        final fr = feeAsync.valueOrNull;
        totalActiveFee += fr?.deliveryFee ?? AppConstants.defaultDeliveryFee;
        if (fr != null) {
          if (fr.restaurantOverride != null) {
            feeTypes.add('Store');
          } else if (fr.calculation == 'distance_based') {
            feeTypes.add('KM');
          } else {
            feeTypes.add('Base');
          }
        }
      } else {
        totalActiveFee += AppConstants.defaultDeliveryFee;
      }
    }
    final feeTypeLabel = feeTypes.isNotEmpty ? ' (${feeTypes.join(', ')})' : '';

    // MealHub+ free-delivery preview (delivery only).
    final activeSub = ref.watch(activeSubscriptionProvider).valueOrNull;
    final subDeliveryFree =
        activeSub != null &&
        activeSub.isActive &&
        activeSub.hasDeliveries &&
        !isPickup;
    final effectiveFee = subDeliveryFree ? 0.0 : totalActiveFee;

    final platformServiceFee = AppConstants.calculateServiceFee(subtotal);
    final tax = subtotal * AppConstants.taxRate;
    final total = subtotal + effectiveFee + platformServiceFee + tax;

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
        title: Text(
          'Grocery Cart',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
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
      body: cartItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_grocery_store_outlined,
                    size: 80,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your grocery cart is empty',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                          color: scheme.surfaceContainerHighest,
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
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Delivery',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: !isPickup
                                              ? Colors.white
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
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
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Pickup',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: isPickup
                                              ? Colors.white
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
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
                                children: [
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
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
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
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
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
                                      Text(
                                        'Deliver to',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        deliveryAddress,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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
                              Icon(
                                Icons.storefront_rounded,
                                color: AppTheme.primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  storeData[sid]?.name ?? 'Store',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${grouped[sid]!.length} item${grouped[sid]!.length == 1 ? '' : 's'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── Suggested Items ───────────────────────────────
                        _SuggestedItems(
                          storeIds: storeIds,
                          cartItemIds: cartItems
                              .map((c) => c.menuItem.id)
                              .toSet(),
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
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                            width: 0.7,
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
                                '${AppConstants.currencySymbol}${effectiveFee.toStringAsFixed(2)}',
                                valueColor: const Color(0xFF10B981),
                              )
                            else
                              _PriceRow(
                                subDeliveryFree
                                    ? 'Delivery (MealHub+ FREE)'
                                    : surgeMultiplier > 1.0
                                    ? 'Delivery (${((surgeMultiplier - 1) * 100).toStringAsFixed(0)}% surge)'
                                    : 'Delivery$feeTypeLabel${storeIds.length > 1 ? ' – ${storeIds.length} stores' : ''}',
                                anyFeeLoading
                                    ? 'Calculating…'
                                    : subDeliveryFree
                                    ? '\$0.00'
                                    : '${AppConstants.currencySymbol}${totalActiveFee.toStringAsFixed(2)}',
                                valueColor: subDeliveryFree
                                    ? const Color(0xFF6C63FF)
                                    : surgeMultiplier > 1.0
                                    ? const Color(0xFFFFA630)
                                    : null,
                              ),
                            const SizedBox(height: 8),
                            _PriceRow(
                              'Service Fee',
                              '${AppConstants.currencySymbol}${platformServiceFee.toStringAsFixed(2)}',
                            ),
                            const SizedBox(height: 8),
                            _PriceRow(
                              'Tax',
                              '${AppConstants.currencySymbol}${tax.toStringAsFixed(2)}',
                            ),
                            Divider(color: scheme.outlineVariant, height: 16),
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
                      color: Theme.of(context).cardColor,
                      border: Border(
                        top: BorderSide(color: scheme.outlineVariant),
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
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor, width: 0.7),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${AppConstants.currencySymbol}${(price * quantity).toStringAsFixed(2)}',
                  style: TextStyle(
                    color: AppTheme.priceColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
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
                    color: quantity >= maxQuantity
                        ? Theme.of(context).disabledColor
                        : null,
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
    child: Icon(Icons.shopping_bag_outlined, color: Colors.grey[700], size: 28),
  );
}

// ── Suggested Items ───────────────────────────────────────────────────────────

class _SuggestedItems extends ConsumerWidget {
  final List<String> storeIds;
  final Set<String> cartItemIds;

  const _SuggestedItems({required this.storeIds, required this.cartItemIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<MenuItem> suggestions = [];
    for (final sid in storeIds) {
      final items = ref.watch(restaurantMenuProvider(sid)).valueOrNull ?? [];
      for (final item in items) {
        if (!cartItemIds.contains(item.id) &&
            item.isAvailable &&
            item.inStock) {
          suggestions.add(item);
        }
      }
    }
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final shown = suggestions.take(10).toList();

    // Card width = 42 % of screen, clamped for tiny → tablet
    final cardW = (MediaQuery.of(context).size.width * 0.42)
        .clamp(140.0, 200.0);
    // Card total height is screen-proportional — no manual content maths.
    // The image section uses Expanded to fill whatever space is left after
    // the fixed-height text + button area. Nothing can overflow.
    final cardH = (MediaQuery.of(context).size.width * 0.58)
        .clamp(200.0, 260.0);
    // Image fills whatever remains after the fixed 110 dp text+button area
    final imgH = (cardH - 110).clamp(88.0, 150.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Suggested Items',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'Top picks based on the items in your cart',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // Add 8 dp vertical padding inside the SizedBox so cards have
        // breathing room top/bottom without adding to the card's own height.
        SizedBox(
          height: cardH + 8,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: shown.length,
            itemBuilder: (ctx, i) => _SuggestionCard(
              item: shown[i],
              cardWidth: cardW,
              imageHeight: imgH,
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  final MenuItem item;
  final double cardWidth;
  final double imageHeight;

  const _SuggestionCard({
    required this.item,
    required this.cardWidth,
    required this.imageHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart = ref
        .watch(groceryCartProvider)
        .any((c) => c.menuItem.id == item.id);
    final scheme = Theme.of(context).colorScheme;

    // Card has an explicit fixed height — the Column is max-sized inside it.
    // Image section uses Expanded so it fills whatever remains after the
    // fixed text + button rows. Nothing can grow past the card bounds.
    return Container(
      width: cardWidth,
      // height == cardH exactly (no vertical margin so nothing spills out)
      height: imageHeight + 110,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor, width: 0.7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          // ── Image (Expanded — fills all space above the text area) ──────
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(11),
                  ),
                  child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                      ? Image.network(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                if (item.weight != null)
                  Positioned(
                    bottom: 5,
                    left: 5,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: cardWidth - 14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2BA84A),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          item.weight!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Name (fixed 2-line height) ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: SizedBox(
              height: 32,
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ),

          // ── Price (fixed 1-line height) ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
            child: SizedBox(
              height: 18,
              child: Text(
                '${AppConstants.currencySymbol}${item.discountedPrice.toStringAsFixed(2)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.priceColor,
                ),
              ),
            ),
          ),

          // ── Add button (fixed 32 dp, overrides Material 36 dp minimum) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: SizedBox(
              width: double.infinity,
              height: 32,
              child: ElevatedButton.icon(
                onPressed: inCart
                    ? null
                    : () => ref
                        .read(groceryCartProvider.notifier)
                        .addItem(item),
                style: ElevatedButton.styleFrom(
                  backgroundColor: inCart
                      ? scheme.surfaceContainerHighest
                      : const Color(0xFF2BA84A),
                  foregroundColor:
                      inCart ? scheme.onSurfaceVariant : Colors.white,
                  elevation: 0,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: Icon(
                  inCart ? Icons.check_rounded : Icons.shopping_cart_outlined,
                  size: 13,
                ),
                label: Text(
                  inCart ? 'Added' : 'Add',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    color: Colors.grey[100],
    child: Icon(Icons.shopping_bag_outlined, color: Colors.grey[400], size: 28),
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
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: isBold ? 1.0 : 0.75),
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
            color: valueColor ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
