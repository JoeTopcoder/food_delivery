import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/catalog/menu_model.dart';
import '../../providers/auth_user/user_provider.dart';
import '../../providers/platform/feature_providers.dart';
import '../../utils/app_feedback_widgets.dart';
import '../menu/menu_item_detail_sheet.dart';
import '../../providers/rewards/membership_provider.dart';

/// Opens the existing menu-item detail sheet and, on confirm, adds the item to
/// the cart — handling the multi-restaurant conflict flow. Shared by the
/// restaurant detail screen and the Home food search so the behaviour (and cart
/// rules) stay identical everywhere.
Future<void> presentMenuItemAndAddToCart(
  BuildContext context,
  WidgetRef ref,
  MenuItem rawItem,
) async {
  // HotBite+ item pricing: an active member sees and pays the member price.
  // Substituting a member-priced copy makes the detail sheet, the cart and the
  // (server-revalidated) checkout all use the correct price with no extra
  // plumbing. Non-members are unaffected.
  // The menu list is fetched WITHOUT option groups/choices for speed, so pull
  // this one item's full options now (fast — a single row). If it fails or the
  // item has none, fall back to what we already have.
  MenuItem base = rawItem;
  if (rawItem.optionGroups.isEmpty) {
    final full = await ref.read(menuServiceProvider).getMenuItemWithOptions(rawItem.id);
    if (full != null) base = full;
  }

  final isMember = ref.read(isHotBitePlusMemberProvider);
  // For a member, present a copy whose CHARGED price (discountedPrice) is the
  // member price, while keeping the regular price on `price` so the cart and
  // checkout can show the member saving. The order records both.
  MenuItem item = base;
  if (isMember && base.hasMemberPrice) {
    final regular = base.discountedPrice; // non-member price
    final pct = ((1 - base.memberPrice / regular) * 100).clamp(0.0, 100.0);
    item = base.copyWith(price: regular, discount: pct);
  }
  if (!context.mounted) return;
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
