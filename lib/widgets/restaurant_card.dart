import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/restaurant_model.dart';
import '../utils/app_theme.dart';
import 'app_cached_image.dart';
import '../core/utils/responsive.dart';
import '../providers/auth_provider.dart';
import '../providers/premium_providers.dart';
import '../utils/app_feedback_widgets.dart';

class RestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onTap;

  /// Optional "nearest to you" distance label (e.g. "2.3 km"). When set, a
  /// small location chip is shown on the card. Used by the grocery list, which
  /// orders stores nearest-first relative to the customer's address.
  final String? distanceLabel;

  const RestaurantCard({
    super.key,
    required this.restaurant,
    required this.onTap,
    this.distanceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isOpen = restaurant.isCurrentlyOpen;
    final cardPadding = Responsive.cardPadding(context);
    final spacing = Responsive.spacing(context);
    final imageHeight = Responsive.restaurantCardAspectRatio(context) > 0.65
        ? 200
        : 160;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: spacing),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Restaurant Image
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  child: restaurant.imageUrl != null &&
                      restaurant.imageUrl!.isNotEmpty
                      ? AppCachedImage(
                          url: restaurant.imageUrl,
                          height: imageHeight.toDouble(),
                          width: double.infinity,
                          // Card spans ~full width; decode at a sensible cap.
                          decodeWidth: 600,
                        )
                      : _PlaceholderImage(height: imageHeight.toDouble()),
                ),
                // Rating badge
                Positioned(
                  top: spacing * 0.75,
                  right: spacing * 0.75,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing * 0.5,
                      vertical: spacing * 0.25,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star_rounded,
                          color: Colors.amber,
                          size: Responsive.isSmallPhone(context) ? 14 : 16,
                        ),
                        SizedBox(width: spacing * 0.2),
                        Text(
                          '${restaurant.rating ?? '-'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: Responsive.smallText(context),
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Open/Closed badge — always shown
                Positioned(
                  top: spacing * 0.75,
                  left: spacing * 0.75,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing * 0.5,
                      vertical: spacing * 0.25,
                    ),
                    decoration: BoxDecoration(
                      color: isOpen
                          ? AppTheme.successColor
                          : AppTheme.accentColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isOpen ? 'Open Now' : 'Closed',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: Responsive.smallText(context) - 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                // Favorite (save) button
                Positioned(
                  bottom: spacing * 0.75,
                  right: spacing * 0.75,
                  child: _FavoriteHeart(restaurantId: restaurant.id),
                ),
              ],
            ),
            // Info section
            Padding(
              padding: EdgeInsets.all(cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: Responsive.headingSmall(context),
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: spacing * 0.5),
                      // View Menu button
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: spacing * 0.75,
                          vertical: spacing * 0.4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'View Menu',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: Responsive.smallText(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacing * 0.4),
                  // Cuisine tags
                  Text(
                    restaurant.cuisineType ?? 'Multi-cuisine',
                    style: TextStyle(
                      fontSize: Responsive.smallText(context),
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: spacing * 0.5),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: Responsive.isSmallPhone(context) ? 13 : 15,
                        color: Colors.grey[700],
                      ),
                      SizedBox(width: spacing * 0.2),
                      Flexible(
                        child: Text(
                          restaurant.formattedTodayHours ??
                              '${restaurant.estimatedDeliveryTime ?? 30} min',
                          style: TextStyle(
                            fontSize:
                                Responsive.smallText(context),
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (distanceLabel != null) ...[
                    SizedBox(height: spacing * 0.4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: Responsive.isSmallPhone(context) ? 13 : 15,
                          color: AppTheme.primaryColor,
                        ),
                        SizedBox(width: spacing * 0.2),
                        Text(
                          '$distanceLabel away',
                          style: TextStyle(
                            fontSize: Responsive.smallText(context),
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Heart button overlaid on the restaurant card image. Tapping toggles the
/// restaurant in the customer's favourites with an optimistic update.
class _FavoriteHeart extends ConsumerStatefulWidget {
  final String restaurantId;
  const _FavoriteHeart({required this.restaurantId});

  @override
  ConsumerState<_FavoriteHeart> createState() => _FavoriteHeartState();
}

class _FavoriteHeartState extends ConsumerState<_FavoriteHeart> {
  bool? _override;
  bool _busy = false;

  Future<void> _toggle() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null || _busy) return;
    final isFavNow = _override ??
        (ref.read(isFavoriteProvider((userId, widget.restaurantId))).valueOrNull ??
            false);
    setState(() {
      _override = !isFavNow;
      _busy = true;
    });
    try {
      await ref
          .read(favoritesServiceProvider)
          .toggleFavorite(userId, widget.restaurantId);
      ref.invalidate(isFavoriteProvider((userId, widget.restaurantId)));
      ref.invalidate(favoriteRestaurantsProvider(userId));
    } catch (_) {
      if (mounted) setState(() => _override = isFavNow);
      if (mounted) {
        AppSnackbar.error(context, 'Could not update favourite. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    final isFav = _override ??
        (userId == null
            ? false
            : ref
                    .watch(isFavoriteProvider((userId, widget.restaurantId)))
                    .valueOrNull ??
                false);
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 19,
          color: isFav ? AppTheme.accentColor : Colors.grey[700],
        ),
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  final double height;

  static final _gradientColors = [
    AppTheme.primaryColor.withValues(alpha: 0.15),
    AppTheme.primaryColor.withValues(alpha: 0.05),
  ];
  static final _iconColor = AppTheme.primaryColor.withValues(alpha: 0.4);

  const _PlaceholderImage({this.height = 160});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradientColors,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.restaurant_rounded,
            size: height * 0.25,
            color: _iconColor,
          ),
          SizedBox(height: height * 0.08),
          Text(
            'No image available',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}
