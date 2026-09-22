import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_constants.dart';
import '../providers/hotbite_picks_provider.dart';
import '../providers/user_provider.dart';
import '../providers/feature_providers.dart';
import '../core/utils/responsive.dart';
import '../utils/rating_format.dart';
import '../screens/customer/restaurants_by_category_screen.dart';
import 'app_cached_image.dart';

/// 🔥 HotBite Picks — the discovery hub. Composes several real-data rails
/// (admin-curated Featured, Most Ordered, Top Rated, Hot Deals) plus popular
/// categories. Each rail self-hides when it has no data; when nothing at all
/// qualifies it shows a "coming soon" state instead of fake rankings.
class HotBitePicksSection extends ConsumerWidget {
  const HotBitePicksSection({super.key});

  static const _flame = Color(0xFFFF5A1F);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final curated = ref.watch(curatedPicksProvider).valueOrNull ?? const [];
    final mostOrdered = ref.watch(mostOrderedProvider).valueOrNull ?? const [];
    final topRated = ref.watch(topRatedPicksProvider).valueOrNull ?? const [];
    final deals = ref.watch(hotDealsProvider).valueOrNull ?? const [];
    final categories =
        ref.watch(foodCategoriesProvider).valueOrNull ?? const [];

    final hasAny = curated.isNotEmpty ||
        mostOrdered.isNotEmpty ||
        topRated.isNotEmpty ||
        deals.isNotEmpty;

    final hPad = Responsive.horizontalPadding(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 2),
          child: Row(
            children: [
              const Text('🔥', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text(
                'HotBite Picks',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
          child: Text(
            'Good food. Great finds. Picked for you.',
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.55),
            ),
          ),
        ),

        if (!hasAny)
          _ComingSoon(hPad: hPad)
        else ...[
          if (curated.isNotEmpty)
            _RestaurantRail(
                label: '⭐ Featured on HotBite', items: curated, hPad: hPad),
          if (mostOrdered.isNotEmpty)
            _RestaurantRail(
                label: '🔥 Most Ordered',
                items: mostOrdered,
                hPad: hPad,
                showOrders: true),
          if (topRated.isNotEmpty)
            _RestaurantRail(
                label: '⭐ Top Rated', items: topRated, hPad: hPad),
          if (deals.isNotEmpty) _DealRail(deals: deals, hPad: hPad),
        ],

        // Popular categories always reuse the existing category browse.
        if (categories.isNotEmpty)
          _CategoryRail(categories: categories, hPad: hPad),
      ],
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.hPad});
  final double hPad;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          color: HotBitePicksSection._flame.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: HotBitePicksSection._flame.withValues(alpha: 0.2)),
        ),
        child: const Text(
          '🔥 HotBite Picks are coming soon.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

Future<void> _openRestaurant(
    BuildContext context, WidgetRef ref, String id) async {
  final store = await ref.read(restaurantServiceProvider).getRestaurantById(id);
  if (store != null && context.mounted) {
    Navigator.pushNamed(context, '/restaurant-detail', arguments: store);
  }
}

class _RestaurantRail extends ConsumerWidget {
  const _RestaurantRail({
    required this.label,
    required this.items,
    required this.hPad,
    this.showOrders = false,
  });

  final String label;
  final List<PickRestaurant> items;
  final double hPad;
  final bool showOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 8),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800)),
        ),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.symmetric(horizontal: hPad),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final r = items[i];
              return GestureDetector(
                onTap: () => _openRestaurant(context, ref, r.id),
                child: SizedBox(
                  width: 178,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AppCachedImage(
                            url: r.imageUrl,
                            width: 178,
                            height: 104,
                            decodeWidth: 178),
                      ),
                      const SizedBox(height: 8),
                      Text(r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 14, color: Color(0xFFFFB300)),
                          const SizedBox(width: 2),
                          Text(formatRating(r.rating),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700)),
                          if (showOrders && (r.orderCount ?? 0) > 0) ...[
                            Text('  •  ',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.4))),
                            Text('${r.orderCount} orders',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6))),
                          ] else if ((r.cuisineType ?? '').isNotEmpty) ...[
                            Text('  •  ',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.4))),
                            Flexible(
                              child: Text(r.cuisineType!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6))),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DealRail extends ConsumerWidget {
  const _DealRail({required this.deals, required this.hPad});
  final List<PickDeal> deals;
  final double hPad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sym = AppConstants.currencySymbol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 8),
          child: const Text('💰 Hot Deals',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
        ),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.symmetric(horizontal: hPad),
            itemCount: deals.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final d = deals[i];
              return GestureDetector(
                onTap: () => _openRestaurant(context, ref, d.restaurantId),
                child: SizedBox(
                  width: 168,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AppCachedImage(
                              url: d.imageUrl,
                              width: 168,
                              height: 100,
                              decodeWidth: 168),
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text('-${d.discount.toStringAsFixed(0)}%',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Text('$sym${d.salePrice.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFDC2626))),
                        const SizedBox(width: 6),
                        Text('$sym${d.price.toStringAsFixed(0)}',
                            style: TextStyle(
                                fontSize: 12,
                                decoration: TextDecoration.lineThrough,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5))),
                      ]),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.categories, required this.hPad});
  final List<Map<String, String>> categories;
  final double hPad;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 8),
          child: const Text('🍽 Popular Categories',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.symmetric(horizontal: hPad),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = categories[i];
              return ActionChip(
                label: Text('${c['emoji'] ?? ''} ${c['name'] ?? ''}'.trim()),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RestaurantsByCategoryScreen(
                      categoryName: c['name'] ?? '',
                      categoryEmoji: c['emoji'],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
