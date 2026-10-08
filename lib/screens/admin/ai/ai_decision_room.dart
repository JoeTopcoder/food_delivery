import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/ai/ai_decision_service.dart';
import '../../../utils/app_theme.dart';

final _svc = AiDecisionService();

/// Access gate: {allowed, is_super_admin, used_today, daily_limit}.
final aiDecisionAccessProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return _svc.usage();
});

const _categories = [
  'operations', 'pricing', 'marketing', 'restaurants',
  'grocery', 'membership', 'technology', 'other'
];
const _statuses = ['draft', 'assessing', 'cross_review', 'synthesizing', 'completed', 'failed', 'cancelled'];

Color _statusColor(String s) => switch (s) {
      'completed' => const Color(0xFF22C55E),
      'failed' => Colors.red,
      'cancelled' => Colors.grey,
      'draft' => Colors.blueGrey,
      _ => AppTheme.primaryColor,
    };

// ═══════════════════════════ Dashboard ═══════════════════════════
class AiDecisionDashboardScreen extends ConsumerStatefulWidget {
  const AiDecisionDashboardScreen({super.key});
  @override
  ConsumerState<AiDecisionDashboardScreen> createState() => _DashState();
}

class _DashState extends ConsumerState<AiDecisionDashboardScreen> {
  String _search = '';
  String? _filter;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _svc.list();
  }

  void _reload() => setState(() => _future = _svc.list(status: _filter, search: _search));

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(aiDecisionAccessProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('AI Decision Room')),
      body: access.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (a) {
          if (a['allowed'] != true) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('You do not have access to the AI Decision Room.\nAsk the super admin to grant access.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return Column(children: [
            Container(
              width: double.infinity,
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              padding: const EdgeInsets.all(12),
              child: Text('Used today: ${a['used_today'] ?? 0} / ${a['daily_limit'] ?? 0}'
                  '${a['is_super_admin'] == true ? '   •   Super admin' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(
                    hintText: 'Search by title', prefixIcon: Icon(Icons.search), isDense: true,
                    border: OutlineInputBorder()),
                onChanged: (v) => _search = v,
                onSubmitted: (_) => _reload(),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                _chip('all', null),
                ..._statuses.map((s) => _chip(s, s)),
              ]),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (_, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final rows = snap.data!;
                  if (rows.isEmpty) return const Center(child: Text('No decisions yet'));
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _decisionCard(rows[i]),
                    ),
                  );
                },
              ),
            ),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<String>(
              context, MaterialPageRoute(builder: (_) => const AiDecisionNewScreen()));
          if (created != null && mounted) _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('New decision'),
      ),
    );
  }

  Widget _chip(String label, String? value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == value,
          onSelected: (_) => setState(() { _filter = value; _reload(); }),
        ),
      );

  Widget _decisionCard(Map<String, dynamic> d) {
    final status = (d['status'] ?? '').toString();
    return InkWell(
      onTap: () {
        final id = d['id'] as String;
        if (status == 'completed') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => AiDecisionReportScreen(decisionId: id)));
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => AiDecisionAnalysisScreen(decisionId: id)))
              .then((_) => _reload());
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(d['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(status, style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(d['question'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 6),
          Text('${d['category'] ?? ''} • ${(d['created_at'] ?? '').toString().substring(0, 10)}'
              '${d['final_choice'] != null ? '  ✓ decided' : ''}',
              style: const TextStyle(fontSize: 11, color: Colors.black38)),
        ]),
      ),
    );
  }
}

// ═══════════════════════════ New decision ═══════════════════════════
class AiDecisionNewScreen extends ConsumerStatefulWidget {
  const AiDecisionNewScreen({super.key});
  @override
  ConsumerState<AiDecisionNewScreen> createState() => _NewState();
}

class _NewState extends ConsumerState<AiDecisionNewScreen> {
  final _title = TextEditingController();
  final _question = TextEditingController();
  final _context = TextEditingController();
  final _options = TextEditingController();
  final _goals = TextEditingController();
  final _budget = TextEditingController();
  final _constraints = TextEditingController();
  String _category = 'other';
  String _synth = 'openai';
  bool _includeMetrics = false;
  Map<String, dynamic>? _metricsPreview;
  bool _busy = false;

  Future<void> _togglePreview(bool v) async {
    setState(() => _includeMetrics = v);
    if (v && _metricsPreview == null) {
      final m = await _svc.metricsPreview(days: 30);
      if (mounted) setState(() => _metricsPreview = m);
    }
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _question.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title and question are required')));
      return;
    }
    setState(() => _busy = true);
    final opts = _options.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final res = await _svc.create(
      title: _title.text.trim(), question: _question.text.trim(),
      context: _context.text.trim(), options: opts,
      goals: _goals.text.trim(), budget: _budget.text.trim(), constraints: _constraints.text.trim(),
      category: _category, includeMetrics: _includeMetrics, synthModel: _synth,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create: ${res.reason}')));
      return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AiDecisionAnalysisScreen(decisionId: res.id!)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New decision')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _field(_title, 'Title *'),
        _field(_question, 'Question *', lines: 2),
        _field(_context, 'Context (manual HotBite context)', lines: 3),
        _field(_options, 'Options (one per line)', lines: 3),
        _field(_goals, 'Goals'),
        _field(_budget, 'Budget'),
        _field(_constraints, 'Constraints', lines: 2),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setState(() => _category = v ?? 'other'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Synthesis model:'),
          const SizedBox(width: 12),
          ChoiceChip(label: const Text('OpenAI'), selected: _synth == 'openai', onSelected: (_) => setState(() => _synth = 'openai')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Claude'), selected: _synth == 'anthropic', onSelected: (_) => setState(() => _synth = 'anthropic')),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Include business metrics'),
          subtitle: const Text('Aggregate figures only — no customer identities, phones, addresses or payment data.'),
          value: _includeMetrics,
          onChanged: _togglePreview,
        ),
        if (_includeMetrics && _metricsPreview != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('These exact aggregates will be sent:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              Text(_metricsPreview.toString(), style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            ]),
          ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create & run'),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController c, String label, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c, maxLines: lines,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );
}

// ═══════════════════════════ Analysis (progress) ═══════════════════════════
class AiDecisionAnalysisScreen extends ConsumerStatefulWidget {
  final String decisionId;
  const AiDecisionAnalysisScreen({super.key, required this.decisionId});
  @override
  ConsumerState<AiDecisionAnalysisScreen> createState() => _AnalysisState();
}

class _AnalysisState extends ConsumerState<AiDecisionAnalysisScreen> {
  List<Map<String, dynamic>> _stages = [];
  String _status = '';
  bool _running = false;
  bool _mock = false;
  String? _error;

  static const _labels = {
    'openai_assess': 'OpenAI assessment',
    'claude_assess': 'Claude assessment',
    'openai_review': 'OpenAI cross-review',
    'claude_review': 'Claude cross-review',
    'synthesis': 'Synthesis',
  };

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _refreshStages() async {
    final s = await _svc.stages(widget.decisionId);
    final d = await _svc.get(widget.decisionId);
    if (mounted) setState(() { _stages = s; _status = (d?['status'] ?? '').toString(); });
  }

  Future<void> _run() async {
    setState(() { _running = true; _error = null; });
    await _refreshStages();
    for (var i = 0; i < 8; i++) {
      final res = await _svc.advance(widget.decisionId);
      await _refreshStages();
      if (res['mock'] == true) _mock = true;
      if (res['done'] == true) break;
      if (res['stage_status'] == 'failed' || res['ok'] == false) {
        setState(() => _error = (res['reason'] ?? 'stage_failed').toString());
        break;
      }
    }
    if (!mounted) return;
    setState(() => _running = false);
    if (_status == 'completed') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AiDecisionReportScreen(decisionId: widget.decisionId)));
    }
  }

  Future<void> _cancel() async {
    await _svc.cancel(widget.decisionId);
    await _refreshStages();
  }

  Future<void> _retry(String stage) async {
    await _svc.retryStage(widget.decisionId, stage);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analysis'), actions: [
        if (_running) TextButton(onPressed: _cancel, child: const Text('Cancel', style: TextStyle(color: Colors.white))),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_mock)
          Container(
            padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: const Text('⚠ MOCK MODE — a provider key is missing, so some results are placeholders, not real model output.',
                style: TextStyle(fontSize: 12, color: Colors.orange)),
          ),
        Text('Status: $_status', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ..._stages.map((s) {
          final st = (s['status'] ?? '').toString();
          final icon = switch (st) {
            'done' => const Icon(Icons.check_circle, color: Color(0xFF22C55E)),
            'running' => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            'failed' => const Icon(Icons.error, color: Colors.red),
            _ => const Icon(Icons.radio_button_unchecked, color: Colors.black26),
          };
          return ListTile(
            leading: icon,
            title: Text(_labels[s['stage']] ?? s['stage'].toString()),
            subtitle: s['error'] != null ? Text('${s['error']}', style: const TextStyle(color: Colors.red, fontSize: 12)) : null,
            trailing: st == 'failed'
                ? TextButton(onPressed: () => _retry(s['stage'].toString()), child: const Text('Retry'))
                : null,
          );
        }),
        if (_error != null) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Stopped: $_error', style: const TextStyle(color: Colors.red)),
        ),
        if (!_running && _status == 'completed')
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ElevatedButton(
              onPressed: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => AiDecisionReportScreen(decisionId: widget.decisionId))),
              child: const Text('View report'),
            ),
          ),
      ]),
    );
  }
}

// ═══════════════════════════ Report ═══════════════════════════
class AiDecisionReportScreen extends ConsumerStatefulWidget {
  final String decisionId;
  const AiDecisionReportScreen({super.key, required this.decisionId});
  @override
  ConsumerState<AiDecisionReportScreen> createState() => _ReportState();
}

class _ReportState extends ConsumerState<AiDecisionReportScreen> {
  Map<String, dynamic>? _d;
  List<Map<String, dynamic>> _stages = [];
  final _choice = TextEditingController();
  final _notes = TextEditingController();
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await _svc.get(widget.decisionId);
    final s = await _svc.stages(widget.decisionId);
    if (mounted) setState(() {
      _d = d; _stages = s;
      _choice.text = (d?['final_choice'] ?? '').toString();
      _notes.text = (d?['final_notes'] ?? '').toString();
    });
  }

  List<String> _arr(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : [];

  Map<String, dynamic>? _stageOut(String name) {
    for (final s in _stages) {
      if (s['stage'] == name) return (s['output'] as Map?)?.cast<String, dynamic>();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final r = (d['result'] as Map?)?.cast<String, dynamic>() ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('Decision report')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (r['mock'] == true)
          Container(
            padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: const Text('⚠ Contains MOCK output (a provider key was missing).', style: TextStyle(fontSize: 12, color: Colors.orange)),
          ),
        Text(d['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(d['question'] ?? '', style: const TextStyle(color: Colors.black54)),
        const Divider(height: 28),
        _section('✅ Final recommendation', [r['recommendation']?.toString() ?? '—']),
        _section('🤝 Agreements', _arr(r['agreements'])),
        _section('⚔️ Disagreements', _arr(r['disagreements'])),
        _section('🧩 Assumptions', _arr(r['assumptions'])),
        _section('🔍 Facts to verify', _arr(r['facts_to_verify'])),
        _section('➡️ Next 3 actions', _arr(r['next_actions'])),
        const Divider(height: 28),
        _collapsible('OpenAI assessment', _stageOut('openai_assess')),
        _collapsible('Claude assessment', _stageOut('claude_assess')),
        _collapsible('OpenAI cross-review', _stageOut('openai_review')),
        _collapsible('Claude cross-review', _stageOut('claude_review')),
        const Divider(height: 28),
        const Text('Your final decision', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const Text('Advisory only — this records your choice and notes; it changes no business data.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),
        TextField(controller: _choice, decoration: const InputDecoration(labelText: 'My decision', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final ok = await _svc.saveFinal(widget.decisionId, _choice.text.trim(), _notes.text.trim());
            if (mounted) {
              setState(() => _saved = ok);
              messenger.showSnackBar(SnackBar(content: Text(ok ? 'Saved' : 'Save failed')));
            }
          },
          child: Text(_saved ? 'Saved ✓' : 'Save my decision'),
        ),
      ]),
    );
  }

  Widget _section(String title, List<String> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 4),
        ...items.map((i) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('• $i', style: const TextStyle(fontSize: 14)),
            )),
      ]),
    );
  }

  Widget _collapsible(String title, Map<String, dynamic>? out) {
    if (out == null) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.all(12),
      children: [Align(alignment: Alignment.centerLeft, child: Text(out.toString(), style: const TextStyle(fontSize: 12)))],
    );
  }
}
