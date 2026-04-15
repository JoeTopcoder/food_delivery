import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/menu_model.dart';
import '../../models/restaurant_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/grocery_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/grocery_service.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import 'package:food_driver/config/app_constants.dart';

class GroceryManagementScreen extends ConsumerStatefulWidget {
  const GroceryManagementScreen({super.key});

  @override
  ConsumerState<GroceryManagementScreen> createState() =>
      _GroceryManagementScreenState();
}

class _GroceryManagementScreenState
    extends ConsumerState<GroceryManagementScreen> {
  @override
  Widget build(BuildContext context) {
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
                      child: const Icon(
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
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
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
            const Text(
              'Grocery Store',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
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
            cacheExtent: 500,
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            itemBuilder: (context, catIndex) {
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
                        const Icon(
                          Icons.category_rounded,
                          size: 16,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          category,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${items.length} items',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...items.map(
                    (item) => _GroceryProductTile(
                      product: item,
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

    showDialog(
      context: context,
      builder: (_) => _AddGroceryProductDialog(
        storeId: storeId,
        existingCategories: existingCategories..sort(),
        groceryService: ref.read(groceryServiceProvider),
        onProductAdded: () {
          ref.invalidate(ownerGroceryProductsProvider(storeId));
        },
      ),
    );
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
  final VoidCallback onToggleStock;
  final VoidCallback onToggleAvailability;
  final VoidCallback onDelete;

  const _GroceryProductTile({
    required this.product,
    required this.onToggleStock,
    required this.onToggleAvailability,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        style: const TextStyle(
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
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                      if (product.weight != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          product.weight!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _StatusChip(
                        label: product.isAvailable ? 'Available' : 'Hidden',
                        color: product.isAvailable ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      _StatusChip(
                        label: product.inStock ? 'In Stock' : 'Out of Stock',
                        color: product.inStock ? Colors.blue : Colors.red,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Actions
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
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
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              itemBuilder: (_) => [
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
                        product.inStock ? 'Mark Out of Stock' : 'Mark In Stock',
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

// ── Add Product Dialog ──────────────────────────────────────────────────────

class _AddGroceryProductDialog extends StatefulWidget {
  final String storeId;
  final List<String> existingCategories;
  final GroceryService groceryService;
  final VoidCallback onProductAdded;

  const _AddGroceryProductDialog({
    required this.storeId,
    required this.existingCategories,
    required this.groceryService,
    required this.onProductAdded,
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

  String? _selectedCategory;
  String? _customCategory;
  String _selectedUnit = 'each';
  bool _saving = false;
  File? _imageFile;
  String? _uploadedImageUrl;

  final _units = ['each', 'lb', 'kg', 'oz', 'pack', 'bottle', 'can', 'bag'];

  @override
  void dispose() {
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
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<String?> _uploadImage() async {
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
      debugPrint('Grocery image upload failed: $e');
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

      await widget.groceryService.addGroceryProduct(
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
                    const Icon(
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

                // Image picker
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: _imageFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_imageFile!, fit: BoxFit.cover),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 36,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap to add photo',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                  ),
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
      borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
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
                borderSide: const BorderSide(
                  color: AppTheme.primaryColor,
                  width: 2,
                ),
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
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              Text(
                '120 min',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
