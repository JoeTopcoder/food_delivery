import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/menu_model.dart';
import '../../models/inventory_model.dart';
import '../../models/product_image_result.dart';
import '../../models/restaurant_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/grocery_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/grocery_service.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import 'package:food_driver/config/app_constants.dart';
import 'barcode_scan_screen.dart';

class GroceryManagementScreen extends ConsumerStatefulWidget {
  /// When [store] is provided (admin path), that store is managed directly and
  /// the owner-session lookup is skipped. When null (store-owner path), the
  /// screen resolves the store owned by the signed-in user.
  const GroceryManagementScreen({super.key, this.store});

  final Restaurant? store;

  @override
  ConsumerState<GroceryManagementScreen> createState() =>
      _GroceryManagementScreenState();
}

class _GroceryManagementScreenState
    extends ConsumerState<GroceryManagementScreen> {
  @override
  Widget build(BuildContext context) {
    // Admin path: a specific store was handed in — manage its catalogue
    // directly (menus RLS already allows admins to write any store's products).
    if (widget.store != null) {
      return _GroceryStoreBody(store: widget.store!);
    }

    final currentUserId = ref.watch(currentUserIdProvider);

    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to manage grocery products.')),
      );
    }

    final storeAsync = ref.watch(ownerGroceryStoreProvider(currentUserId));

    return storeAsync.when(
      loading: () => const Scaffold(
        body: AppLoadingIndicator(message: 'Loading store...'),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Grocery Management')),
        body: AppErrorState(
          message: friendlyError(error),
          onRetry: () =>
              ref.invalidate(ownerGroceryStoreProvider(currentUserId)),
        ),
      ),
      data: (groceryStore) {
        if (groceryStore == null) {
          return _CreateGroceryStoreView(
            ownerId: currentUserId,
            onStoreCreated: () =>
                ref.invalidate(ownerGroceryStoreProvider(currentUserId)),
          );
        }

        return _GroceryStoreBody(store: groceryStore);
      },
    );
  }
}

// ── Create Store View ───────────────────────────────────────────────────────

class _CreateGroceryStoreView extends ConsumerStatefulWidget {
  final String ownerId;
  final VoidCallback onStoreCreated;

  const _CreateGroceryStoreView({
    required this.ownerId,
    required this.onStoreCreated,
  });

  @override
  ConsumerState<_CreateGroceryStoreView> createState() =>
      _CreateGroceryStoreViewState();
}

class _CreateGroceryStoreViewState
    extends ConsumerState<_CreateGroceryStoreView> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _createStore() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _creating = true);
    try {
      final service = ref.read(groceryServiceProvider);
      await service.createGroceryStore(
        ownerId: widget.ownerId,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty
            ? null
            : _addressCtrl.text.trim(),
      );
      widget.onStoreCreated();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text(
          'Create Grocery Store',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withValues(alpha: 0.08),
                      AppTheme.primaryColor.withValues(alpha: 0.03),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.storefront_rounded,
                        size: 40,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Set Up Your Grocery Store',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a separate grocery store with its own name. '
                      'You\'ll manage it using the same account as your restaurant.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Store Name
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDecor(
                  'Store Name *',
                  icon: Icons.store_rounded,
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Store name is required'
                    : null,
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descCtrl,
                decoration: _inputDecor(
                  'Description (optional)',
                  icon: Icons.description_outlined,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Phone
              TextFormField(
                controller: _phoneCtrl,
                decoration: _inputDecor(
                  'Phone (optional)',
                  icon: Icons.phone_outlined,
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              // Address
              TextFormField(
                controller: _addressCtrl,
                decoration: _inputDecor(
                  'Address (optional)',
                  icon: Icons.location_on_outlined,
                ),
              ),
              const SizedBox(height: 32),

              // Create button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _creating ? null : _createStore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  icon: _creating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Icon(Icons.add_business_rounded),
                  label: Text(
                    _creating ? 'Creating...' : 'Create Grocery Store',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String label, {IconData? icon}) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        filled: true,
        fillColor: Theme.of(context).inputDecorationTheme.fillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
      );
}

// ── Store Body (product list) ───────────────────────────────────────────────

class _GroceryStoreBody extends ConsumerWidget {
  final Restaurant store;
  const _GroceryStoreBody({required this.store});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(ownerGroceryProductsProvider(store.id));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              store.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            Text(
              'Grocery Store',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_a_photo_outlined),
            tooltip: 'Add product from photo',
            onPressed: () => _addFromPhoto(context, ref, store.id),
          ),
          IconButton(
            icon: const Icon(Icons.local_shipping_outlined),
            tooltip: 'Delivery Settings',
            onPressed: () => _showDeliverySettings(context, ref, store),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(ownerGroceryProductsProvider(store.id)),
          ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Center(
          child: AppLoadingIndicator(message: 'Loading products...'),
        ),
        error: (error, _) => AppErrorState(
          message: friendlyError(error),
          onRetry: () => ref.invalidate(ownerGroceryProductsProvider(store.id)),
        ),
        data: (products) {
          if (products.isEmpty) {
            return AppEmptyState(
              icon: Icons.local_grocery_store_outlined,
              title: 'No grocery products yet',
              subtitle: 'Add your first grocery product to start selling.',
              actionLabel: 'Add Product',
              onAction: () => _showAddProductDialog(context, ref, store.id),
            );
          }

          // Inventory fills in slightly after the product list; render products
          // immediately and let stock chips appear once it loads.
          final invMap =
              ref.watch(storeInventoryProvider(store.id)).valueOrNull ??
              const <String, ProductInventory>{};

          // Store-level low-stock list (tracked items at/below their threshold).
          final lowStock = [
            for (final p in products)
              if (invMap[p.id]?.isLow ?? false) (product: p, inv: invMap[p.id]!),
          ]..sort((a, b) => a.inv.stockQuantity.compareTo(b.inv.stockQuantity));

          // Group items by category
          final grouped = <String, List<MenuItem>>{};
          for (final item in products) {
            grouped.putIfAbsent(item.category, () => []).add(item);
          }
          final categories = grouped.keys.toList()..sort();

          return ListView.builder(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            scrollCacheExtent: const ScrollCacheExtent.pixels(500),
            padding: const EdgeInsets.all(16),
            // +1 leading slot for the low-stock banner.
            itemCount: categories.length + 1,
            itemBuilder: (context, rawIndex) {
              if (rawIndex == 0) {
                if (lowStock.isEmpty) return const SizedBox.shrink();
                return _LowStockBanner(
                  items: lowStock,
                  onTapItem: (item) =>
                      _showInventorySheet(context, ref, item, store.id),
                );
              }
              final catIndex = rawIndex - 1;
              final category = categories[catIndex];
              final items = grouped[category]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (catIndex > 0) const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.category_rounded,
                          size: 16,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          category,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${items.length} items',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...items.map(
                    (item) => _GroceryProductTile(
                      product: item,
                      inventory: invMap[item.id],
                      onScanBarcode: () =>
                          _scanAndAssignBarcode(context, ref, item, store.id),
                      onRemoveBarcode: () =>
                          _removeBarcode(context, ref, item, store.id),
                      onManageStock: () =>
                          _showInventorySheet(context, ref, item, store.id),
                      onToggleStock: () =>
                          _toggleStock(context, ref, item, store.id),
                      onToggleAvailability: () =>
                          _toggleAvailability(context, ref, item, store.id),
                      onDelete: () => _confirmDelete(
                        context,
                        ref,
                        item.id,
                        item.name,
                        store.id,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddProductDialog(context, ref, store.id),
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Product',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  void _showDeliverySettings(
    BuildContext context,
    WidgetRef ref,
    Restaurant store,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DeliverySettingsSheet(
        store: store,
        onSaved: () {
          ref.invalidate(ownerGroceryStoreProvider(store.ownerId));
        },
      ),
    );
  }

  void _showAddProductDialog(
    BuildContext context,
    WidgetRef ref,
    String storeId,
  ) {
    _openAddDialog(context, ref, storeId);
  }

  /// Opens the add-product dialog, optionally pre-filled (from AI photo
  /// identification) and with a starting photo.
  void _openAddDialog(
    BuildContext context,
    WidgetRef ref,
    String storeId, {
    File? image,
    String? imageUrl,
    bool aiPrefilled = false,
    String? name,
    String? brand,
    String? weight,
    String? description,
    String? category,
    String? unit,
  }) {
    final categoriesAsync = ref.read(groceryCategoriesProvider);
    final existingCategories = <String>[];
    categoriesAsync.whenData((cats) {
      existingCategories.addAll(cats.map((c) => c.name));
    });

    final productsAsync = ref.read(ownerGroceryProductsProvider(storeId));
    productsAsync.whenData((products) {
      for (final p in products) {
        if (!existingCategories.contains(p.category)) {
          existingCategories.add(p.category);
        }
      }
    });

    String? clean(String? s) => (s == null ||
            s.trim().isEmpty ||
            s.trim().toLowerCase() == 'null')
        ? null
        : s.trim();

    // Include a new AI category so it can be pre-selected.
    final cat = clean(category);
    if (cat != null && !existingCategories.contains(cat)) {
      existingCategories.add(cat);
    }

    showDialog(
      context: context,
      builder: (_) => _AddGroceryProductDialog(
        storeId: storeId,
        existingCategories: existingCategories..sort(),
        groceryService: ref.read(groceryServiceProvider),
        onProductAdded: () {
          ref.invalidate(ownerGroceryProductsProvider(storeId));
          ref.invalidate(storeInventoryProvider(storeId));
        },
        aiPrefilled: aiPrefilled,
        initialName: clean(name),
        initialBrand: clean(brand),
        initialWeight: clean(weight),
        initialDescription: clean(description),
        initialCategory: cat,
        initialUnit: clean(unit),
        initialImage: image,
        initialImageUrl: imageUrl,
      ),
    );
  }

  /// Take/pick a product photo, identify it with AI, then open the add dialog
  /// pre-filled with the result and the captured photo.
  Future<void> _addFromPhoto(
    BuildContext context,
    WidgetRef ref,
    String storeId,
  ) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 82,
      );
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
      return;
    }
    if (picked == null || !context.mounted) return;
    final file = File(picked.path);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(
        title: 'Identifying product…',
        subtitle: 'Reading the photo with AI',
      ),
    );

    Map<String, dynamic>? result;
    Object? error;
    try {
      final bytes = await file.readAsBytes();
      result = await ref.read(groceryServiceProvider).identifyProduct(bytes);
    } catch (e) {
      error = e;
    }

    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return;

    if (error != null) {
      // Identification failed — still let the admin add manually with the photo.
      AppSnackbar.error(context, friendlyError(error));
      _openAddDialog(context, ref, storeId, image: file);
      return;
    }

    final r = result ?? const {};
    final identified = r['identified'] == true;
    final name = (r['name'] as String?)?.trim() ?? '';
    if (!identified) {
      final note = (r['notes'] as String?)?.trim();
      AppSnackbar.warning(
        context,
        (note != null && note.isNotEmpty)
            ? note
            : 'Couldn’t identify it — please fill in the details.',
      );
    }

    final aiDesc = (r['description'] as String?)?.trim() ?? '';
    final dims = (r['dimensions'] as String?)?.trim();
    final desc = [
      if (aiDesc.isNotEmpty) aiDesc,
      if (dims != null && dims.isNotEmpty && dims.toLowerCase() != 'null')
        'Dimensions: $dims',
    ].join('\n');

    // The raw snapshot is only for identification — offer real web catalogue
    // images to use as the product photo instead.
    String? webImageUrl;
    if (identified && name.isNotEmpty && context.mounted) {
      final chosen = await showModalBottomSheet<ProductImageResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _WebImageSearchSheet(
          query: name,
          service: ref.read(groceryServiceProvider),
        ),
      );
      if (chosen != null && context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _BusyDialog(
            title: 'Saving image…',
            subtitle: 'Importing the selected photo',
          ),
        );
        try {
          webImageUrl = await ref
              .read(groceryServiceProvider)
              .importProductImage(chosen.original, storeId);
        } catch (e) {
          if (context.mounted) AppSnackbar.error(context, friendlyError(e));
        }
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      }
    }
    if (!context.mounted) return;

    _openAddDialog(
      context,
      ref,
      storeId,
      // Use the imported web image if one was chosen, else the captured photo.
      image: webImageUrl == null ? file : null,
      imageUrl: webImageUrl,
      aiPrefilled: identified,
      name: r['name'] as String?,
      brand: r['brand'] as String?,
      weight: r['size'] as String?,
      description: desc.isEmpty ? null : desc,
      category: r['category'] as String?,
      unit: r['unit'] as String?,
    );
  }

  void _showInventorySheet(
    BuildContext context,
    WidgetRef ref,
    MenuItem product,
    String storeId,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InventorySheet(product: product, storeId: storeId),
    );
  }

  /// Open the scanner and link the scanned barcode / QR to [product].
  Future<void> _scanAndAssignBarcode(
    BuildContext context,
    WidgetRef ref,
    MenuItem product,
    String storeId, {
    bool replacing = false,
  }) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BarcodeScanScreen(
          title: replacing ? 'Rescan ${product.name}' : 'Scan ${product.name}',
          subtitle: 'Point at the product’s barcode or QR code',
        ),
      ),
    );
    if (code == null || !context.mounted) return;
    try {
      await ref.read(groceryServiceProvider).setProductBarcode(product.id, code);
      ref.invalidate(storeInventoryProvider(storeId));
      ref.invalidate(ownerGroceryProductsProvider(storeId));
      if (context.mounted) {
        AppSnackbar.success(context, 'Code linked to ${product.name}');
      }
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _removeBarcode(
    BuildContext context,
    WidgetRef ref,
    MenuItem product,
    String storeId,
  ) async {
    try {
      await ref.read(groceryServiceProvider).clearProductBarcode(product.id);
      ref.invalidate(storeInventoryProvider(storeId));
      ref.invalidate(ownerGroceryProductsProvider(storeId));
      if (context.mounted) {
        AppSnackbar.success(context, 'Code removed from ${product.name}');
      }
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _toggleStock(
    BuildContext context,
    WidgetRef ref,
    MenuItem product,
    String storeId,
  ) async {
    try {
      final service = ref.read(groceryServiceProvider);
      await service.updateStockStatus(product.id, !product.inStock);
      ref.invalidate(ownerGroceryProductsProvider(storeId));
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _toggleAvailability(
    BuildContext context,
    WidgetRef ref,
    MenuItem product,
    String storeId,
  ) async {
    try {
      final service = ref.read(groceryServiceProvider);
      await service.toggleAvailability(product.id, !product.isAvailable);
      ref.invalidate(ownerGroceryProductsProvider(storeId));
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String productId,
    String productName,
    String storeId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "$productName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final service = ref.read(groceryServiceProvider);
      await service.deleteGroceryProduct(productId);
      ref.invalidate(ownerGroceryProductsProvider(storeId));
      if (context.mounted) {
        AppSnackbar.success(context, '"$productName" deleted');
      }
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

// ── Product tile ────────────────────────────────────────────────────────────

class _GroceryProductTile extends StatelessWidget {
  final MenuItem product;
  final ProductInventory? inventory;
  final VoidCallback onScanBarcode;
  final VoidCallback onRemoveBarcode;
  final VoidCallback onManageStock;
  final VoidCallback onToggleStock;
  final VoidCallback onToggleAvailability;
  final VoidCallback onDelete;

  const _GroceryProductTile({
    required this.product,
    required this.inventory,
    required this.onScanBarcode,
    required this.onRemoveBarcode,
    required this.onManageStock,
    required this.onToggleStock,
    required this.onToggleAvailability,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final linked = inventory?.hasBarcode ?? false;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      // Tapping the product opens the scanner to link a barcode / QR code.
      child: InkWell(
        onTap: onScanBarcode,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                  ? Image.network(
                      product.imageUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${AppConstants.currencySymbol}${product.price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                          fontSize: 13,
                        ),
                      ),
                      if (product.brand != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          product.brand!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                      if (product.weight != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          product.weight!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatusChip(
                        label: product.isAvailable ? 'Available' : 'Hidden',
                        color: product.isAvailable ? Colors.green : Colors.grey,
                      ),
                      // When tracked, the live quantity chip replaces the plain
                      // in/out flag; untracked products keep the manual flag.
                      if (inventory?.trackInventory ?? false)
                        _StockChip(inventory: inventory!)
                      else
                        _StatusChip(
                          label: product.inStock ? 'In Stock' : 'Out of Stock',
                          color: product.inStock ? Colors.blue : Colors.red,
                        ),
                      // Barcode / QR link state.
                      _BarcodeChip(linked: linked),
                    ],
                  ),
                ],
              ),
            ),

            // Actions
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'scan':
                    onScanBarcode();
                    break;
                  case 'remove_code':
                    onRemoveBarcode();
                    break;
                  case 'inventory':
                    onManageStock();
                    break;
                  case 'stock':
                    onToggleStock();
                    break;
                  case 'availability':
                    onToggleAvailability();
                    break;
                  case 'delete':
                    onDelete();
                    break;
                }
              },
              icon: Icon(Icons.more_vert, color: Colors.grey[700]),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'scan',
                  child: Row(
                    children: [
                      Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 18,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(linked ? 'Rescan barcode / QR' : 'Scan barcode / QR'),
                    ],
                  ),
                ),
                if (linked)
                  const PopupMenuItem(
                    value: 'remove_code',
                    child: Row(
                      children: [
                        Icon(Icons.link_off, size: 18, color: Colors.grey),
                        SizedBox(width: 8),
                        Text('Remove code'),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'inventory',
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 18,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        (inventory?.trackInventory ?? false)
                            ? 'Manage stock'
                            : 'Track stock',
                      ),
                    ],
                  ),
                ),
                // Manual in/out toggle only for untracked products — when
                // tracking is on, in_stock is derived from the quantity.
                if (!(inventory?.trackInventory ?? false))
                  PopupMenuItem(
                    value: 'stock',
                    child: Row(
                      children: [
                        Icon(
                          product.inStock
                              ? Icons.remove_shopping_cart
                              : Icons.add_shopping_cart,
                          size: 18,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          product.inStock
                              ? 'Mark Out of Stock'
                              : 'Mark In Stock',
                        ),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'availability',
                  child: Row(
                    children: [
                      Icon(
                        product.isAvailable
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        product.isAvailable ? 'Hide Product' : 'Show Product',
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(Icons.shopping_bag_outlined, color: Colors.grey[300], size: 28),
  );
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Small chip showing whether a barcode / QR is linked to the product. Tapping
/// the tile scans one; this just signals the current state.
class _BarcodeChip extends StatelessWidget {
  final bool linked;
  const _BarcodeChip({required this.linked});

  @override
  Widget build(BuildContext context) {
    final color = linked ? const Color(0xFF6941C6) : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            linked ? Icons.qr_code_2 : Icons.qr_code_scanner_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            linked ? 'Code linked' : 'Tap to add code',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Blocking progress dialog with a title + subtitle.
class _BusyDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  const _BusyDialog({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add Product Dialog ──────────────────────────────────────────────────────

class _AddGroceryProductDialog extends StatefulWidget {
  final String storeId;
  final List<String> existingCategories;
  final GroceryService groceryService;
  final VoidCallback onProductAdded;

  // AI-identified prefills (all optional). When [aiPrefilled] is true the
  // dialog shows an "AI-identified" banner and pre-selects the photo.
  final bool aiPrefilled;
  final String? initialName;
  final String? initialBrand;
  final String? initialWeight;
  final String? initialDescription;
  final String? initialCategory;
  final String? initialUnit;
  final File? initialImage;
  final String? initialImageUrl; // already-hosted image (e.g. web-imported)

  const _AddGroceryProductDialog({
    required this.storeId,
    required this.existingCategories,
    required this.groceryService,
    required this.onProductAdded,
    this.aiPrefilled = false,
    this.initialName,
    this.initialBrand,
    this.initialWeight,
    this.initialDescription,
    this.initialCategory,
    this.initialUnit,
    this.initialImage,
    this.initialImageUrl,
  });

  @override
  State<_AddGroceryProductDialog> createState() =>
      _AddGroceryProductDialogState();
}

class _AddGroceryProductDialogState extends State<_AddGroceryProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _maxQtyCtrl = TextEditingController(text: '99');
  final _stockQtyCtrl = TextEditingController();

  String? _selectedCategory;
  String? _customCategory;
  String _selectedUnit = 'each';
  bool _saving = false;
  bool _importingImage = false;
  File? _imageFile;
  String? _selectedImageUrl; // already-hosted image chosen from the web
  String? _uploadedImageUrl;

  final _units = ['each', 'lb', 'kg', 'oz', 'pack', 'bottle', 'can', 'bag'];

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.initialName ?? '';
    _brandCtrl.text = widget.initialBrand ?? '';
    _weightCtrl.text = widget.initialWeight ?? '';
    _descCtrl.text = widget.initialDescription ?? '';
    _imageFile = widget.initialImage;
    _selectedImageUrl = widget.initialImageUrl;
    if (widget.initialUnit != null && _units.contains(widget.initialUnit)) {
      _selectedUnit = widget.initialUnit!;
    }
    // Pre-select the AI category only if it's one the store already uses;
    // otherwise leave it for the admin to pick / add as a custom category.
    final cat = widget.initialCategory?.trim();
    if (cat != null && cat.isNotEmpty && widget.existingCategories.contains(cat)) {
      _selectedCategory = cat;
    }
  }

  @override
  void dispose() {
    _stockQtyCtrl.dispose();
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _brandCtrl.dispose();
    _weightCtrl.dispose();
    _maxQtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() {
        _imageFile = File(picked.path);
        _selectedImageUrl = null; // a local photo replaces any web image
      });
    }
  }

  /// Search the web for a catalogue image and import the chosen one.
  Future<void> _searchWebImage() async {
    final q = _nameCtrl.text.trim();
    if (q.isEmpty) {
      AppSnackbar.info(context, 'Enter the product name first, then search');
      return;
    }
    final chosen = await showModalBottomSheet<ProductImageResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WebImageSearchSheet(
        query: q,
        service: widget.groceryService,
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _importingImage = true);
    try {
      final url = await widget.groceryService.importProductImage(
        chosen.original,
        widget.storeId,
      );
      setState(() {
        _selectedImageUrl = url;
        _imageFile = null;
      });
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _importingImage = false);
    }
  }

  Widget _imagePlaceholder() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(
        Icons.add_photo_alternate_outlined,
        size: 36,
        color: Colors.grey[700],
      ),
      const SizedBox(height: 4),
      Text(
        'Tap to add a photo, or use the buttons below',
        style: TextStyle(color: Colors.grey[700], fontSize: 13),
      ),
    ],
  );

  Future<String?> _uploadImage() async {
    // A web-imported image is already hosted — use it directly.
    if (_selectedImageUrl != null) return _selectedImageUrl;
    if (_imageFile == null) return null;
    try {
      final fileName =
          'grocery-products/${widget.storeId}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Supabase.instance.client.storage
          .from('profile-photos')
          .upload(fileName, _imageFile!);
      return Supabase.instance.client.storage
          .from('profile-photos')
          .getPublicUrl(fileName);
    } catch (e) {
      if (kDebugMode) debugPrint('Grocery image upload failed: $e');
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final category = _selectedCategory == '__custom__'
        ? (_customCategory ?? '').trim()
        : _selectedCategory ?? '';
    if (category.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a category')));
      return;
    }

    setState(() => _saving = true);

    try {
      _uploadedImageUrl = await _uploadImage();

      final created = await widget.groceryService.addGroceryProduct(
        storeId: widget.storeId,
        name: _nameCtrl.text.trim(),
        price: double.parse(_priceCtrl.text.trim()),
        category: category,
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        imageUrl: _uploadedImageUrl,
        unit: _selectedUnit,
        brand: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
        weight: _weightCtrl.text.trim().isEmpty
            ? null
            : _weightCtrl.text.trim(),
        maxQuantity: int.tryParse(_maxQtyCtrl.text) ?? 99,
      );

      // Seed starting stock (turns on inventory tracking for the product).
      final startQty = int.tryParse(_stockQtyCtrl.text.trim());
      if (created != null && startQty != null && startQty > 0) {
        try {
          await widget.groceryService.setInventory(created.id, startQty);
        } catch (_) {
          // Product was created; a stock-seed failure shouldn't block it.
        }
      }

      widget.onProductAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_grocery_store,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Add Grocery Product',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),

                if (widget.aiPrefilled) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6941C6).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF6941C6).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          size: 16,
                          color: Color(0xFF6941C6),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Filled in from the photo — check the details, then '
                            'set price & quantity.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Image preview
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: _importingImage
                        ? const Center(child: CircularProgressIndicator())
                        : _selectedImageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              _selectedImageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  _imagePlaceholder(),
                            ),
                          )
                        : _imageFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_imageFile!, fit: BoxFit.cover),
                          )
                        : _imagePlaceholder(),
                  ),
                ),
                const SizedBox(height: 8),
                // Image source buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _importingImage ? null : _searchWebImage,
                        icon: const Icon(Icons.travel_explore, size: 18),
                        label: const Text('Web image'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6941C6),
                          side: const BorderSide(color: Color(0xFF6941C6)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _importingImage ? null : _pickImage,
                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                        label: const Text('Gallery'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Name
                TextFormField(
                  controller: _nameCtrl,
                  decoration: _inputDecor('Product Name *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Price + Unit row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _priceCtrl,
                        decoration: _inputDecor('Price *'),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (double.tryParse(v) == null) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedUnit,
                        decoration: _inputDecor('Unit'),
                        items: _units
                            .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedUnit = v ?? 'each'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Brand + Weight row
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _brandCtrl,
                        decoration: _inputDecor('Brand'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _weightCtrl,
                        decoration: _inputDecor('Weight (e.g. 16 oz)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Category
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: _inputDecor('Category *'),
                  isExpanded: true,
                  items: [
                    ...widget.existingCategories.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                    const DropdownMenuItem(
                      value: '__custom__',
                      child: Text('+ Custom category'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedCategory = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                if (_selectedCategory == '__custom__') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: _inputDecor('Custom Category Name'),
                    onChanged: (v) => _customCategory = v,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ],
                const SizedBox(height: 12),

                // Description
                TextFormField(
                  controller: _descCtrl,
                  decoration: _inputDecor('Description (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                // Max quantity
                TextFormField(
                  controller: _maxQtyCtrl,
                  decoration: _inputDecor('Max Quantity per Order'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),

                // Starting stock — seeds inventory tracking for the product.
                TextFormField(
                  controller: _stockQtyCtrl,
                  decoration: _inputDecor('Starting stock quantity (optional)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter how many you have in stock to start tracking inventory. '
                  'Leave blank to add without tracking.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Add Product',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 13),
    filled: true,
    fillColor: Colors.grey[50],
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
    ),
  );
}

// ─── Delivery Settings Bottom Sheet ──────────────────────────────────────────

class _DeliverySettingsSheet extends ConsumerStatefulWidget {
  final Restaurant store;
  final VoidCallback onSaved;

  const _DeliverySettingsSheet({required this.store, required this.onSaved});

  @override
  ConsumerState<_DeliverySettingsSheet> createState() =>
      _DeliverySettingsSheetState();
}

class _DeliverySettingsSheetState
    extends ConsumerState<_DeliverySettingsSheet> {
  late TextEditingController _feeController;
  late double _estimatedTime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _feeController = TextEditingController(
      text: (widget.store.deliveryFee ?? 0).toStringAsFixed(2),
    );
    _estimatedTime = (widget.store.estimatedDeliveryTime ?? 30).toDouble();
  }

  @override
  void dispose() {
    _feeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final fee = double.tryParse(_feeController.text);
    if (fee == null || fee < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid delivery fee')),
      );
      return;
    }
    if (fee > 50000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery fee cannot exceed \$50,000')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final restaurantService = ref.read(restaurantServiceProvider);
      await restaurantService.updateRestaurant(
        restaurantId: widget.store.id,
        deliveryFee: fee,
        estimatedDeliveryTime: _estimatedTime.round(),
      );
      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              Icon(Icons.local_shipping, color: Colors.green[700]),
              const SizedBox(width: 10),
              const Text(
                'Delivery Settings',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Configure delivery fee and estimated delivery time for your grocery store.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          // Delivery Fee
          const Text(
            'Delivery Fee',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _feeController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: '\$ ',
              prefixStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              hintText: '0.00',
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Estimated Delivery Time
          const Text(
            'Estimated Delivery Time',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            '${_estimatedTime.round()} minutes',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.green[700],
            ),
          ),
          Slider(
            value: _estimatedTime,
            min: 10,
            max: 120,
            divisions: 22,
            activeColor: Colors.green[700],
            label: '${_estimatedTime.round()} min',
            onChanged: (v) => setState(() => _estimatedTime = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '10 min',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
              Text(
                '120 min',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Save Delivery Settings',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inventory: stock quantity chip ──────────────────────────────────────────

class _StockChip extends StatelessWidget {
  final ProductInventory inventory;
  const _StockChip({required this.inventory});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (inventory.isOut) {
      color = Colors.red;
      label = 'Out of stock';
    } else if (inventory.isLow) {
      color = const Color(0xFFB54708); // amber-700
      label = 'Low · ${inventory.stockQuantity} left';
    } else {
      color = const Color(0xFF067647); // green-700
      label = '${inventory.stockQuantity} in stock';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inventory: store-level low-stock banner ─────────────────────────────────

class _LowStockBanner extends StatelessWidget {
  final List<({MenuItem product, ProductInventory inv})> items;
  final void Function(MenuItem) onTapItem;
  const _LowStockBanner({required this.items, required this.onTapItem});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECDCA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFB42318),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${items.length} item${items.length == 1 ? '' : 's'} low on stock',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFFB42318),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...items.map(
            (it) => InkWell(
              onTap: () => onTapItem(it.product),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        it.product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      it.inv.isOut ? 'Out' : '${it.inv.stockQuantity} left',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: it.inv.isOut
                            ? Colors.red
                            : const Color(0xFFB54708),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Color(0xFFB42318),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inventory: manage-stock bottom sheet ────────────────────────────────────

class _InventorySheet extends ConsumerStatefulWidget {
  final MenuItem product;
  final String storeId;
  const _InventorySheet({required this.product, required this.storeId});

  @override
  ConsumerState<_InventorySheet> createState() => _InventorySheetState();
}

class _InventorySheetState extends ConsumerState<_InventorySheet> {
  final _qtyCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _thresholdCtrl = TextEditingController();
  String _mode = 'add'; // add | remove | set
  bool _busy = false;
  bool _thresholdInit = false;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(storeInventoryProvider(widget.storeId));
    ref.invalidate(ownerGroceryProductsProvider(widget.storeId));
    ref.invalidate(productMovementsProvider(widget.product.id));
  }

  Future<void> _apply() async {
    final raw = int.tryParse(_qtyCtrl.text.trim());
    if (raw == null || raw < 0) {
      AppSnackbar.error(context, 'Enter a valid quantity');
      return;
    }
    if ((_mode == 'add' || _mode == 'remove') && raw == 0) {
      AppSnackbar.error(context, 'Enter an amount greater than zero');
      return;
    }
    setState(() => _busy = true);
    final svc = ref.read(groceryServiceProvider);
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    try {
      switch (_mode) {
        case 'add':
          await svc.adjustInventory(
            widget.product.id,
            raw,
            reason: 'restock',
            note: note,
          );
          break;
        case 'remove':
          await svc.adjustInventory(
            widget.product.id,
            -raw,
            reason: 'waste',
            note: note,
          );
          break;
        case 'set':
          await svc.setInventory(widget.product.id, raw, note: note);
          break;
      }
      _refresh();
      _qtyCtrl.clear();
      _noteCtrl.clear();
      if (mounted) AppSnackbar.success(context, 'Stock updated');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveThreshold() async {
    final t = int.tryParse(_thresholdCtrl.text.trim());
    if (t == null || t < 0) {
      AppSnackbar.error(context, 'Enter a valid alert level');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(groceryServiceProvider)
          .setLowStockThreshold(widget.product.id, t);
      _refresh();
      if (mounted) AppSnackbar.success(context, 'Reorder alert saved');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopTracking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Stop tracking stock?'),
        content: Text(
          '"${widget.product.name}" will no longer count quantity. Its '
          'availability will fall back to the manual In Stock switch. You can '
          'turn tracking back on any time by restocking or setting a count.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop tracking'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(groceryServiceProvider)
          .stopTrackingInventory(widget.product.id);
      _refresh();
      if (mounted) {
        Navigator.of(context).pop();
        AppSnackbar.success(context, 'Tracking turned off');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MovementHistorySheet(
        productId: widget.product.id,
        productName: widget.product.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inv = ref
        .watch(storeInventoryProvider(widget.storeId))
        .valueOrNull?[widget.product.id];
    final tracked = inv?.trackInventory ?? false;
    final qty = inv?.stockQuantity ?? 0;
    if (!_thresholdInit && inv != null) {
      _thresholdCtrl.text = inv.lowStockThreshold.toString();
      _thresholdInit = true;
    }

    final Color qtyColor = !tracked
        ? Colors.grey
        : (inv!.isOut
              ? Colors.red
              : (inv.isLow ? const Color(0xFFB54708) : const Color(0xFF067647)));

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header: name + current on-hand
              Row(
                children: [
                  Icon(
                    Icons.inventory_2_rounded,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: qtyColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      tracked ? '$qty' : '—',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: qtyColor,
                      ),
                    ),
                    Text(
                      tracked
                          ? 'on hand${inv!.isOut
                                ? ' · out of stock'
                                : inv.isLow
                                ? ' · low'
                                : ''}'
                          : 'not tracked yet',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: qtyColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (!tracked) ...[
                const SizedBox(height: 10),
                Text(
                  'Adding stock or setting a count starts tracking this '
                  'product. Once tracked, orders decrement it automatically and '
                  'it can’t be oversold.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
                ),
              ],
              const SizedBox(height: 20),

              // Mode selector
              Row(
                children: [
                  _modeChip('add', 'Add', Icons.add),
                  const SizedBox(width: 8),
                  _modeChip('remove', 'Remove', Icons.remove),
                  const SizedBox(width: 8),
                  _modeChip('set', 'Set to', Icons.tune),
                ],
              ),
              const SizedBox(height: 12),

              // Quantity
              TextField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: _decor(
                  _mode == 'set' ? 'New count' : 'Quantity',
                  icon: Icons.numbers,
                ),
              ),
              const SizedBox(height: 12),

              // Optional note
              TextField(
                controller: _noteCtrl,
                decoration: _decor('Note (optional)', icon: Icons.notes),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Icon(
                          _mode == 'add'
                              ? Icons.add
                              : _mode == 'remove'
                              ? Icons.remove
                              : Icons.check,
                        ),
                  label: Text(
                    _mode == 'add'
                        ? 'Add stock'
                        : _mode == 'remove'
                        ? 'Remove stock'
                        : 'Set count',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Reorder alert threshold
              Text(
                'Reorder alert',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Flag this product as low when on-hand drops to or below:',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _thresholdCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _decor('Level'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : _saveThreshold,
                    child: const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Footer actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _showHistory,
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Movement history'),
                  ),
                  if (tracked)
                    TextButton(
                      onPressed: _busy ? null : _stopTracking,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                      ),
                      child: const Text('Stop tracking'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeChip(String value, String label, IconData icon) {
    final selected = _mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryColor.withValues(alpha: 0.12)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.primaryColor : Colors.grey[300]!,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppTheme.primaryColor : Colors.grey[700],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppTheme.primaryColor : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decor(String label, {IconData? icon}) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 13),
    prefixIcon: icon != null ? Icon(icon, size: 18) : null,
    isDense: true,
    filled: true,
    fillColor: Colors.grey[50],
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
    ),
  );
}

// ── Inventory: movement history bottom sheet ────────────────────────────────

class _MovementHistorySheet extends ConsumerWidget {
  final String productId;
  final String productName;
  const _MovementHistorySheet({
    required this.productId,
    required this.productName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movesAsync = ref.watch(productMovementsProvider(productId));
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Movement history',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: movesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => AppErrorState(
                  message: friendlyError(e),
                  onRetry: () => ref.invalidate(productMovementsProvider(productId)),
                ),
                data: (moves) {
                  if (moves.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No movements yet',
                      subtitle:
                          'Restocks, sales and adjustments will appear here.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: moves.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _MovementRow(move: moves[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  final InventoryMovement move;
  const _MovementRow({required this.move});

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final positive = move.change >= 0;
    final color = positive ? const Color(0xFF067647) : Colors.red;
    final d = move.createdAt.toLocal();
    final when =
        '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
    final IconData icon = switch (move.reason) {
      'restock' => Icons.add_box_outlined,
      'sale' => Icons.shopping_cart_outlined,
      'adjustment' => Icons.tune,
      'waste' => Icons.delete_outline,
      'stocktake' => Icons.fact_check_outlined,
      'order_restored' => Icons.undo,
      _ => Icons.swap_vert,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  move.reasonLabel,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  move.note?.isNotEmpty == true ? '${move.note} · $when' : when,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${positive ? '+' : ''}${move.change}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                '→ ${move.balanceAfter}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Web image search sheet ───────────────────────────────────────────────────

/// Shows real web catalogue images for a product name (via SerpAPI, server
/// side). Tapping one pops with that [ProductImageResult]; dismissing returns
/// null (keep the current / captured photo).
class _WebImageSearchSheet extends StatefulWidget {
  final String query;
  final GroceryService service;
  const _WebImageSearchSheet({required this.query, required this.service});

  @override
  State<_WebImageSearchSheet> createState() => _WebImageSearchSheetState();
}

class _WebImageSearchSheetState extends State<_WebImageSearchSheet> {
  late final TextEditingController _searchCtrl;
  bool _loading = true;
  String? _error;
  List<ProductImageResult> _images = const [];

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.query);
    _run(widget.query);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final imgs = await widget.service.searchProductImages(query);
      if (mounted) {
        setState(() {
          _images = imgs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  const Icon(Icons.travel_explore, color: Color(0xFF6941C6)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Choose a product image',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: _run,
                decoration: InputDecoration(
                  hintText: 'Search products',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey[100],
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward, size: 20),
                    onPressed: () => _run(_searchCtrl.text),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? AppErrorState(
                      message: _error!,
                      onRetry: () => _run(_searchCtrl.text),
                    )
                  : _images.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.image_search,
                      title: 'No images found',
                      subtitle: 'Try a different search term.',
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: _images.length,
                      itemBuilder: (_, i) {
                        final img = _images[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.of(context).pop(img),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.network(
                              img.thumbnail,
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, progress) =>
                                  progress == null
                                  ? child
                                  : const Center(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.broken_image_outlined,
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
