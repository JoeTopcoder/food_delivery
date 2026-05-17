import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Provider ─────────────────────────────────────────────────────────────────

final _shippingCompaniesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await Supabase.instance.client
      .from('shipping_companies')
      .select()
      .order('name');
  return List<Map<String, dynamic>>.from(data as List);
});

// ── List Screen ───────────────────────────────────────────────────────────────

class AdminShippingCompaniesScreen extends ConsumerWidget {
  const AdminShippingCompaniesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companiesAsync = ref.watch(_shippingCompaniesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shipping Companies'),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_shippingCompaniesProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddEditShippingCompanyScreen(),
            ),
          );
          ref.invalidate(_shippingCompaniesProvider);
        },
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Company'),
      ),
      body: companiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('$e'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(_shippingCompaniesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (companies) {
          if (companies.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_shipping_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('No shipping companies yet.',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  const Text('Tap + to register the first company.',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: companies.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final co = companies[i];
              return _CompanyTile(
                company: co,
                onEdit: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AddEditShippingCompanyScreen(existing: co),
                    ),
                  );
                  ref.invalidate(_shippingCompaniesProvider);
                },
                onToggleActive: () async {
                  await Supabase.instance.client
                      .from('shipping_companies')
                      .update({'active': !(co['active'] as bool? ?? true)})
                      .eq('id', co['id'] as String);
                  ref.invalidate(_shippingCompaniesProvider);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _CompanyTile extends StatelessWidget {
  final Map<String, dynamic> company;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  const _CompanyTile({
    required this.company,
    required this.onEdit,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final active = company['active'] as bool? ?? true;
    final vtype = company['verification_type'] as String? ?? 'manual';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.local_shipping,
                      color: Color(0xFF7C3AED)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(company['name'] as String? ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        company['warehouse_address'] as String? ?? '',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Active toggle
                Switch(
                  value: active,
                  onChanged: (_) => onToggleActive(),
                  activeColor: const Color(0xFF7C3AED),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Tag(
                  label: vtype.toUpperCase(),
                  color: vtype == 'webhook'
                      ? Colors.orange
                      : vtype == 'api'
                          ? Colors.blue
                          : Colors.grey,
                ),
                const SizedBox(width: 8),
                _Tag(
                  label: active ? 'ACTIVE' : 'INACTIVE',
                  color: active ? Colors.green : Colors.red,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF7C3AED)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

// ── Add / Edit Screen ─────────────────────────────────────────────────────────

class AddEditShippingCompanyScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const AddEditShippingCompanyScreen({super.key, this.existing});

  @override
  State<AddEditShippingCompanyScreen> createState() =>
      _AddEditShippingCompanyScreenState();
}

class _AddEditShippingCompanyScreenState
    extends State<AddEditShippingCompanyScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _showSecrets = false;

  // Controllers
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _apiEndpoint;
  late final TextEditingController _apiKey;
  late final TextEditingController _webhookEndpoint;
  late final TextEditingController _webhookSecret;

  String _verificationType = 'manual';
  bool _active = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name'] as String? ?? '');
    _address = TextEditingController(
        text: e?['warehouse_address'] as String? ?? '');
    _lat = TextEditingController(
        text: e?['warehouse_lat']?.toString() ?? '');
    _lng = TextEditingController(
        text: e?['warehouse_lng']?.toString() ?? '');
    _email = TextEditingController(
        text: e?['support_email'] as String? ?? '');
    _phone = TextEditingController(
        text: e?['support_phone'] as String? ?? '');
    _apiEndpoint = TextEditingController(
        text: e?['api_endpoint'] as String? ?? '');
    _apiKey = TextEditingController(text: e?['api_key'] as String? ?? '');
    _webhookEndpoint = TextEditingController(
        text: e?['webhook_endpoint'] as String? ?? '');
    _webhookSecret = TextEditingController(
        text: e?['webhook_secret'] as String? ?? '');
    _verificationType = e?['verification_type'] as String? ?? 'manual';
    _active = e?['active'] as bool? ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _name, _address, _lat, _lng, _email, _phone,
      _apiEndpoint, _apiKey, _webhookEndpoint, _webhookSecret,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final payload = {
      'name': _name.text.trim(),
      'warehouse_address': _address.text.trim(),
      'warehouse_lat': double.tryParse(_lat.text.trim()),
      'warehouse_lng': double.tryParse(_lng.text.trim()),
      'support_email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      'support_phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'verification_type': _verificationType,
      'api_endpoint': _apiEndpoint.text.trim().isEmpty
          ? null
          : _apiEndpoint.text.trim(),
      'api_key': _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim(),
      'webhook_endpoint': _webhookEndpoint.text.trim().isEmpty
          ? null
          : _webhookEndpoint.text.trim(),
      'webhook_secret': _webhookSecret.text.trim().isEmpty
          ? null
          : _webhookSecret.text.trim(),
      'active': _active,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      if (_isEdit) {
        await Supabase.instance.client
            .from('shipping_companies')
            .update(payload)
            .eq('id', widget.existing!['id'] as String);
      } else {
        await Supabase.instance.client
            .from('shipping_companies')
            .insert(payload);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Company' : 'Register Shipping Company'),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Save',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Business Info ─────────────────────────────────────────
            _SectionHeader(icon: Icons.business, title: 'Business Info'),
            const SizedBox(height: 12),
            _Field(
              controller: _name,
              label: 'Business Name',
              hint: 'e.g. Applizone Shipping',
              required: true,
              icon: Icons.store,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _address,
              label: 'Warehouse Address',
              hint: '15 Red Hills Road, Kingston, Jamaica',
              required: true,
              icon: Icons.warehouse,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    controller: _lat,
                    label: 'Latitude',
                    hint: '18.0145',
                    icon: Icons.location_on,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    controller: _lng,
                    label: 'Longitude',
                    hint: '-76.8023',
                    icon: Icons.location_on,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _email,
              label: 'Support Email',
              hint: 'support@company.com',
              icon: Icons.email,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _phone,
              label: 'Support Phone',
              hint: '+18765550101',
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),

            // ── Verification Type ─────────────────────────────────────
            _SectionHeader(
                icon: Icons.verified_user, title: 'Verification Type'),
            const SizedBox(height: 4),
            const Text(
              'How will packages from this company be verified?',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ...[
              ('manual', 'Manual', 'Admin verifies packages manually',
                  Icons.check_circle_outline),
              ('api', 'API', 'Verify via REST API call to company',
                  Icons.api),
              ('webhook', 'Webhook',
                  'Company pushes status updates via webhook',
                  Icons.webhook),
            ].map((opt) {
              final (val, label, sub, icon) = opt;
              return RadioListTile<String>(
                value: val,
                groupValue: _verificationType,
                onChanged: (v) => setState(() => _verificationType = v!),
                title: Row(
                  children: [
                    Icon(icon, size: 18, color: const Color(0xFF7C3AED)),
                    const SizedBox(width: 8),
                    Text(label,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                subtitle: Text(sub,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey)),
                activeColor: const Color(0xFF7C3AED),
                contentPadding: EdgeInsets.zero,
              );
            }),

            // ── API Credentials ───────────────────────────────────────
            if (_verificationType == 'api') ...[
              const SizedBox(height: 20),
              _SectionHeader(
                  icon: Icons.api,
                  title: 'API Credentials',
                  trailing: _secretsToggle()),
              const SizedBox(height: 12),
              _Field(
                controller: _apiEndpoint,
                label: 'API Endpoint',
                hint: 'https://courier.shipavecorp.com/rpc',
                icon: Icons.link,
                required: true,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 14),
              _Field(
                controller: _apiKey,
                label: 'API Key',
                hint: 'pub_key_...',
                icon: Icons.vpn_key,
                required: true,
                obscure: !_showSecrets,
              ),
            ],

            // ── Webhook Credentials ───────────────────────────────────
            if (_verificationType == 'webhook') ...[
              const SizedBox(height: 20),
              _SectionHeader(
                  icon: Icons.webhook,
                  title: 'Webhook Credentials',
                  trailing: _secretsToggle()),
              const SizedBox(height: 12),
              _Field(
                controller: _webhookEndpoint,
                label: 'Webhook Endpoint URL',
                hint: 'https://company.com/rpc/hook/wh_...',
                icon: Icons.link,
                required: true,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 14),
              _Field(
                controller: _webhookSecret,
                label: 'Webhook Secret',
                hint: 'whsec_...',
                icon: Icons.lock,
                required: true,
                obscure: !_showSecrets,
              ),
            ],

            const SizedBox(height: 20),

            // ── Status ────────────────────────────────────────────────
            _SectionHeader(icon: Icons.toggle_on, title: 'Status'),
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Active'),
              subtitle: const Text(
                  'Inactive companies are hidden from customers'),
              activeColor: const Color(0xFF7C3AED),
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        _isEdit
                            ? 'Save Changes'
                            : 'Register Shipping Company',
                        style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _secretsToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showSecrets = !_showSecrets),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _showSecrets ? Icons.visibility_off : Icons.visibility,
            size: 16,
            color: Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            _showSecrets ? 'Hide' : 'Show',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _SectionHeader(
      {required this.icon, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF7C3AED)),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15)),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool required;
  final bool obscure;
  final TextInputType? keyboardType;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.required = false,
    this.obscure = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label + (required ? ' *' : ''),
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF7C3AED), size: 20),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF7C3AED), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
          : null,
    );
  }
}
