import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/supabase_config.dart';
import '../../models/restaurant_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/banner_provider.dart';
import '../../models/banner_model.dart' as app;
import '../../utils/app_theme.dart';
import '../../widgets/restaurant_card.dart';
import '../../widgets/search_bar.dart' as search_bar;
import '../../utils/friendly_error.dart';

// Emoji categories for the Browse by Category grid
const _emojiCategories = <Map<String, String>>[
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
  {'emoji': '\u{1F964}', 'name': 'Drinks'},
  {'emoji': '\u{1F331}', 'name': 'Vegan'},
];

class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final defaultAddrAsync = currentUser != null
        ? ref.watch(defaultAddressProvider(currentUser.id))
        : null;
    final userAddress =
        defaultAddrAsync?.valueOrNull?.address ??
        currentUser?.address ??
        'Tap to set delivery address';

    final isSearching = _searchQuery.isNotEmpty;
    final searchAsync = isSearching
        ? ref.watch(restaurantSearchProvider(_searchQuery))
        : null;

    final newlyAddedAsync = ref.watch(newlyAddedRestaurantsProvider);
    final topRatedAsync = ref.watch(topRatedRestaurantsProvider);
    final breakfastAsync = ref.watch(breakfastRestaurantsProvider);
    final mustTryAsync = ref.watch(mustTryRestaurantsProvider);
    final allRestaurantsAsync = ref.watch(allRestaurantsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.restaurant_menu,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'FoodDriver',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            actions: [
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.shopping_cart_outlined,
                      color: AppTheme.textPrimary,
                    ),
                    onPressed: () => Navigator.pushNamed(context, '/cart'),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Consumer(
                      builder: (context, ref, _) {
                        final cartItems = ref.watch(cartProvider);
                        if (cartItems.isEmpty) return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppTheme.accentColor,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '${cartItems.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(
                  Icons.notifications_none_rounded,
                  color: AppTheme.textPrimary,
                ),
                onPressed: () => Navigator.pushNamed(context, '/notifications'),
              ),
              const SizedBox(width: 4),
            ],
          ),

          // Location picker
          SliverToBoxAdapter(
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/address-book'),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Deliver to',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            userAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 14)),

          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: search_bar.CustomSearchBar(
                hintText: 'Search for restaurant or food',
                onChanged: (q) => setState(() => _searchQuery = q),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 18)),

          if (isSearching && searchAsync != null)
            ..._buildSearchResults(searchAsync),

          if (!isSearching) ...[
            // Dynamic Promotional Banners
            SliverToBoxAdapter(child: _DynamicBannerCarousel()),

            const SliverToBoxAdapter(child: SizedBox(height: 18)),

            // Browse by Category
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: const Text(
                  'Browse by Category',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _emojiCategories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final cat = _emojiCategories[index];
                    return GestureDetector(
                      onTap: () => Navigator.pushNamed(
                        context,
                        '/all-restaurants',
                        arguments: cat['name'],
                      ),
                      child: SizedBox(
                        width: 68,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.grey.shade200,
                                  width: 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                cat['emoji']!,
                                style: const TextStyle(fontSize: 26),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              cat['name']!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 10)),

            _buildHorizontalSection(
              title: 'You might love these \u{2764}\u{FE0F}',
              asyncValue: topRatedAsync,
            ),

            _buildHorizontalSection(
              title: 'Newly Added \u{1F195}',
              asyncValue: newlyAddedAsync,
            ),

            _buildHorizontalSection(
              title: 'Breakfast \u{1F373}',
              asyncValue: breakfastAsync,
            ),

            _buildHorizontalSection(
              title: 'Must Try \u{1F525}',
              asyncValue: mustTryAsync,
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: const Text(
                  'All Restaurants',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),

            allRestaurantsAsync.when(
              data: (restaurants) {
                final display = restaurants.take(15).toList();
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final r = display[index];
                      return RestaurantCard(
                        restaurant: r,
                        onTap: () => Navigator.pushNamed(
                          context,
                          '/restaurant-detail',
                          arguments: r,
                        ),
                      );
                    }, childCount: display.length),
                  ),
                );
              },
              loading: () => SliverToBoxAdapter(child: _loadingIndicator()),
              error: (err, _) => SliverToBoxAdapter(
                child: _emptyPlaceholder(friendlyError(err)),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/all-restaurants'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'See All Restaurants',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _buildSearchResults(AsyncValue<List<Restaurant>> asyncValue) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: const Text(
            'Search Results',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      asyncValue.when(
        data: (restaurants) {
          if (restaurants.isEmpty) {
            return SliverToBoxAdapter(
              child: _emptyPlaceholder('No restaurants found'),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final r = restaurants[index];
                return RestaurantCard(
                  restaurant: r,
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/restaurant-detail',
                    arguments: r,
                  ),
                );
              }, childCount: restaurants.length),
            ),
          );
        },
        loading: () => SliverToBoxAdapter(child: _loadingIndicator()),
        error: (err, _) =>
            SliverToBoxAdapter(child: _emptyPlaceholder(friendlyError(err))),
      ),
    ];
  }

  Widget _buildHorizontalSection({
    required String title,
    required AsyncValue<List<Restaurant>> asyncValue,
  }) {
    return SliverToBoxAdapter(
      child: asyncValue.when(
        data: (restaurants) {
          if (restaurants.isEmpty) return const SizedBox.shrink();
          return _HorizontalRestaurantRow(
            title: title,
            restaurants: restaurants,
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _loadingIndicator() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: CircularProgressIndicator(color: AppTheme.primaryColor),
    ),
  );

  Widget _emptyPlaceholder(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.restaurant_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(text, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    ),
  );
}

class _HorizontalRestaurantRow extends StatelessWidget {
  final String title;
  final List<Restaurant> restaurants;

  const _HorizontalRestaurantRow({
    required this.title,
    required this.restaurants,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: restaurants.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final r = restaurants[index];
              return _CompactRestaurantCard(
                restaurant: r,
                onTap: () => Navigator.pushNamed(
                  context,
                  '/restaurant-detail',
                  arguments: r,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CompactRestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onTap;

  const _CompactRestaurantCard({required this.restaurant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child:
                  restaurant.imageUrl != null && restaurant.imageUrl!.isNotEmpty
                  ? Image.network(
                      restaurant.imageUrl!,
                      height: 110,
                      width: 180,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        height: 110,
                        width: 180,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.primaryColor.withValues(alpha: 0.15),
                              AppTheme.primaryColor.withValues(alpha: 0.05),
                            ],
                          ),
                        ),
                        child: Icon(
                          Icons.restaurant_rounded,
                          size: 36,
                          color: AppTheme.primaryColor.withValues(alpha: 0.4),
                        ),
                      ),
                    )
                  : Container(
                      height: 110,
                      width: 180,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primaryColor.withValues(alpha: 0.15),
                            AppTheme.primaryColor.withValues(alpha: 0.05),
                          ],
                        ),
                      ),
                      child: Icon(
                        Icons.restaurant_rounded,
                        size: 36,
                        color: AppTheme.primaryColor.withValues(alpha: 0.4),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    restaurant.cuisineType ?? 'Multi-cuisine',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
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
                              size: 14,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${restaurant.rating ?? '-'}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${restaurant.estimatedDeliveryTime ?? 30} min',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dynamic Banner Carousel ──────────────────────────────────────────────────

class _DynamicBannerCarousel extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DynamicBannerCarousel> createState() =>
      _DynamicBannerCarouselState();
}

class _DynamicBannerCarouselState
    extends ConsumerState<_DynamicBannerCarousel> {
  final PageController _pageCtrl = PageController(viewportFraction: 1.0);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bannersAsync = ref.watch(activeBannersProvider);

    return bannersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (banners) {
        if (banners.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            SizedBox(
              height: 140,
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: banners.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  final banner = banners[index];
                  return _bannerCard(context, banner);
                },
              ),
            ),
            if (banners.length > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  banners.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _currentPage == i ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _currentPage == i
                          ? AppTheme.primaryColor
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _bannerCard(BuildContext context, app.Banner banner) {
    return GestureDetector(
      onTap: () async {
        try {
          final data = await SupabaseConfig.client
              .from('restaurants')
              .select()
              .eq('id', banner.restaurantId)
              .single();
          final restaurant = Restaurant.fromJson(data);
          if (context.mounted) {
            Navigator.pushNamed(
              context,
              '/restaurant-detail',
              arguments: restaurant,
            );
          }
        } catch (_) {
          // Silently fail if restaurant not found
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryColor,
              AppTheme.primaryColor.withValues(alpha: 0.75),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (banner.imageUrl != null && banner.imageUrl!.isNotEmpty)
              Image.network(
                banner.imageUrl!,
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.35),
                colorBlendMode: BlendMode.darken,
                errorBuilder: (_, _, _) => Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor,
                          AppTheme.primaryColor.withValues(alpha: 0.75),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 0, bottom: 0),
                        child: Icon(
                          Icons.local_offer_rounded,
                          size: 120,
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (banner.imageUrl == null || banner.imageUrl!.isEmpty)
              Positioned(
                right: -10,
                bottom: -10,
                child: Icon(
                  Icons.local_offer_rounded,
                  size: 120,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    banner.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (banner.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      banner.subtitle!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Visit ${banner.restaurantName ?? 'Restaurant'}',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
