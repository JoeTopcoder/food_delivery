import 'package:flutter/material.dart';
import '../models/restaurant_model.dart';
import '../utils/app_theme.dart';
import '../core/utils/responsive.dart';
import 'package:food_driver/config/app_constants.dart';

class RestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onTap;

  const RestaurantCard({
    super.key,
    required this.restaurant,
    required this.onTap,
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
          borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Restaurant Image
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(Responsive.cardRadius(context)),
                  ),
                  child: restaurant.imageUrl != null &&
                      restaurant.imageUrl!.isNotEmpty
                      ? Image.network(
                          restaurant.imageUrl!,
                          height: imageHeight.toDouble(),
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _PlaceholderImage(height: imageHeight.toDouble()),
                          loadingBuilder: (_, child, progress) => progress == null
                              ? child
                              : _PlaceholderImage(height: imageHeight.toDouble()),
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
                      borderRadius:
                          BorderRadius.circular(Responsive.cardRadius(context) - 2),
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
                      borderRadius:
                          BorderRadius.circular(Responsive.cardRadius(context) - 4),
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
                          borderRadius: BorderRadius.circular(
                              Responsive.cardRadius(context) - 2),
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
                      SizedBox(width: spacing * 0.75),
                      Icon(
                        Icons.delivery_dining_rounded,
                        size: Responsive.isSmallPhone(context) ? 13 : 15,
                        color: Colors.grey[700],
                      ),
                      SizedBox(width: spacing * 0.2),
                      Flexible(
                        child: Text(
                          () {
                            final fee = restaurant.deliveryFee;
                            if (fee == null) return 'Delivery';
                            if (fee <= 0) return 'Free delivery';
                            return '${AppConstants.currencySymbol}${fee.toStringAsFixed(2)} delivery';
                          }(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize:
                                Responsive.smallText(context),
                            color: Colors.grey[600],
                          ),
                        ),
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
