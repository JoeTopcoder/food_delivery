import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/menu_model.dart';
import '../../models/restaurant_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/premium_providers.dart';
import '../../utils/friendly_error.dart';
import '../../providers/auth_provider.dart';
import '../../providers/recommendation_provider.dart';
import '../../providers/feature_providers.dart';
import '../../utils/app_theme.dart';
import '../../widgets/menu_item_card.dart';
import '../../widgets/menu_item_detail_sheet.dart';
import '../../utils/app_feedback_widgets.dart';
import 'group_order_detail_screen.dart';

class RestaurantDetailScreen extends ConsumerStatefulWidget {
  final Restaurant restaurant;

  /// When coming from a group order, these link the cart back to the participant.
  final String? groupOrderId;
  final String? groupParticipantId;

  const RestaurantDetailScreen({
    super.key,
    required this.restaurant,
    this.groupOrderId,
    this.groupParticipantId,
  });

  @override
  ConsumerState<RestaurantDetailScreen> createState() =>
      _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState
    extends ConsumerState<RestaurantDetailScreen> {
  late ScrollController _scrollController;
  bool _showAppBar = false;
  String? _selectedCategory;
  bool _startingGroupOrder = false;
  bool _savingToGroup = false;

  Future<void> _saveToGroupOrder() async {
    final participantId = widget.groupParticipantId;
    if (participantId == null) return;
    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) {
      AppSnackbar.info(context, 'Add some items first!');
      return;
    }
    setState(() => _savingToGroup = true);
    try {
      final service = ref.read(groupOrderServiceProvider);
      final items = cartItems.map((c) => c.toJson()).toList();
      final subtotal = cartItems.fold(0.0, (sum, c) => sum + c.subtotal);
      final ok = await service.updateParticipantItems(
        participantId: participantId,
        items: items,
        subtotal: subtotal,
      );
      if (!mounted) return;
      if (ok) {
        AppSnackbar.success(context, 'Items saved to group order!');
        // Clear the regular cart so items aren't double-counted
        ref.read(cartProvider.notifier).clearCart();
        Navigator.pop(context);
      } else {
        AppSnackbar.error(context, 'Failed to save items. Try again.');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _savingToGroup = false);
    }
  }

  Future<void> _startGroupOrder() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    setState(() => _startingGroupOrder = true);
    try {
      final service = ref.read(groupOrderServiceProvider);
      final group = await service.createGroupOrder(
        hostUserId: userId,
        restaurantId: widget.restaurant.id,
        name: '${widget.restaurant.name} Group Order',
        deadlineMinutes: 60,
      );
      if (group == null) throw Exception('Failed to create group order');
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupOrderDetailScreen(groupOrderId: group.id),
        ),
      );
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _startingGroupOrder = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    // Track restaurant view for AI engine
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) {
        ref
            .read(behaviorTrackingProvider)
            .trackRestaurantView(
              userId,
              widget.restaurant.id,
              cuisineType: widget.restaurant.cuisineType,
            );
        // Record for real-time session boost
        if (widget.restaurant.cuisineType != null) {
          ref
              .read(realtimeBoostProvider.notifier)
              .recordInteraction(widget.restaurant.cuisineType!);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    setState(() {
      _showAppBar = _scrollController.offset > 200;
    });
  }

  @override
  Widget build(BuildContext context) {
    final menuItemsAsync = ref.watch(
      restaurantMenuProvider(widget.restaurant.id),
    );
    final currentUserId = ref.watch(currentUserIdProvider);
    final isFavAsync = currentUserId != null
        ? ref.watch(isFavoriteProvider((currentUserId, widget.restaurant.id)))
        : const AsyncValue<bool>.data(false);
    final isFav = isFavAsync.valueOrNull ?? false;

    Future<void> toggleFav() async {
      if (currentUserId == null) return;
      final svc = ref.read(favoritesServiceProvider);
      await svc.toggleFavorite(currentUserId, widget.restaurant.id);
      ref.invalidate(isFavoriteProvider((currentUserId, widget.restaurant.id)));
      ref.invalidate(favoriteRestaurantsProvider(currentUserId));
    }

    return Scaffold(
      appBar: _showAppBar
          ? AppBar(
              elevation: 0,
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                widget.restaurant.name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    isFav ? Icons.favorite : Icons.favorite_outline,
                    color: isFav
                        ? AppTheme.accentColor
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: toggleFav,
                ),
                IconButton(
                  icon: Icon(
                    Icons.share_outlined,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: () => Share.share(
                    'Check out ${widget.restaurant.name} on MealHub!',
                  ),
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Restaurant Hero Image
                Stack(
                  children: [
                    ClipRRect(
                      child:
                          widget.restaurant.imageUrl != null &&
                              widget.restaurant.imageUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: widget.restaurant.imageUrl!,
                              height: 260,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              memCacheWidth: 800,
                              errorWidget: (_, _, _) => Container(
                                height: 260,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppTheme.primaryColor.withValues(
                                        alpha: 0.15,
                                      ),
                                      AppTheme.primaryColor.withValues(
                                        alpha: 0.05,
                                      ),
                                    ],
                                  ),
                                ),
                                child: Icon(
                                  Icons.restaurant_rounded,
                                  size: 64,
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              height: 260,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppTheme.primaryColor.withValues(
                                      alpha: 0.15,
                                    ),
                                    AppTheme.primaryColor.withValues(
                                      alpha: 0.05,
                                    ),
                                  ],
                                ),
                              ),
                              child: Icon(
                                Icons.restaurant_rounded,
                                size: 64,
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                    ),
                    Positioned(
                      top: 40,
                      left: 16,
                      child: _showAppBar
                          ? const SizedBox.shrink()
                          : GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.1,
                                      ),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(8),
                                child: const Icon(Icons.arrow_back, size: 24),
                              ),
                            ),
                    ),
                    Positioned(
                      top: 40,
                      right: 16,
                      child: GestureDetector(
                        onTap: toggleFav,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            isFav ? Icons.favorite : Icons.favorite_outline,
                            size: 24,
                            color: isFav ? Colors.red : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Restaurant Info
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.restaurant.name,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (widget.restaurant.address != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 16,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.restaurant.address!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Status + rating row
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: widget.restaurant.isCurrentlyOpen
                                  ? AppTheme.successColor.withValues(alpha: 0.1)
                                  : AppTheme.accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.restaurant.isCurrentlyOpen
                                      ? Icons.check_circle_rounded
                                      : Icons.cancel_rounded,
                                  size: 14,
                                  color: widget.restaurant.isCurrentlyOpen
                                      ? AppTheme.successColor
                                      : AppTheme.accentColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.restaurant.isCurrentlyOpen
                                      ? 'Open Now'
                                      : 'Closed',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: widget.restaurant.isCurrentlyOpen
                                        ? AppTheme.successColor
                                        : AppTheme.accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.restaurant.formattedTodayHours != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.restaurant.formattedTodayHours!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${widget.restaurant.rating ?? '-'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                if (widget.restaurant.reviewCount != null) ...[
                                  Text(
                                    ' (${widget.restaurant.reviewCount})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.delivery_dining_rounded,
                                  size: 16,
                                  color: AppTheme.primaryColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.restaurant.estimatedDeliveryTime ?? 30} min',
                                  style: TextStyle(
                                    color: AppTheme.primaryColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Cuisine + delivery fee row
                      Row(
                        children: [
                          Text(
                            widget.restaurant.cuisineType ?? 'Multi-cuisine',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'Delivery: \$${widget.restaurant.deliveryFee ?? 0}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      if (widget.restaurant.description != null &&
                          widget.restaurant.description!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          widget.restaurant.description!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Menu Items
                menuItemsAsync.when(
                  data: (menuItems) {
                    // Group items by category
                    final grouped = <String, List<MenuItem>>{};
                    for (final item in menuItems) {
                      grouped.putIfAbsent(item.category, () => []).add(item);
                    }
                    final categories = grouped.keys.toList();
                    if (categories.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Center(child: Text('No menu items yet')),
                      );
                    }

                    // Default to first category
                    final activeCategory =
                        _selectedCategory ?? categories.first;
                    final activeItems = grouped[activeCategory] ?? [];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Horizontal category tabs (7krave pill style)
                        SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: categories.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final cat = categories[index];
                              final isActive = cat == activeCategory;
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedCategory = cat),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AppTheme.primaryColor
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: isActive
                                          ? AppTheme.primaryColor
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    cat,
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Category header
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Text(
                            activeCategory,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Items under selected category
                        ...activeItems.map(
                          (item) => MenuItemCard(
                            item: item,
                            onTap: () => _showMenuItemDetail(context, item),
                            onAddTap: () => _showMenuItemDetail(context, item),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: AppLoadingIndicator(color: AppTheme.primaryColor),
                    ),
                  ),
                  error: (err, stack) =>
                      AppErrorState(message: friendlyError(err)),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
          // Footer with View Cart / Schedule Order
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Group Order mode: save items back to participant ──
                    if (widget.groupOrderId != null) ...[
                      Consumer(
                        builder: (context, ref, _) {
                          final count = ref.watch(cartItemCountProvider);
                          return SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _savingToGroup
                                  ? null
                                  : _saveToGroupOrder,
                              icon: _savingToGroup
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.group_add_rounded,
                                      size: 20,
                                    ),
                              label: Text(
                                count > 0
                                    ? 'Save $count item${count != 1 ? 's' : ''} to Group Order'
                                    : 'Save to Group Order',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                            ),
                          );
                        },
                      ),
                    ] else ...[
                      // ── Normal mode ─────────────────────────────────────
                      if (!widget.restaurant.isCurrentlyOpen) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.accentColor.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 18,
                                color: AppTheme.accentColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'This restaurant is closed. '
                                  '${widget.restaurant.nextOpenLabel}. '
                                  'You can schedule an order.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.accentColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (!widget.restaurant.isCurrentlyOpen) {
                              Navigator.pushNamed(
                                context,
                                '/cart',
                                arguments: {
                                  'forceSchedule': true,
                                  'restaurant': widget.restaurant,
                                },
                              );
                            } else {
                              Navigator.pushNamed(context, '/cart');
                            }
                          },
                          icon: Icon(
                            widget.restaurant.isCurrentlyOpen
                                ? Icons.shopping_cart_rounded
                                : Icons.schedule_rounded,
                            size: 20,
                          ),
                          label: Text(
                            widget.restaurant.isCurrentlyOpen
                                ? 'View Cart'
                                : 'Schedule Order',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.restaurant.isCurrentlyOpen
                                ? AppTheme.primaryColor
                                : AppTheme.accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Group Order secondary button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _startingGroupOrder
                              ? null
                              : _startGroupOrder,
                          icon: _startingGroupOrder
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.group_add_rounded, size: 18),
                          label: const Text(
                            'Start Group Order',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                            side: BorderSide(color: AppTheme.primaryColor),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ], // end else (normal mode)
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<List<MenuItemSide>?> _showSidesSheet(
    BuildContext context,
    MenuItem item,
  ) async {
    final availableSides = item.sides!.where((s) => s.isAvailable).toList();
    final selected = <String, bool>{
      for (final s in availableSides) s.id: false,
    };

    return showModalBottomSheet<List<MenuItemSide>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final chosenSides = availableSides
                .where((s) => selected[s.id] == true)
                .toList();
            final sidesTotal = chosenSides.fold(0.0, (sum, s) => sum + s.price);

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add sides to ${item.name}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select any extras you\'d like',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...availableSides.map(
                    (side) => CheckboxListTile(
                      activeColor: AppTheme.primaryColor,
                      title: Text(side.name),
                      subtitle: Text('+ \$${side.price.toStringAsFixed(2)}'),
                      value: selected[side.id],
                      onChanged: (v) =>
                          setSheetState(() => selected[side.id] = v!),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(ctx, chosenSides),
                      child: Text(
                        sidesTotal > 0
                            ? 'Add to Cart (+\$${sidesTotal.toStringAsFixed(2)})'
                            : 'Add to Cart',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showMenuItemDetail(BuildContext context, MenuItem item) async {
    final result = await showMenuItemDetailSheet(context, item);
    if (result == null) return; // cancelled
    if (!context.mounted) return;

    final cartNotifier = ref.read(cartProvider.notifier);

    if (cartNotifier.isDifferentRestaurant(item)) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace cart?'),
          content: const Text(
            'Your cart has items from another restaurant. '
            'Clear it and add this item instead?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (replace != true) return;
      cartNotifier.replaceWithItem(
        item,
        sides: result.selectedSides,
        options: result.selectedOptions,
      );
    } else {
      // Add the item with the chosen quantity
      for (int i = 0; i < result.quantity; i++) {
        cartNotifier.addItem(
          item,
          sides: result.selectedSides,
          options: result.selectedOptions,
        );
      }
    }

    if (!context.mounted) return;
    AppSnackbar.success(
      context,
      '${result.quantity}x ${item.name} added to cart',
    );
  }
}
