import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/menu_model.dart';
import '../../models/restaurant_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/premium_providers.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/menu_item_card.dart';

class RestaurantDetailScreen extends ConsumerStatefulWidget {
  final Restaurant restaurant;

  const RestaurantDetailScreen({super.key, required this.restaurant});

  @override
  ConsumerState<RestaurantDetailScreen> createState() =>
      _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState
    extends ConsumerState<RestaurantDetailScreen> {
  late ScrollController _scrollController;
  bool _showAppBar = false;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
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
      backgroundColor: Colors.white,
      appBar: _showAppBar
          ? AppBar(
              elevation: 0,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                widget.restaurant.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    isFav ? Icons.favorite : Icons.favorite_outline,
                    color: isFav ? AppTheme.accentColor : AppTheme.textPrimary,
                  ),
                  onPressed: toggleFav,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.share_outlined,
                    color: AppTheme.textPrimary,
                  ),
                  onPressed: () => Share.share(
                    'Check out ${widget.restaurant.name} on FoodDriver!',
                  ),
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
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
                          ? Image.network(
                              widget.restaurant.imageUrl!,
                              height: 260,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
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
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
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
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Status + rating row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: widget.restaurant.isOpen
                                  ? AppTheme.successColor.withValues(alpha: 0.1)
                                  : AppTheme.accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.restaurant.isOpen ? 'Open Now' : 'Closed',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: widget.restaurant.isOpen
                                    ? AppTheme.successColor
                                    : AppTheme.accentColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
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
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Spacer(),
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
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'Delivery: JMD\$${widget.restaurant.deliveryFee ?? 0}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (widget.restaurant.description != null &&
                          widget.restaurant.description!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          widget.restaurant.description!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
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
                                          : AppTheme.textPrimary,
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
                            onAddTap: () async {
                              final hasSides =
                                  item.sides != null && item.sides!.isNotEmpty;
                              List<MenuItemSide> selectedSides = [];

                              if (hasSides) {
                                final result = await _showSidesSheet(
                                  context,
                                  item,
                                );
                                if (result == null) return; // cancelled
                                selectedSides = result;
                              }

                              if (!context.mounted) return;
                              final cartNotifier = ref.read(
                                cartProvider.notifier,
                              );
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
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Replace'),
                                      ),
                                    ],
                                  ),
                                );
                                if (replace != true) return;
                                cartNotifier.replaceWithItem(
                                  item,
                                  sides: selectedSides,
                                );
                              } else {
                                cartNotifier.addItem(
                                  item,
                                  sides: selectedSides,
                                );
                              }
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${item.name} added to cart'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  error: (err, stack) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('Error loading menu: $err'),
                    ),
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
          // Footer with View Cart
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/cart'),
                    icon: const Icon(Icons.shopping_cart_rounded, size: 20),
                    label: const Text(
                      'View Cart',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
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
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  ...availableSides.map(
                    (side) => CheckboxListTile(
                      activeColor: AppTheme.primaryColor,
                      title: Text(side.name),
                      subtitle: Text('+ JMD\$${side.price.toStringAsFixed(2)}'),
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
                            ? 'Add to Cart (+JMD\$${sidesTotal.toStringAsFixed(2)})'
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
}
