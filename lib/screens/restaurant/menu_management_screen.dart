import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/menu_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/menu_service.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';

class MenuManagementScreen extends ConsumerStatefulWidget {
  const MenuManagementScreen({super.key});

  @override
  ConsumerState<MenuManagementScreen> createState() =>
      _MenuManagementScreenState();
}

class _MenuManagementScreenState extends ConsumerState<MenuManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);

    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to manage menu.')),
      );
    }

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(currentUserId));

    return restaurantAsync.when(
      loading: () => const Scaffold(
        body: AppLoadingIndicator(message: 'Loading restaurant...'),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Menu Management')),
        body: AppErrorState(
          message: friendlyError(error),
          onRetry: () =>
              ref.invalidate(restaurantByOwnerProvider(currentUserId)),
        ),
      ),
      data: (restaurant) {
        if (restaurant == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Menu Management')),
            body: const AppEmptyState(
              icon: Icons.storefront_rounded,
              title: 'No Restaurant Found',
              subtitle: 'No restaurant found for your account.',
            ),
          );
        }

        final menuAsync = ref.watch(restaurantMenuProvider(restaurant.id));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Menu Management'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.invalidate(restaurantMenuProvider(restaurant.id)),
              ),
            ],
          ),
          body: menuAsync.when(
            loading: () => const Center(
              child: AppLoadingIndicator(message: 'Loading menu...'),
            ),
            error: (error, _) => AppErrorState(
              message: friendlyError(error),
              onRetry: () =>
                  ref.invalidate(restaurantMenuProvider(restaurant.id)),
            ),
            data: (menuItems) {
              if (menuItems.isEmpty) {
                return AppEmptyState(
                  icon: Icons.restaurant_menu,
                  title: 'No menu items yet',
                  subtitle: 'Add your first menu item to get started.',
                  actionLabel: 'Add Menu Item',
                  onAction: () =>
                      _showAddMenuItemDialog(context, restaurant.id),
                );
              }

              // Group items by category
              final grouped = <String, List<MenuItem>>{};
              for (final item in menuItems) {
                grouped.putIfAbsent(item.category, () => []).add(item);
              }
              final categories = grouped.keys.toList();

              return ListView.builder(
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
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...items.map(
                        (item) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: item.isAvailable
                                  ? Colors.green.withValues(alpha: 0.2)
                                  : Colors.grey.withValues(alpha: 0.2),
                              child: Icon(
                                Icons.fastfood,
                                color: item.isAvailable
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                            title: Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${AppConstants.currencySymbol}${item.price.toStringAsFixed(2)}'),
                                if (item.discount != null && item.discount! > 0)
                                  Text(
                                    '${item.discount!.toStringAsFixed(0)}% off',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 12,
                                    ),
                                  ),
                                Text(
                                  item.isAvailable
                                      ? 'Available'
                                      : 'Unavailable',
                                  style: TextStyle(
                                    color: item.isAvailable
                                        ? Colors.green
                                        : Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                                if (item.sides != null &&
                                    item.sides!.isNotEmpty)
                                  Text(
                                    '${item.sides!.length} side(s)',
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    color: Colors.blue,
                                  ),
                                  tooltip: 'Manage Sides',
                                  onPressed: () => _showSidesDialog(
                                    context,
                                    item,
                                    restaurant.id,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _confirmDelete(
                                    context,
                                    item.id,
                                    item.name,
                                    restaurant.id,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddMenuItemDialog(context, restaurant.id),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  void _showSidesDialog(
    BuildContext context,
    MenuItem item,
    String restaurantId,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => _ManageSidesDialog(
        menuItem: item,
        menuService: ref.read(menuServiceProvider),
        onChanged: () => ref.invalidate(restaurantMenuProvider(restaurantId)),
      ),
    );
  }

  void _showAddMenuItemDialog(BuildContext context, String restaurantId) {
    // Collect existing categories from current menu
    final menuAsync = ref.read(restaurantMenuProvider(restaurantId));
    final existingCategories = <String>{};
    menuAsync.whenData((items) {
      for (final item in items) {
        existingCategories.add(item.category);
      }
    });

    showDialog(
      context: context,
      builder: (dialogContext) => _AddMenuItemDialog(
        restaurantId: restaurantId,
        existingCategories: existingCategories.toList()..sort(),
        onItemAdded: () {
          ref.invalidate(restaurantMenuProvider(restaurantId));
        },
        menuService: ref.read(menuServiceProvider),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    String menuItemId,
    String itemName,
    String restaurantId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Menu Item'),
        content: Text('Are you sure you want to delete "$itemName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final menuService = ref.read(menuServiceProvider);
        await menuService.deleteMenuItem(menuItemId);
        ref.invalidate(restaurantMenuProvider(restaurantId));

        if (context.mounted) {
          AppSnackbar.success(context, '"$itemName" deleted.');
        }
      } catch (e) {
        if (context.mounted) {
          AppSnackbar.error(context, friendlyError(e));
        }
      }
    }
  }
}

class _AddMenuItemDialog extends StatefulWidget {
  final String restaurantId;
  final VoidCallback onItemAdded;
  final MenuService menuService;
  final List<String> existingCategories;

  const _AddMenuItemDialog({
    required this.restaurantId,
    required this.onItemAdded,
    required this.menuService,
    this.existingCategories = const [],
  });

  @override
  State<_AddMenuItemDialog> createState() => _AddMenuItemDialogState();
}

class _AddMenuItemDialogState extends State<_AddMenuItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _categoryController = TextEditingController();
  String? _selectedCategory;
  bool _isNewCategory = false;
  double _discount = 0;
  bool _isAdding = false;
  File? _pickedImage;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  Future<String?> _uploadImage() async {
    if (_pickedImage == null) return null;
    final bytes = await _pickedImage!.readAsBytes();
    final fileName =
        'menu-items/${widget.restaurantId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await Supabase.instance.client.storage
        .from('profile-photos')
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return Supabase.instance.client.storage
        .from('profile-photos')
        .getPublicUrl(fileName);
  }

  Future<void> _addMenuItem() async {
    if (!_formKey.currentState!.validate()) return;

    final category = _isNewCategory
        ? _categoryController.text.trim()
        : _selectedCategory;
    if (category == null || category.isEmpty) return;

    setState(() => _isAdding = true);

    try {
      // Upload image if selected (non-blocking — item still saves without image)
      String? imageUrl;
      if (_pickedImage != null) {
        try {
          imageUrl = await _uploadImage();
        } catch (_) {
          // Image upload failed — continue without image
          debugPrint('Image upload failed, saving item without image');
        }
      }

      await widget.menuService.addMenuItem(
        restaurantId: widget.restaurantId,
        name: _nameController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        category: category,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        discount: _discount > 0 ? _discount : null,
        imageUrl: imageUrl,
      );

      widget.onItemAdded();

      if (mounted) {
        Navigator.of(context).pop();
        AppSnackbar.success(context, 'Menu item added!');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Menu Item'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Item Name',
                    prefixIcon: Icon(Icons.fastfood),
                  ),
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return 'Please enter item name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.description),
                  ),
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return 'Please enter price';
                    }
                    if (double.tryParse(value!) == null) {
                      return 'Please enter valid price';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                if (widget.existingCategories.isNotEmpty && !_isNewCategory)
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category),
                    ),
                    items: [
                      ...widget.existingCategories.map(
                        (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
                      ),
                      const DropdownMenuItem(
                        value: '__new__',
                        child: Text('+ New Category'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == '__new__') {
                        setState(() {
                          _isNewCategory = true;
                          _selectedCategory = null;
                        });
                      } else {
                        setState(() => _selectedCategory = value);
                      }
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select a category';
                      }
                      return null;
                    },
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _categoryController,
                          decoration: const InputDecoration(
                            labelText: 'New Category',
                            prefixIcon: Icon(Icons.category),
                          ),
                          validator: (value) {
                            if (_isNewCategory ||
                                widget.existingCategories.isEmpty) {
                              if (value?.isEmpty ?? true) {
                                return 'Please enter category';
                              }
                            }
                            return null;
                          },
                        ),
                      ),
                      if (widget.existingCategories.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Pick existing category',
                          onPressed: () {
                            setState(() {
                              _isNewCategory = false;
                              _categoryController.clear();
                            });
                          },
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                // Image picker
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
                    child: _pickedImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _pickedImage!,
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo_rounded,
                                size: 36,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 8),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        label: '${_discount.toStringAsFixed(0)}%',
                        value: _discount,
                        onChanged: (value) {
                          setState(() {
                            _discount = value;
                          });
                        },
                        min: 0,
                        max: 50,
                      ),
                    ),
                    Text('${_discount.toStringAsFixed(0)}%'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isAdding ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isAdding ? null : _addMenuItem,
          child: _isAdding
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}

class _ManageSidesDialog extends StatefulWidget {
  final MenuItem menuItem;
  final MenuService menuService;
  final VoidCallback onChanged;

  const _ManageSidesDialog({
    required this.menuItem,
    required this.menuService,
    required this.onChanged,
  });

  @override
  State<_ManageSidesDialog> createState() => _ManageSidesDialogState();
}

class _ManageSidesDialogState extends State<_ManageSidesDialog> {
  late List<MenuItemSide> _sides;
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _sides = List.from(widget.menuItem.sides ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _addSide() async {
    final name = _nameController.text.trim();
    final priceText = _priceController.text.trim();
    if (name.isEmpty || priceText.isEmpty) return;
    final price = double.tryParse(priceText);
    if (price == null) return;

    setState(() => _adding = true);
    try {
      final side = await widget.menuService.addSide(
        menuItemId: widget.menuItem.id,
        name: name,
        price: price,
      );
      setState(() {
        _sides.add(side);
        _nameController.clear();
        _priceController.clear();
      });
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _deleteSide(MenuItemSide side) async {
    try {
      await widget.menuService.deleteSide(side.id);
      setState(() => _sides.removeWhere((s) => s.id == side.id));
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Sides for ${widget.menuItem.name}'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_sides.isNotEmpty)
              ...(_sides.map(
                (side) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(side.name),
                  subtitle: Text('${AppConstants.currencySymbol}${side.price.toStringAsFixed(2)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                    onPressed: () => _deleteSide(side),
                  ),
                ),
              ))
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No sides yet'),
              ),
            const Divider(),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Side name',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Price',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _adding ? null : _addSide,
                icon: _adding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('Add Side'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
