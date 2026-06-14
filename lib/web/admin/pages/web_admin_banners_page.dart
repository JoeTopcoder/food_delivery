import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../models/banner_model.dart' as app;
import '../../../providers/banner_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

class WebAdminBannersPage extends ConsumerWidget {
  const WebAdminBannersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bannersAsync = ref.watch(allBannersProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Banners', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Manage promotional banners shown on the home screen', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () => ref.invalidate(allBannersProvider)),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                label: const Text('New Banner', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => _showBannerDialog(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 28),

          bannersAsync.when(
            loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(allBannersProvider)),
            data: (banners) {
              if (banners.isEmpty) {
                return Container(
                  height: 200,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const AppEmptyState(icon: Icons.campaign_outlined, title: 'No banners yet', subtitle: 'Create a promotional banner'),
                );
              }
              return Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))]),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
                      child: const Row(children: [
                        SizedBox(width: 60, child: Text('IMG', style: _h)),
                        SizedBox(width: 200, child: Text('TITLE', style: _h)),
                        SizedBox(width: 160, child: Text('RESTAURANT', style: _h)),
                        SizedBox(width: 100, child: Text('SECTION', style: _h)),
                        SizedBox(width: 80, child: Text('ORDER', style: _h)),
                        SizedBox(width: 90, child: Text('STATUS', style: _h)),
                        Expanded(child: Text('ACTIONS', style: _h, textAlign: TextAlign.right)),
                      ]),
                    ),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: banners.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      itemBuilder: (_, i) => _BannerRow(
                        banner: banners[i],
                        onEdit: () => _showBannerDialog(context, ref, existing: banners[i]),
                        onToggle: () => _toggle(ref, banners[i]),
                        onDelete: () => _delete(context, ref, banners[i]),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(WidgetRef ref, app.Banner banner) async {
    await SupabaseConfig.client.from('banners').update({'is_active': !banner.isActive}).eq('id', banner.id);
    ref.invalidate(allBannersProvider);
    ref.invalidate(activeBannersProvider);
  }

  Future<void> _delete(BuildContext ctx, WidgetRef ref, app.Banner banner) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Banner?'),
        content: Text('Remove "${banner.title}" permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await SupabaseConfig.client.from('banners').delete().eq('id', banner.id);
      ref.invalidate(allBannersProvider);
      ref.invalidate(activeBannersProvider);
    }
  }

  void _showBannerDialog(BuildContext ctx, WidgetRef ref, {app.Banner? existing}) {
    showDialog(
      context: ctx,
      builder: (_) => _BannerDialog(
        existing: existing,
        onSaved: () {
          ref.invalidate(allBannersProvider);
          ref.invalidate(activeBannersProvider);
        },
      ),
    );
  }

  static const _h = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5);
}

// ── Banner Row ────────────────────────────────────────────────────────────────

class _BannerRow extends StatelessWidget {
  final app.Banner banner;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  const _BannerRow({required this.banner, required this.onEdit, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: banner.imageUrl != null && banner.imageUrl!.isNotEmpty
                ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(banner.imageUrl!, width: 48, height: 36, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback()))
                : _fallback(),
          ),
          SizedBox(width: 200, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(banner.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
            if (banner.subtitle != null) Text(banner.subtitle!, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ])),
          SizedBox(width: 160, child: Text(banner.restaurantName ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF374151)))),
          SizedBox(
            width: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
              child: Text(banner.section.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
            ),
          ),
          SizedBox(width: 80, child: Text('#${banner.sortOrder + 1}', style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))),
          SizedBox(
            width: 90,
            child: Switch.adaptive(
              value: banner.isActive,
              onChanged: (_) => onToggle(),
              activeTrackColor: AppTheme.primaryColor,
            ),
          ),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              IconButton(icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF6366F1)), onPressed: onEdit),
              IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red), onPressed: onDelete),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _fallback() => Container(
    width: 48, height: 36,
    decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
    child: Icon(Icons.campaign_rounded, color: AppTheme.primaryColor, size: 20),
  );
}

// ── Banner Dialog ─────────────────────────────────────────────────────────────

class _BannerDialog extends ConsumerStatefulWidget {
  final app.Banner? existing;
  final VoidCallback onSaved;
  const _BannerDialog({this.existing, required this.onSaved});

  @override
  ConsumerState<_BannerDialog> createState() => _BannerDialogState();
}

class _BannerDialogState extends ConsumerState<_BannerDialog> {
  final _titleCtrl    = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _imageCtrl    = TextEditingController();
  String? _selectedRestaurantId;
  String  _section = 'food';
  bool    _saving  = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _titleCtrl.text       = widget.existing!.title;
      _subtitleCtrl.text    = widget.existing!.subtitle ?? '';
      _imageCtrl.text       = widget.existing!.imageUrl ?? '';
      _selectedRestaurantId = widget.existing!.restaurantId;
      _section              = widget.existing!.section;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose(); _subtitleCtrl.dispose(); _imageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final data = {
        'title': _titleCtrl.text.trim(),
        'subtitle': _subtitleCtrl.text.trim().isEmpty ? null : _subtitleCtrl.text.trim(),
        'image_url': _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
        'restaurant_id': _selectedRestaurantId,
        'section': _section,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (widget.existing != null) {
        await Supabase.instance.client.from('banners').update(data).eq('id', widget.existing!.id);
      } else {
        await Supabase.instance.client.from('banners').insert({...data, 'sort_order': 0, 'created_at': DateTime.now().toIso8601String()});
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurantsAsync = ref.watch(allRestaurantsProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 500,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(widget.existing != null ? 'Edit Banner' : 'New Banner', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 16),
              TextFormField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title *', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextFormField(controller: _subtitleCtrl, decoration: const InputDecoration(labelText: 'Subtitle (optional)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextFormField(controller: _imageCtrl, decoration: const InputDecoration(labelText: 'Image URL (optional)', border: OutlineInputBorder(), hintText: 'https://...')),
              const SizedBox(height: 12),
              restaurantsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox.shrink(),
                data: (rests) => DropdownButtonFormField<String>(
                  initialValue: _selectedRestaurantId,
                  decoration: const InputDecoration(labelText: 'Restaurant (optional)', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    ...rests.map((r) => DropdownMenuItem(value: r.id, child: Text(r.name))),
                  ],
                  onChanged: (v) => setState(() => _selectedRestaurantId = v),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _section,
                decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'food', child: Text('Food Delivery')),
                  DropdownMenuItem(value: 'grocery', child: Text('Grocery')),
                  DropdownMenuItem(value: 'rides', child: Text('Rides')),
                  DropdownMenuItem(value: 'home', child: Text('Home (all)')),
                ],
                onChanged: (v) => setState(() => _section = v!),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                    child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(widget.existing != null ? 'Save Changes' : 'Create Banner'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
