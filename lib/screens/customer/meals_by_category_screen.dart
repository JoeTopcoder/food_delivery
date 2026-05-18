import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_constants.dart';
import '../../providers/user_provider.dart';
import '../../services/food/menu_category_service.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import 'restaurant_detail_screen.dart';

/// Screen shown when a customer taps a category chip on the home screen.
/// Lists every available menu item across open restaurants in that category,
/// loaded via the `menu-by-category` edge function.
class MealsByCategoryScreen extends ConsumerWidget {
  final String categoryName;
  final String? categoryEmoji;

  const MealsByCategoryScreen({
    super.key,
    required this.categoryName,
    this.categoryEmoji,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mealsAsync = ref.watch(mealsByCategoryProvider(categoryName));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (categoryEmoji != null) ...[
              Text(categoryEmoji!, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                categoryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(mealsByCategoryProvider(categoryName)),
        child: mealsAsync.when(
          loading: () => const AppLoadingIndicator(message: 'Finding meals…'),
          error: (e, _) => AppErrorState(
            message: friendlyError(e),
            onRetry: () =>
                ref.invalidate(mealsByCategoryProvider(categoryName)),
          ),
          data: (meals) {
            if (meals.isEmpty) {
              return AppEmptyState(
                icon: Icons.restaurant_menu,
                title: 'No $categoryName meals yet',
                subtitle:
                    'No restaurant currently offers this category. Check back soon!',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              itemCount: meals.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _MealCard(meal: meals[i], ref: ref),
            );
          },
        ),
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  final MenuItemWithRestaurant meal;
  final WidgetRef ref;
  const _MealCard({required this.meal, required this.ref});

  @override
  Widget build(BuildContext context) {
    final item = meal.item;
    final hasDiscount = (item.discount ?? 0) > 0;
    final discounted = hasDiscount
        ? item.price * (1 - (item.discount! / 100))
        : item.price;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        if (meal.restaurantId == null) return;
        final restaurantService = ref.read(restaurantServiceProvider);
        try {
          final restaurant = await restaurantService.getRestaurantById(
            meal.restaurantId!,
          );
          if (!context.mounted) return;
          if (restaurant == null) {
            AppSnackbar.error(
              context,
              'This restaurant is no longer available.',
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RestaurantDetailScreen(restaurant: restaurant),
            ),
          );
        } catch (e) {
          if (context.mounted) {
            AppSnackbar.error(context, friendlyError(e));
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200, width: 0.5),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 92,
                height: 92,
                child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: item.imageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Container(
                          color: Colors.grey.shade100,
                          child: const Icon(Icons.fastfood, color: Colors.grey),
                        ),
                      )
                    : Container(
                        color: Colors.grey.shade100,
                        child: const Icon(Icons.fastfood, color: Colors.grey),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (meal.restaurantName != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.storefront_rounded,
                          size: 13,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            meal.restaurantName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                        if (meal.restaurantRating != null) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: Colors.amber,
                          ),
                          Text(
                            meal.restaurantRating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (item.description != null &&
                      item.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (hasDiscount) ...[
                        Text(
                          '${AppConstants.currencySymbol}${item.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '${AppConstants.currencySymbol}${discounted.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const Spacer(),
                      if (!meal.restaurantIsCurrentlyOpen)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Closed',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
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
