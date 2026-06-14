import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../models/menu_model.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';
import '../../../config/app_constants.dart';

class WebMenuPage extends ConsumerWidget {
  const WebMenuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerId = ref.watch(currentUserIdProvider);
    if (ownerId == null) return const AppLoadingIndicator();

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(ownerId));

    return restaurantAsync.when(
      loading: () => const AppLoadingIndicator(message: 'Loading…'),
      error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(restaurantByOwnerProvider(ownerId))),
      data: (restaurant) {
        if (restaurant == null) {
          return const AppEmptyState(icon: Icons.storefront_rounded, title: 'No restaurant found');
        }
        return _MenuBody(restaurantId: restaurant.id);
      },
    );
  }
}

class _MenuBody extends ConsumerStatefulWidget {
  final String restaurantId;
  const _MenuBody({required this.restaurantId});

  @override
  ConsumerState<_MenuBody> createState() => _MenuBodyState();
}

class _MenuBodyState extends ConsumerState<_MenuBody> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(restaurantMenuManagementProvider(widget.restaurantId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
          child: Row(
            children: [
              const Text('Menu Management', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                onPressed: () => ref.invalidate(restaurantMenuManagementProvider(widget.restaurantId)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showAddDialog(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Item'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        // ── Search ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
          child: SizedBox(
            width: 360,
            child: TextField(
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search menu items…',
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // ── Grid ──────────────────────────────────────────────────────
        Expanded(
          child: menuAsync.when(
            loading: () => const AppLoadingIndicator(message: 'Loading menu…'),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(restaurantMenuManagementProvider(widget.restaurantId))),
            data: (items) {
              final filtered = _search.isEmpty
                  ? items
                  : items.where((i) => i.name.toLowerCase().contains(_search) || (i.description?.toLowerCase().contains(_search) ?? false)).toList();

              if (filtered.isEmpty) {
                return AppEmptyState(
                  icon: Icons.restaurant_menu_rounded,
                  title: _search.isEmpty ? 'No menu items yet' : 'No results for "$_search"',
                  subtitle: _search.isEmpty ? 'Tap "Add Item" to get started.' : null,
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.85,
                ),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _MenuItemCard(item: filtered[i], restaurantId: widget.restaurantId),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _MenuItemDialog(
        restaurantId: widget.restaurantId,
        onSaved: () => ref.invalidate(restaurantMenuManagementProvider(widget.restaurantId)),
      ),
    );
  }
}

// ─── Menu Item Card ───────────────────────────────────────────────────────────

class _MenuItemCard extends ConsumerStatefulWidget {
  final MenuItem item;
  final String restaurantId;
  const _MenuItemCard({required this.item, required this.restaurantId});

  @override
  ConsumerState<_MenuItemCard> createState() => _MenuItemCardState();
}

class _MenuItemCardState extends ConsumerState<_MenuItemCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasDiscount = item.discount != null && item.discount! > 0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hover ? 0.10 : 0.05),
              blurRadius: _hover ? 16 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                  ? Image.network(item.imageUrl!, height: 120, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (!item.isAvailable)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                            child: const Text('Off', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    if (item.description != null && item.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(item.description!, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          '${AppConstants.currencySymbol}${item.discountedPrice.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E293B)),
                        ),
                        if (hasDiscount) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${AppConstants.currencySymbol}${item.price.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), decoration: TextDecoration.lineThrough),
                          ),
                        ],
                        const Spacer(),
                        InkWell(
                          onTap: _showEditDialog,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.edit_rounded, size: 18, color: Colors.grey[400])),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: _confirmDelete,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red[300])),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    height: 120, width: double.infinity,
    color: const Color(0xFFF1F5F9),
    child: const Icon(Icons.fastfood_rounded, size: 40, color: Color(0xFFCBD5E1)),
  );

  void _showEditDialog() {
    showDialog(
      context: context,
      builder: (_) => _MenuItemDialog(
        restaurantId: widget.restaurantId,
        item: widget.item,
        onSaved: () => ref.invalidate(restaurantMenuManagementProvider(widget.restaurantId)),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Remove "${widget.item.name}" from the menu?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final svc = ref.read(menuServiceProvider);
      await svc.deleteMenuItem(widget.item.id);
      ref.invalidate(restaurantMenuManagementProvider(widget.restaurantId));
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

// ─── Add / Edit Dialog ────────────────────────────────────────────────────────

class _MenuItemDialog extends ConsumerStatefulWidget {
  final String restaurantId;
  final MenuItem? item;
  final VoidCallback onSaved;

  const _MenuItemDialog({required this.restaurantId, this.item, required this.onSaved});

  @override
  ConsumerState<_MenuItemDialog> createState() => _MenuItemDialogState();
}

class _MenuItemDialogState extends ConsumerState<_MenuItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _price;
  late final TextEditingController _category;
  late final TextEditingController _discount;
  bool _available = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _name = TextEditingController(text: i?.name ?? '');
    _desc = TextEditingController(text: i?.description ?? '');
    _price = TextEditingController(text: i != null ? i.price.toStringAsFixed(2) : '');
    _category = TextEditingController(text: i?.category ?? '');
    _discount = TextEditingController(text: i?.discount?.toString() ?? '');
    _available = i?.isAvailable ?? true;
  }

  @override
  void dispose() {
    _name.dispose(); _desc.dispose(); _price.dispose(); _category.dispose(); _discount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final svc = ref.read(menuServiceProvider);
      final price = double.parse(_price.text.trim());
      final discount = double.tryParse(_discount.text.trim());
      if (widget.item == null) {
        await svc.addMenuItem(
          restaurantId: widget.restaurantId,
          name: _name.text.trim(),
          price: price,
          category: _category.text.trim().isEmpty ? 'General' : _category.text.trim(),
          description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          discount: discount,
        );
      } else {
        await svc.updateMenuItem(
          menuItemId: widget.item!.id,
          name: _name.text.trim(),
          price: price,
          description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          isAvailable: _available,
          discount: discount,
        );
      }
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.item != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isEdit ? 'Edit Item' : 'Add Menu Item',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                const SizedBox(height: 20),
                _field(_name, 'Item Name *', validator: (v) => v!.isEmpty ? 'Required' : null),
                const SizedBox(height: 12),
                _field(_desc, 'Description'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _field(_price, 'Price *', keyboard: TextInputType.number, validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid' : null)),
                  const SizedBox(width: 12),
                  Expanded(child: _field(_discount, 'Discount %', keyboard: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                _field(_category, 'Category (e.g. Mains, Drinks)'),
                if (isEdit) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    const Text('Available', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                    const Spacer(),
                    Switch(value: _available, activeThumbColor: const Color(0xFF6366F1), onChanged: (v) => setState(() => _available = v)),
                  ]),
                ],
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF64748B), side: const BorderSide(color: Color(0xFFE2E8F0)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(isEdit ? 'Save Changes' : 'Add Item'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {TextInputType? keyboard, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.red)),
      ),
    );
  }
}
