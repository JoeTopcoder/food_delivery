import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_constants.dart';
import '../../../models/menu_model.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../data/lunch_cart_provider.dart';
import 'lunch_cart_screen.dart';
import 'lunch_orders_screen.dart';

/// Browse lunch and add to the cart.
///
/// Deliberately an ordinary shopping screen: it never asks who the lunch is
/// for. That question belongs at checkout, so a parent can fill a basket
/// without having decided yet, and so the same basket can go to a child or be
/// kept for themselves.
class LunchMenuScreen extends ConsumerWidget {
  const LunchMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(lunchMenuProvider);
    final count = ref.watch(lunchItemCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('School Lunch'),
        actions: [
          IconButton(
            tooltip: 'Past lunch orders',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LunchOrdersScreen()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LunchCartScreen()),
                  ),
                ),
                if (count > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: menuAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(friendlyError(e), textAlign: TextAlign.center),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No lunch items available today.'));
          }
          final byCategory = <String, List<MenuItem>>{};
          for (final i in items) {
            byCategory.putIfAbsent(i.category, () => []).add(i);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              for (final entry in byCategory.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 12, 0, 8),
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                for (final item in entry.value) _LunchItemTile(item: item),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: count == 0
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LunchCartScreen()),
                    ),
                    child: Text(
                      'View cart ($count)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _LunchItemTile extends ConsumerWidget {
  const _LunchItemTile({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                ),
                if (item.description?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${AppConstants.currencySymbol}${item.price.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              ref.read(lunchCartProvider.notifier).add(item);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('${item.name} added'),
                    duration: const Duration(milliseconds: 900),
                  ),
                );
            },
            child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
