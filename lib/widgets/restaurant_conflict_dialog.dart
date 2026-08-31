import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/menu_model.dart';
import '../providers/feature_providers.dart';
import '../providers/user_provider.dart';

/// What happened when adding [item] was checked against the cart's current
/// restaurant(s) — [noConflict] means the caller should just call
/// `cartProvider.notifier.addItem(...)` as usual; [replace]/[addSecond] mean
/// the customer was asked and chose how to resolve a real conflict;
/// `null` from [resolveRestaurantConflict] means they cancelled.
enum RestaurantConflictChoice { noConflict, replace, addSecond }

/// Checks whether adding [item] would conflict with the restaurant(s)
/// already in the cart and, if so, asks the customer how to proceed —
/// exactly the same prompt/logic used by the manual "add to cart" flow.
///
/// Returns `null` if the customer cancelled the dialog (caller should not
/// mutate the cart at all), otherwise the resolved [RestaurantConflictChoice].
Future<RestaurantConflictChoice?> resolveRestaurantConflict({
  required BuildContext context,
  required WidgetRef ref,
  required MenuItem item,
}) async {
  final cartNotifier = ref.read(cartProvider.notifier);
  if (!cartNotifier.isDifferentRestaurant(item)) {
    // Nothing in the cart yet, or already the same restaurant — no conflict.
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

  if (choice == null || choice == 'cancel') return null;
  return choice == 'replace'
      ? RestaurantConflictChoice.replace
      : RestaurantConflictChoice.addSecond;
}
