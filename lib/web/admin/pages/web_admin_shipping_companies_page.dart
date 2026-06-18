import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

// ── Provider ─────────────────────────────────────────────────────────────────

final _webShippingCompaniesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await Supabase.instance.client
      .from('shipping_companies')
      .select()
      .order('name');
  return List<Map<String, dynamic>>.from(data as List);
});

// ── Page ─────────────────────────────────────────────────────────────────────

class WebAdminShippingCompaniesPage extends ConsumerWidget {
  const WebAdminShippingCompaniesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companiesAsync = ref.watch(_webShippingCompaniesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Shipping Companies', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Registered logistics and courier partners', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () => ref.invalidate(_webShippingCompaniesProvider)),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
              label: const Text('Add Company', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _ShippingCompanyDialog(onSaved: () => ref.invalidate(_webShippingCompaniesProvider)),
              ),
            ),
          ]),
          const SizedBox(height: 28),

          companiesAsync.when(
            loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(_webShippingCompaniesProvider)),
            data: (companies) {
              if (companies.isEmpty) {
                return Container(
                  height: 200,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const AppEmptyState(icon: Icons.local_shipping_rounded, title: 'No shipping companies yet'),
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
                      Expanded(flex: 3, child: Text('Company Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 2, child: Text('Contact', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 2, child: Text('Email', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 2, child: Text('Tracking URL', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 1, child: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      SizedBox(width: 60),
                    ]),
                  ),
                  const Divider(height: 1),
                  ...companies.asMap().entries.map((e) => _CompanyRow(
                    company: e.value,
                    isLast: e.key == companies.length - 1,
                    onChanged: () => ref.invalidate(_webShippingCompaniesProvider),
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

// ── Company Row ───────────────────────────────────────────────────────────────

class _CompanyRow extends StatelessWidget {
  final Map<String, dynamic> company;
  final bool isLast;
  final VoidCallback onChanged;
  const _CompanyRow({required this.company, required this.isLast, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isActive = company['is_active'] != false;
    final trackingUrl = company['tracking_url_template'] ?? company['tracking_url'] ?? '—';

    return Container(
      decoration: BoxDecoration(border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Expanded(flex: 3, child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF7C3AED).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.inventory_2_rounded, color: Color(0xFF7C3AED), size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(company['name'] ?? '—',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
          ])),
          Expanded(flex: 2, child: Text(company['contact_phone'] ?? company['phone'] ?? '—',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)))),
          Expanded(flex: 2, child: Text(company['contact_email'] ?? company['email'] ?? '—',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(
            trackingUrl.length > 30 ? '${trackingUrl.substring(0, 30)}…' : trackingUrl,
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          )),
          Expanded(flex: 1, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(isActive ? 'Active' : 'Inactive',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: isActive ? const Color(0xFF059669) : const Color(0xFF94A3B8))),
          )),
          SizedBox(width: 60, child: Row(children: [
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF64748B)),
              onPressed: () => showDialog(context: context,
                builder: (_) => _ShippingCompanyDialog(existing: company, onSaved: onChanged)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded, size: 16, color: Color(0xFFEF4444)),
              onPressed: () => _delete(context),
            ),
          ])),
        ]),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Delete Company'),
      content: Text('Remove "${company['name']}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: const Text('Delete')),
      ],
    ));
    if (ok != true) return;
    try {
      await Supabase.instance.client.from('shipping_companies').delete().eq('id', company['id']);
      onChanged();
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

// ── Create / Edit Dialog ──────────────────────────────────────────────────────

class _ShippingCompanyDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const _ShippingCompanyDialog({this.existing, required this.onSaved});

  @override
  State<_ShippingCompanyDialog> createState() => _ShippingCompanyDialogState();
}

class _ShippingCompanyDialogState extends State<_ShippingCompanyDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _trackingUrl;
  late final TextEditingController _apiKey;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name'] ?? '');
    _phone = TextEditingController(text: e?['contact_phone'] ?? e?['phone'] ?? '');
    _email = TextEditingController(text: e?['contact_email'] ?? e?['email'] ?? '');
    _trackingUrl = TextEditingController(text: e?['tracking_url_template'] ?? e?['tracking_url'] ?? '');
    _apiKey = TextEditingController(text: e?['api_key'] ?? '');
    _active = e?['is_active'] ?? true;
  }

  @override
  void dispose() {
    _name.dispose(); _phone.dispose(); _email.dispose(); _trackingUrl.dispose(); _apiKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'name': _name.text.trim(),
        'contact_phone': _phone.text.trim(),
        'contact_email': _email.text.trim(),
        'tracking_url_template': _trackingUrl.text.trim(),
        'api_key': _apiKey.text.trim(),
        'is_active': _active,
      };
      if (widget.existing != null) {
        await Supabase.instance.client.from('shipping_companies').update(data).eq('id', widget.existing!['id']);
      } else {
        await Supabase.instance.client.from('shipping_companies').insert(data);
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
        width: 460,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.existing != null ? 'Edit Shipping Company' : 'Add Shipping Company',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
            const SizedBox(height: 20),
            _field(_name, 'Company Name', validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _field(_phone, 'Contact Phone', type: TextInputType.phone)),
              const SizedBox(width: 12),
              Expanded(child: _field(_email, 'Contact Email', type: TextInputType.emailAddress)),
            ]),
            const SizedBox(height: 12),
            _field(_trackingUrl, 'Tracking URL Template (use {tracking_number})'),
            const SizedBox(height: 12),
            _field(_apiKey, 'API Key (optional)'),
            const SizedBox(height: 12),
            Row(children: [
              Switch(value: _active, onChanged: (v) => setState(() => _active = v), activeThumbColor: const Color(0xFF7C3AED)),
              const SizedBox(width: 8),
              Text(_active ? 'Active' : 'Inactive',
                style: TextStyle(fontWeight: FontWeight.w600, color: _active ? const Color(0xFF7C3AED) : const Color(0xFF94A3B8))),
            ]),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
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
