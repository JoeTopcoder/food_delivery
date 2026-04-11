import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/restaurant_model.dart';
import '../../providers/user_provider.dart';
import 'restaurant_detail_screen.dart';
import '../../utils/friendly_error.dart';

class SmartSearchScreen extends ConsumerStatefulWidget {
  const SmartSearchScreen({super.key});

  @override
  ConsumerState<SmartSearchScreen> createState() => _SmartSearchScreenState();
}

class _SmartSearchScreenState extends ConsumerState<SmartSearchScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selectedCuisines = {};
  final Set<String> _selectedDietary = {};
  double _minRating = 0;
  RangeValues _priceRange = const RangeValues(0, 500);

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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final restaurantsAsync = ref.watch(allRestaurantsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Search & Discover',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
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
                          setState(() => _query = '');
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

          // Filter chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cuisine filters
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
                            selectedColor: AppTheme.primaryColor.withValues(
                              alpha: 0.15,
                            ),
                            checkmarkColor: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
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

          // Results
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
                          builder: (_) => RestaurantDetailScreen(restaurant: r),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text(friendlyError(err))),
            ),
          ),
        ],
      ),
    );
  }

  List<Restaurant> _applyFilters(List<Restaurant> restaurants) {
    return restaurants.where((r) {
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
                    'Delivery Fee: JMD\$${_priceRange.start.toInt()} - JMD\$${_priceRange.end.toInt()}',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  RangeSlider(
                    values: _priceRange,
                    min: 0,
                    max: 500,
                    divisions: 10,
                    activeColor: AppTheme.primaryColor,
                    labels: RangeLabels(
                      'JMD\$${_priceRange.start.toInt()}',
                      'JMD\$${_priceRange.end.toInt()}',
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
                  : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? AppTheme.primaryColor
                    : const Color(0xFF6B7280),
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
          color: Colors.white,
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
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'JMD\$${restaurant.deliveryFee ?? 0}',
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
