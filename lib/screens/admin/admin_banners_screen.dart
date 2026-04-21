import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/supabase_config.dart';
import '../../models/banner_model.dart' as app;
import '../../providers/banner_provider.dart';
import '../../providers/grocery_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class AdminBannersScreen extends ConsumerStatefulWidget {
  const AdminBannersScreen({super.key});

  @override
  ConsumerState<AdminBannersScreen> createState() => _AdminBannersScreenState();
}

class _AdminBannersScreenState extends ConsumerState<AdminBannersScreen> {
  @override
  Widget build(BuildContext context) {
    final bannersAsync = ref.watch(allBannersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Manage Banners',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryColor,
        onPressed: () => _showBannerSheet(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: bannersAsync.when(
        loading: () => const AppLoadingIndicator(message: 'Loading banners...'),
        error: (e, _) => AppErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(allBannersProvider),
        ),
        data: (banners) {
          if (banners.isEmpty) {
            return const AppEmptyState(
              icon: Icons.campaign_outlined,
              title: 'No banners yet',
              subtitle: 'Tap + to create a promotional banner',
            );
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: banners.length,
            onReorder: (oldIndex, newIndex) =>
                _reorder(banners, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final banner = banners[index];
              return _BannerTile(
                key: ValueKey(banner.id),
                banner: banner,
                onEdit: () => _showBannerSheet(context, existing: banner),
                onToggle: () => _toggleActive(banner),
                onDelete: () => _deleteBanner(banner),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _reorder(
    List<app.Banner> banners,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex--;
    final list = List<app.Banner>.from(banners);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    // Update sort_order for all items
    for (int i = 0; i < list.length; i++) {
      await SupabaseConfig.client
          .from('banners')
          .update({'sort_order': i})
          .eq('id', list[i].id);
    }
    ref.invalidate(allBannersProvider);
    ref.invalidate(activeBannersProvider);
  }

  Future<void> _toggleActive(app.Banner banner) async {
    await SupabaseConfig.client
        .from('banners')
        .update({'is_active': !banner.isActive})
        .eq('id', banner.id);
    ref.invalidate(allBannersProvider);
    ref.invalidate(activeBannersProvider);
  }

  Future<void> _deleteBanner(app.Banner banner) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Banner?'),
        content: Text('Remove "${banner.title}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await SupabaseConfig.client.from('banners').delete().eq('id', banner.id);
    ref.invalidate(allBannersProvider);
    ref.invalidate(activeBannersProvider);
  }

  void _showBannerSheet(BuildContext context, {app.Banner? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _BannerForm(
        existing: existing,
        onSaved: () {
          ref.invalidate(allBannersProvider);
          ref.invalidate(activeBannersProvider);
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

// ─── Banner Tile ───────────────────────────────────────────────────────────────

class _BannerTile extends StatelessWidget {
  final app.Banner banner;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _BannerTile({
    super.key,
    required this.banner,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.campaign_rounded, color: AppTheme.primaryColor),
        ),
        title: Text(
          banner.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          banner.restaurantName ?? 'Unknown restaurant',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch.adaptive(
              value: banner.isActive,
              onChanged: (_) => onToggle(),
              activeTrackColor: AppTheme.primaryColor,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Banner Form (Create / Edit) ──────────────────────────────────────────────

class _BannerForm extends ConsumerStatefulWidget {
  final app.Banner? existing;
  final VoidCallback onSaved;

  const _BannerForm({this.existing, required this.onSaved});

  @override
  ConsumerState<_BannerForm> createState() => _BannerFormState();
}

class _BannerFormState extends ConsumerState<_BannerForm> {
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  String? _selectedRestaurantId;
  String _section = 'food'; // 'food' or 'grocery'
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _titleCtrl.text = widget.existing!.title;
      _subtitleCtrl.text = widget.existing!.subtitle ?? '';
      _imageUrlCtrl.text = widget.existing!.imageUrl ?? '';
      _selectedRestaurantId = widget.existing!.restaurantId;
      _section = widget.existing!.section;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _imageUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _selectedRestaurantId == null) {
      AppSnackbar.warning(context, 'Title and restaurant are required');
      return;
    }
    setState(() => _saving = true);
    try {
      final data = {
        'title': title,
        'subtitle': _subtitleCtrl.text.trim().isEmpty
            ? null
            : _subtitleCtrl.text.trim(),
        'image_url': _imageUrlCtrl.text.trim().isEmpty
            ? null
            : _imageUrlCtrl.text.trim(),
        'restaurant_id': _selectedRestaurantId,
        'section': _section,
      };

      if (widget.existing != null) {
        await SupabaseConfig.client
            .from('banners')
            .update(data)
            .eq('id', widget.existing!.id);
      } else {
        await SupabaseConfig.client.from('banners').insert(data);
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurantsAsync = ref.watch(allRestaurantsProvider);
    final groceryStoresAsync = ref.watch(groceryStoresProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing != null ? 'Edit Banner' : 'New Banner',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          // Section toggle
          Text(
            'Banner Section *',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'food',
                label: Text('Food'),
                icon: Icon(Icons.restaurant_menu),
              ),
              ButtonSegment(
                value: 'grocery',
                label: Text('Grocery'),
                icon: Icon(Icons.local_grocery_store),
              ),
            ],
            selected: {_section},
            onSelectionChanged: (sel) => setState(() {
              _section = sel.first;
              _selectedRestaurantId = null; // reset when section changes
            }),
          ),
          const SizedBox(height: 16),

          // Title
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Banner Title *',
              hintText: 'e.g. Free Delivery Weekend!',
            ),
          ),
          const SizedBox(height: 12),

          // Subtitle
          TextField(
            controller: _subtitleCtrl,
            decoration: const InputDecoration(
              labelText: 'Subtitle',
              hintText: 'e.g. Order now and save 20%',
            ),
          ),
          const SizedBox(height: 12),

          // Image URL
          TextField(
            controller: _imageUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'Image URL (optional)',
              hintText: 'https://...',
            ),
          ),
          const SizedBox(height: 12),

          // Store picker — swaps list based on section
          Text(
            _section == 'grocery'
                ? 'Link to Grocery Store *'
                : 'Link to Restaurant *',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          if (_section == 'grocery')
            groceryStoresAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(friendlyError(e)),
              data: (stores) => DropdownButtonFormField<String>(
                initialValue: _selectedRestaurantId,
                isExpanded: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                hint: const Text('Select a grocery store'),
                items: stores
                    .map(
                      (r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(r.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (id) => setState(() => _selectedRestaurantId = id),
              ),
            )
          else
            restaurantsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(friendlyError(e)),
              data: (restaurants) => DropdownButtonFormField<String>(
                initialValue: _selectedRestaurantId,
                isExpanded: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                hint: const Text('Select a restaurant'),
                items: restaurants
                    .map(
                      (r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(r.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (id) => setState(() => _selectedRestaurantId = id),
              ),
            ),
          const SizedBox(height: 20),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      widget.existing != null
                          ? 'Update Banner'
                          : 'Create Banner',
                      style: const TextStyle(
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
