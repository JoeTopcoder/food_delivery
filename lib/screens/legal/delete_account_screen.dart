// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/compliance_service.dart';
import '../../utils/app_theme.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirmCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _agreedToTerms = false;
  bool _isLoading = false;
  int _step = 0; // 0 = warning, 1 = confirm

  @override
  void dispose() {
    _confirmCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  bool get _canProceed =>
      _agreedToTerms && _confirmCtrl.text.trim() == 'DELETE';

  Future<void> _deleteAccount() async {
    if (!_canProceed) return;
    setState(() => _isLoading = true);
    try {
      final user = ref.read(currentUserProvider);
      final service = ComplianceService(Supabase.instance.client);
      // Log deletion request first
      await service.requestAccountDeletion(
        userId: user?.id,
        email: user?.email ?? '',
        reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      );
      // Then attempt account deletion via auth provider
      await ref.read(authNotifierProvider.notifier).deleteAccount();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/signin', (_) => false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your account deletion request has been submitted.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete account: ${e.toString()}'),
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
        title: const Text('Delete Account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: _step == 0 ? _warningStep(context) : _confirmStep(context),
    );
  }

  Widget _warningStep(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 36),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Before you delete your account',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Deleting your account is permanent and cannot be undone.',
            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          _WarningItem(
            icon: Icons.person_off_outlined,
            text: 'Your profile, name, email, and personal details will be removed.',
          ),
          _WarningItem(
            icon: Icons.notifications_off_outlined,
            text: 'You will stop receiving all notifications and messages.',
          ),
          _WarningItem(
            icon: Icons.credit_card_off_outlined,
            text: 'Your payment methods and wallet balance will be removed.',
          ),
          _WarningItem(
            icon: Icons.history_toggle_off_outlined,
            text: 'Order history and loyalty points cannot be recovered.',
          ),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFFFEF3C7),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Transaction records may be retained for up to 7 years as required by tax and financial regulations. This data will be anonymized and not linked to your identity.',
                style: TextStyle(fontSize: 13, color: Color(0xFF92400E), height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: () => setState(() => _step = 1),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text('I Understand, Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _confirmStep(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Confirm Account Deletion',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Optional reason
          TextFormField(
            controller: _reasonCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Reason for leaving (optional)',
              prefixIcon: const Icon(Icons.feedback_outlined),
              filled: true,
              fillColor: isDark ? Theme.of(context).colorScheme.surfaceContainerHighest : const Color(0xFFF9FAFB),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 2)),
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),

          // Confirmation checkbox
          CheckboxListTile(
            value: _agreedToTerms,
            onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
            title: const Text(
              'I understand that this action is permanent and cannot be undone.',
              style: TextStyle(fontSize: 13),
            ),
            activeColor: const Color(0xFFEF4444),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),

          // Type DELETE
          Text(
            'Type DELETE in the field below to confirm:',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 2),
            decoration: InputDecoration(
              hintText: 'DELETE',
              filled: true,
              fillColor: isDark ? Theme.of(context).colorScheme.surfaceContainerHighest : const Color(0xFFF9FAFB),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2)),
            ),
          ),
          const SizedBox(height: 28),

          ElevatedButton(
            onPressed: (_canProceed && !_isLoading) ? _deleteAccount : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE5E7EB),
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
                : const Text('Delete My Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _step = 0),
            child: const Text('Go Back'),
          ),
          const SizedBox(height: 12),
          Text(
            'Having trouble? Contact ${AppConstants.supportEmailAddress}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _WarningItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _WarningItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFEF4444), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
