import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/supabase_config.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _webSurgeZonesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await SupabaseConfig.client
      .from('surge_zones')
      .select()
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data as List);
});

// ── Page ─────────────────────────────────────────────────────────────────────

class WebAdminSurgePage extends ConsumerWidget {
  const WebAdminSurgePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesAsync = ref.watch(_webSurgeZonesProvider);

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
                    Text('Surge Zones', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Dynamic pricing zones on the map', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                onPressed: () => ref.invalidate(_webSurgeZonesProvider),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                label: const Text('New Zone', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFA630),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _showZoneDialog(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Zone List ───────────────────────────────────────────────────
          zonesAsync.when(
            loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(_webSurgeZonesProvider)),
            data: (zones) {
              if (zones.isEmpty) {
                return Container(
                  height: 200,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const AppEmptyState(icon: Icons.bolt_rounded, title: 'No surge zones configured'),
                );
              }
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Column(
                  children: [
                    // Table header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                      ),
                      child: const Row(children: [
                        Expanded(flex: 3, child: Text('Zone Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('Multiplier', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('Radius (km)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 2, child: Text('Coordinates', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        Expanded(flex: 1, child: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                        SizedBox(width: 80, child: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      ]),
                    ),
                    const Divider(height: 1),
                    ...zones.asMap().entries.map((e) {
                      final i = e.key;
                      final z = e.value;
                      return _SurgeZoneRow(
                        zone: z,
                        isLast: i == zones.length - 1,
                        onChanged: () => ref.invalidate(_webSurgeZonesProvider),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showZoneDialog(BuildContext context, WidgetRef ref, {Map<String, dynamic>? existing}) {
    showDialog(
      context: context,
      builder: (_) => _SurgeZoneDialog(existing: existing, onSaved: () => ref.invalidate(_webSurgeZonesProvider)),
    );
  }
}

// ── Zone Row ─────────────────────────────────────────────────────────────────

class _SurgeZoneRow extends ConsumerWidget {
  final Map<String, dynamic> zone;
  final bool isLast;
  final VoidCallback onChanged;
  const _SurgeZoneRow({required this.zone, required this.isLast, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = zone['is_active'] == true;
    final multiplier = (zone['multiplier'] as num?)?.toStringAsFixed(2) ?? '1.00';
    final radius = (zone['radius_km'] as num?)?.toStringAsFixed(1) ?? '-';
    final lat = (zone['latitude'] as num?)?.toStringAsFixed(4) ?? '-';
    final lng = (zone['longitude'] as num?)?.toStringAsFixed(4) ?? '-';

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
              decoration: BoxDecoration(
                color: const Color(0xFFFFA630).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt_rounded, color: Color(0xFFFFA630), size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(zone['name'] ?? 'Zone', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
          ])),
          Expanded(flex: 2, child: Text('$multiplier×', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFFF97316)))),
          Expanded(flex: 2, child: Text(radius, style: const TextStyle(fontSize: 13, color: Color(0xFF475569)))),
          Expanded(flex: 2, child: Text('$lat, $lng', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))),
          Expanded(flex: 1, child: _StatusBadge(isActive: isActive)),
          SizedBox(
            width: 80,
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF64748B)),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _SurgeZoneDialog(existing: zone, onSaved: onChanged),
                ),
              ),
              IconButton(
                icon: Icon(isActive ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 16,
                  color: isActive ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
                onPressed: () => _toggleActive(context, ref),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _toggleActive(BuildContext context, WidgetRef ref) async {
    try {
      await SupabaseConfig.client
          .from('surge_zones')
          .update({'is_active': !(zone['is_active'] == true)})
          .eq('id', zone['id']);
      onChanged();
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF10B981).withValues(alpha: 0.1) : const Color(0xFF94A3B8).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(isActive ? 'Active' : 'Inactive',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
          color: isActive ? const Color(0xFF059669) : const Color(0xFF64748B))),
    );
  }
}

// ── Create/Edit Dialog ────────────────────────────────────────────────────────

class _SurgeZoneDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const _SurgeZoneDialog({this.existing, required this.onSaved});

  @override
  State<_SurgeZoneDialog> createState() => _SurgeZoneDialogState();
}

class _SurgeZoneDialogState extends State<_SurgeZoneDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late final TextEditingController _radius;
  late final TextEditingController _multiplier;
  late final TextEditingController _reason;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name'] ?? '');
    _lat = TextEditingController(text: e?['latitude']?.toString() ?? '19.2869');
    _lng = TextEditingController(text: e?['longitude']?.toString() ?? '-81.3812');
    _radius = TextEditingController(text: e?['radius_km']?.toString() ?? '3.0');
    _multiplier = TextEditingController(text: e?['multiplier']?.toString() ?? '1.5');
    _reason = TextEditingController(text: e?['reason'] ?? '');
    _active = e?['is_active'] ?? true;
  }

  @override
  void dispose() {
    _name.dispose(); _lat.dispose(); _lng.dispose();
    _radius.dispose(); _multiplier.dispose(); _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'name': _name.text.trim(),
        'latitude': double.parse(_lat.text.trim()),
        'longitude': double.parse(_lng.text.trim()),
        'radius_km': double.parse(_radius.text.trim()),
        'multiplier': double.parse(_multiplier.text.trim()),
        'reason': _reason.text.trim(),
        'is_active': _active,
      };
      if (widget.existing != null) {
        await SupabaseConfig.client.from('surge_zones').update(data).eq('id', widget.existing!['id']);
      } else {
        await SupabaseConfig.client.from('surge_zones').insert(data);
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
        width: 440,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.existing != null ? 'Edit Surge Zone' : 'New Surge Zone',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
              const SizedBox(height: 20),
              _field(_name, 'Zone Name', validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _field(_lat, 'Latitude', type: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _field(_lng, 'Longitude', type: TextInputType.number)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _field(_radius, 'Radius (km)', type: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _field(_multiplier, 'Multiplier (e.g. 1.5)', type: TextInputType.number,
                  validator: (v) {
                    final d = double.tryParse(v ?? '');
                    if (d == null || d < 1) return 'Min 1.0';
                    return null;
                  })),
              ]),
              const SizedBox(height: 12),
              _field(_reason, 'Reason (optional)'),
              const SizedBox(height: 12),
              Row(children: [
                Switch(value: _active, onChanged: (v) => setState(() => _active = v),
                  activeThumbColor: const Color(0xFFFFA630)),
                const SizedBox(width: 8),
                Text(_active ? 'Active' : 'Inactive',
                  style: TextStyle(fontWeight: FontWeight.w600,
                    color: _active ? const Color(0xFFFFA630) : const Color(0xFF94A3B8))),
              ]),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFA630), foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Zone'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {TextInputType? type, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      validator: validator,
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
