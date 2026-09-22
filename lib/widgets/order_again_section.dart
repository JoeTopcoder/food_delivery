import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/order_again_provider.dart';
import '../services/reorder/reorder_flow.dart';
import '../core/utils/responsive.dart';
import '../utils/rating_format.dart';
import 'app_cached_image.dart';

/// ⭐ Order Again — the customer's usual orders, one tap away.
///
/// Built entirely from real completed order history ([orderAgainProvider]);
/// self-hides when the customer has no meaningful history. Each card re-orders
/// through the shared [ReorderFlow], which re-checks live price/availability
/// before touching the cart. Works for both food and grocery orders.
class OrderAgainSection extends ConsumerWidget {
  const OrderAgainSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(orderAgainProvider);
    if (entries.isEmpty) return const SizedBox.shrink();

    final hPad = Responsive.horizontalPadding(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 2),
          child: Row(
            children: [
              const Icon(Icons.star_rounded,
                  size: 20, color: Color(0xFFFFB300)),
              const SizedBox(width: 6),
              Text(
                'Order Again',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
          child: Text(
            'Your usual orders, one tap away.',
            style: TextStyle(
              fontSize: 12.5,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
        SizedBox(
          height: 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.symmetric(horizontal: hPad),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _OrderAgainCard(entry: entries[i]),
          ),
        ),
      ],
    );
  }
}

class _OrderAgainCard extends ConsumerWidget {
  const _OrderAgainCard({required this.entry});

  final OrderAgainEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final storeAsync = ref.watch(orderAgainStoreProvider(entry.restaurantId));
    final store = storeAsync.valueOrNull;
    final isGrocery = store?.storeType == 'grocery';
    final name = store?.name ?? 'Your order';

    return SizedBox(
      width: 208,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: (store?.imageUrl ?? '').isNotEmpty
                        ? AppCachedImage(
                            url: store!.imageUrl, width: 40, height: 40)
                        : Container(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.12),
                            child: Icon(
                              isGrocery
                                  ? Icons.local_grocery_store_rounded
                                  : Icons.restaurant_rounded,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(isGrocery ? '🛒' : '🍽',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    entry.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
            if ((store?.rating ?? 0) > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      size: 14, color: Color(0xFFFFB300)),
                  const SizedBox(width: 2),
                  Text(
                    formatRating(store!.rating),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if ((store.reviewCount ?? 0) > 0)
                    Text(
                      ' (${store.reviewCount})',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => ReorderFlow.start(context, ref, entry.order),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Order Again',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
