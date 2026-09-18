import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/menu_model.dart';
import '../providers/user_provider.dart';
import '../providers/feature_providers.dart';
import '../utils/app_feedback_widgets.dart';
import 'menu_item_detail_sheet.dart';

/// Opens the existing menu-item detail sheet and, on confirm, adds the item to
/// the cart — handling the multi-restaurant conflict flow. Shared by the
/// restaurant detail screen and the Home food search so the behaviour (and cart
/// rules) stay identical everywhere.
Future<void> presentMenuItemAndAddToCart(
  BuildContext context,
  WidgetRef ref,
  MenuItem item,
) async {
  final result = await showMenuItemDetailSheet(context, item);
  if (result == null) return; // cancelled
  if (!context.mounted) return;

  final cartNotifier = ref.read(cartProvider.notifier);

  if (cartNotifier.isDifferentRestaurant(item)) {
    final maxRestaurants =
        ref.read(maxRestaurantsPerOrderProvider).valueOrNull ?? 2;
    final limitReached =
        cartNotifier.wouldExceedRestaurantLimit(item, maxRestaurants);

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

    if (choice == null || choice == 'cancel') return;
    if (choice == 'replace') {
      cartNotifier.replaceWithItem(
        item,
        sides: result.selectedSides,
        options: result.selectedOptions,
      );
    } else {
      for (int i = 0; i < result.quantity; i++) {
        cartNotifier.addItemFromNewRestaurant(
          item,
          sides: result.selectedSides,
          options: result.selectedOptions,
        );
      }
    }
  } else {
    for (int i = 0; i < result.quantity; i++) {
      cartNotifier.addItem(
        item,
        sides: result.selectedSides,
        options: result.selectedOptions,
      );
    }
  }

  if (!context.mounted) return;
  AppSnackbar.success(context, '${result.quantity}x ${item.name} added to cart');
}
