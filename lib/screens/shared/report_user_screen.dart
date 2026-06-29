// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../services/compliance_service.dart';
import '../../utils/app_theme.dart';

class ReportUserScreen extends ConsumerStatefulWidget {
  final String? reportedUserId;
  final String? messageId;
  final String? orderId;
  final String? reportedUserName;

  const ReportUserScreen({
    super.key,
    this.reportedUserId,
    this.messageId,
    this.orderId,
    this.reportedUserName,
  });

  @override
  ConsumerState<ReportUserScreen> createState() => _ReportUserScreenState();
}

class _ReportUserScreenState extends ConsumerState<ReportUserScreen> {
  String _selectedReason = 'Harassment or threatening behavior';
  final _detailsCtrl = TextEditingController();
  bool _isLoading = false;
  bool _submitted = false;

  static const _reasons = [
    'Harassment or threatening behavior',
    'Inappropriate messages or content',
    'Fraud or scam attempt',
    'Racism or discrimination',
    'Physical safety concern',
    'Fake identity or impersonation',
    'Other',
  ];

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to submit a report.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final service = ComplianceService(Supabase.instance.client);
      await service.submitChatReport(
        reporterId: currentUser.id,
        reportedUserId: widget.reportedUserId,
        messageId: widget.messageId,
        orderId: widget.orderId,
        reason: _selectedReason,
        details: _detailsCtrl.text.trim().isEmpty ? null : _detailsCtrl.text.trim(),
      );
      setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit report: ${e.toString()}'),
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
        title: const Text('Report', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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
            Icon(Icons.shield_outlined, color: AppTheme.successColor, size: 72),
            const SizedBox(height: 20),
            const Text('Report Submitted', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'Thank you for helping keep 7Dash safe. Our trust & safety team will review your report and take appropriate action.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(160, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Done'),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.reportedUserName != null) ...[
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text('Reporting: ${widget.reportedUserName}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('7Dash Trust & Safety', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            'Select a reason for this report:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          RadioGroup<String>(
            groupValue: _selectedReason,
            onChanged: (v) { if (v != null) setState(() => _selectedReason = v); },
            child: Column(
              children: _reasons.map(
                (r) => RadioListTile<String>(
                  value: r,
                  title: Text(r, style: const TextStyle(fontSize: 14)),
                  activeColor: AppTheme.primaryColor,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ).toList(),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _detailsCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Additional details (optional)',
              prefixIcon: const Icon(Icons.notes_outlined),
              filled: true,
              fillColor: isDark ? Theme.of(context).colorScheme.surfaceContainerHighest : const Color(0xFFF9FAFB),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 2)),
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Reports are anonymous. False or malicious reports may result in action against your account. For emergencies, contact local law enforcement.',
                style: TextStyle(fontSize: 12, height: 1.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
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
                : const Text('Submit Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
