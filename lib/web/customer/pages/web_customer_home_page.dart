import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_constants.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/search_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';
import '../../../models/restaurant_model.dart';

class WebCustomerHomePage extends ConsumerStatefulWidget {
  final void Function(Restaurant) onRestaurantTapped;
  const WebCustomerHomePage({super.key, required this.onRestaurantTapped});

  @override
  ConsumerState<WebCustomerHomePage> createState() => _WebCustomerHomePageState();
}

class _WebCustomerHomePageState extends ConsumerState<WebCustomerHomePage> {
  final _searchCtrl = TextEditingController();
  String _selectedCategory = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _categories = [
    (emoji: '🍳', label: 'Breakfast'),
    (emoji: '🍔', label: 'Fast Food'),
    (emoji: '🍕', label: 'Pizza'),
    (emoji: '🍗', label: 'Chicken'),
    (emoji: '🌮', label: 'Mexican'),
    (emoji: '🍜', label: 'Chinese'),
    (emoji: '🍱', label: 'Sushi'),
    (emoji: '🥗', label: 'Healthy'),
    (emoji: '🍰', label: 'Dessert'),
    (emoji: '☕', label: 'Coffee'),
    (emoji: '🥤', label: 'Drinks'),
    (emoji: '🥦', label: 'Vegan'),
  ];

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final allAsync = ref.watch(allRestaurantsProvider);
    final topAsync = ref.watch(topRatedRestaurantsProvider);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + Search
          Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Find Food', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                Text('Order from hundreds of restaurants nearby', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
              onPressed: () {
                ref.invalidate(allRestaurantsProvider);
                ref.invalidate(topRatedRestaurantsProvider);
              },
            ),
          ]),
          const SizedBox(height: 16),

          // Search bar
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => ref.read(searchQueryProvider.notifier).update(v),
            decoration: InputDecoration(
              hintText: 'Search restaurants or dishes...',
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8)),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8)),
                      onPressed: () {
                        _searchCtrl.clear();
                        ref.read(searchQueryProvider.notifier).update('');
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 16),

          // Categories
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final selected = _selectedCategory == cat.label;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = selected ? '' : cat.label),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFFF6B35) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: selected ? const Color(0xFFFF6B35) : const Color(0xFFE2E8F0)),
                    ),
                    child: Row(children: [
                      Text(cat.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(cat.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : const Color(0xFF475569))),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Restaurant grid
          Expanded(
            child: query.isNotEmpty
                ? _SearchResults(query: query, category: _selectedCategory, onTap: widget.onRestaurantTapped)
                : _selectedCategory.isNotEmpty
                    ? _CategoryResults(category: _selectedCategory, allAsync: allAsync, onTap: widget.onRestaurantTapped)
                    : _HomeContent(allAsync: allAsync, topAsync: topAsync, onTap: widget.onRestaurantTapped),
          ),
        ],
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  final String query;
  final String category;
  final void Function(Restaurant) onTap;
  const _SearchResults({required this.query, required this.category, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(restaurantSearchProvider(query));
    return async.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(restaurantSearchProvider(query))),
      data: (list) {
        final filtered = category.isEmpty ? list : list.where((r) => (r.cuisineType ?? '').toLowerCase().contains(category.toLowerCase())).toList();
        if (filtered.isEmpty) return const Center(child: Text('No restaurants found', style: TextStyle(color: Color(0xFF94A3B8))));
        return _RestaurantGrid(restaurants: filtered, onTap: onTap);
      },
    );
  }
}

class _CategoryResults extends StatelessWidget {
  final String category;
  final AsyncValue<List<Restaurant>> allAsync;
  final void Function(Restaurant) onTap;
  const _CategoryResults({required this.category, required this.allAsync, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return allAsync.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e)),
      data: (list) {
        final filtered = list.where((r) => (r.cuisineType ?? '').toLowerCase().contains(category.toLowerCase())).toList();
        if (filtered.isEmpty) return Center(child: Text('No "$category" restaurants found', style: const TextStyle(color: Color(0xFF94A3B8))));
        return _RestaurantGrid(restaurants: filtered, onTap: onTap);
      },
    );
  }
}

class _HomeContent extends StatelessWidget {
  final AsyncValue<List<Restaurant>> allAsync;
  final AsyncValue<List<Restaurant>> topAsync;
  final void Function(Restaurant) onTap;
  const _HomeContent({required this.allAsync, required this.topAsync, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('⭐ Top Rated', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 160,
            child: topAsync.when(
              loading: () => const AppLoadingIndicator(),
              error: (e, _) => AppErrorState(message: friendlyError(e)),
              data: (list) => ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _RestaurantCard(restaurant: list[i], compact: true, onTap: onTap),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('🍽️ All Restaurants', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          ),
        ),
        allAsync.when(
          loading: () => const SliverToBoxAdapter(child: AppLoadingIndicator()),
          error: (e, _) => SliverToBoxAdapter(child: AppErrorState(message: friendlyError(e))),
          data: (list) => SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.4,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => _RestaurantCard(restaurant: list[i], onTap: onTap),
              childCount: list.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _RestaurantGrid extends StatelessWidget {
  final List<Restaurant> restaurants;
  final void Function(Restaurant) onTap;
  const _RestaurantGrid({required this.restaurants, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.4,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: restaurants.length,
      itemBuilder: (_, i) => _RestaurantCard(restaurant: restaurants[i], onTap: onTap),
    );
  }
}

class _RestaurantCard extends StatefulWidget {
  final Restaurant restaurant;
  final bool compact;
  final void Function(Restaurant) onTap;
  const _RestaurantCard({required this.restaurant, required this.onTap, this.compact = false});

  @override
  State<_RestaurantCard> createState() => _RestaurantCardState();
}

class _RestaurantCardState extends State<_RestaurantCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.restaurant;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => widget.onTap(r),
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: widget.compact ? 200 : null,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hover ? 0.12 : 0.05),
              blurRadius: _hover ? 16 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner
            Container(
              height: widget.compact ? 90 : 100,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3ED),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                image: r.imageUrl != null
                    ? DecorationImage(image: NetworkImage(r.imageUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: r.imageUrl == null
                  ? const Center(child: Icon(Icons.storefront_rounded, size: 40, color: Color(0xFFFF6B35)))
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis, maxLines: 1),
                const SizedBox(height: 2),
                Row(children: [
                  Text(r.cuisineType ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                  const Spacer(),
                  const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 2),
                  Text(r.rating?.toStringAsFixed(1) ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                ]),
                if (!widget.compact) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 3),
                    Text('${r.estimatedDeliveryTime ?? 30} min', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    const SizedBox(width: 10),
                    const Icon(Icons.delivery_dining_rounded, size: 12, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 3),
                    Text('${AppConstants.currencySymbol}${r.deliveryFee?.toStringAsFixed(2) ?? "0.00"}', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: r.isOpen ? const Color(0xFF10B981).withValues(alpha: 0.1) : const Color(0xFFEF4444).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(r.isOpen ? 'Open' : 'Closed', style: TextStyle(fontSize: 10, color: r.isOpen ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ],
              ]),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
