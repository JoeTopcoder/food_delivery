import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/restaurant_card.dart';
import '../../widgets/search_bar.dart' as search_bar;
import '../../utils/friendly_error.dart';
import '../../utils/context_extensions.dart';

const _filterCategories = [
  {'emoji': '\u{1F4AB}', 'name': 'All'},
  {'emoji': '\u{1F373}', 'name': 'Breakfast'},
  {'emoji': '\u{1F354}', 'name': 'Fast Food'},
  {'emoji': '\u{1F355}', 'name': 'Pizza'},
  {'emoji': '\u{1F357}', 'name': 'Chicken'},
  {'emoji': '\u{1F32E}', 'name': 'Mexican'},
  {'emoji': '\u{1F35C}', 'name': 'Chinese'},
  {'emoji': '\u{1F363}', 'name': 'Sushi'},
  {'emoji': '\u{1F957}', 'name': 'Healthy'},
  {'emoji': '\u{1F370}', 'name': 'Dessert'},
  {'emoji': '\u{2615}', 'name': 'Coffee'},
];

class AllRestaurantsScreen extends ConsumerStatefulWidget {
  const AllRestaurantsScreen({super.key});

  @override
  ConsumerState<AllRestaurantsScreen> createState() =>
      _AllRestaurantsScreenState();
}

class _AllRestaurantsScreenState extends ConsumerState<AllRestaurantsScreen> {
  String _searchQuery = '';
  String _selectedCategory = 'All';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args.isNotEmpty && _selectedCategory == 'All') {
      _selectedCategory = args;
      _searchQuery = args;
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurantsAsync = _searchQuery.isEmpty
        ? ref.watch(allRestaurantsProvider)
        : ref.watch(restaurantSearchProvider(_searchQuery));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.restaurants,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: search_bar.CustomSearchBar(
              hintText: 'Search for restaurant or food',
              onChanged: (value) => setState(() {
                _searchQuery = value;
                if (value.isEmpty) _selectedCategory = 'All';
              }),
            ),
          ),
          // Category filter chips
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filterCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _filterCategories[index];
                final isSelected = _selectedCategory == cat['name'];
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedCategory = cat['name']!;
                    _searchQuery = cat['name'] == 'All' ? '' : cat['name']!;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cat['emoji']!,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          cat['name']!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // Restaurant list
          Expanded(
            child: restaurantsAsync.when(
              data: (restaurants) {
                if (restaurants.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.restaurant_outlined,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No restaurants found',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollCacheExtent: const ScrollCacheExtent.pixels(800),
                  itemCount: restaurants.length,
                  itemBuilder: (context, index) {
                    final r = restaurants[index];
                    return RepaintBoundary(
                      child: RestaurantCard(
                        restaurant: r,
                        onTap: () => Navigator.pushNamed(
                          context,
                          '/restaurant-detail',
                          arguments: r,
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor),
              ),
              error: (err, _) => Center(child: Text(friendlyError(err))),
            ),
          ),
        ],
      ),
    );
  }
}
