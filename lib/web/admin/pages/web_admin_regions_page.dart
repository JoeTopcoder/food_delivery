import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/app_constants.dart';
import '../../../models/delivery_region_model.dart';
import '../../../providers/delivery_region_provider.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

class WebAdminRegionsPage extends ConsumerWidget {
  const WebAdminRegionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regionsAsync = ref.watch(allRegionsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Delivery Regions', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Manage geographic zones for deliveries and tax settings', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () => ref.invalidate(allRegionsProvider)),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_location_alt_rounded, size: 18, color: Colors.white),
              label: const Text('New Region', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _RegionDialog(onSaved: () => ref.invalidate(allRegionsProvider)),
              ),
            ),
          ]),
          const SizedBox(height: 28),

          regionsAsync.when(
            loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(allRegionsProvider)),
            data: (regions) {
              if (regions.isEmpty) {
                return Container(
                  height: 200,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const AppEmptyState(icon: Icons.map_rounded, title: 'No delivery regions configured'),
                );
              }
              final active = regions.where((r) => r.isActive).length;
              return Column(children: [
                // Summary strip
                Row(children: [
                  _SummaryTile(label: 'Total Regions', value: '${regions.length}', color: const Color(0xFF10B981)),
                  const SizedBox(width: 16),
                  _SummaryTile(label: 'Active', value: '$active', color: const Color(0xFF6366F1)),
                  const SizedBox(width: 16),
                  _SummaryTile(label: 'Inactive', value: '${regions.length - active}', color: const Color(0xFF94A3B8)),
                ]),
                const SizedBox(height: 20),
                Container(
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
                        Expanded(flex: 3, child: Text('Region Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('Center (lat, lng)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('Radius (km)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('Tax', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 1, child: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        SizedBox(width: 80),
                      ]),
                    ),
                    const Divider(height: 1),
                    ...regions.asMap().entries.map((e) => _RegionRow(
                      region: e.value,
                      isLast: e.key == regions.length - 1,
                      onChanged: () => ref.invalidate(allRegionsProvider),
                    )),
                  ]),
                ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      ]),
    ),
  );
}

// ── Region Row ────────────────────────────────────────────────────────────────

class _RegionRow extends StatelessWidget {
  final DeliveryRegion region;
  final bool isLast;
  final VoidCallback onChanged;
  const _RegionRow({required this.region, required this.isLast, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Expanded(flex: 3, child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.map_rounded, color: Color(0xFF10B981), size: 15),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(region.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
          ])),
          Expanded(flex: 2, child: Text(
            '${region.latitude.toStringAsFixed(4)}, ${region.longitude.toStringAsFixed(4)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          )),
          Expanded(flex: 2, child: Text(
            '${region.radiusKm.toStringAsFixed(1)} km',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
          )),
          Expanded(flex: 2, child: region.taxEnabled
            ? Text('${((region.taxRate ?? 0) * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0EA5E9)))
            : const Text('No tax', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))),
          Expanded(flex: 1, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: region.isActive ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(region.isActive ? 'Active' : 'Off',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: region.isActive ? const Color(0xFF059669) : const Color(0xFF94A3B8))),
          )),
          SizedBox(width: 80, child: Row(children: [
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF64748B)),
              onPressed: () => showDialog(context: context,
                builder: (_) => _RegionDialog(existing: region, onSaved: onChanged)),
            ),
            IconButton(
              icon: Icon(region.isActive ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 16,
                color: region.isActive ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
              onPressed: () => _toggle(context),
            ),
          ])),
        ]),
      ),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    try {
      await Supabase.instance.client
          .from('delivery_regions')
          .update({'is_active': !region.isActive})
          .eq('id', region.id);
      onChanged();
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

// ── Create / Edit Dialog ──────────────────────────────────────────────────────

class _RegionDialog extends StatefulWidget {
  final DeliveryRegion? existing;
  final VoidCallback onSaved;
  const _RegionDialog({this.existing, required this.onSaved});

  @override
  State<_RegionDialog> createState() => _RegionDialogState();
}

class _RegionDialogState extends State<_RegionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late final TextEditingController _radius;
  late final TextEditingController _taxRate;
  bool _active = true;
  bool _taxEnabled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _lat = TextEditingController(text: e?.latitude.toStringAsFixed(4) ?? '19.2869');
    _lng = TextEditingController(text: e?.longitude.toStringAsFixed(4) ?? '-81.3812');
    _radius = TextEditingController(text: e?.radiusKm.toStringAsFixed(1) ?? '10.0');
    _taxRate = TextEditingController(text: e != null ? ((e.taxRate ?? 0) * 100).toStringAsFixed(1) : '');
    _active = e?.isActive ?? true;
    _taxEnabled = e?.taxEnabled ?? false;
  }

  @override
  void dispose() {
    _name.dispose(); _lat.dispose(); _lng.dispose(); _radius.dispose(); _taxRate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final taxRatePct = double.tryParse(_taxRate.text.trim()) ?? 0;
      final data = {
        'name': _name.text.trim(),
        'latitude': double.tryParse(_lat.text.trim()) ?? 0,
        'longitude': double.tryParse(_lng.text.trim()) ?? 0,
        'radius_km': double.tryParse(_radius.text.trim()) ?? 10,
        'tax_enabled': _taxEnabled,
        'tax_rate': _taxEnabled ? taxRatePct / 100 : 0,
        'is_active': _active,
      };
      if (widget.existing != null) {
        await Supabase.instance.client.from('delivery_regions').update(data).eq('id', widget.existing!.id);
      } else {
        await Supabase.instance.client.from('delivery_regions').insert(data);
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
    final sym = AppConstants.currencySymbol;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.existing != null ? 'Edit Region' : 'New Delivery Region',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
            const SizedBox(height: 4),
            Text('Currency: $sym', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            const SizedBox(height: 16),
            _field(_name, 'Region Name', validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _field(_lat, 'Latitude', type: TextInputType.number,
                validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid' : null)),
              const SizedBox(width: 12),
              Expanded(child: _field(_lng, 'Longitude', type: TextInputType.number,
                validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid' : null)),
            ]),
            const SizedBox(height: 12),
            _field(_radius, 'Radius (km)', type: TextInputType.number,
              validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid' : null),
            const SizedBox(height: 12),
            Row(children: [
              Switch(value: _taxEnabled, onChanged: (v) => setState(() => _taxEnabled = v), activeThumbColor: const Color(0xFF0EA5E9)),
              const SizedBox(width: 8),
              const Text('Enable Tax', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
            if (_taxEnabled) ...[
              const SizedBox(height: 8),
              _field(_taxRate, 'Tax Rate (%)', type: TextInputType.number),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Switch(value: _active, onChanged: (v) => setState(() => _active = v), activeThumbColor: const Color(0xFF10B981)),
              const SizedBox(width: 8),
              Text(_active ? 'Active' : 'Inactive',
                style: TextStyle(fontWeight: FontWeight.w600, color: _active ? const Color(0xFF10B981) : const Color(0xFF94A3B8))),
            ]),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Region'),
              ),
            ]),
          ])),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {TextInputType? type, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl, keyboardType: type, validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
        filled: true, fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.primaryColor, width: 2)),
      ),
    );
  }
}
