import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
            onReorderItem: (oldIndex, newIndex) =>
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

  Widget _fallbackIcon() => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.campaign_rounded, color: AppTheme.primaryColor),
      );

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
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: banner.imageUrl != null && banner.imageUrl!.isNotEmpty
              ? Image.network(
                  banner.imageUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallbackIcon(),
                )
              : _fallbackIcon(),
        ),
        title: Text(
          banner.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                banner.restaurantName ?? 'Unknown restaurant',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (banner.discountType != null && banner.discountValue != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  banner.discountType == 'percentage'
                      ? '${banner.discountValue!.toStringAsFixed(banner.discountValue! % 1 == 0 ? 0 : 2)}% off'
                      : '\$${banner.discountValue!.toStringAsFixed(banner.discountValue! % 1 == 0 ? 0 : 2)} off',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF16A34A)),
                ),
              ),
            ],
          ],
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
  final _titleCtrl    = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  String? _selectedRestaurantId;
  String  _section = 'food';
  bool    _saving  = false;

  // Image state
  File?   _pickedImage;
  String? _existingImageUrl;
  bool    _uploadingImage = false;

  // Discount state — null discountType means "no discount attached"
  String? _discountType;
  final _discountValueCtrl = TextEditingController();
  String  _appliesTo = 'subtotal';
  String? _existingPromoCode;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _titleCtrl.text           = widget.existing!.title;
      _subtitleCtrl.text        = widget.existing!.subtitle ?? '';
      _existingImageUrl         = widget.existing!.imageUrl;
      _selectedRestaurantId     = widget.existing!.restaurantId;
      _section                  = widget.existing!.section;
      _discountType             = widget.existing!.discountType;
      _discountValueCtrl.text   = widget.existing!.discountValue != null
          ? _stripTrailingZeros(widget.existing!.discountValue!)
          : '';
      _appliesTo                = widget.existing!.appliesTo ?? 'subtotal';
      _existingPromoCode        = widget.existing!.promoCode;
    }
  }

  String _stripTrailingZeros(double value) {
    return value == value.roundToDouble() ? value.toInt().toString() : value.toString();
  }

  Future<String> _generateUniqueBannerCode() async {
    final rand = Random();
    for (var attempt = 0; attempt < 5; attempt++) {
      final suffix = List.generate(5, (_) => rand.nextInt(36).toRadixString(36)).join().toUpperCase();
      final candidate = 'BANNER$suffix';
      final existing = await SupabaseConfig.client
          .from('promo_codes')
          .select('id')
          .eq('code', candidate)
          .maybeSingle();
      if (existing == null) return candidate;
    }
    return 'BANNER${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _discountValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (picked != null && mounted) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  Future<String?> _uploadImageIfNeeded() async {
    if (_pickedImage == null) return _existingImageUrl;
    setState(() => _uploadingImage = true);
    try {
      final bytes    = await _pickedImage!.readAsBytes();
      final fileName = 'banner_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Supabase.instance.client.storage
          .from('banners')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      return Supabase.instance.client.storage
          .from('banners')
          .getPublicUrl(fileName);
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Widget _imagePlaceholder(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey[600]),
        const SizedBox(height: 8),
        Text(
          'Tap to add banner image',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ],
    );
  }

  /// Creates or updates the promo_codes row this banner's discount is backed
  /// by, so tapping the banner has a real code to auto-apply — not just a
  /// number shown on an image. Reuses the existing code across edits so a
  /// customer who's already seen/shared it keeps working; only mints a new
  /// one the first time a discount is set. Returns the code to store on the
  /// banner, or null if no discount is set (deactivating any old code).
  Future<String?> _syncPromoCode(String title) async {
    if (_discountType == null) {
      if (_existingPromoCode != null) {
        await SupabaseConfig.client
            .from('promo_codes')
            .update({'is_active': false})
            .eq('code', _existingPromoCode!);
      }
      return null;
    }

    final value = double.tryParse(_discountValueCtrl.text.trim());
    if (value == null || value <= 0) {
      throw Exception('Enter a valid discount value');
    }
    if (_discountType == 'percentage' && value > 100) {
      throw Exception('Percentage discount cannot exceed 100');
    }

    if (_existingPromoCode != null) {
      await SupabaseConfig.client
          .from('promo_codes')
          .update({
            'discount_type': _discountType,
            'discount_value': value,
            'applies_to': _appliesTo,
            'restaurant_id': _selectedRestaurantId,
            'is_active': true,
          })
          .eq('code', _existingPromoCode!);
      return _existingPromoCode;
    }

    final code = await _generateUniqueBannerCode();
    await SupabaseConfig.client.from('promo_codes').insert({
      'code': code,
      'description': 'Banner promotion — $title',
      'discount_type': _discountType,
      'discount_value': value,
      'applies_to': _appliesTo,
      'restaurant_id': _selectedRestaurantId,
      'max_uses': null,
      'usage_count': 0,
      'is_active': true,
    });
    return code;
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _selectedRestaurantId == null) {
      AppSnackbar.warning(context, 'Title and restaurant are required');
      return;
    }
    setState(() => _saving = true);
    try {
      final imageUrl = await _uploadImageIfNeeded();
      final promoCode = await _syncPromoCode(title);
      final data = {
        'title': title,
        'subtitle': _subtitleCtrl.text.trim().isEmpty
            ? null
            : _subtitleCtrl.text.trim(),
        'image_url': imageUrl,
        'restaurant_id': _selectedRestaurantId,
        'section': _section,
        'discount_type': _discountType,
        'discount_value': _discountType != null ? double.tryParse(_discountValueCtrl.text.trim()) : null,
        'applies_to': _discountType != null ? _appliesTo : null,
        'promo_code': promoCode,
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

    return SingleChildScrollView(
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
          const SizedBox(height: 16),

          // Discount toggle — attaches a real promo code, auto-applied when
          // a customer taps this banner.
          Text(
            'Discount (optional)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String?>(
            segments: const [
              ButtonSegment(value: null, label: Text('None')),
              ButtonSegment(value: 'percentage', label: Text('% off')),
              ButtonSegment(value: 'fixed', label: Text('\$ off')),
            ],
            selected: {_discountType},
            onSelectionChanged: (sel) => setState(() => _discountType = sel.first),
          ),
          if (_discountType != null) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _discountValueCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _discountType == 'percentage' ? 'Percent off *' : 'Amount off (\$) *',
                hintText: _discountType == 'percentage' ? 'e.g. 15' : 'e.g. 5',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Applies to *',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _appliesTo,
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: const [
                DropdownMenuItem(value: 'subtotal', child: Text('The meal (food subtotal)')),
                DropdownMenuItem(value: 'delivery_fee', child: Text('Delivery fee')),
                DropdownMenuItem(value: 'total', child: Text('Entire order total')),
              ],
              onChanged: (v) => setState(() => _appliesTo = v ?? 'subtotal'),
            ),
            const SizedBox(height: 6),
            Text(
              'Tapping this banner automatically applies this discount for the customer — no code to type in.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 12),

          // Banner image picker
          GestureDetector(
            onTap: _uploadingImage ? null : _pickImage,
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _uploadingImage
                  ? const Center(child: CircularProgressIndicator())
                  : _pickedImage != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(_pickedImage!, fit: BoxFit.cover),
                            Positioned(
                              top: 8, right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Tap to change', style: TextStyle(color: Colors.white, fontSize: 11)),
                              ),
                            ),
                          ],
                        )
                      : _existingImageUrl != null && _existingImageUrl!.isNotEmpty
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(_existingImageUrl!, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _imagePlaceholder(context)),
                                Positioned(
                                  top: 8, right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('Tap to change', style: TextStyle(color: Colors.white, fontSize: 11)),
                                  ),
                                ),
                              ],
                            )
                          : _imagePlaceholder(context),
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
