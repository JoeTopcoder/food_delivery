import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/index.dart';
import '../../providers/laundry_providers.dart';
import '../../../../config/supabase_config.dart';
import '../../../../utils/app_theme.dart';
import '../../../../utils/app_feedback_widgets.dart';
import '../../../../utils/friendly_error.dart';

class LaundryProviderSettingsScreen extends ConsumerStatefulWidget {
  final LaundryProvider provider;
  const LaundryProviderSettingsScreen({super.key, required this.provider});

  @override
  ConsumerState<LaundryProviderSettingsScreen> createState() =>
      _LaundryProviderSettingsScreenState();
}

class _LaundryProviderSettingsScreenState
    extends ConsumerState<LaundryProviderSettingsScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addrCtrl;
  late final TextEditingController _pickupFeeCtrl;
  late final TextEditingController _deliveryFeeCtrl;
  late final TextEditingController _minFeeCtrl;

  File? _logoFile;
  bool _isActive = false;
  bool _saving   = false;

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _nameCtrl        = TextEditingController(text: p.businessName);
    _descCtrl        = TextEditingController(text: p.description ?? '');
    _phoneCtrl       = TextEditingController(text: p.phone ?? '');
    _addrCtrl        = TextEditingController(text: p.address ?? '');
    _pickupFeeCtrl   = TextEditingController(
        text: p.pricing?.pickupFee.toStringAsFixed(2) ?? '0.00');
    _deliveryFeeCtrl = TextEditingController(
        text: p.pricing?.deliveryFee.toStringAsFixed(2) ?? '0.00');
    _minFeeCtrl      = TextEditingController(
        text: p.pricing?.minOrderFee.toStringAsFixed(2) ?? '5.00');
    _isActive = p.isActive;
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _descCtrl.dispose();
    _phoneCtrl.dispose(); _addrCtrl.dispose();
    _pickupFeeCtrl.dispose(); _deliveryFeeCtrl.dispose(); _minFeeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery, imageQuality: 85, maxWidth: 512,
    );
    if (f != null && mounted) setState(() => _logoFile = File(f.path));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final svc = ref.read(laundryServiceProvider);

      String? logoUrl;
      if (_logoFile != null) {
        logoUrl = await svc.uploadProviderLogo(widget.provider.id, _logoFile!);
      }

      await svc.updateProviderProfile(widget.provider.id, {
        'business_name': _nameCtrl.text.trim(),
        'description':   _descCtrl.text.trim(),
        'phone':         _phoneCtrl.text.trim(),
        'address':       _addrCtrl.text.trim(),
        'is_active':     _isActive,
        if (logoUrl != null) 'logo_url': logoUrl,
      });

      // Update or insert pricing row
      await SupabaseConfig.client
          .from('laundry_pricing')
          .upsert({
            'provider_id':   widget.provider.id,
            'pickup_fee':    double.tryParse(_pickupFeeCtrl.text) ?? 0,
            'delivery_fee':  double.tryParse(_deliveryFeeCtrl.text) ?? 0,
            'min_order_fee': double.tryParse(_minFeeCtrl.text) ?? 5,
            'updated_at':    DateTime.now().toIso8601String(),
          }, onConflict: 'provider_id');

      ref.invalidate(myLaundryProviderProvider);
      if (mounted) {
        AppSnackbar.success(context, 'Settings saved!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Provider Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo
            Center(
              child: GestureDetector(
                onTap: _pickLogo,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(60),
                      child: _logoFile != null
                          ? Image.file(_logoFile!, width: 100, height: 100, fit: BoxFit.cover)
                          : widget.provider.logoUrl != null
                              ? Image.network(widget.provider.logoUrl!,
                                  width: 100, height: 100, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _logoPlaceholder())
                              : _logoPlaceholder(),
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F4C81),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Store open/closed toggle
            SwitchListTile.adaptive(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: const Text('Store is Open', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_isActive ? 'Accepting new orders' : 'Not accepting orders'),
              contentPadding: EdgeInsets.zero,
              activeTrackColor: AppTheme.successColor,
            ),
            const Divider(),
            const SizedBox(height: 8),

            _SectionHeader('Business Info'),
            const SizedBox(height: 10),
            _Field('Business Name', _nameCtrl),
            const SizedBox(height: 10),
            _Field('Description', _descCtrl, maxLines: 3),
            const SizedBox(height: 10),
            _Field('Phone', _phoneCtrl, keyboardType: TextInputType.phone),
            const SizedBox(height: 10),
            _Field('Address', _addrCtrl),

            const SizedBox(height: 24),
            _SectionHeader('Fees'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _Field('Pickup Fee', _pickupFeeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                const SizedBox(width: 10),
                Expanded(child: _Field('Delivery Fee', _deliveryFeeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true))),
              ],
            ),
            const SizedBox(height: 10),
            _Field('Minimum Order Fee', _minFeeCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Save Settings',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoPlaceholder() => Container(
        width: 100, height: 100,
        color: const Color(0xFF0F4C81).withValues(alpha: 0.1),
        child: const Icon(Icons.local_laundry_service_rounded,
            color: Color(0xFF0F4C81), size: 40),
      );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      );
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;

  const _Field(this.label, this.controller,
      {this.maxLines = 1, this.keyboardType});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      );
}

