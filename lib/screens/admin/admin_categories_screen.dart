import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../providers/feature_providers.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _foodCatsAdminProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('food_categories')
      .select()
      .order('sort_order');
  return List<Map<String, dynamic>>.from(rows as List);
});

final _groceryCatsAdminProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('grocery_categories')
      .select()
      .order('sort_order');
  return List<Map<String, dynamic>>.from(rows as List);
});

// ── Screen ────────────────────────────────────────────────────────────────────

class AdminCategoriesScreen extends ConsumerStatefulWidget {
  const AdminCategoriesScreen({super.key});

  @override
  ConsumerState<AdminCategoriesScreen> createState() =>
      _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState
    extends ConsumerState<AdminCategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(_foodCatsAdminProvider);
    ref.invalidate(_groceryCatsAdminProvider);
    ref.invalidate(foodCategoriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Food'),
            Tab(text: 'Grocery'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add category',
            onPressed: () => _showEditDialog(context, isFood: _tab.index == 0),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _CatList(
            provider: _foodCatsAdminProvider,
            isFood: true,
            onChanged: _refresh,
          ),
          _CatList(
            provider: _groceryCatsAdminProvider,
            isFood: false,
            onChanged: _refresh,
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, {required bool isFood, Map<String, dynamic>? row}) {
    showDialog(
      context: context,
      builder: (_) => _EditDialog(
        isFood: isFood,
        row: row,
        onSaved: _refresh,
      ),
    );
  }
}

// ── Category list ─────────────────────────────────────────────────────────────

class _CatList extends ConsumerWidget {
  const _CatList({
    required this.provider,
    required this.isFood,
    required this.onChanged,
  });

  final ProviderBase<AsyncValue<List<Map<String, dynamic>>>> provider;
  final bool isFood;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (cats) {
        if (cats.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.category_outlined, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text('No categories yet', style: TextStyle(color: Colors.grey[600])),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => _EditDialog(isFood: isFood, onSaved: onChanged),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add first category'),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: cats.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, i) {
            final cat = cats[i];
            final imageUrl = (cat['image_url'] as String?) ?? '';
            final emoji = (cat['emoji'] ?? cat['icon'] ?? '') as String;
            final name = cat['name'] as String;
            final isActive = (cat['is_active'] as bool?) ?? true;

            return ListTile(
              onTap: isFood
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _CategoryItemsScreen(
                            categoryName: name,
                            categoryEmoji: emoji,
                          ),
                        ),
                      ),
              leading: _CategoryThumb(imageUrl: imageUrl, emoji: emoji),
              title: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isActive ? null : Colors.grey,
                  decoration: isActive ? null : TextDecoration.lineThrough,
                ),
              ),
              subtitle: Row(
                children: [
                  if (imageUrl.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.image_not_supported_outlined,
                          size: 12, color: Colors.orange),
                    ),
                  Expanded(
                    child: Text(
                      '${isFood ? 'emoji' : 'icon'}: $emoji  •  sort: ${cat['sort_order'] ?? 0}  •  ${isActive ? 'Active' : 'Hidden'}'
                      '${imageUrl.isEmpty ? '  •  No image' : ''}',
                      style: TextStyle(
                          fontSize: 12,
                          color: imageUrl.isEmpty ? Colors.orange : null),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isFood)
                    IconButton(
                      icon: Icon(Icons.shopping_basket_rounded,
                          size: 20, color: AppTheme.primaryColor),
                      tooltip: 'Manage items',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _CategoryItemsScreen(
                            categoryName: name,
                            categoryEmoji: emoji,
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      isActive ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      size: 20,
                      color: isActive ? AppTheme.primaryColor : Colors.grey,
                    ),
                    tooltip: isActive ? 'Hide' : 'Show',
                    onPressed: () => _toggleActive(context, ref, cat, isFood),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 20),
                    tooltip: 'Edit',
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _EditDialog(
                        isFood: isFood,
                        row: cat,
                        onSaved: onChanged,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDelete(context, ref, cat, isFood),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> cat,
    bool isFood,
  ) async {
    final table = isFood ? 'food_categories' : 'grocery_categories';
    final newVal = !((cat['is_active'] as bool?) ?? true);
    try {
      await Supabase.instance.client
          .from(table)
          .update({'is_active': newVal})
          .eq('id', cat['id']);
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> cat,
    bool isFood,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('Delete "${cat['name']}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final table = isFood ? 'food_categories' : 'grocery_categories';
    try {
      await Supabase.instance.client.from(table).delete().eq('id', cat['id']);
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ── Thumbnail ─────────────────────────────────────────────────────────────────

class _CategoryThumb extends StatelessWidget {
  const _CategoryThumb({required this.imageUrl, required this.emoji});
  final String imageUrl;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  Center(child: Text(emoji.isEmpty ? '📷' : emoji, style: const TextStyle(fontSize: 22))),
            )
          : Center(child: Text(emoji.isEmpty ? '📷' : emoji, style: const TextStyle(fontSize: 22))),
    );
  }
}

// ── Edit / Add Dialog ─────────────────────────────────────────────────────────

class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.isFood,
    this.row,
    required this.onSaved,
  });

  final bool isFood;
  final Map<String, dynamic>? row;
  final VoidCallback onSaved;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _emoji;
  late final TextEditingController _imageUrl;
  late final TextEditingController _sortOrder;

  File? _pickedImage;
  bool _uploading = false;
  bool _saving = false;
  String _previewUrl = '';

  bool get _isEdit => widget.row != null;
  String get _table => widget.isFood ? 'food_categories' : 'grocery_categories';
  String get _emojiLabel => widget.isFood ? 'Emoji' : 'Icon emoji';

  @override
  void initState() {
    super.initState();
    final row = widget.row;
    _name = TextEditingController(text: row?['name'] as String? ?? '');
    _emoji = TextEditingController(
      text: (row?['emoji'] ?? row?['icon'] ?? '') as String,
    );
    _previewUrl = (row?['image_url'] as String?) ?? '';
    _imageUrl = TextEditingController(text: _previewUrl);
    _sortOrder = TextEditingController(
      text: (row?['sort_order'] as int? ?? 0).toString(),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    _imageUrl.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 400,
      maxHeight: 400,
    );
    if (picked != null && mounted) {
      setState(() {
        _pickedImage = File(picked.path);
        _previewUrl = picked.path;
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_pickedImage == null) return _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim();
    setState(() => _uploading = true);
    try {
      final bytes = await _pickedImage!.readAsBytes();
      final catName = _name.text.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
      final fileName = 'cat_${catName}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Supabase.instance.client.storage
          .from('category-images')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      return Supabase.instance.client.storage
          .from('category-images')
          .getPublicUrl(fileName);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final uploadedUrl = await _uploadImage();

      final data = <String, dynamic>{
        'name': name,
        'sort_order': int.tryParse(_sortOrder.text) ?? 0,
        if (uploadedUrl != null) 'image_url': uploadedUrl,
      };

      // food_categories uses 'emoji'; grocery_categories uses 'icon'
      if (widget.isFood) {
        data['emoji'] = _emoji.text.trim();
      } else {
        data['icon'] = _emoji.text.trim();
      }

      if (_isEdit) {
        await Supabase.instance.client
            .from(_table)
            .update(data)
            .eq('id', widget.row!['id']);
      } else {
        data['is_active'] = true;
        await Supabase.instance.client.from(_table).insert(data);
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit category' : 'Add category'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image preview + pick
            Center(
              child: GestureDetector(
                onTap: _uploading ? null : _pickImage,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildImagePreview(),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: _uploading ? null : _pickImage,
                icon: const Icon(Icons.photo_library_rounded, size: 16),
                label: const Text('Pick from gallery'),
              ),
            ),
            const SizedBox(height: 4),
            // OR paste URL
            TextField(
              controller: _imageUrl,
              decoration: const InputDecoration(
                labelText: 'Or paste image URL',
                hintText: 'https://images.unsplash.com/...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() {
                _pickedImage = null;
                _previewUrl = v.trim();
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emoji,
              decoration: InputDecoration(
                labelText: _emojiLabel,
                hintText: '🍔',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sortOrder,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sort order',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _uploading) ? null : _save,
          child: (_saving || _uploading)
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    if (_pickedImage != null) {
      return Image.file(_pickedImage!, fit: BoxFit.cover);
    }
    if (_previewUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: _previewUrl,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined, size: 28, color: Colors.grey[500]),
        const SizedBox(height: 4),
        Text('Tap to add', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Grocery Items Screen — lists all products in a category across all stores
// ══════════════════════════════════════════════════════════════════════════════

final _categoryItemsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, categoryName) async {
  final rows = await Supabase.instance.client
      .from('menus')
      .select('*, restaurants(name)')
      .eq('product_type', 'grocery')
      .eq('category', categoryName)
      .order('name');
  return List<Map<String, dynamic>>.from(rows as List);
});

final _groceryStoresProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('restaurants')
      .select('id, name')
      .inFilter('store_type', ['grocery', 'both'])
      .eq('is_verified', true)
      .order('name');
  return List<Map<String, dynamic>>.from(rows as List);
});

class _CategoryItemsScreen extends ConsumerWidget {
  const _CategoryItemsScreen({
    required this.categoryName,
    required this.categoryEmoji,
  });

  final String categoryName;
  final String categoryEmoji;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(_categoryItemsProvider(categoryName));

    return Scaffold(
      appBar: AppBar(
        title: Text('$categoryEmoji  $categoryName',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add item',
            onPressed: () => _showItemDialog(context, ref),
          ),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_basket_outlined,
                      size: 56, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text('No items in $categoryName yet',
                      style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showItemDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Add first item'),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              final item = items[i];
              final imgUrl = (item['image_url'] as String?) ?? '';
              final inStock = (item['in_stock'] as bool?) ?? true;
              final storeName =
                  (item['restaurants'] as Map?)?['name'] as String? ?? '—';

              return ListTile(
                leading: _CategoryThumb(imageUrl: imgUrl, emoji: categoryEmoji),
                title: Text(item['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '\$${(item['price'] as num).toStringAsFixed(2)}  •  $storeName'
                  '${item['brand'] != null ? '  •  ${item['brand']}' : ''}'
                  '${item['unit'] != null ? '  •  ${item['unit']}' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // In-stock toggle
                    GestureDetector(
                      onTap: () async {
                        await Supabase.instance.client
                            .from('menus')
                            .update({'in_stock': !inStock})
                            .eq('id', item['id']);
                        ref.invalidate(_categoryItemsProvider(categoryName));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: inStock
                              ? const Color(0xFF10B981).withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          inStock ? 'In stock' : 'Out',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: inStock
                                ? const Color(0xFF10B981)
                                : Colors.red,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, size: 20),
                      onPressed: () => _showItemDialog(context, ref, row: item),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 20, color: Colors.red),
                      onPressed: () =>
                          _confirmDelete(context, ref, item),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showItemDialog(BuildContext context, WidgetRef ref,
      {Map<String, dynamic>? row}) {
    showDialog(
      context: context,
      builder: (_) => _ItemEditDialog(
        categoryName: categoryName,
        row: row,
        onSaved: () => ref.invalidate(_categoryItemsProvider(categoryName)),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Delete "${item['name']}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Supabase.instance.client
        .from('menus')
        .delete()
        .eq('id', item['id']);
    ref.invalidate(_categoryItemsProvider(categoryName));
  }
}

// ── Item edit / add dialog ────────────────────────────────────────────────────

class _ItemEditDialog extends ConsumerStatefulWidget {
  const _ItemEditDialog({
    required this.categoryName,
    this.row,
    required this.onSaved,
  });

  final String categoryName;
  final Map<String, dynamic>? row;
  final VoidCallback onSaved;

  @override
  ConsumerState<_ItemEditDialog> createState() => _ItemEditDialogState();
}

class _ItemEditDialogState extends ConsumerState<_ItemEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _description;
  late final TextEditingController _brand;
  late final TextEditingController _unit;
  late final TextEditingController _weight;
  late final TextEditingController _imageUrl;

  String? _selectedStoreId;
  File? _pickedImage;
  String _previewUrl = '';
  bool _inStock = true;
  bool _saving = false;
  bool _uploading = false;

  bool get _isEdit => widget.row != null;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _name = TextEditingController(text: r?['name'] as String? ?? '');
    _price = TextEditingController(
        text: r != null ? (r['price'] as num).toStringAsFixed(2) : '');
    _description =
        TextEditingController(text: r?['description'] as String? ?? '');
    _brand = TextEditingController(text: r?['brand'] as String? ?? '');
    _unit = TextEditingController(text: r?['unit'] as String? ?? '');
    _weight = TextEditingController(text: r?['weight'] as String? ?? '');
    _previewUrl = (r?['image_url'] as String?) ?? '';
    _imageUrl = TextEditingController(text: _previewUrl);
    _inStock = (r?['in_stock'] as bool?) ?? true;
    _selectedStoreId = r?['restaurant_id'] as String?;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _description.dispose();
    _brand.dispose();
    _unit.dispose();
    _weight.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 600,
      maxHeight: 600,
    );
    if (picked != null && mounted) {
      setState(() {
        _pickedImage = File(picked.path);
        _previewUrl = picked.path;
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_pickedImage == null) {
      return _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim();
    }
    setState(() => _uploading = true);
    try {
      final bytes = await _pickedImage!.readAsBytes();
      final slug = _name.text
          .trim()
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
          .toLowerCase();
      final fileName = 'grocery_${slug}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Supabase.instance.client.storage
          .from('category-images')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions:
                const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      return Supabase.instance.client.storage
          .from('category-images')
          .getPublicUrl(fileName);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final priceVal = double.tryParse(_price.text.trim());
    if (name.isEmpty || priceVal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and valid price are required')),
      );
      return;
    }
    if (!_isEdit && _selectedStoreId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a store')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final uploadedUrl = await _uploadImage();
      final data = <String, dynamic>{
        'name': name,
        'price': priceVal,
        'category': widget.categoryName,
        'product_type': 'grocery',
        'in_stock': _inStock,
        'is_available': true,
        if (_description.text.trim().isNotEmpty)
          'description': _description.text.trim(),
        if (_brand.text.trim().isNotEmpty) 'brand': _brand.text.trim(),
        if (_unit.text.trim().isNotEmpty) 'unit': _unit.text.trim(),
        if (_weight.text.trim().isNotEmpty) 'weight': _weight.text.trim(),
        if (uploadedUrl != null) 'image_url': uploadedUrl,
      };

      if (_isEdit) {
        await Supabase.instance.client
            .from('menus')
            .update(data)
            .eq('id', widget.row!['id']);
      } else {
        data['restaurant_id'] = _selectedStoreId!;
        await Supabase.instance.client.from('menus').insert(data);
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storesAsync = ref.watch(_groceryStoresProvider);

    return AlertDialog(
      title: Text(_isEdit ? 'Edit item' : 'Add item to ${widget.categoryName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Center(
              child: GestureDetector(
                onTap: _uploading ? null : _pickImage,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.3)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildPreview(),
                ),
              ),
            ),
            Center(
              child: TextButton.icon(
                onPressed: _uploading ? null : _pickImage,
                icon: const Icon(Icons.photo_library_rounded, size: 16),
                label: const Text('Pick image'),
              ),
            ),
            TextField(
              controller: _imageUrl,
              decoration: const InputDecoration(
                labelText: 'Or paste image URL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() {
                _pickedImage = null;
                _previewUrl = v.trim();
              }),
            ),
            const SizedBox(height: 12),

            // Store picker (add mode only)
            if (!_isEdit) ...[
              storesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(friendlyError(e),
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
                data: (stores) => InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Store *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButton<String>(
                    value: _selectedStoreId,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    hint: const Text('Select store'),
                    items: stores
                        .map((s) => DropdownMenuItem(
                              value: s['id'] as String,
                              child: Text(s['name'] as String),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedStoreId = v),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price *',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _brand,
                    decoration: const InputDecoration(
                      labelText: 'Brand',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(
                      labelText: 'Unit (lb, kg…)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _weight,
              decoration: const InputDecoration(
                labelText: 'Weight / size (e.g. 500g)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              value: _inStock,
              onChanged: (v) => setState(() => _inStock = v),
              title: const Text('In stock', style: TextStyle(fontSize: 14)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _uploading) ? null : _save,
          child: (_saving || _uploading)
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(_isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    if (_pickedImage != null) {
      return Image.file(_pickedImage!, fit: BoxFit.cover);
    }
    if (_previewUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: _previewUrl,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 24, color: Colors.grey[500]),
          Text('Add photo',
              style: TextStyle(fontSize: 9, color: Colors.grey[500])),
        ],
      );
}
