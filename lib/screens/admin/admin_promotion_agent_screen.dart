// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';

/// Promotion Agent — drafts a promo code proposal grounded in Marketing
/// Strategy's promo_opportunities (at-risk restaurants with no active promo)
/// and Customer Retention's at-risk count. Drafting never creates anything;
/// only Approve & Create does, via ops-report-agent's promotion_agent action.
class AdminPromotionAgentScreen extends StatefulWidget {
  const AdminPromotionAgentScreen({super.key});

  @override
  State<AdminPromotionAgentScreen> createState() => _AdminPromotionAgentScreenState();
}

class _AdminPromotionAgentScreenState extends State<AdminPromotionAgentScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _opportunities = [];
  List<Map<String, dynamic>> _recentPromos = [];
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
      final results = await Future.wait([
        _client
            .from('ai_agent_runs')
            .select('output')
            .eq('agent_name', 'marketing_strategy')
            .eq('status', 'completed')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        _client.from('promo_codes').select().order('created_at', ascending: false).limit(10),
      ]);
      final strategyRun = results[0] as Map<String, dynamic>?;
      final metrics = (strategyRun?['output'] as Map?)?['metrics'] as Map?;
      final opportunities = (metrics?['promo_opportunities'] as List?) ?? [];
      if (mounted) {
        setState(() {
          _opportunities = opportunities.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _recentPromos = List<Map<String, dynamic>>.from(results[1] as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _openDraftSheet({String? restaurantId, String? restaurantName}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PromotionDraftSheet(restaurantId: restaurantId, restaurantName: restaurantName),
    ).whenComplete(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promotion Agent', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _openDraftSheet(),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Draft Platform-Wide Promotion'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text('Restaurants Needing a Promo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      const Text('From the Marketing Strategy agent\'s latest run — at-risk restaurants with no active promo.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 8),
                      if (_opportunities.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('None right now. Run Marketing Strategy to refresh this.', style: TextStyle(color: Colors.grey, fontSize: 13)))
                      else
                        ..._opportunities.map((o) => Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                              child: ListTile(
                                title: Text(o['restaurant']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                subtitle: Text('At-risk score: ${o['at_risk_score']}', style: const TextStyle(fontSize: 12)),
                                trailing: TextButton(
                                  onPressed: () => _openDraftSheet(restaurantId: o['restaurant_id']?.toString(), restaurantName: o['restaurant']?.toString()),
                                  child: const Text('Draft', style: TextStyle(fontSize: 12)),
                                ),
                                onTap: () => _openDraftSheet(restaurantId: o['restaurant_id']?.toString(), restaurantName: o['restaurant']?.toString()),
                              ),
                            )),
                      const SizedBox(height: 24),
                      Text('Recent Promo Codes (${_recentPromos.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (_recentPromos.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No promo codes created yet.', style: TextStyle(color: Colors.grey, fontSize: 13)))
                      else
                        ..._recentPromos.map((p) => Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                              child: ListTile(
                                title: Text(p['code'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'monospace')),
                                subtitle: Text(
                                  '${p['discount_type'] == 'percentage' ? '${p['discount_value']}% off' : '\$${p['discount_value']} off'} · ${p['usage_count'] ?? 0}/${p['max_uses'] ?? '∞'} used',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (p['is_active'] == true ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(p['is_active'] == true ? 'active' : 'inactive', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }
}

class _PromotionDraftSheet extends StatefulWidget {
  final String? restaurantId;
  final String? restaurantName;
  const _PromotionDraftSheet({this.restaurantId, this.restaurantName});

  @override
  State<_PromotionDraftSheet> createState() => _PromotionDraftSheetState();
}

class _PromotionDraftSheetState extends State<_PromotionDraftSheet> {
  final _codeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _discountValueCtrl = TextEditingController();
  final _maxUsesCtrl = TextEditingController();
  final _expiresInDaysCtrl = TextEditingController();
  String _discountType = 'percentage';
  String? _rationale;
  String? _runId;
  bool _drafting = false;
  bool _submitting = false;
  bool _hasDraft = false;
  bool _created = false;

  @override
  void initState() {
    super.initState();
    _generateDraft();
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

  Future<void> _generateDraft() async {
    setState(() => _drafting = true);
    try {
      final res = await Supabase.instance.client.functions.invoke('ops-report-agent', body: {
        'agent_slug': 'promotion_agent',
        if (widget.restaurantId != null) 'restaurant_id': widget.restaurantId,
      });
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      final proposal = Map<String, dynamic>.from(data['proposal'] as Map);
      setState(() {
        _codeCtrl.text = proposal['code'] ?? '';
        _descCtrl.text = proposal['description'] ?? '';
        _discountType = proposal['discount_type'] ?? 'percentage';
        _discountValueCtrl.text = '${proposal['discount_value'] ?? ''}';
        _maxUsesCtrl.text = '${proposal['max_uses'] ?? ''}';
        _expiresInDaysCtrl.text = '${proposal['expires_in_days'] ?? ''}';
        _rationale = proposal['rationale'] as String?;
        _runId = data['run_id'] as String?;
        _hasDraft = true;
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
        'agent_slug': 'promotion_agent',
        'decision': decision,
        'run_id': _runId,
        if (decision == 'approve') ...{
          'final_code': _codeCtrl.text.trim(),
          'final_description': _descCtrl.text.trim(),
          'final_discount_type': _discountType,
          'final_discount_value': double.tryParse(_discountValueCtrl.text.trim()) ?? 0,
          'final_max_uses': int.tryParse(_maxUsesCtrl.text.trim()) ?? 0,
          'final_expires_in_days': int.tryParse(_expiresInDaysCtrl.text.trim()) ?? 0,
          'final_restaurant_id': widget.restaurantId,
        },
      });
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      if (decision == 'approve') {
        setState(() => _created = true);
        final notified = data is Map ? data['customers_notified'] : null;
        _toast(notified != null ? 'Promo code created — $notified customer${notified == 1 ? '' : 's'} notified in-app.' : 'Promo code created.');
      } else {
        if (mounted) Navigator.of(context).pop();
      }
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
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
                const SizedBox(width: 6),
                Text(
                  widget.restaurantName != null ? 'Promotion for ${widget.restaurantName}' : 'Platform-Wide Promotion',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_drafting)
              const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 24), child: CircularProgressIndicator()))
            else if (_hasDraft) ...[
              if (_rationale != null && _rationale!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF7C3AED).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFEDE9FE))),
                  child: Text(_rationale!, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, height: 1.4)),
                ),
                const SizedBox(height: 14),
              ],
              TextField(controller: _codeCtrl, readOnly: _created, decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: _descCtrl, readOnly: _created, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
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
                      onChanged: _created ? null : (v) => setState(() => _discountType = v ?? 'percentage'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _discountValueCtrl,
                      readOnly: _created,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Discount', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _maxUsesCtrl,
                      readOnly: _created,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Max uses', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _expiresInDaysCtrl,
                      readOnly: _created,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Expires in (days)', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_created)
                const Text('✓ Promo code created', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w600))
              else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submitting ? null : () => _decide('approve'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                        child: _submitting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Approve & Create'),
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
