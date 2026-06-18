import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/supabase_config.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

// ── Provider ─────────────────────────────────────────────────────────────────

final _webAllAdsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await SupabaseConfig.client
      .from('restaurant_ads')
      .select('*, restaurants(name)')
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data as List);
});

// ── Page ─────────────────────────────────────────────────────────────────────

class WebAdminAdsPage extends ConsumerWidget {
  const WebAdminAdsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adsAsync = ref.watch(_webAllAdsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Restaurant Ads', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Manage sponsored restaurant advertisements', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                onPressed: () => ref.invalidate(_webAllAdsProvider),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                label: const Text('New Ad', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _AdDialog(onSaved: () => ref.invalidate(_webAllAdsProvider)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          adsAsync.when(
            loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(_webAllAdsProvider)),
            data: (ads) {
              if (ads.isEmpty) {
                return Container(
                  height: 200,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const AppEmptyState(icon: Icons.campaign_rounded, title: 'No ads yet'),
                );
              }
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
                    child: const Row(children: [
                      Expanded(flex: 3, child: Text('Restaurant', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 3, child: Text('Title', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 2, child: Text('Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 2, child: Text('Expires', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 1, child: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      SizedBox(width: 60, child: Text('', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                    ]),
                  ),
                  const Divider(height: 1),
                  ...ads.asMap().entries.map((e) => _AdRow(
                    ad: e.value,
                    isLast: e.key == ads.length - 1,
                    onChanged: () => ref.invalidate(_webAllAdsProvider),
                  )),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Ad Row ────────────────────────────────────────────────────────────────────

class _AdRow extends ConsumerWidget {
  final Map<String, dynamic> ad;
  final bool isLast;
  final VoidCallback onChanged;
  const _AdRow({required this.ad, required this.isLast, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ad['is_active'] == true;
    final restaurant = (ad['restaurants'] as Map?)?['name'] ?? 'Unknown';
    final title = ad['title'] ?? '';
    final type = ad['ad_type'] ?? ad['type'] ?? '-';
    final expiresAt = DateTime.tryParse(ad['expires_at'] ?? '');
    final isExpired = expiresAt != null && expiresAt.isBefore(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Expanded(flex: 3, child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.campaign_rounded, color: Color(0xFFEF4444), size: 14),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(restaurant, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
          ])),
          Expanded(flex: 3, child: Text(title, style: const TextStyle(fontSize: 13, color: Color(0xFF475569)), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: _TypeBadge(type: type)),
          Expanded(flex: 2, child: Text(
            expiresAt != null ? DateFormat('MMM d, yyyy').format(expiresAt.toLocal()) : '—',
            style: TextStyle(fontSize: 12, color: isExpired ? const Color(0xFFEF4444) : const Color(0xFF94A3B8)),
          )),
          Expanded(flex: 1, child: _StatusDot(isActive: isActive && !isExpired)),
          SizedBox(width: 60, child: Row(children: [
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF64748B)),
              onPressed: () => showDialog(context: context, builder: (_) => _AdDialog(existing: ad, onSaved: onChanged)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded, size: 16, color: Color(0xFFEF4444)),
              onPressed: () => _delete(context, ref),
            ),
          ])),
        ]),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Delete Ad'),
      content: const Text('Remove this advertisement permanently?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: const Text('Delete'),
        ),
      ],
    ));
    if (ok != true) return;
    try {
      await SupabaseConfig.client.from('restaurant_ads').delete().eq('id', ad['id']);
      onChanged();
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(20)),
      child: Text(type, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2563EB))),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool isActive;
  const _StatusDot({required this.isActive});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(color: isActive ? const Color(0xFF10B981) : const Color(0xFF94A3B8), shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(isActive ? 'Active' : 'Off', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? const Color(0xFF059669) : const Color(0xFF94A3B8))),
    ]);
  }
}

// ── Create / Edit Dialog ──────────────────────────────────────────────────────

class _AdDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const _AdDialog({this.existing, required this.onSaved});

  @override
  ConsumerState<_AdDialog> createState() => _AdDialogState();
}

class _AdDialogState extends ConsumerState<_AdDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _imageUrl;
  late final TextEditingController _expiresAt;
  String _type = 'banner';
  bool _active = true;
  bool _saving = false;
  String? _restaurantId;
  List<Map<String, dynamic>> _restaurants = [];
  bool _loadingRest = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?['title'] ?? '');
    _description = TextEditingController(text: e?['description'] ?? '');
    _imageUrl = TextEditingController(text: e?['image_url'] ?? '');
    _expiresAt = TextEditingController(text: e?['expires_at']?.toString().split('T').first ?? '');
    _type = e?['ad_type'] ?? e?['type'] ?? 'banner';
    _active = e?['is_active'] ?? true;
    _restaurantId = e?['restaurant_id']?.toString();
    _loadRestaurants();
  }

  Future<void> _loadRestaurants() async {
    try {
      final data = await SupabaseConfig.client.from('restaurants').select('id, name').eq('is_verified', true).order('name');
      if (mounted) setState(() { _restaurants = List<Map<String, dynamic>>.from(data as List); _loadingRest = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingRest = false);
    }
  }

  @override
  void dispose() {
    _title.dispose(); _description.dispose(); _imageUrl.dispose(); _expiresAt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'restaurant_id': _restaurantId,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'image_url': _imageUrl.text.trim(),
        'ad_type': _type,
        'is_active': _active,
        if (_expiresAt.text.trim().isNotEmpty) 'expires_at': _expiresAt.text.trim(),
      };
      if (widget.existing != null) {
        await SupabaseConfig.client.from('restaurant_ads').update(data).eq('id', widget.existing!['id']);
      } else {
        await SupabaseConfig.client.from('restaurant_ads').insert(data);
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.existing != null ? 'Edit Ad' : 'New Restaurant Ad',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
              const SizedBox(height: 20),
              if (_loadingRest)
                const Center(child: CircularProgressIndicator())
              else
                DropdownButtonFormField<String>(
                  value: _restaurantId,
                  decoration: _dec('Restaurant'),
                  items: _restaurants.map((r) => DropdownMenuItem(value: r['id'].toString(), child: Text(r['name'] ?? ''))).toList(),
                  onChanged: (v) => setState(() => _restaurantId = v),
                  validator: (v) => v == null ? 'Select a restaurant' : null,
                ),
              const SizedBox(height: 12),
              TextFormField(controller: _title, decoration: _dec('Ad Title'), validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _description, decoration: _dec('Description'), maxLines: 2),
              const SizedBox(height: 12),
              TextFormField(controller: _imageUrl, decoration: _dec('Image URL')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: _dec('Ad Type'),
                items: ['banner', 'featured', 'sponsored', 'popup'].map((t) => DropdownMenuItem(value: t, child: Text(t[0].toUpperCase() + t.substring(1)))).toList(),
                onChanged: (v) => setState(() => _type = v ?? 'banner'),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _expiresAt, decoration: _dec('Expires At (YYYY-MM-DD)'), keyboardType: TextInputType.datetime),
              const SizedBox(height: 12),
              Row(children: [
                Switch(value: _active, onChanged: (v) => setState(() => _active = v), activeThumbColor: const Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text(_active ? 'Active' : 'Inactive', style: TextStyle(fontWeight: FontWeight.w600, color: _active ? const Color(0xFF10B981) : const Color(0xFF94A3B8))),
              ]),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Ad'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
    filled: true, fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.primaryColor, width: 2)),
  );
}
