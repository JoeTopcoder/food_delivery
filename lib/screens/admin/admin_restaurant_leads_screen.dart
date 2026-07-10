// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';

/// Restaurant Leads CRM — manual entry (this app has no external
/// business-data API to auto-discover prospects) plus the Restaurant Sales
/// Agent's draft/approve outreach flow. Drafting never sends anything;
/// only Approve & Send does, via ops-report-agent's restaurant_sales action.
class AdminRestaurantLeadsScreen extends StatefulWidget {
  const AdminRestaurantLeadsScreen({super.key});

  @override
  State<AdminRestaurantLeadsScreen> createState() => _AdminRestaurantLeadsScreenState();
}

class _AdminRestaurantLeadsScreenState extends State<AdminRestaurantLeadsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _leads = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _client.from('restaurant_leads').select().order('created_at', ascending: false);
      if (mounted) setState(() { _leads = List<Map<String, dynamic>>.from(data); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _showAddLeadSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddLeadSheet(onAdded: _load),
    );
  }

  void _showDetail(Map<String, dynamic> lead) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LeadDetailSheet(lead: lead, onChanged: _load),
    ).whenComplete(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurant Leads', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _showAddLeadSheet, child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _leads.isEmpty
                  ? const Center(child: Text('No leads yet. Tap + to add one you\'ve identified.', style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _leads.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final l = _leads[i];
                        final status = l['status'] as String? ?? 'new';
                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                          child: ListTile(
                            onTap: () => _showDetail(l),
                            title: Text(l['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text(l['cuisine_type'] ?? l['email'] ?? '', style: const TextStyle(fontSize: 12)),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                              child: Text(status, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _AddLeadSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddLeadSheet({required this.onAdded});

  @override
  State<_AddLeadSheet> createState() => _AddLeadSheetState();
}

class _AddLeadSheetState extends State<_AddLeadSheet> {
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cuisineCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('restaurant_leads').insert({
        'name': _nameCtrl.text.trim(),
        'contact_name': _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'cuisine_type': _cuisineCtrl.text.trim().isEmpty ? null : _cuisineCtrl.text.trim(),
        'source': _sourceCtrl.text.trim().isEmpty ? null : _sourceCtrl.text.trim(),
        'created_by': Supabase.instance.client.auth.currentUser?.id,
      });
      widget.onAdded();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _cuisineCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Add Restaurant Lead', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Restaurant Name *', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _contactCtrl, decoration: const InputDecoration(labelText: 'Contact Person', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _cuisineCtrl, decoration: const InputDecoration(labelText: 'Cuisine Type', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _sourceCtrl, decoration: const InputDecoration(labelText: 'Source (e.g. referral, drove by)', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Add Lead'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadDetailSheet extends StatefulWidget {
  final Map<String, dynamic> lead;
  final VoidCallback onChanged;
  const _LeadDetailSheet({required this.lead, required this.onChanged});

  @override
  State<_LeadDetailSheet> createState() => _LeadDetailSheetState();
}

class _LeadDetailSheetState extends State<_LeadDetailSheet> {
  late Map<String, dynamic> _lead;
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _drafting = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _lead = Map<String, dynamic>.from(widget.lead);
    final draft = _lead['ai_draft_outreach'] as String?;
    if (draft != null) {
      final parts = draft.split('\n\n');
      _subjectCtrl.text = parts.first.replaceFirst('Subject: ', '');
      _bodyCtrl.text = parts.length > 1 ? parts.sublist(1).join('\n\n') : '';
    }
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
      final res = await Supabase.instance.client.functions.invoke('ops-report-agent', body: {'agent_slug': 'restaurant_sales', 'lead_id': _lead['id']});
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() {
        _subjectCtrl.text = data['subject'] as String? ?? '';
        _bodyCtrl.text = data['body'] as String? ?? '';
        _lead['ai_status'] = 'drafted';
      });
    } catch (e) {
      _toast('Draft failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  Future<void> _decide(String decision) async {
    setState(() => _submitting = true);
    try {
      final res = await Supabase.instance.client.functions.invoke('ops-report-agent', body: {
        'agent_slug': 'restaurant_sales',
        'lead_id': _lead['id'],
        'decision': decision,
        if (decision == 'approve') 'final_subject': _subjectCtrl.text.trim(),
        if (decision == 'approve') 'final_body': _bodyCtrl.text.trim(),
      });
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() => _lead['ai_status'] = decision == 'approve' ? 'sent' : 'rejected');
      widget.onChanged();
      if (decision == 'approve') _toast(data['email_sent'] == true ? 'Sent to lead.' : 'Marked sent (email delivery could not be confirmed).');
    } catch (e) {
      _toast('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiStatus = _lead['ai_status'] as String?;
    final sent = aiStatus == 'sent';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(_lead['name'] ?? '', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            const SizedBox(height: 8),
            if (_lead['contact_name'] != null) Text('Contact: ${_lead['contact_name']}', style: const TextStyle(fontSize: 13)),
            if (_lead['email'] != null) Text('Email: ${_lead['email']}', style: const TextStyle(fontSize: 13)),
            if (_lead['phone'] != null) Text('Phone: ${_lead['phone']}', style: const TextStyle(fontSize: 13)),
            if (_lead['address'] != null) Text('Address: ${_lead['address']}', style: const TextStyle(fontSize: 13)),
            if (_lead['cuisine_type'] != null) Text('Cuisine: ${_lead['cuisine_type']}', style: const TextStyle(fontSize: 13)),
            if (_lead['source'] != null) Text('Source: ${_lead['source']}', style: const TextStyle(fontSize: 13)),
            const Divider(height: 28),
            Row(
              children: const [
                Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
                SizedBox(width: 6),
                Text('AI Sales Outreach', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            if (_lead['email'] == null)
              const Text('Add an email address to this lead before drafting outreach.', style: TextStyle(color: Colors.grey, fontSize: 12))
            else ...[
              if (aiStatus == null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _drafting ? null : _generateDraft,
                    icon: _drafting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(_drafting ? 'Drafting…' : 'Generate AI Draft Outreach'),
                  ),
                )
              else ...[
                TextField(controller: _subjectCtrl, readOnly: sent, decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(
                  controller: _bodyCtrl,
                  maxLines: 8,
                  readOnly: sent,
                  decoration: InputDecoration(
                    labelText: sent ? 'Sent' : 'Message (edit before sending)',
                    border: const OutlineInputBorder(),
                    filled: sent,
                    fillColor: sent ? Colors.grey[100] : null,
                  ),
                ),
                const SizedBox(height: 10),
                if (!sent)
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
                  )
                else
                  const Text('✓ Sent to lead', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w600)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
