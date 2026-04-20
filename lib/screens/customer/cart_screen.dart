import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_constants.dart';
import '../../models/restaurant_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/feature_providers.dart';
import '../../services/delivery_fee_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/context_extensions.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final isPickup = ref.watch(isPickupProvider);
    final defaultAddrAsync = currentUserId != null
        ? ref.watch(defaultAddressProvider(currentUserId))
        : null;
    final deliveryAddress =
        defaultAddrAsync?.valueOrNull?.address ??
        currentUser?.address ??
        'No address saved';
    final restaurantId = cartItems.isNotEmpty
        ? cartItems.first.menuItem.restaurantId
        : null;
    final restaurantAsync = restaurantId != null
        ? ref.watch(restaurantByIdProvider(restaurantId))
        : const AsyncValue<Restaurant?>.data(null);
    final restaurant = restaurantAsync.valueOrNull;

    // Admin-configured delivery fee (local haversine + admin config)
    final delAddr = defaultAddrAsync?.valueOrNull;
    final delLat = delAddr?.latitude ?? currentUser?.latitude;
    final delLng = delAddr?.longitude ?? currentUser?.longitude;
    // Only build a valid key when we have real coordinates — avoids
    // creating a throwaway provider instance that returns null on first render.
    final hasCoords = delLat != null && delLng != null && restaurantId != null;
    final feeKey = hasCoords
        ? '$restaurantId|$delLat|$delLng|${restaurant?.latitude ?? ''}|${restaurant?.longitude ?? ''}|${restaurant?.deliveryFee ?? ''}'
        : '';
    final feeAsync = feeKey.isNotEmpty && !isPickup
        ? ref.watch(deliveryFeeProvider(feeKey))
        : const AsyncValue<DeliveryFeeResult?>.data(null);
    final feeLoading = hasCoords && !isPickup && feeAsync.isLoading;
    final feeResult = feeAsync.valueOrNull;
    final deliveryFee =
        feeResult?.deliveryFee ?? AppConstants.defaultDeliveryFee;
    final distanceKm = feeResult?.distanceKm;

    final pickupServiceFee =
        restaurant?.serviceFee ?? AppConstants.pickupServiceFee;

    // ── MealHub+ subscription benefit ──────────────────────────────
    final activeSub = ref.watch(activeSubscriptionProvider).valueOrNull;
    final subEligible =
        activeSub != null &&
        activeSub.isActive &&
        activeSub.hasDeliveries &&
        !isPickup;
    final subDeliveryFree = subEligible;
    final subServiceDiscount = subEligible
        ? (pickupServiceFee * activeSub.serviceFeeDiscount)
        : 0.0;

    final rawFee = isPickup
        ? (pickupServiceFee - subServiceDiscount).clamp(0.0, double.infinity)
        : deliveryFee;
    final activeFee = subDeliveryFree ? 0.0 : rawFee;

    final tax = subtotal * AppConstants.taxRate;
    final total = subtotal + activeFee + tax;

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
          'Shopping Cart',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: cartItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your cart is empty',
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
                      'Continue Shopping',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
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
                                    ref.read(isPickupProvider.notifier).state =
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
                                    ref.read(isPickupProvider.notifier).state =
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
                          child: Row(
                            children: [
                              const Icon(
                                Icons.store_rounded,
                                color: Color(0xFF10B981),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Pick up from',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      restaurant?.name ?? 'Restaurant',
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
                      // Cart Items
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cartItems.length,
                        itemBuilder: (context, index) {
                          final cartItem = cartItems[index];
                          return _CartItemWidget(
                            name: cartItem.menuItem.name,
                            quantity: cartItem.quantity,
                            price: cartItem.menuItem.discountedPrice,
                            onRemove: () {
                              ref
                                  .read(cartProvider.notifier)
                                  .removeItem(cartItem.menuItem.id);
                            },
                            onQuantityChanged: (newQuantity) {
                              ref
                                  .read(cartProvider.notifier)
                                  .updateQuantity(
                                    cartItem.menuItem.id,
                                    newQuantity,
                                  );
                            },
                          );
                        },
                      ),
                      // Price Breakdown
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            // MealHub+ banner
                            if (subDeliveryFree) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF6C63FF,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Color(0xFF6C63FF),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'MealHub+ Free Delivery Applied',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF6C63FF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            _PriceRow(
                              context.l10n.subtotal,
                              '${AppConstants.currencySymbol}${subtotal.toStringAsFixed(2)}',
                            ),
                            const SizedBox(height: 8),
                            if (isPickup)
                              _PriceRow(
                                subServiceDiscount > 0
                                    ? 'Service Fee (MealHub+ ${(activeSub!.serviceFeeDiscount * 100).toInt()}% off)'
                                    : 'Service Fee',
                                '${AppConstants.currencySymbol}${rawFee.toStringAsFixed(2)}',
                                valueColor: subServiceDiscount > 0
                                    ? const Color(0xFF6C63FF)
                                    : const Color(0xFF10B981),
                              )
                            else
                              _PriceRow(
                                subDeliveryFree
                                    ? 'Delivery (MealHub+ FREE)'
                                    : 'Delivery${feeResult?.calculation == 'distance_based'
                                          ? ' (KM)'
                                          : feeResult?.restaurantOverride != null
                                          ? ' (Store)'
                                          : ' (Base)'}${distanceKm != null ? ' – ${distanceKm.toStringAsFixed(1)} km' : ''}',
                                feeLoading
                                    ? 'Calculating…'
                                    : subDeliveryFree
                                    ? '\$0.00'
                                    : '${AppConstants.currencySymbol}${deliveryFee.toStringAsFixed(2)}',
                                valueColor: subDeliveryFree
                                    ? const Color(0xFF6C63FF)
                                    : null,
                              ),
                            const SizedBox(height: 8),
                            _PriceRow(
                              context.l10n.tax,
                              '${AppConstants.currencySymbol}${tax.toStringAsFixed(2)}',
                            ),
                            Divider(color: Colors.grey[300], height: 16),
                            _PriceRow(
                              'Total',
                              '${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
                              isBold: true,
                            ),
                          ],
                        ),
                      ),

                      // Promo Code
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
                // Checkout Button
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: SafeArea(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/checkout');
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

class _CartItemWidget extends StatelessWidget {
  final String name;
  final int quantity;
  final double price;
  final VoidCallback onRemove;
  final Function(int) onQuantityChanged;

  const _CartItemWidget({
    required this.name,
    required this.quantity,
    required this.price,
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
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.image, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
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
                  icon: const Icon(Icons.add, size: 16),
                  onPressed: () => onQuantityChanged(quantity + 1),
                  constraints: const BoxConstraints(
                    minHeight: 30,
                    minWidth: 30,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
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
}

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
              color: isBold
                  ? Colors.black
                  : Theme.of(context).colorScheme.onSurfaceVariant,
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
