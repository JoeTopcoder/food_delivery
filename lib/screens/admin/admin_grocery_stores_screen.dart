import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/restaurant_model.dart';
import '../../providers/grocery_provider.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import '../restaurant/grocery_management_screen.dart';

/// Admin: pick a grocery store, then manage its products in the same screen
/// the store owner uses. menus RLS already permits admins to add / edit / delete
/// any store's products, so this reuses the owner flow rather than duplicating
/// it.
final adminGroceryStoresProvider = FutureProvider.autoDispose<List<Restaurant>>(
  (ref) {
    return ref.watch(groceryServiceProvider).getGroceryStoresForAdmin();
  },
);

class AdminGroceryStoresScreen extends ConsumerWidget {
  const AdminGroceryStoresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(adminGroceryStoresProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Grocery Products',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
      ),
      body: storesAsync.when(
        loading: () =>
            const AppLoadingIndicator(message: 'Loading grocery stores…'),
        error: (e, _) => AppErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(adminGroceryStoresProvider),
        ),
        data: (stores) {
          if (stores.isEmpty) {
            return const AppEmptyState(
              icon: Icons.storefront_outlined,
              title: 'No grocery stores',
              subtitle:
                  'Create a store with type Grocery first, then add products here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(adminGroceryStoresProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: stores.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final store = stores[i];
                return _StoreTile(
                  store: store,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroceryManagementScreen(store: store),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({required this.store, required this.onTap});
  final Restaurant store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_grocery_store_rounded,
                  color: Color(0xFF059669),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      store.isVerified ? 'Verified' : 'Not verified',
                      style: TextStyle(
                        fontSize: 12,
                        color: store.isVerified
                            ? const Color(0xFF12B76A)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
