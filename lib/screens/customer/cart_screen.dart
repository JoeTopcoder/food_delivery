import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/responsive.dart';
import '../../config/app_constants.dart';
import '../../models/restaurant_model.dart';
import '../../models/cart_recommendation_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/feature_providers.dart';
import '../../services/driver/delivery_fee_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/context_extensions.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  String? _buildCustomizationSummary(CartItem cartItem) {
    final parts = <String>[];
    for (final side in cartItem.selectedSides) {
      parts.add(side.name);
    }
    for (final choices in cartItem.selectedOptions.values) {
      for (final c in choices) {
        parts.add(c.name);
      }
    }
    if (cartItem.notes != null && cartItem.notes!.trim().isNotEmpty) {
      parts.add('Note: ${cartItem.notes!.trim()}');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
    final cartNotifier = ref.read(cartProvider.notifier);
    final restaurantCount = cartNotifier.restaurantCount;
    final isMultiRestaurant = restaurantCount > 1;

    final restaurantId = cartItems.isNotEmpty
        ? cartItems.first.menuItem.restaurantId
        : null;
    final restaurantAsync = restaurantId != null
        ? ref.watch(restaurantByIdProvider(restaurantId))
        : const AsyncValue<Restaurant?>.data(null);
    final restaurant = restaurantAsync.valueOrNull;

    // Multi-restaurant feature flags
    final multiEnabled = ref.watch(multiRestaurantEnabledProvider).valueOrNull ?? false;
    final extraStopFee = ref.watch(extraStopFeeProvider).valueOrNull ?? 2.0;
    final totalExtraStopFee = isMultiRestaurant ? extraStopFee * (restaurantCount - 1) : 0.0;

    // Admin-configured delivery fee (local haversine + admin config)
    final delAddr = defaultAddrAsync?.valueOrNull;
    final delLat = delAddr?.latitude ?? currentUser?.latitude;
    final delLng = delAddr?.longitude ?? currentUser?.longitude;
    final hasCoords = delLat != null && delLng != null;

    // AI cart recommendations — fetch when multi-restaurant is enabled & cart has items
    final cartRestaurantIds = cartItems.map((i) => i.menuItem.restaurantId).toSet().toList();
    final cartRecs = (multiEnabled && currentUserId != null && cartRestaurantIds.isNotEmpty)
        ? (ref.watch(cartRecommendationsProvider((
              userId: currentUserId,
              cartRestaurantIds: cartRestaurantIds,
              lat: delLat,
              lng: delLng,
            ))).valueOrNull ?? [])
        : <CartRecommendation>[];

    // For multi-restaurant: calculate fee from each restaurant → customer and sum.
    // For single restaurant: use the existing single provider.
    double baseDeliveryFee;
    double? distanceKm;
    bool feeLoading = false;

    if (isMultiRestaurant && !isPickup && hasCoords) {
      double multiTotal = 0.0;
      for (final restId in cartNotifier.restaurantIds) {
        final restInfo = ref.watch(restaurantByIdProvider(restId)).valueOrNull;
        final feeKey = restInfo != null
            ? '$restId|$delLat|$delLng|${restInfo.latitude ?? ''}|${restInfo.longitude ?? ''}|${restInfo.deliveryFee ?? ''}'
            : '';
        if (feeKey.isEmpty) {
          multiTotal += AppConstants.defaultDeliveryFee;
          continue;
        }
        final fa = ref.watch(deliveryFeeProvider(feeKey));
        if (fa.isLoading) feeLoading = true;
        multiTotal += fa.valueOrNull?.deliveryFee ?? AppConstants.defaultDeliveryFee;
      }
      baseDeliveryFee = multiTotal;
    } else {
      final hasRestCoords = hasCoords && restaurantId != null;
      final feeKey = hasRestCoords
          ? '$restaurantId|$delLat|$delLng|${restaurant?.latitude ?? ''}|${restaurant?.longitude ?? ''}|${restaurant?.deliveryFee ?? ''}'
          : '';
      final feeAsync = feeKey.isNotEmpty && !isPickup
          ? ref.watch(deliveryFeeProvider(feeKey))
          : const AsyncValue<DeliveryFeeResult?>.data(null);
      if (hasRestCoords && !isPickup && feeAsync.isLoading) feeLoading = true;
      final feeResult = feeAsync.valueOrNull;
      baseDeliveryFee = feeResult?.deliveryFee ?? AppConstants.defaultDeliveryFee;
      distanceKm = feeResult?.distanceKm;
    }

    // ── Group order discount (60 % of regular delivery fee) ─────────
    final groupParticipantCount = ref.watch(groupOrderParticipantCountProvider);
    final isGroupOrder = groupParticipantCount > 0;
    final deliveryFee = isGroupOrder ? baseDeliveryFee * 0.60 : baseDeliveryFee;

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

    final platformServiceFee = AppConstants.calculateServiceFee(subtotal);
    // Tax is determined server-side (zone-based) at checkout — omit from estimate.
    final total = subtotal + activeFee + platformServiceFee + totalExtraStopFee;

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
                    color: Colors.grey[700],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your cart is empty',
                    style: TextStyle(
                      fontSize: Responsive.headingMedium(context),
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
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  child: Column(
                    children: [
                      // ── Delivery / Pickup Toggle ──────────────────────
                      Container(
                        margin: EdgeInsets.fromLTRB(
                          Responsive.horizontalPadding(context),
                          Responsive.spacingSmall(context),
                          Responsive.horizontalPadding(context),
                          0,
                        ),
                        padding: EdgeInsets.all(Responsive.spacingSmall(context) * 0.5),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
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
                                  padding: EdgeInsets.symmetric(
                                    vertical: Responsive.spacingSmall(context),
                                  ),
                                  decoration: BoxDecoration(
                                    color: !isPickup
                                        ? AppTheme.primaryColor
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(Responsive.cardRadius(context) - 2),
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
                                          fontSize: Responsive.bodyText(context),
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
                                  padding: EdgeInsets.symmetric(
                                    vertical: Responsive.spacingSmall(context),
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPickup
                                        ? AppTheme.primaryColor
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(Responsive.cardRadius(context) - 2),
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
                                          fontSize: Responsive.bodyText(context),
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
                          margin: EdgeInsets.fromLTRB(
                            Responsive.horizontalPadding(context),
                            0,
                            Responsive.horizontalPadding(context),
                            0,
                          ),
                          padding: EdgeInsets.all(Responsive.cardPadding(context)),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
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
                                        fontSize: Responsive.smallText(context),
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      restaurant?.name ?? 'Restaurant',
                                      style: TextStyle(
                                        fontSize: Responsive.bodyText(context),
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
                            margin: EdgeInsets.fromLTRB(
                              Responsive.horizontalPadding(context),
                              0,
                              Responsive.horizontalPadding(context),
                              0,
                            ),
                            padding: EdgeInsets.all(Responsive.cardPadding(context)),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.07,
                              ),
                              borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
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
                                          fontSize: Responsive.smallText(context),
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        deliveryAddress,
                                        style: TextStyle(
                                          fontSize: Responsive.bodyText(context),
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

                      // Multi-restaurant banner
                      if (multiEnabled && isMultiRestaurant)
                        Container(
                          margin: EdgeInsets.fromLTRB(
                            Responsive.horizontalPadding(context),
                            0,
                            Responsive.horizontalPadding(context),
                            8,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: Responsive.spacingSmall(context),
                            vertical: Responsive.spacingSmall(context) * 0.6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.restaurant_rounded, color: AppTheme.primaryColor, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Multi-restaurant order – $restaurantCount restaurants',
                                  style: TextStyle(
                                    fontSize: Responsive.smallText(context),
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Cart Items grouped by restaurant
                      if (multiEnabled && isMultiRestaurant)
                        ...cartNotifier.itemsByRestaurant.entries.map((entry) {
                          final restId = entry.key;
                          final items = entry.value;
                          final restSubtotal = cartNotifier.subtotalForRestaurant(restId);
                          final restAsync = ref.watch(restaurantByIdProvider(restId));
                          final restName = restAsync.valueOrNull?.name ?? 'Restaurant';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Restaurant section header
                              Container(
                                margin: EdgeInsets.fromLTRB(
                                  Responsive.horizontalPadding(context),
                                  4,
                                  Responsive.horizontalPadding(context),
                                  0,
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: Responsive.spacingSmall(context),
                                  vertical: Responsive.spacingSmall(context) * 0.6,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.store_rounded, size: 16, color: scheme.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        restName,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: Responsive.smallText(context),
                                          fontWeight: FontWeight.w700,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${AppConstants.currencySymbol}${restSubtotal.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: Responsive.smallText(context),
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.priceColor,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () {
                                        showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('Remove restaurant?'),
                                            content: Text('Remove all items from $restName?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context, false),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(context, true),
                                                child: const Text('Remove', style: TextStyle(color: Colors.red)),
                                              ),
                                            ],
                                          ),
                                        ).then((confirmed) {
                                          if (confirmed == true) {
                                            ref.read(cartProvider.notifier).removeRestaurantGroup(restId);
                                          }
                                        });
                                      },
                                      child: Icon(Icons.close, size: 16, color: Colors.red.shade400),
                                    ),
                                  ],
                                ),
                              ),
                              // Items under this restaurant
                              ...items.map((cartItem) => _CartItemWidget(
                                name: cartItem.menuItem.name,
                                imageUrl: cartItem.menuItem.imageUrl,
                                quantity: cartItem.quantity,
                                price: cartItem.menuItem.discountedPrice,
                                customizationSummary: _buildCustomizationSummary(cartItem),
                                onRemove: () => ref.read(cartProvider.notifier).removeItem(cartItem.menuItem.id),
                                onQuantityChanged: (q) => ref.read(cartProvider.notifier).updateQuantity(cartItem.menuItem.id, q),
                              )),
                            ],
                          );
                        })
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: cartItems.length,
                          itemBuilder: (context, index) {
                            final cartItem = cartItems[index];
                            return _CartItemWidget(
                              name: cartItem.menuItem.name,
                              imageUrl: cartItem.menuItem.imageUrl,
                              quantity: cartItem.quantity,
                              price: cartItem.menuItem.discountedPrice,
                              customizationSummary: _buildCustomizationSummary(cartItem),
                              onRemove: () => ref.read(cartProvider.notifier).removeItem(cartItem.menuItem.id),
                              onQuantityChanged: (q) => ref.read(cartProvider.notifier).updateQuantity(cartItem.menuItem.id, q),
                            );
                          },
                        ),
                      // AI recommendation banner
                      if (cartRecs.isNotEmpty)
                        _CartRecommendationBanner(recommendations: cartRecs),

                      // Price Breakdown
                      Container(
                        margin: EdgeInsets.all(Responsive.horizontalPadding(context)),
                        padding: EdgeInsets.all(Responsive.cardPadding(context)),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
                        ),
                        child: Column(
                          children: [
                            // Group order discount banner
                            if (isGroupOrder) ...[
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: Responsive.spacingSmall(context),
                                  vertical: Responsive.spacingSmall(context) * 0.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(Responsive.cardRadius(context) - 2),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.groups_rounded,
                                      color: Color(0xFF10B981),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Group Order – 40% delivery discount ($groupParticipantCount members)',
                                        style: TextStyle(
                                          fontSize: Responsive.smallText(context),
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF10B981),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            // MealHub+ banner
                            if (subDeliveryFree) ...[
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: Responsive.spacingSmall(context),
                                  vertical: Responsive.spacingSmall(context) * 0.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF6C63FF,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(Responsive.cardRadius(context) - 2),
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
                                        fontSize: Responsive.smallText(context),
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
                            if (isGroupOrder) ...[
                              _PriceRow(
                                'Delivery (Group 40% off – $groupParticipantCount members)',
                                feeLoading
                                    ? 'Calculating…'
                                    : '${AppConstants.currencySymbol}${deliveryFee.toStringAsFixed(2)}',
                                valueColor: const Color(0xFF10B981),
                              ),
                            ] else if (isPickup)
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
                                    : isMultiRestaurant
                                    ? 'Delivery (per restaurant)${distanceKm != null ? ' – ${distanceKm.toStringAsFixed(1)} km' : ''}'
                                    : 'Delivery${distanceKm != null ? ' (KM) – ${distanceKm.toStringAsFixed(1)} km' : ' (Base)'}',
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
                              'Service Fee',
                              '${AppConstants.currencySymbol}${platformServiceFee.toStringAsFixed(2)}',
                            ),
                            if (multiEnabled && isMultiRestaurant) ...[
                              const SizedBox(height: 8),
                              _PriceRow(
                                'Multi-stop Fee (${restaurantCount - 1} extra stop${restaurantCount - 1 > 1 ? 's' : ''})',
                                '${AppConstants.currencySymbol}${totalExtraStopFee.toStringAsFixed(2)}',
                              ),
                            ],
                            Divider(color: scheme.outlineVariant, height: 16),
                            _PriceRow(
                              'Total',
                              '${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
                              isBold: true,
                            ),
                          ],
                        ),
                      ),

                      // Bottom padding to clear the sticky checkout button
                      const SizedBox(height: 80),
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
                        top: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
                    child: SafeArea(
                      child: ElevatedButton(
                        onPressed: () {
                          if (isMultiRestaurant) {
                            Navigator.pushNamed(context, '/multi-restaurant-checkout');
                          } else {
                            Navigator.pushNamed(context, '/checkout');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: Responsive.buttonHeight(context) * 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Proceed to Checkout - \$${total.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: Responsive.bodyText(context),
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
  final String? imageUrl;
  final int quantity;
  final double price;
  final String? customizationSummary;
  final VoidCallback onRemove;
  final Function(int) onQuantityChanged;

  const _CartItemWidget({
    required this.name,
    this.imageUrl,
    required this.quantity,
    required this.price,
    this.customizationSummary,
    required this.onRemove,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: Responsive.spacing(context) * 0.375,
      ),
      padding: EdgeInsets.all(Responsive.cardPadding(context)),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
        border: Border.all(color: Theme.of(context).dividerColor, width: 0.7),
      ),
      child: Row(
        children: [
          Container(
            width: Responsive.cartItemImageSize(context),
            height: Responsive.cartItemImageSize(context),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Responsive.cardRadius(context) - 2),
            ),
            child: imageUrl != null && imageUrl!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(Responsive.cardRadius(context) - 2),
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.image,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Icon(
                    Icons.image,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: Responsive.bodyText(context),
                  ),
                ),
                if (customizationSummary != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    customizationSummary!,
                    style: TextStyle(
                      fontSize: Responsive.smallText(context),
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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
              fontSize: isBold ? Responsive.bodyText(context) : Responsive.smallText(context),
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
            fontSize: isBold ? Responsive.bodyText(context) : Responsive.smallText(context),
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: valueColor ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

// ── AI Cart Recommendation Banner ─────────────────────────────────────────────

class _CartRecommendationBanner extends StatelessWidget {
  final List<CartRecommendation> recommendations;
  const _CartRecommendationBanner({required this.recommendations});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withValues(alpha: 0.08),
            AppTheme.primaryColor.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 16, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  'Add from a nearby restaurant',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),

          // Restaurant cards
          ...recommendations.map((rec) => _RecommendationCard(rec: rec)),

          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final CartRecommendation rec;
  const _RecommendationCard({required this.rec});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        '/restaurant-detail',
        arguments: rec.restaurantId,
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: rec.imageUrl != null && rec.imageUrl!.isNotEmpty
                  ? Image.network(
                      rec.imageUrl!,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _PlaceholderThumb(),
                    )
                  : _PlaceholderThumb(),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rec.restaurantName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rec.reason,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (rec.rating != null) ...[
                        const Icon(Icons.star_rounded, size: 12, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 2),
                        Text(
                          rec.rating!.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (rec.distanceKm != null) ...[
                        Icon(Icons.place_outlined, size: 12, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 2),
                        Text(
                          '${rec.distanceKm!.toStringAsFixed(1)} km',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (rec.estimatedDeliveryTime != null)
                        Text(
                          '${rec.estimatedDeliveryTime} min',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // CTA arrow
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.primaryColor),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderThumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.restaurant_rounded, color: AppTheme.primaryColor, size: 24),
      );
}
