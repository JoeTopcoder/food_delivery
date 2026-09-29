import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_constants.dart';
import '../../config/supabase_config.dart';
import '../../models/menu_model.dart';
import '../../models/order_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/promo_provider.dart';
import '../../providers/loyalty_provider.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_logger.dart';

/// One resolved reorder line: the live product, the quantity from the original
/// order, and the old unit price (to surface price changes to the customer).
class _ResolvedLine {
  final MenuItem live;
  final int quantity;
  final double oldUnitPrice;
  _ResolvedLine(this.live, this.quantity, this.oldUnitPrice);

  double get newUnitPrice => live.discountedPrice;
  bool get priceChanged =>
      (newUnitPrice - oldUnitPrice).abs() >= 0.01;
}

/// Shared "Order Again" reorder flow used by both the home Order Again rail and
/// the order-history screen. It NEVER blindly copies the old order:
///  - re-fetches every item live (availability, stock, current price/sale),
///  - verifies the restaurant/store is still active and accepting orders,
///  - routes food orders to the food cart and grocery orders to the grocery
///    cart (they stay separate),
///  - shows a "few items changed" review when anything is unavailable or the
///    price moved, and
///  - prompts before replacing a cart that holds another restaurant's items.
class ReorderFlow {
  /// Entry point. Resolves [order] against live data and drives the customer
  /// to the correct checkout, or explains why it can't.
  static Future<void> start(
    BuildContext context,
    WidgetRef ref,
    Order order,
  ) async {
    _showLoading(context);
    try {
      final menuService = ref.read(menuServiceProvider);

      // 1) Verify the store is still active + accepting orders.
      final store = await SupabaseConfig.client
          .from('restaurants')
          .select('is_open, is_verified, store_type')
          .eq('id', order.restaurantId)
          .maybeSingle();

      if (store == null || store['is_verified'] != true) {
        if (!context.mounted) return;
        _dismiss(context);
        AppSnackbar.warning(
            context, 'This store is no longer available on HotBite.');
        return;
      }
      if (store['is_open'] != true) {
        if (!context.mounted) return;
        _dismiss(context);
        AppSnackbar.warning(context,
            'This store isn\'t accepting orders right now. Try again later.');
        return;
      }
      final isGrocery = store['store_type'] == 'grocery';

      // 2) Re-fetch every item live (current availability, stock, price).
      final live = await Future.wait(
        order.items.map((i) => menuService.getMenuItemById(i.menuItemId)),
      );

      final resolved = <_ResolvedLine>[];
      final unavailable = <String>[];
      for (var i = 0; i < order.items.length; i++) {
        final m = live[i];
        final orig = order.items[i];
        if (m != null && m.isAvailable && m.inStock) {
          resolved.add(_ResolvedLine(m, orig.quantity, orig.price));
        } else {
          unavailable.add(orig.itemName);
        }
      }

      if (!context.mounted) return;
      _dismiss(context);
      if (!context.mounted) return;

      if (resolved.isEmpty) {
        AppSnackbar.warning(context,
            'None of the items from this order are available right now.');
        return;
      }

      // 3) If anything changed (unavailable item or price move), let the
      // customer review before we touch their cart.
      final hasPriceChange = resolved.any((r) => r.priceChanged);
      if (unavailable.isNotEmpty || hasPriceChange) {
        final proceed = await _showChangedSheet(
          context,
          resolved: resolved,
          unavailable: unavailable,
        );
        if (proceed != true || !context.mounted) return;
      }

      // 4) Cart-conflict guard, then add + navigate.
      if (isGrocery) {
        await _fillGroceryCart(context, ref, order.restaurantId, resolved);
      } else {
        await _fillFoodCart(context, ref, order, resolved);
      }
    } catch (e) {
      AppLogger.error('Reorder error: $e');
      if (!context.mounted) return;
      _dismiss(context);
      AppSnackbar.error(context, 'Could not reorder. Please try again.');
    }
  }

  // ── Food ────────────────────────────────────────────────────────────────
  static Future<void> _fillFoodCart(
    BuildContext context,
    WidgetRef ref,
    Order order,
    List<_ResolvedLine> lines,
  ) async {
    final cart = ref.read(cartProvider.notifier);
    final current = ref.read(cartProvider);
    final conflict = current.isNotEmpty &&
        current.first.menuItem.restaurantId != order.restaurantId;

    if (conflict) {
      final replace = await _confirmReplaceCart(context);
      if (replace != true) return;
      cart.clearCart();
    }

    for (final line in lines) {
      for (var q = 0; q < line.quantity; q++) {
        cart.addItem(line.live);
      }
    }

    // Fresh cart → checkout, like a normal order.
    ref.read(appliedPromoProvider.notifier).clear();
    ref.read(redeemPointsProvider.notifier).state = 0;
    ref.read(groupOrderIdForCheckoutProvider.notifier).state = null;
    ref.read(groupOrderParticipantCountProvider.notifier).state = 0;
    ref.read(isPickupProvider.notifier).state = order.isPickup;

    if (context.mounted) Navigator.pushNamed(context, '/checkout');
  }

  // ── Grocery ──────────────────────────────────────────────────────────────
  static Future<void> _fillGroceryCart(
    BuildContext context,
    WidgetRef ref,
    String storeId,
    List<_ResolvedLine> lines,
  ) async {
    final cart = ref.read(groceryCartProvider.notifier);
    final current = ref.read(groceryCartProvider);
    final conflict = current.isNotEmpty &&
        cart.currentStoreId != null &&
        cart.currentStoreId != storeId;

    if (conflict) {
      final replace = await _confirmReplaceCart(context, grocery: true);
      if (replace != true) return;
      cart.clearCart();
    }

    for (final line in lines) {
      // Respect the product's live quantity limit.
      final want = line.quantity.clamp(1, line.live.maxQuantity);
      for (var q = 0; q < want; q++) {
        cart.addItem(line.live);
      }
    }

    if (context.mounted) Navigator.pushNamed(context, '/grocery-checkout');
  }

  // ── Dialogs / sheets ──────────────────────────────────────────────────────
  static void _showLoading(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Checking prices & availability...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _dismiss(BuildContext context) {
    if (context.mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  /// "A few items changed" review sheet.
  static Future<bool?> _showChangedSheet(
    BuildContext context, {
    required List<_ResolvedLine> resolved,
    required List<String> unavailable,
  }) {
    String currency(double v) =>
        '${AppConstants.currencySymbol}${v.toStringAsFixed(2)}';
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('A few items changed',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'We checked current prices and availability. Nothing is added '
                'until you tap below.',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in resolved)
                        _changedRow(
                          ctx,
                          ok: true,
                          name: r.live.name,
                          trailing: r.priceChanged
                              ? '${currency(r.oldUnitPrice)} → ${currency(r.newUnitPrice)}'
                              : currency(r.newUnitPrice),
                          highlight: r.priceChanged,
                        ),
                      for (final name in unavailable)
                        _changedRow(ctx,
                            ok: false,
                            name: name,
                            trailing: 'unavailable',
                            highlight: false),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Add available items'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _changedRow(
    BuildContext context, {
    required bool ok,
    required String name,
    required String trailing,
    required bool highlight,
  }) {
    final color = ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  decoration: ok ? null : TextDecoration.lineThrough,
                  color: ok
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                )),
          ),
          const SizedBox(width: 8),
          Text(trailing,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w500,
                color: highlight
                    ? const Color(0xFFEA580C)
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
              )),
        ],
      ),
    );
  }

  static Future<bool?> _confirmReplaceCart(BuildContext context,
      {bool grocery = false}) {
    final what = grocery ? 'grocery store' : 'restaurant';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace your cart?'),
        content: Text(
          'Your cart contains items from another $what. Reordering will '
          'replace those items.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep current cart'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace cart'),
          ),
        ],
      ),
    );
  }
}
