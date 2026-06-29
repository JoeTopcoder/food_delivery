// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../services/compliance_service.dart';
import '../../utils/app_theme.dart';

/// Public screen — accessible without login. Required for Google Play data
/// deletion URL and App Store data deletion compliance.
class DataDeletionRequestScreen extends StatefulWidget {
  const DataDeletionRequestScreen({super.key});

  @override
  State<DataDeletionRequestScreen> createState() => _DataDeletionRequestScreenState();
}

class _DataDeletionRequestScreenState extends State<DataDeletionRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _confirmsOwnership = false;
  bool _isLoading = false;
  bool _submitted = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_confirmsOwnership) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please confirm that you own this account.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final service = ComplianceService(Supabase.instance.client);
      await service.requestAccountDeletion(
        email: _emailCtrl.text.trim(),
        reason: [
          if (_phoneCtrl.text.trim().isNotEmpty) 'Phone: ${_phoneCtrl.text.trim()}',
          if (_reasonCtrl.text.trim().isNotEmpty) _reasonCtrl.text.trim(),
        ].join(' | '),
      );
      setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit request: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Deletion Request', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: _submitted ? _successView(context) : _formView(context),
    );
  }

  Widget _successView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_read_outlined, color: AppTheme.successColor, size: 72),
            const SizedBox(height: 20),
            const Text(
              'Request Received',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your data deletion request has been received. We will review and process eligible deletion requests according to our policy within 30 days.\n\nYou may receive a confirmation email at the address provided.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(160, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Request deletion of your personal data from 7Dash. You do not need to be logged in to submit this form.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),

            _field(
              controller: _nameCtrl,
              label: 'Full Name',
              icon: Icons.person_outline,
              isDark: isDark,
              validator: (v) => v?.trim().isEmpty == true ? 'Please enter your name' : null,
            ),
            const SizedBox(height: 14),

            _field(
              controller: _emailCtrl,
              label: 'Email Address (used for account)',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              isDark: isDark,
              validator: (v) {
                if (v?.trim().isEmpty == true) return 'Please enter your email';
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v!)) return 'Please enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 14),

            _field(
              controller: _phoneCtrl,
              label: 'Phone Number (optional)',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              isDark: isDark,
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _reasonCtrl,
              maxLines: 3,
              decoration: _decoration('Reason (optional)', Icons.feedback_outlined, isDark),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),

            CheckboxListTile(
              value: _confirmsOwnership,
              onChanged: (v) => setState(() => _confirmsOwnership = v ?? false),
              title: const Text(
                'I confirm that I am the owner of this account and authorize the deletion of my personal data.',
                style: TextStyle(fontSize: 13),
              ),
              activeColor: AppTheme.primaryColor,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),

            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Transaction records may be retained for up to 7 years for legal and tax purposes. All personal identifiers will be removed. Contact ${AppConstants.supportEmailAddress} with questions.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                    )
                  : const Text('Submit Deletion Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon, bool isDark) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppTheme.primaryColor, size: 20),
      filled: true,
      fillColor: isDark ? Theme.of(context).colorScheme.surfaceContainerHighest : const Color(0xFFF9FAFB),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 2)),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 14),
      decoration: _decoration(label, icon, isDark),
    );
  }
}
