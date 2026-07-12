import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';
import 'admin_customer_retention_screen.dart' show deliveryMessage;

/// Workflow Station — the native-Supabase equivalent of an n8n canvas.
/// Lists scheduled automations (pg_cron + automation-workflow-runner) with
/// their last-run status, a manual "Run Now" trigger, and drafts waiting on
/// human review. Every workflow ends at a draft unless auto-approve is on for
/// it — social campaign drafts actually post to real platforms (Facebook/
/// Instagram/X/TikTok) once approved here, same as retention/promotion send
/// real emails/promo codes once approved.
class AdminWorkflowStationScreen extends StatefulWidget {
  const AdminWorkflowStationScreen({super.key});

  @override
  State<AdminWorkflowStationScreen> createState() => _AdminWorkflowStationScreenState();
}

class _AdminWorkflowStationScreenState extends State<AdminWorkflowStationScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _workflows = [];
  List<Map<String, dynamic>> _drafts = [];
  List<Map<String, dynamic>> _retentionDrafts = [];
  List<Map<String, dynamic>> _promotionDrafts = [];
  bool _loading = true;
  String? _error;
  String? _runningSlug;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Both customer_retention_outreach and promotion_agent log their
  /// draft AND their approve/reject decision as separate ai_agent_runs rows
  /// (no dedicated status column, unlike marketing_content) — so "still
  /// pending" has to be derived here: a draft is pending unless a later
  /// decision row resolves it. See ops-report-agent's retentionApproveOutreach
  /// / approvePromotion for exactly how each decision row links back.
  List<Map<String, dynamic>> _pendingRetentionDrafts(List<Map<String, dynamic>> runs) {
    final byCustomer = <String, Map<String, dynamic>>{};
    for (final r in runs) {
      final id = r['entity_id'] as String?;
      if (id == null) continue;
      byCustomer.putIfAbsent(id, () => r); // runs arrive newest-first
    }
    return byCustomer.values.where((r) => (r['input'] as Map?)?['decision'] == null).toList();
  }

  List<Map<String, dynamic>> _pendingPromotionDrafts(List<Map<String, dynamic>> runs) {
    final drafts = <String, Map<String, dynamic>>{};
    final resolvedDraftIds = <String>{};
    for (final r in runs) {
      final decision = (r['input'] as Map?)?['decision'] as String?;
      if (decision == 'reject') {
        final id = r['entity_id'] as String?;
        if (id != null) resolvedDraftIds.add(id);
      } else if (decision == 'approve') {
        final runId = (r['input'] as Map?)?['run_id'] as String?;
        if (runId != null) resolvedDraftIds.add(runId);
      } else {
        final id = r['id'] as String?;
        if (id != null) drafts[id] = r;
      }
    }
    return drafts.values.where((r) => !resolvedDraftIds.contains(r['id'])).toList();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _client.from('automation_workflows').select().order('name'),
        _client.from('marketing_content').select().eq('status', 'draft').order('created_at', ascending: false),
        _client.from('ai_agent_runs').select().eq('agent_name', 'customer_retention_outreach').order('created_at', ascending: false).limit(100),
        _client.from('ai_agent_runs').select().eq('agent_name', 'promotion_agent').order('created_at', ascending: false).limit(100),
      ]);
      if (mounted) {
        setState(() {
          _workflows = List<Map<String, dynamic>>.from(results[0] as List);
          _drafts = List<Map<String, dynamic>>.from(results[1] as List);
          _retentionDrafts = _pendingRetentionDrafts(List<Map<String, dynamic>>.from(results[2] as List));
          _promotionDrafts = _pendingPromotionDrafts(List<Map<String, dynamic>>.from(results[3] as List));
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _describeCron(String cron) {
    const days = {'0': 'Sunday', '1': 'Monday', '2': 'Tuesday', '3': 'Wednesday', '4': 'Thursday', '5': 'Friday', '6': 'Saturday'};
    final parts = cron.split(' ');
    if (parts.length == 5) {
      final minute = parts[0], hour = parts[1], dow = parts[4];
      if (parts[2] == '*' && parts[3] == '*' && dow != '*' && days.containsKey(dow)) {
        final h = int.tryParse(hour) ?? 0;
        final m = int.tryParse(minute) ?? 0;
        final period = h >= 12 ? 'PM' : 'AM';
        final h12 = h % 12 == 0 ? 12 : h % 12;
        return 'Weekly, ${days[dow]} $h12:${m.toString().padLeft(2, '0')} $period';
      }
    }
    return cron;
  }

  Future<void> _toggleActive(Map<String, dynamic> workflow) async {
    try {
      await _client.from('automation_workflows').update({'is_active': !(workflow['is_active'] as bool)}).eq('id', workflow['id']);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor));
    }
  }

  Future<void> _toggleAutoApprove(Map<String, dynamic> workflow) async {
    final turningOn = !(workflow['auto_approve'] == true);
    if (turningOn) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Turn On Auto-Approve?'),
          content: Text(
            '"${workflow['name']}" will run start-to-finish with no human review — '
            '${workflow['slug'] == 'weekly_promotion_scan'
                ? 'promo codes will go live automatically'
                : workflow['slug'] == 'weekly_social_campaign'
                    ? 'posts will go live on your connected social accounts automatically'
                    : 'emails will be sent to real customers automatically'} '
            'every time it runs. You can turn this off again any time.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
              child: const Text('Turn On'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await _client.from('automation_workflows').update({'auto_approve': turningOn}).eq('id', workflow['id']);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor));
    }
  }

  Future<void> _runNow(Map<String, dynamic> workflow) async {
    setState(() => _runningSlug = workflow['slug']);
    try {
      final res = await _client.functions.invoke('automation-workflow-runner', body: {'workflow_slug': workflow['slug']});
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['summary'] ?? 'Workflow ran successfully')));
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Run failed: $e'), backgroundColor: AppTheme.errorColor));
    } finally {
      if (mounted) setState(() => _runningSlug = null);
    }
  }

  Future<void> _decideDraft(Map<String, dynamic> draft, String status, {int captionIndex = 0}) async {
    try {
      await _client.from('marketing_content').update({
        'status': status,
        'reviewed_by': _client.auth.currentUser?.id,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', draft['id']);

      if (status == 'approved') {
        final res = await _client.functions.invoke('automation-workflow-runner', body: {
          'publish_content_id': draft['id'],
          'caption_index': captionIndex,
        });
        final data = res.data;
        if (mounted) {
          final results = Map<String, dynamic>.from(data?['results'] as Map? ?? {});
          final posted = results.entries.where((e) => (e.value as Map?)?['ok'] == true).map((e) => e.key).toList();
          final msg = posted.isEmpty
              ? 'No platform posted — check credentials for Facebook/Instagram/X/TikTok in Workflow Station.'
              : 'Posted to: ${posted.join(', ')}';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: posted.isEmpty ? AppTheme.errorColor : null));
        }
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor));
    }
  }

  void _openRetentionSheet(Map<String, dynamic> run) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RetentionReviewSheet(run: run),
    ).whenComplete(_load);
  }

  void _openPromotionSheet(Map<String, dynamic> run) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PromotionReviewSheet(run: run),
    ).whenComplete(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workflow Station', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('Automations', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (_workflows.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No automations configured.', style: TextStyle(color: Colors.grey)))
                      else
                        ..._workflows.map((w) => _WorkflowCard(
                              workflow: w,
                              scheduleLabel: _describeCron(w['schedule_cron'] as String),
                              running: _runningSlug == w['slug'],
                              onToggle: () => _toggleActive(w),
                              onRunNow: () => _runNow(w),
                              onToggleAutoApprove: () => _toggleAutoApprove(w),
                            )),
                      const SizedBox(height: 24),
                      Text('Drafts Pending Review (${_drafts.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (_drafts.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Nothing waiting on review.', style: TextStyle(color: Colors.grey)))
                      else
                        ..._drafts.map((d) => _DraftCard(draft: d, onApprove: (captionIndex) => _decideDraft(d, 'approved', captionIndex: captionIndex), onReject: () => _decideDraft(d, 'rejected'))),
                      const SizedBox(height: 24),
                      Text('Retention Emails Pending Review (${_retentionDrafts.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (_retentionDrafts.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Nothing waiting on review.', style: TextStyle(color: Colors.grey)))
                      else
                        ..._retentionDrafts.map((r) {
                          final output = Map<String, dynamic>.from(r['output'] as Map? ?? {});
                          final input = Map<String, dynamic>.from(r['input'] as Map? ?? {});
                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                            child: ListTile(
                              onTap: () => _openRetentionSheet(r),
                              leading: const Icon(Icons.mail_outline, color: Color(0xFF7C3AED)),
                              title: Text(output['subject']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${input['days_since_last_order'] ?? '?'} days since last order', style: const TextStyle(fontSize: 12)),
                              trailing: const Icon(Icons.chevron_right, size: 18),
                            ),
                          );
                        }),
                      const SizedBox(height: 24),
                      Text('Promotions Pending Review (${_promotionDrafts.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (_promotionDrafts.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Nothing waiting on review.', style: TextStyle(color: Colors.grey)))
                      else
                        ..._promotionDrafts.map((r) {
                          final output = Map<String, dynamic>.from(r['output'] as Map? ?? {});
                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                            child: ListTile(
                              onTap: () => _openPromotionSheet(r),
                              leading: const Icon(Icons.local_offer_outlined, color: Color(0xFF7C3AED)),
                              title: Text(output['code']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'monospace')),
                              subtitle: Text(
                                output['restaurant_name'] != null ? 'For ${output['restaurant_name']}' : 'Platform-wide',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: const Icon(Icons.chevron_right, size: 18),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  static const _autoApproveSupportedSlugs = {'weekly_retention_outreach', 'weekly_promotion_scan', 'weekly_social_campaign'};

  final Map<String, dynamic> workflow;
  final String scheduleLabel;
  final bool running;
  final VoidCallback onToggle;
  final VoidCallback onRunNow;
  final VoidCallback onToggleAutoApprove;

  const _WorkflowCard({
    required this.workflow,
    required this.scheduleLabel,
    required this.running,
    required this.onToggle,
    required this.onRunNow,
    required this.onToggleAutoApprove,
  });

  @override
  Widget build(BuildContext context) {
    final active = workflow['is_active'] == true;
    final autoApprove = workflow['auto_approve'] == true;
    final supportsAutoApprove = _autoApproveSupportedSlugs.contains(workflow['slug']);
    final lastStatus = workflow['last_run_status'] as String?;
    final lastAt = workflow['last_run_at'] as String?;
    final lastSummary = workflow['last_run_summary'] as String?;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF7C3AED).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.schedule_rounded, color: Color(0xFF7C3AED), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(workflow['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(scheduleLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Switch(value: active, onChanged: (_) => onToggle(), activeThumbColor: AppTheme.primaryColor),
              ],
            ),
            if (workflow['description'] != null) ...[
              const SizedBox(height: 8),
              Text(workflow['description'], style: const TextStyle(fontSize: 12, height: 1.4)),
            ],
            if (supportsAutoApprove) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: autoApprove ? const Color(0xFFFEF2F2) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: autoApprove ? const Color(0xFFFCA5A5) : Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(autoApprove ? Icons.flash_on_rounded : Icons.flash_off_rounded, size: 16, color: autoApprove ? const Color(0xFFDC2626) : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        autoApprove ? 'Auto-approve ON — runs with no review' : 'Auto-approve off — drafts wait for review',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: autoApprove ? const Color(0xFFB91C1C) : Colors.grey[700]),
                      ),
                    ),
                    Switch(value: autoApprove, onChanged: (_) => onToggleAutoApprove(), activeThumbColor: const Color(0xFFDC2626)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (lastAt != null)
              Row(
                children: [
                  Icon(
                    lastStatus == 'failed' ? Icons.error_outline : Icons.check_circle_outline,
                    size: 14,
                    color: lastStatus == 'failed' ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Last run ${DateFormat('MMM d, h:mm a').format(DateTime.parse(lastAt).toLocal())}${lastSummary != null ? ' — $lastSummary' : ''}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            else
              const Text('Never run yet', style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: running ? null : onRunNow,
                icon: running
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow_rounded, size: 16),
                label: Text(running ? 'Running…' : 'Run Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftCard extends StatefulWidget {
  final Map<String, dynamic> draft;
  final void Function(int captionIndex) onApprove;
  final VoidCallback onReject;

  const _DraftCard({required this.draft, required this.onApprove, required this.onReject});

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final captions = List<String>.from(widget.draft['captions'] ?? []);
    final imageUrl = widget.draft['image_url'] as String?;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(imageUrl, height: 160, width: double.infinity, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(height: 160, color: Colors.grey.shade100, child: const Center(child: Icon(Icons.image_not_supported_outlined)))),
              ),
              const SizedBox(height: 10),
            ],
            const Text('Pick the caption to post:', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
            ...captions.asMap().entries.map((e) => RadioListTile<int>(
                  value: e.key,
                  groupValue: _selectedIndex,
                  onChanged: (v) => setState(() => _selectedIndex = v ?? 0),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value, style: const TextStyle(fontSize: 13, height: 1.4)),
                )),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => widget.onApprove(_selectedIndex),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                    child: const Text('Approve & Post'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: widget.onReject,
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorColor, side: BorderSide(color: AppTheme.errorColor)),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Reviews an existing scheduled-draft ai_agent_runs row for
/// customer_retention_outreach (source: weekly_retention_outreach) — unlike
/// AdminCustomerRetentionScreen's sheet, this never generates a new draft,
/// it only lets an admin edit/approve/reject the one already sitting here.
class _RetentionReviewSheet extends StatefulWidget {
  final Map<String, dynamic> run;
  const _RetentionReviewSheet({required this.run});

  @override
  State<_RetentionReviewSheet> createState() => _RetentionReviewSheetState();
}

class _RetentionReviewSheetState extends State<_RetentionReviewSheet> {
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _bodyCtrl;
  bool _submitting = false;
  bool _done = false;
  num? _discountPercent;

  @override
  void initState() {
    super.initState();
    final output = Map<String, dynamic>.from(widget.run['output'] as Map? ?? {});
    _subjectCtrl = TextEditingController(text: output['subject']?.toString() ?? '');
    _bodyCtrl = TextEditingController(text: output['body']?.toString() ?? '');
    _discountPercent = output['discount_percent'] as num?;
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

  Future<void> _decide(String decision) async {
    setState(() => _submitting = true);
    try {
      final res = await Supabase.instance.client.functions.invoke('ops-report-agent', body: {
        'agent_slug': 'customer_retention_outreach',
        'customer_id': widget.run['entity_id'],
        'decision': decision,
        if (decision == 'approve') 'final_subject': _subjectCtrl.text.trim(),
        if (decision == 'approve') 'final_body': _bodyCtrl.text.trim(),
        if (decision == 'approve' && _discountPercent != null) 'final_discount_percent': _discountPercent,
      });
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() => _done = true);
      if (decision == 'approve') {
        _toast(deliveryMessage(data));
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast('Failed: $e', isError: true);
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
            const Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
                SizedBox(width: 6),
                Text('Retention Email — Weekly Draft', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(controller: _subjectCtrl, decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _bodyCtrl, maxLines: 8, decoration: const InputDecoration(labelText: 'Message (edit before sending)', border: OutlineInputBorder())),
            if (_bodyCtrl.text.contains('[DISCOUNT]') || _bodyCtrl.text.contains('[PROMO_CODE]')) ...[
              const SizedBox(height: 8),
              Text(
                '[DISCOUNT] and [PROMO_CODE] will be replaced with a real, one-time ${_discountPercent ?? 15}% code when you approve.',
                style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_submitting || _done) ? null : () => _decide('approve'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                    child: _submitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Approve & Send'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: (_submitting || _done) ? null : () => _decide('reject'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorColor, side: BorderSide(color: AppTheme.errorColor)),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Reviews an existing scheduled-draft ai_agent_runs row for promotion_agent
/// (source: weekly_promotion_scan) — same "review what's already here, don't
/// generate a new one" discipline as _RetentionReviewSheet above.
class _PromotionReviewSheet extends StatefulWidget {
  final Map<String, dynamic> run;
  const _PromotionReviewSheet({required this.run});

  @override
  State<_PromotionReviewSheet> createState() => _PromotionReviewSheetState();
}

class _PromotionReviewSheetState extends State<_PromotionReviewSheet> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _discountValueCtrl;
  late final TextEditingController _maxUsesCtrl;
  late final TextEditingController _expiresInDaysCtrl;
  late String _discountType;
  late String? _restaurantId;
  String? _rationale;
  bool _submitting = false;
  bool _created = false;

  @override
  void initState() {
    super.initState();
    final output = Map<String, dynamic>.from(widget.run['output'] as Map? ?? {});
    _codeCtrl = TextEditingController(text: output['code']?.toString() ?? '');
    _descCtrl = TextEditingController(text: output['description']?.toString() ?? '');
    _discountType = output['discount_type']?.toString() ?? 'percentage';
    _discountValueCtrl = TextEditingController(text: '${output['discount_value'] ?? ''}');
    _maxUsesCtrl = TextEditingController(text: '${output['max_uses'] ?? ''}');
    _expiresInDaysCtrl = TextEditingController(text: '${output['expires_in_days'] ?? ''}');
    _restaurantId = output['restaurant_id']?.toString();
    _rationale = output['rationale']?.toString();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _descCtrl.dispose();
    _discountValueCtrl.dispose();
    _maxUsesCtrl.dispose();
    _expiresInDaysCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isError ? AppTheme.errorColor : null));
  }

  Future<void> _decide(String decision) async {
    setState(() => _submitting = true);
    try {
      final res = await Supabase.instance.client.functions.invoke('ops-report-agent', body: {
        'agent_slug': 'promotion_agent',
        'decision': decision,
        'run_id': widget.run['id'],
        if (decision == 'approve') ...{
          'final_code': _codeCtrl.text.trim(),
          'final_description': _descCtrl.text.trim(),
          'final_discount_type': _discountType,
          'final_discount_value': double.tryParse(_discountValueCtrl.text.trim()) ?? 0,
          'final_max_uses': int.tryParse(_maxUsesCtrl.text.trim()) ?? 0,
          'final_expires_in_days': int.tryParse(_expiresInDaysCtrl.text.trim()) ?? 0,
          'final_restaurant_id': _restaurantId,
        },
      });
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      if (decision == 'approve') {
        setState(() => _created = true);
        final notified = data is Map ? data['customers_notified'] : null;
        _toast(notified != null ? 'Promo code created — $notified customer${notified == 1 ? '' : 's'} notified in-app.' : 'Promo code created.');
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast('Failed: $e', isError: true);
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
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
                SizedBox(width: 6),
                Text('Promotion — Weekly Scan Draft', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 16),
            if (_rationale != null && _rationale!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF7C3AED).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFEDE9FE))),
                child: Text(_rationale!, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, height: 1.4)),
              ),
              const SizedBox(height: 14),
            ],
            TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _discountType,
                    decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'percentage', child: Text('% off')),
                      DropdownMenuItem(value: 'fixed', child: Text('\$ off')),
                    ],
                    onChanged: (v) => setState(() => _discountType = v ?? 'percentage'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _discountValueCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Discount', border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: TextField(controller: _maxUsesCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max uses', border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _expiresInDaysCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Expires in (days)', border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_submitting || _created) ? null : () => _decide('approve'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                    child: _submitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Approve & Create'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: (_submitting || _created) ? null : () => _decide('reject'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorColor, side: BorderSide(color: AppTheme.errorColor)),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
