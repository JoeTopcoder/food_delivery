import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/laundry_providers.dart';
import '../../../../utils/app_feedback_widgets.dart';
import '../../../../utils/friendly_error.dart';

class LaundryProviderOnboardingScreen extends ConsumerStatefulWidget {
  const LaundryProviderOnboardingScreen({super.key});

  @override
  ConsumerState<LaundryProviderOnboardingScreen> createState() =>
      _LaundryProviderOnboardingScreenState();
}

class _LaundryProviderOnboardingScreenState
    extends ConsumerState<LaundryProviderOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addrCtrl  = TextEditingController();
  bool _saving = false;

  static const _kBlue = Color(0xFF0F4C81);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(laundryServiceProvider).createProviderProfile(
        businessName: _nameCtrl.text.trim(),
        description:  _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        phone:        _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        email:        _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        address:      _addrCtrl.text.trim().isEmpty ? null : _addrCtrl.text.trim(),
      );
      ref.invalidate(myLaundryProviderProvider);
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/laundry/provider-dashboard',
          (r) => false,
        );
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
      appBar: AppBar(
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        title: const Text('Register Your Laundry'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _kBlue.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _kBlue.withValues(alpha: 0.15)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.local_laundry_service_rounded, color: _kBlue, size: 32),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Become a Provider',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          SizedBox(height: 4),
                          Text(
                            'Submit your details and our team will review your application.',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              _sectionLabel('Business Details'),
              const SizedBox(height: 10),
              _Field(
                label: 'Business Name *',
                controller: _nameCtrl,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              _Field(
                label: 'Description',
                controller: _descCtrl,
                maxLines: 3,
                hint: 'Tell customers what makes your laundry special…',
              ),

              const SizedBox(height: 24),
              _sectionLabel('Contact Info'),
              const SizedBox(height: 10),
              _Field(
                label: 'Phone',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              _Field(
                label: 'Email',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _Field(
                label: 'Address',
                controller: _addrCtrl,
                hint: 'Street, area, city',
              ),

              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Text('Submit Application',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Applications are reviewed within 1–2 business days.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      );
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? hint;
  final String? Function(String?)? validator;

  const _Field({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.keyboardType,
    this.hint,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      );
}
