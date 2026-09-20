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
                  onEditStorefront: () =>
                      _editStorefront(context, ref, store),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Admin edits the customer-facing storefront name/logo for a partner store.
  /// The real store name (e.g. "Loshusan Supermarket") is never shown to
  /// customers — only this public alias, or the global "HotBite Groceries"
  /// brand when left blank.
  Future<void> _editStorefront(
    BuildContext context,
    WidgetRef ref,
    Restaurant store,
  ) async {
    final service = ref.read(groceryServiceProvider);
    ({String? publicName, String? publicImageUrl}) current;
    try {
      current = await service.getStorePublicStorefront(store.id);
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
      return;
    }
    if (!context.mounted) return;

    final realNameCtrl = TextEditingController(text: store.name);
    final addressCtrl = TextEditingController(text: store.address ?? '');
    final nameCtrl = TextEditingController(text: current.publicName ?? '');
    final logoCtrl = TextEditingController(text: current.publicImageUrl ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Edit store'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Store details (admin/owner/driver only)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: realNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Store name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
              ),
              const Divider(height: 28),
              const Text(
                'Customer-facing storefront',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Public name shown to customers',
                  hintText: 'HotBite Groceries',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: logoCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Public logo URL (optional)',
                  hintText: 'https://…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Leave the public fields blank to use the default "HotBite '
                'Groceries" brand. Customers never see the store name/address.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(dialogCtx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    try {
      await service.updateStoreDetails(
        store.id,
        name: realNameCtrl.text,
        address: addressCtrl.text,
      );
      await service.setStorePublicStorefront(
        store.id,
        publicName: nameCtrl.text,
        publicImageUrl: logoCtrl.text,
      );
      if (context.mounted) {
        AppSnackbar.success(context, 'Store updated');
        ref.invalidate(adminGroceryStoresProvider);
      }
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({
    required this.store,
    required this.onTap,
    required this.onEditStorefront,
  });
  final Restaurant store;
  final VoidCallback onTap;
  final VoidCallback onEditStorefront;

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
              IconButton(
                tooltip: 'Edit store details',
                icon: const Icon(Icons.badge_outlined),
                color: const Color(0xFF059669),
                onPressed: onEditStorefront,
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
