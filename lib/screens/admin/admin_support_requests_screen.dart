// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/compliance_service.dart';
import '../../services/ai/support_agent_service.dart';
import '../../utils/app_theme.dart';

class AdminSupportRequestsScreen extends StatefulWidget {
  const AdminSupportRequestsScreen({super.key});

  @override
  State<AdminSupportRequestsScreen> createState() =>
      _AdminSupportRequestsScreenState();
}

class _AdminSupportRequestsScreenState
    extends State<AdminSupportRequestsScreen> {
  late final ComplianceService _service;
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;
  String _filterStatus = 'all';

  static const _statuses = ['all', 'open', 'reviewing', 'resolved'];
  static const _statusColors = {
    'open': Color(0xFFF59E0B),
    'reviewing': Color(0xFF0077C8),
    'resolved': Color(0xFF10B981),
  };

  @override
  void initState() {
    super.initState();
    _service = ComplianceService(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _service.fetchSupportRequests(
        status: _filterStatus == 'all' ? null : _filterStatus,
        limit: 100,
      );
      if (mounted) setState(() { _requests = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await _service.updateSupportRequestStatus(id, status);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  void _showDetail(Map<String, dynamic> req) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _DetailSheet(
        request: req,
        onStatusChange: _updateStatus,
        onRefresh: _load,
      ),
    ).whenComplete(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Requests', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          // Status filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _statuses.map((s) {
                final selected = _filterStatus == s;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(s[0].toUpperCase() + s.substring(1)),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _filterStatus = s);
                      _load();
                    },
                    selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                    checkmarkColor: AppTheme.primaryColor,
                    labelStyle: TextStyle(
                      color: selected ? AppTheme.primaryColor : null,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorView(error: _error!, onRetry: _load)
                    : _requests.isEmpty
                        ? _EmptyView(status: _filterStatus)
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _requests.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final r = _requests[i];
                              final status = r['status'] as String? ?? 'open';
                              final color = _statusColors[status] ?? const Color(0xFF6B7280);
                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  onTap: () => _showDetail(r),
                                  leading: CircleAvatar(
                                    backgroundColor: color.withValues(alpha: 0.15),
                                    child: Icon(Icons.support_agent, color: color, size: 20),
                                  ),
                                  title: Text(
                                    r['name'] as String? ?? 'Unknown',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(r['category'] as String? ?? '', style: const TextStyle(fontSize: 12)),
                                      if (r['created_at'] != null)
                                        Text(
                                          _fmt(r['created_at'] as String),
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                    ],
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  String _fmt(String iso) {
    try {
      return DateFormat('MMM d, y – h:mm a').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }
}

class _DetailSheet extends StatefulWidget {
  final Map<String, dynamic> request;
  final Future<void> Function(String id, String status) onStatusChange;
  final VoidCallback onRefresh;

  const _DetailSheet({
    required this.request,
    required this.onStatusChange,
    required this.onRefresh,
  });

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  late Map<String, dynamic> _request;
  late final SupportAgentService _agentService;
  late final TextEditingController _replyCtrl;
  bool _drafting = false;
  bool _submitting = false;
  bool _issueCredit = true;

  @override
  void initState() {
    super.initState();
    _request = Map<String, dynamic>.from(widget.request);
    _agentService = SupportAgentService(Supabase.instance.client);
    _replyCtrl = TextEditingController(text: _request['ai_draft_reply'] as String? ?? '');
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppTheme.errorColor : null),
    );
  }

  Future<void> _generateDraft() async {
    setState(() => _drafting = true);
    try {
      final result = await _agentService.generateDraft(_request['id'] as String);
      setState(() {
        _request['ai_draft_reply'] = result['draft_reply'];
        _request['ai_suggested_action'] = result['suggested_action'];
        _request['ai_suggested_amount'] = result['suggested_amount'];
        _request['ai_confidence'] = result['confidence'];
        _request['ai_reasoning'] = result['reasoning'];
        _request['ai_status'] = 'drafted';
        _replyCtrl.text = result['draft_reply'] as String? ?? '';
      });
    } catch (e) {
      _toast('Draft failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  Future<void> _approve() async {
    setState(() => _submitting = true);
    try {
      final result = await _agentService.approve(
        supportRequestId: _request['id'] as String,
        finalReply: _replyCtrl.text.trim(),
        executeCredit: _issueCredit && _request['ai_suggested_action'] == 'credit',
      );
      setState(() {
        _request['ai_status'] = 'sent';
        _request['ai_final_reply'] = _replyCtrl.text.trim();
        _request['status'] = 'resolved';
      });
      final creditIssued = result['credit_issued'] == true;
      final emailSent = result['email_sent'] == true;
      _toast(
        'Sent to customer.'
        '${creditIssued ? ' Wallet credited \$${(result['credit_amount'] as num).toStringAsFixed(2)}.' : ''}'
        '${!emailSent ? ' (Email delivery could not be confirmed.)' : ''}',
      );
      widget.onRefresh();
    } catch (e) {
      _toast('Could not send: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _submitting = true);
    try {
      await _agentService.reject(_request['id'] as String);
      setState(() => _request['ai_status'] = 'rejected');
      widget.onRefresh();
    } catch (e) {
      _toast('Could not reject: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildAiSection() {
    final aiStatus = _request['ai_status'] as String?;
    final suggestedAction = _request['ai_suggested_action'] as String?;
    final suggestedAmount = _request['ai_suggested_amount'];
    final confidence = _request['ai_confidence'];
    final reasoning = _request['ai_reasoning'] as String?;
    final hasUser = _request['user_id'] != null;

    if (aiStatus == null || aiStatus == 'rejected') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (aiStatus == 'rejected')
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Previous AI draft was rejected.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _drafting ? null : _generateDraft,
              icon: _drafting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_drafting ? 'Drafting…' : 'Generate AI Draft Reply'),
            ),
          ),
        ],
      );
    }

    final sent = aiStatus == 'sent';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Chip(
              label: Text('Action: ${suggestedAction ?? 'none'}'),
              visualDensity: VisualDensity.compact,
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
            ),
            if (confidence != null)
              Chip(
                label: Text('Confidence: ${((confidence as num) * 100).toStringAsFixed(0)}%'),
                visualDensity: VisualDensity.compact,
              ),
            if (suggestedAmount != null)
              Chip(
                label: Text('Suggested: \$${(suggestedAmount as num).toStringAsFixed(2)}'),
                visualDensity: VisualDensity.compact,
                backgroundColor: const Color(0xFFFEF3C7),
              ),
          ],
        ),
        if (reasoning != null && reasoning.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(reasoning, style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _replyCtrl,
          maxLines: 6,
          readOnly: sent,
          decoration: InputDecoration(
            labelText: sent ? 'Reply sent' : 'Reply (edit before sending)',
            border: const OutlineInputBorder(),
            filled: sent,
            fillColor: sent ? Colors.grey[100] : null,
          ),
        ),
        if (!sent && suggestedAction == 'credit') ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _issueCredit,
            onChanged: hasUser ? (v) => setState(() => _issueCredit = v ?? false) : null,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(
              hasUser
                  ? 'Also issue \$${(suggestedAmount as num?)?.toStringAsFixed(2) ?? '0.00'} wallet credit'
                  : 'Cannot issue credit — guest ticket has no linked account',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (!sent)
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _submitting ? null : _approve,
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                  child: _submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Approve & Send'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _submitting ? null : _reject,
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorColor, side: BorderSide(color: AppTheme.errorColor)),
                child: const Text('Reject'),
              ),
            ],
          )
        else
          const Text('✓ Sent to customer', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w600)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = _request['id'] as String? ?? '';
    final status = _request['status'] as String? ?? 'open';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
        children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          Text('Support Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
          const SizedBox(height: 16),
          _Row(label: 'Name', value: _request['name'] ?? ''),
          _Row(label: 'Email', value: _request['email'] ?? ''),
          _Row(label: 'Category', value: _request['category'] ?? ''),
          if (_request['order_id'] != null) _Row(label: 'Order ID', value: _request['order_id']),
          _Row(label: 'Status', value: status),
          const Divider(height: 24),
          const Text('Message', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SelectableText(_request['message'] ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
          if (_request['admin_notes'] != null) ...[
            const Divider(height: 24),
            const Text('Admin Notes', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(_request['admin_notes'], style: const TextStyle(fontSize: 14, height: 1.5)),
          ],
          const Divider(height: 24),
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
              const SizedBox(width: 6),
              const Text('AI Support Assistant', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          _buildAiSection(),
          const Divider(height: 32),
          const Text('Update Status', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['open', 'reviewing', 'resolved'].map((s) {
              return OutlinedButton(
                onPressed: s == status ? null : () async {
                  await widget.onStatusChange(id, s);
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: s == status ? Colors.grey : AppTheme.primaryColor),
                ),
                child: Text(s[0].toUpperCase() + s.substring(1)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text('$label:', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF6B7280)))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String status;
  const _EmptyView({required this.status});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('No $status support requests', style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }
}
