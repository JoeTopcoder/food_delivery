import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/menu_model.dart';
import '../../../providers/auth_user/user_provider.dart';
import '../../../providers/platform/feature_providers.dart';

/// What the customer chose when adding an item from a different restaurant
/// than what's already in their cart.
enum RestaurantConflictChoice {
  /// No conflict — the cart was empty or already at this restaurant. Add
  /// normally.
  noConflict,

  /// Clear the cart and start fresh at the new restaurant.
  replace,

  /// Keep the existing restaurant's items and add this one too (multi
  /// -restaurant cart, up to [maxRestaurantsPerOrderProvider]).
  addSecond,
}

/// The one restaurant-lock prompt in the app — extracted out of
/// `restaurant_detail_screen.dart`'s manual "add to cart" flow (byte
/// -identical copy/behavior) so Talk to Order's confirm screen can present
/// the exact same rule instead of duplicating or reinventing it. Returns
/// null if the customer cancelled (nothing should be added).
Future<RestaurantConflictChoice?> resolveRestaurantConflict({
  required BuildContext context,
  required WidgetRef ref,
  required MenuItem item,
}) async {
  final cartNotifier = ref.read(cartProvider.notifier);

  if (!cartNotifier.isDifferentRestaurant(item)) {
    return RestaurantConflictChoice.noConflict;
  }

  final maxRestaurants =
      ref.read(maxRestaurantsPerOrderProvider).valueOrNull ?? 2;
  final limitReached = cartNotifier.wouldExceedRestaurantLimit(
    item,
    maxRestaurants,
  );

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(limitReached ? 'Restaurant limit reached' : 'Add to order?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            limitReached
                ? 'You can order from a maximum of $maxRestaurants restaurants '
                    'at once. Clear your cart to add from this restaurant.'
                : 'Your cart already has items from another restaurant. '
                    'Add this item too, or clear & replace your cart.',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade400,
                side: BorderSide(color: Colors.red.shade300),
              ),
              child: const Text('Clear & replace'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'cancel'),
          child: const Text('Cancel'),
        ),
        if (!limitReached)
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'add'),
            child: const Text('Add to order'),
          ),
      ],
    ),
  );

  switch (choice) {
    case 'replace':
      return RestaurantConflictChoice.replace;
    case 'add':
      return RestaurantConflictChoice.addSecond;
    default:
      return null; // cancelled, or dialog dismissed
  }
}
