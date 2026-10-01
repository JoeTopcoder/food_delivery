import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/company/company_service.dart';
import '../../utils/app_theme.dart';

/// Create a new company or edit the admin's existing company profile.
class CompanyRegisterScreen extends ConsumerStatefulWidget {
  const CompanyRegisterScreen({super.key, this.existing});
  final Company? existing;
  @override
  ConsumerState<CompanyRegisterScreen> createState() => _CompanyRegisterScreenState();
}

class _CompanyRegisterScreenState extends ConsumerState<CompanyRegisterScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _lat;
  late final TextEditingController _lon;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  int _radius = 3;
  bool _active = true;
  bool _busy = false;

  CompanyService get _svc => ref.read(companyServiceProvider);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _address = TextEditingController(text: e?.deliveryAddress ?? '');
    _lat = TextEditingController(text: e?.latitude?.toString() ?? '');
    _lon = TextEditingController(text: e?.longitude?.toString() ?? '');
    _email = TextEditingController(text: e?.contactEmail ?? '');
    _phone = TextEditingController(text: e?.contactPhone ?? '');
    _radius = e?.radiusKm ?? 3;
    _active = e?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _lat, _lon, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final lat = double.tryParse(_lat.text.trim());
      final lon = double.tryParse(_lon.text.trim());
      if (widget.existing == null) {
        await _svc.createCompany(
          name: _name.text.trim(),
          deliveryAddress: _address.text.trim(),
          latitude: lat,
          longitude: lon,
          radiusKm: _radius,
          contactEmail: _email.text.trim().isEmpty ? null : _email.text.trim(),
          contactPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        );
      } else {
        await _svc.updateCompany(widget.existing!.id, {
          'name': _name.text.trim(),
          'delivery_address': _address.text.trim(),
          'latitude': lat,
          'longitude': lon,
          'radius_km': _radius,
          'contact_email': _email.text.trim().isEmpty ? null : _email.text.trim(),
          'contact_phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          'is_active': _active,
        });
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Company profile' : 'Register company')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(_name, 'Company name', required: true),
            _field(_address, 'Saved delivery address (office)', required: true, maxLines: 2),
            Row(children: [
              Expanded(child: _field(_lat, 'Latitude', keyboard: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _field(_lon, 'Longitude', keyboard: TextInputType.number)),
            ]),
            const SizedBox(height: 8),
            Text('Restaurant delivery radius', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            const SizedBox(height: 4),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2 km')),
                ButtonSegment(value: 3, label: Text('3 km')),
                ButtonSegment(value: 4, label: Text('4 km')),
              ],
              selected: {_radius},
              onSelectionChanged: (s) => setState(() => _radius = s.first),
            ),
            const SizedBox(height: 12),
            _field(_email, 'Contact email', keyboard: TextInputType.emailAddress),
            _field(_phone, 'Contact phone', keyboard: TextInputType.phone),
            if (editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Company active'),
                subtitle: const Text('Inactive companies cannot sponsor orders'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(editing ? 'Save changes' : 'Create company'),
            ),
            const SizedBox(height: 8),
            Text('Coordinates are used to measure the straight-line distance to each '
                'restaurant. Only restaurants within your radius can be used for '
                'company-sponsored delivery.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool required = false, int maxLines = 1, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
      ),
    );
  }
}
