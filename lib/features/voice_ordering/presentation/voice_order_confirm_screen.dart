import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/user_provider.dart';
import '../../../screens/customer/restaurant_detail_screen.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/app_theme.dart';
import '../domain/models/resolved_voice_order.dart';
import 'controllers/voice_order_controller.dart';
import 'voice_order_restaurant_conflict.dart';

/// Mandatory review screen — the ONLY place a voice "add to cart" ever
/// touches the real cart, and only when the customer taps Confirm. Shows
/// every matched item with its REAL price/quantity/modifiers (never
/// anything the voice layer "heard"), and every unmatched item with a way
/// to add it manually via the existing menu screen. Cancel discards
/// everything; nothing is added unless Confirm is tapped.
class VoiceOrderConfirmScreen extends ConsumerWidget {
  const VoiceOrderConfirmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceOrderControllerProvider);
    final resolved = state.resolved;

    if (resolved == null) {
      // Defensive — this screen is only ever pushed once resolved is set.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hasIncomplete = resolved.matchedItems.any(
      (i) => i.menuItem.optionGroups.any(
        (g) => g.isRequired && !(i.matchedOptions[g.id]?.isNotEmpty ?? false),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review your order'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            resolved.restaurant.name,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in resolved.matchedItems)
            _MatchedItemTile(
              item: item,
              incomplete: item.menuItem.optionGroups.any(
                (g) => g.isRequired && !(item.matchedOptions[g.id]?.isNotEmpty ?? false),
              ),
              onEdit: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RestaurantDetailScreen(restaurant: resolved.restaurant),
                ),
              ),
            ),
          if (resolved.unmatchedItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "Couldn't find on the menu",
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            for (final item in resolved.unmatchedItems)
              _UnmatchedItemTile(
                item: item,
                onAddManually: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RestaurantDetailScreen(restaurant: resolved.restaurant),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '\$${resolved.subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Text(
            'Delivery fee and tax are calculated at checkout.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          if (hasIncomplete)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Some items need a selection (tap to edit) before adding to cart.',
                style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: state.stage == VoiceOrderStage.addingToCart
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                  onPressed: resolved.matchedItems.isEmpty ||
                          hasIncomplete ||
                          state.stage == VoiceOrderStage.addingToCart
                      ? null
                      : () => _confirm(context, ref),
                  child: state.stage == VoiceOrderStage.addingToCart
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Confirm & Add to Cart'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(voiceOrderControllerProvider.notifier);
    final resolved = ref.read(voiceOrderControllerProvider).resolved!;
    controller.markAddingToCart();

    // One restaurant-conflict check for the whole order (all matched items
    // share the same restaurant) — the exact same prompt as manual add.
    final choice = await resolveRestaurantConflict(
      context: context,
      ref: ref,
      item: resolved.matchedItems.first.menuItem,
    );
    if (choice == null) {
      if (context.mounted) AppSnackbar.error(context, 'Cart unchanged — nothing was added.');
      controller.retry();
      return;
    }

    final cartNotifier = ref.read(cartProvider.notifier);
    for (var i = 0; i < resolved.matchedItems.length; i++) {
      final item = resolved.matchedItems[i];
      for (var q = 0; q < item.quantity; q++) {
        if (choice == RestaurantConflictChoice.replace && i == 0 && q == 0) {
          cartNotifier.replaceWithItem(
            item.menuItem,
            sides: item.matchedSides,
            options: item.matchedOptions,
          );
        } else if (choice == RestaurantConflictChoice.addSecond) {
          cartNotifier.addItemFromNewRestaurant(
            item.menuItem,
            sides: item.matchedSides,
            options: item.matchedOptions,
          );
        } else {
          cartNotifier.addItem(
            item.menuItem,
            sides: item.matchedSides,
            options: item.matchedOptions,
          );
        }
      }
    }

    controller.markDone();
    if (!context.mounted) return;
    final itemCount = resolved.matchedItems.fold<int>(0, (sum, i) => sum + i.quantity);
    Navigator.of(context).pop(); // close confirm screen
    Navigator.of(context).pushNamed('/cart');
    AppSnackbar.success(
      context,
      '$itemCount item${itemCount == 1 ? '' : 's'} added to your cart',
    );
  }
}

class _MatchedItemTile extends StatelessWidget {
  const _MatchedItemTile({required this.item, required this.incomplete, required this.onEdit});

  final MatchedVoiceOrderItem item;
  final bool incomplete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final subtitleLines = [
      if (item.modifierLabels.isNotEmpty) item.modifierLabels.join(' · '),
      if (item.notes != null) 'Note: ${item.notes}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          incomplete ? Icons.error_outline_rounded : Icons.check_circle_rounded,
          color: incomplete ? Colors.orange.shade700 : Colors.green,
        ),
        title: Text('${item.quantity} × ${item.menuItem.name}'),
        subtitle: subtitleLines.isNotEmpty ? Text(subtitleLines.join('\n')) : null,
        trailing: Text(
          '\$${item.lineTotal.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        onTap: onEdit,
      ),
    );
  }
}

class _UnmatchedItemTile extends StatelessWidget {
  const _UnmatchedItemTile({required this.item, required this.onAddManually});

  final UnmatchedVoiceOrderItem item;
  final VoidCallback onAddManually;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.orange.shade50,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.help_outline_rounded, color: Colors.orange.shade700),
        title: Text(item.nameAsSaid),
        subtitle: Text(item.reason ?? "Couldn't match this to the menu"),
        trailing: TextButton(
          onPressed: onAddManually,
          child: const Text('Add manually'),
        ),
      ),
    );
  }
}
