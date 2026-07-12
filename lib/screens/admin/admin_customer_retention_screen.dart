// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';

/// Summarizes the approve response's email_sent/push_sent pair into one
/// toast — email and in-app push are tried independently (push is the
/// fallback while the Resend sending domain is unverified), so either one
/// landing counts as delivered.
String deliveryMessage(Map data) {
  final emailSent = data['email_sent'] == true;
  final pushSent = data['push_sent'] == true;
  if (emailSent && pushSent) return 'Sent — email and in-app notification delivered.';
  if (emailSent) return 'Sent — email delivered.';
  if (pushSent) return 'Sent — in-app notification delivered (email failed, see run log).';
  return 'Could not confirm delivery on any channel — check the run log.';
}

/// Turns a raw FunctionException/Exception into something worth showing an
/// admin — FunctionException.toString() dumps its full Dart record syntax
/// (status/details/reasonPhrase), which reads as a crash log, not an error.
String friendlyErrorMessage(Object e) {
  if (e is FunctionException) {
    final details = e.details;
    if (details is Map) {
      final err = details['error']?.toString();
      if (err != null && err.trim().isNotEmpty) return err;
      final message = details['message']?.toString();
      if (message != null && message.trim().isNotEmpty) return message;
    }
    if (details is String && details.trim().isNotEmpty) return details;
    return 'Something went wrong (${e.status}).';
  }
  final msg = e.toString();
  return msg.startsWith('Exception: ') ? msg.substring('Exception: '.length) : msg;
}

/// Customer Retention Agent — finds customers who haven't ordered in 21+
/// days and lets an admin draft/approve a per-customer win-back email.
/// Drafting never sends anything; only Approve & Send does, via
/// ops-report-agent's customer_retention_outreach action. Never offers
/// outreach to a customer Fraud & Risk has flagged.
class AdminCustomerRetentionScreen extends StatefulWidget {
  const AdminCustomerRetentionScreen({super.key});

  @override
  State<AdminCustomerRetentionScreen> createState() => _AdminCustomerRetentionScreenState();
}

class _AdminCustomerRetentionScreenState extends State<AdminCustomerRetentionScreen> {
  bool _loading = false;
  String? _error;
  String? _narrative;
  List<Map<String, dynamic>> _atRisk = [];

  Future<void> _generate() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client.functions.invoke('ops-report-agent', body: {'agent_slug': 'customer_retention'});
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      final metrics = Map<String, dynamic>.from(data['metrics'] as Map);
      setState(() {
        _narrative = data['narrative'] as String?;
        _atRisk = List<Map<String, dynamic>>.from(metrics['at_risk_customers'] ?? []);
      });
    } catch (e) {
      setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openOutreachSheet(Map<String, dynamic> customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _OutreachSheet(customer: customer),
    );
  }

  /// Lets an admin draft/send outreach to a specific customer by email,
  /// regardless of whether they currently qualify as "at risk" — useful for
  /// verifying end-to-end delivery against a known real address (e.g. your
  /// own account) without waiting for it to naturally age into the list.
  Future<void> _testWithCustomer() async {
    final emailCtrl = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test With a Specific Customer'),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Customer email', hintText: 'name@example.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(emailCtrl.text.trim()), child: const Text('Look Up')),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;

    try {
      final data = await Supabase.instance.client
          .from('users')
          .select('id, name, email')
          .eq('role', 'customer')
          .ilike('email', email)
          .maybeSingle();
      if (data == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No customer found with email "$email".'), backgroundColor: AppTheme.errorColor));
        return;
      }
      _openOutreachSheet({'customer_id': data['id'], 'customer': data['name'] ?? data['email']});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lookup failed: ${friendlyErrorMessage(e)}'), backgroundColor: AppTheme.errorColor));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Retention', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.person_search_outlined), tooltip: 'Test With a Specific Customer', onPressed: _testWithCustomer),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _generate,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome),
              label: Text(_loading ? 'Working…' : 'Find At-Risk Customers'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_narrative != null && _narrative!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Card(
              elevation: 0,
              color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFEDE9FE))),
              child: Padding(padding: const EdgeInsets.all(16), child: Text(_narrative!, style: const TextStyle(fontSize: 14, height: 1.5))),
            ),
          ],
          if (_atRisk.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('At-Risk Customers (${_atRisk.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ..._atRisk.map((c) {
              final flagged = c['flagged_by_fraud_risk'] == true;
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                child: ListTile(
                  title: Text(c['customer']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    '${c['days_since_last_order']} days since last order · ${c['lifetime_orders']} lifetime orders · \$${c['lifetime_spend']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: flagged
                      ? const Chip(
                          label: Text('Fraud review', style: TextStyle(fontSize: 10)),
                          backgroundColor: Color(0xFFFEE2E2),
                          visualDensity: VisualDensity.compact,
                        )
                      : TextButton(onPressed: () => _openOutreachSheet(c), child: const Text('Draft Outreach', style: TextStyle(fontSize: 12))),
                  onTap: flagged ? null : () => _openOutreachSheet(c),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _OutreachSheet extends StatefulWidget {
  final Map<String, dynamic> customer;
  const _OutreachSheet({required this.customer});

  @override
  State<_OutreachSheet> createState() => _OutreachSheetState();
}

class _OutreachSheetState extends State<_OutreachSheet> {
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _drafting = false;
  bool _submitting = false;
  bool _hasDraft = false;
  bool _sent = false;
  num? _discountPercent;

  @override
  void initState() {
    super.initState();
    _generateDraft();
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isError ? AppTheme.errorColor : null));
  }

  Future<void> _generateDraft() async {
    setState(() => _drafting = true);
    try {
      final res = await Supabase.instance.client.functions.invoke('ops-report-agent', body: {
        'agent_slug': 'customer_retention_outreach',
        'customer_id': widget.customer['customer_id'],
      });
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() {
        _subjectCtrl.text = data['subject'] as String? ?? '';
        _bodyCtrl.text = data['body'] as String? ?? '';
        _discountPercent = data['discount_percent'] as num?;
        _hasDraft = true;
      });
    } catch (e) {
      _toast('Draft failed: ${friendlyErrorMessage(e)}', isError: true);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  Future<void> _decide(String decision) async {
    setState(() => _submitting = true);
    try {
      final res = await Supabase.instance.client.functions.invoke('ops-report-agent', body: {
        'agent_slug': 'customer_retention_outreach',
        'customer_id': widget.customer['customer_id'],
        'decision': decision,
        if (decision == 'approve') 'final_subject': _subjectCtrl.text.trim(),
        if (decision == 'approve') 'final_body': _bodyCtrl.text.trim(),
        if (decision == 'approve' && _discountPercent != null) 'final_discount_percent': _discountPercent,
      });
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      if (decision == 'approve') {
        setState(() => _sent = true);
        _toast(deliveryMessage(data));
      } else {
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      _toast('Failed: ${friendlyErrorMessage(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
                const SizedBox(width: 6),
                Expanded(child: Text('Win-back email — ${widget.customer['customer']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              ],
            ),
            const SizedBox(height: 16),
            if (_drafting)
              const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 24), child: CircularProgressIndicator()))
            else if (_hasDraft) ...[
              TextField(controller: _subjectCtrl, readOnly: _sent, decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                controller: _bodyCtrl,
                maxLines: 8,
                readOnly: _sent,
                decoration: InputDecoration(
                  labelText: _sent ? 'Sent' : 'Message (edit before sending)',
                  border: const OutlineInputBorder(),
                  filled: _sent,
                  fillColor: _sent ? Colors.grey[100] : null,
                ),
              ),
              if (!_sent && (_bodyCtrl.text.contains('[DISCOUNT]') || _bodyCtrl.text.contains('[PROMO_CODE]'))) ...[
                const SizedBox(height: 8),
                Text(
                  '[DISCOUNT] and [PROMO_CODE] will be replaced with a real, one-time ${_discountPercent ?? 15}% code when you send. Remove them if you don\'t want to offer a discount.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 14),
              if (_sent)
                const Text('✓ Sent to customer', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w600))
              else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submitting ? null : () => _decide('approve'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                        child: _submitting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Approve & Send'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _submitting ? null : () => _decide('reject'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorColor, side: BorderSide(color: AppTheme.errorColor)),
                      child: const Text('Reject'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
