import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/hotbite_now_provider.dart';
import '../providers/user_provider.dart';
import '../core/utils/responsive.dart';
import '../utils/rating_format.dart';
import 'app_cached_image.dart';

/// The premium "HotBite Now" home section — a horizontally scrolling rail of
/// fast-prep restaurants that have opted in and are currently eligible.
///
/// Renders nothing (zero height) while loading, on error, or when no
/// restaurant qualifies, so it never leaves an empty gap on the home screen.
/// HotBite's own branding — no third-party design is copied.
class HotBiteNowSection extends ConsumerWidget {
  const HotBiteNowSection({super.key});

  static const _accent = Color(0xFFFF5A1F); // HotBite flame orange

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hotBiteNowRestaurantsProvider);
    final restaurants = async.valueOrNull ?? const [];
    if (restaurants.isEmpty) return const SizedBox.shrink();

    final hPad = Responsive.horizontalPadding(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 8),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_accent, Color(0xFFFF8A3D)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 15, color: Colors.white),
                    SizedBox(width: 3),
                    Text(
                      'HotBite Now',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ready fast, delivered fast',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 214,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.symmetric(horizontal: hPad),
            itemCount: restaurants.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) =>
                _HotBiteCard(restaurant: restaurants[i]),
          ),
        ),
      ],
    );
  }
}

class _HotBiteCard extends ConsumerWidget {
  const _HotBiteCard({required this.restaurant});

  final HotBiteNowRestaurant restaurant;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final full = await ref
        .read(restaurantServiceProvider)
        .getRestaurantById(restaurant.id);
    if (full != null && context.mounted) {
      Navigator.pushNamed(context, '/restaurant-detail', arguments: full);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _open(context, ref),
      child: SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AppCachedImage(
                    url: restaurant.imageUrl,
                    width: 200,
                    height: 118,
                    decodeWidth: 200,
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: HotBiteNowSection._accent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt_rounded,
                            size: 12, color: Colors.white),
                        const SizedBox(width: 2),
                        Text(
                          '${restaurant.prepMinutes} min prep',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              restaurant.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if ((restaurant.cuisineType ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                restaurant.cuisineType!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.star_rounded,
                    size: 15, color: Color(0xFFFFB300)),
                const SizedBox(width: 2),
                Text(
                  formatRating(restaurant.rating),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  ' · ',
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                Icon(Icons.access_time_rounded,
                    size: 14,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    restaurant.estimatedDeliveryMinutes != null
                        ? '${restaurant.totalEtaMinutes} min'
                        : '~${restaurant.prepMinutes} min',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ),
                if (restaurant.distanceKm != null) ...[
                  Text(
                    ' · ',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  Text(
                    '${restaurant.distanceKm!.toStringAsFixed(1)} km',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
