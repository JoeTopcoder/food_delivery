import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/user_provider.dart';
import '../../widgets/restaurant_card.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import '../../core/utils/responsive.dart';

/// Shown when a customer taps a category chip on the home screen. Lists the
/// restaurants that serve that category (open, verified, in delivery range),
/// so the customer browses by category at the restaurant level. Tapping a card
/// opens the restaurant.
class RestaurantsByCategoryScreen extends ConsumerWidget {
  final String categoryName;
  final String? categoryEmoji;

  const RestaurantsByCategoryScreen({
    super.key,
    required this.categoryName,
    this.categoryEmoji,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurantsAsync =
        ref.watch(restaurantsByCategoryProvider(categoryName));

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
            ref.invalidate(restaurantsByCategoryProvider(categoryName)),
        child: restaurantsAsync.when(
          loading: () =>
              const AppLoadingIndicator(message: 'Finding restaurants…'),
          error: (e, _) => AppErrorState(
            message: friendlyError(e),
            onRetry: () =>
                ref.invalidate(restaurantsByCategoryProvider(categoryName)),
          ),
          data: (restaurants) {
            if (restaurants.isEmpty) {
              return AppEmptyState(
                icon: Icons.storefront_outlined,
                title: 'No $categoryName places yet',
                subtitle:
                    'No restaurant near you currently offers this category. '
                    'Check back soon!',
              );
            }
            return ListView.builder(
              padding: EdgeInsets.fromLTRB(
                Responsive.horizontalPadding(context),
                14,
                Responsive.horizontalPadding(context),
                24,
              ),
              itemCount: restaurants.length,
              itemBuilder: (context, i) {
                final r = restaurants[i];
                return RestaurantCard(
                  restaurant: r,
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/restaurant-detail',
                    arguments: r,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
