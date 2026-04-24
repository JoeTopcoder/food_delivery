import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/restaurant_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/search_provider.dart';
import 'restaurant_detail_screen.dart';
import '../../utils/friendly_error.dart';
import 'package:food_driver/config/app_constants.dart';

class SmartSearchScreen extends ConsumerStatefulWidget {
  const SmartSearchScreen({super.key});

  @override
  ConsumerState<SmartSearchScreen> createState() => _SmartSearchScreenState();
}

class _SmartSearchScreenState extends ConsumerState<SmartSearchScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selectedCuisines = {};
  final Set<String> _selectedDietary = {};
  double _minRating = 0;
  RangeValues _priceRange = const RangeValues(0, 500);
  late TabController _tabCtrl;
  Timer? _debounce;

  static const _cuisineFilters = [
    'Caribbean',
    'Indian',
    'Chinese',
    'Italian',
    'American',
    'Japanese',
    'Mexican',
    'Thai',
  ];

  static const _dietaryFilters = [
    'Vegetarian',
    'Vegan',
    'Gluten Free',
    'Halal',
    'Kosher',
    'Dairy Free',
    'Nut Free',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value.trim().toLowerCase());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(searchQueryProvider.notifier).update(_query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final restaurantsAsync = ref.watch(allRestaurantsProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Search & Discover',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(text: 'Restaurants'),
            Tab(text: 'Menu Items'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search restaurants, cuisines, dishes...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF9CA3AF),
                ),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // Tabs content
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                // ── Tab 1: Restaurants ──
                Column(
                  children: [
                    // Filter chips
                    Container(
                      color: Theme.of(context).cardColor,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 36,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _FilterChipButton(
                                  label: 'Filters',
                                  icon: Icons.tune_rounded,
                                  isSelected:
                                      _selectedDietary.isNotEmpty ||
                                      _minRating > 0 ||
                                      _priceRange.start > 0 ||
                                      _priceRange.end < 500,
                                  onTap: () => _showFilterSheet(context),
                                ),
                                const SizedBox(width: 8),
                                ..._cuisineFilters.map(
                                  (c) => Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: FilterChip(
                                      label: Text(
                                        c,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      selected: _selectedCuisines.contains(c),
                                      onSelected: (sel) {
                                        setState(() {
                                          if (sel) {
                                            _selectedCuisines.add(c);
                                          } else {
                                            _selectedCuisines.remove(c);
                                          }
                                        });
                                      },
                                      selectedColor: AppTheme.primaryColor
                                          .withValues(alpha: 0.15),
                                      checkmarkColor: AppTheme.primaryColor,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Restaurant results
                    Expanded(
                      child: restaurantsAsync.when(
                        data: (restaurants) {
                          final filtered = _applyFilters(restaurants);
                          if (filtered.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    size: 64,
                                    color: Colors.grey[300],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No restaurants found',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[500],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Try adjusting your filters',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final r = filtered[index];
                              return _RestaurantSearchCard(
                                restaurant: r,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RestaurantDetailScreen(restaurant: r),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (err, _) =>
                            Center(child: Text(friendlyError(err))),
                      ),
                    ),
                  ],
                ),

                // ── Tab 2: Menu Items (full-text search) ──
                _MenuItemsSearchTab(query: _query),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Restaurant> _applyFilters(List<Restaurant> restaurants) {
    return restaurants.where((r) {
      // Exclude grocery-only stores
      if (r.storeType == 'grocery') return false;

      // Text search
      if (_query.isNotEmpty) {
        final matchesName = r.name.toLowerCase().contains(_query);
        final matchesCuisine = (r.cuisineType ?? '').toLowerCase().contains(
          _query,
        );
        final matchesDescription = (r.description ?? '').toLowerCase().contains(
          _query,
        );
        if (!matchesName && !matchesCuisine && !matchesDescription) {
          return false;
        }
      }

      // Cuisine filter
      if (_selectedCuisines.isNotEmpty) {
        final cuisine = (r.cuisineType ?? '').toLowerCase();
        final match = _selectedCuisines.any(
          (c) => cuisine.contains(c.toLowerCase()),
        );
        if (!match) return false;
      }

      // Rating filter
      if (_minRating > 0 && (r.rating ?? 0) < _minRating) {
        return false;
      }

      // Price filter (delivery fee as proxy)
      final fee = r.deliveryFee ?? 0;
      if (fee < _priceRange.start || fee > _priceRange.end) {
        return false;
      }

      // Dietary filter
      if (_selectedDietary.isNotEmpty) {
        final desc = (r.description ?? '').toLowerCase();
        final cuisine = (r.cuisineType ?? '').toLowerCase();
        final name = r.name.toLowerCase();
        final combined = '$desc $cuisine $name';
        final match = _selectedDietary.any(
          (d) => combined.contains(d.toLowerCase()),
        );
        if (!match) return false;
      }

      return true;
    }).toList();
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Filters',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            _selectedDietary.clear();
                            _minRating = 0;
                            _priceRange = const RangeValues(0, 500);
                          });
                          setState(() {});
                        },
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Dietary section
                  const Text(
                    'Dietary Preferences',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _dietaryFilters
                        .map(
                          (d) => FilterChip(
                            label: Text(
                              d,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: _selectedDietary.contains(d),
                            onSelected: (sel) {
                              setSheetState(() {
                                if (sel) {
                                  _selectedDietary.add(d);
                                } else {
                                  _selectedDietary.remove(d);
                                }
                              });
                            },
                            selectedColor: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.15),
                            checkmarkColor: const Color(0xFF10B981),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 20),

                  // Rating filter
                  Text(
                    'Minimum Rating: ${_minRating.toStringAsFixed(1)}',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Slider(
                    value: _minRating,
                    min: 0,
                    max: 5,
                    divisions: 10,
                    activeColor: AppTheme.primaryColor,
                    label: _minRating.toStringAsFixed(1),
                    onChanged: (v) => setSheetState(() {
                      _minRating = v;
                    }),
                  ),
                  const SizedBox(height: 16),

                  // Price range
                  Text(
                    'Delivery Fee: \$${_priceRange.start.toInt()} - \$${_priceRange.end.toInt()}',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  RangeSlider(
                    values: _priceRange,
                    min: 0,
                    max: 500,
                    divisions: 10,
                    activeColor: AppTheme.primaryColor,
                    labels: RangeLabels(
                      '${AppConstants.currencySymbol}${_priceRange.start.toInt()}',
                      '${AppConstants.currencySymbol}${_priceRange.end.toInt()}',
                    ),
                    onChanged: (v) => setSheetState(() {
                      _priceRange = v;
                    }),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {});
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Apply Filters',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
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

class _FilterChipButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : const Color(0xFFD1D5DB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? AppTheme.primaryColor
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? AppTheme.primaryColor
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RestaurantSearchCard extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onTap;

  const _RestaurantSearchCard({required this.restaurant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
              child: SizedBox(
                width: 110,
                height: 100,
                child:
                    restaurant.imageUrl != null &&
                        restaurant.imageUrl!.isNotEmpty
                    ? Image.network(
                        restaurant.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.restaurant_rounded,
                            size: 32,
                            color: AppTheme.primaryColor.withValues(alpha: 0.4),
                          ),
                        ),
                      )
                    : Container(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        child: Icon(
                          Icons.restaurant_rounded,
                          size: 32,
                          color: AppTheme.primaryColor.withValues(alpha: 0.4),
                        ),
                      ),
              ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      restaurant.cuisineType ?? 'Restaurant',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${restaurant.rating ?? 0}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: Color(0xFF9CA3AF),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${restaurant.estimatedDeliveryTime ?? 30} min',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${AppConstants.currencySymbol}${restaurant.deliveryFee ?? 0}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFD1D5DB),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  Menu Items Search Tab (uses full-text search RPC)
// ─────────────────────────────────────────────────────────
class _MenuItemsSearchTab extends ConsumerWidget {
  final String query;
  const _MenuItemsSearchTab({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(menuSearchResultsProvider);
    final recommendationsAsync = ref.watch(recommendationsProvider);

    if (query.isEmpty) {
      // Show recommendations when not searching
      return recommendationsAsync.when(
        data: (recs) {
          if (recs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_rounded, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Search for dishes',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Type a dish name to search across all menus',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Recommended for You',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Based on your order history',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
              const SizedBox(height: 12),
              ...recs.map(
                (r) => _MenuItemCard(
                  name: r.itemName,
                  price: r.itemPrice,
                  imageUrl: r.itemImageUrl,
                  restaurantName: r.restaurantName,
                  restaurantId: r.restaurantId,
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Could not load recommendations')),
      );
    }

    return resultsAsync.when(
      data: (results) {
        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 64,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'No menu items found',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Try a different search term',
                  style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final r = results[index];
            return _MenuItemCard(
              name: r.itemName,
              price: r.discountedPrice,
              originalPrice: r.itemDiscount != null && r.itemDiscount! > 0
                  ? r.itemPrice
                  : null,
              imageUrl: r.itemImageUrl,
              restaurantName: r.restaurantName,
              restaurantId: r.restaurantId,
              restaurantImage: r.restaurantImage,
              rating: r.restaurantRating,
              category: r.itemCategory,
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text(friendlyError(err))),
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final String name;
  final double price;
  final double? originalPrice;
  final String? imageUrl;
  final String restaurantName;
  final String restaurantId;
  final String? restaurantImage;
  final double? rating;
  final String? category;

  const _MenuItemCard({
    required this.name,
    required this.price,
    this.originalPrice,
    this.imageUrl,
    required this.restaurantName,
    required this.restaurantId,
    this.restaurantImage,
    this.rating,
    this.category,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              bottomLeft: Radius.circular(14),
            ),
            child: SizedBox(
              width: 100,
              height: 90,
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    restaurantName,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (category != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      category!,
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${AppConstants.currencySymbol}${price.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      if (originalPrice != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${AppConstants.currencySymbol}${originalPrice!.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                      if (rating != null) ...[
                        const Spacer(),
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

  Widget _placeholder() {
    return Container(
      color: AppTheme.primaryColor.withValues(alpha: 0.1),
      child: Icon(
        Icons.fastfood_rounded,
        size: 28,
        color: AppTheme.primaryColor.withValues(alpha: 0.4),
      ),
    );
  }
}
