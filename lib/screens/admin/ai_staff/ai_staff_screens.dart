import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../providers/ai_staff_provider.dart';
import '../../../utils/app_feedback_widgets.dart';

// ── Provenance labels ───────────────────────────────────────────────────────
// The spec requires clearly separating verified DB facts, AI analysis, and AI
// suggestions. These three chips are used consistently across every screen.
enum _Prov { verified, analysis, suggestion, insufficient }

Widget _provChip(_Prov p) {
  late Color c; late String t; late IconData ic;
  switch (p) {
    case _Prov.verified: c = const Color(0xFF10B981); t = 'Verified data'; ic = Icons.verified_rounded; break;
    case _Prov.analysis: c = const Color(0xFF7C3AED); t = 'AI analysis'; ic = Icons.psychology_rounded; break;
    case _Prov.suggestion: c = const Color(0xFFFF6B35); t = 'AI suggestion'; ic = Icons.lightbulb_rounded; break;
    case _Prov.insufficient: c = const Color(0xFF6B7280); t = 'Insufficient data'; ic = Icons.help_outline_rounded; break;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ic, size: 13, color: c),
      const SizedBox(width: 4),
      Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
    ]),
  );
}

Color _sevColor(String s) {
  switch (s) {
    case 'critical': return const Color(0xFFDC2626);
    case 'high': return const Color(0xFFEA580C);
    case 'warning': return const Color(0xFFF59E0B);
    default: return const Color(0xFF6B7280);
  }
}

Color _priorityColor(String p) {
  switch (p) {
    case 'urgent': return const Color(0xFFDC2626);
    case 'high': return const Color(0xFFEA580C);
    case 'medium': return const Color(0xFF2563EB);
    default: return const Color(0xFF6B7280);
  }
}

String _ago(DateTime? t) {
  if (t == null) return 'never';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

// ════════════════════════════════════════════════════════════════════════════
// HUB
// ════════════════════════════════════════════════════════════════════════════
class AiStaffHubScreen extends StatelessWidget {
  const AiStaffHubScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final tiles = <List<dynamic>>[
      ["Today's Briefing", Icons.summarize_rounded, const Color(0xFF155EEF), '/admin-ai-staff/briefing'],
      ['AI Staff (24 roles)', Icons.groups_rounded, const Color(0xFF7C3AED), '/admin-ai-staff/roles'],
      ['Suggestions', Icons.lightbulb_rounded, const Color(0xFFFF6B35), '/admin-ai-staff/suggestions'],
      ['Alerts', Icons.warning_amber_rounded, const Color(0xFFDC2626), '/admin-ai-staff/alerts'],
      ['History', Icons.history_rounded, const Color(0xFF0891B2), '/admin-ai-staff/history'],
      ['Banner Studio', Icons.auto_awesome_rounded, const Color(0xFFFF6B00), '/admin-ai-banner-studio'],
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('AI Staff'), actions: const [_RunNowButton()]),
      body: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 700 ? 3 : 2;
        return GridView.count(
          crossAxisCount: cols,
          padding: const EdgeInsets.all(16),
          mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.1,
          children: tiles.map((t) => _hubTile(context, t[0] as String, t[1] as IconData, t[2] as Color, t[3] as String)).toList(),
        );
      }),
    );
  }

  Widget _hubTile(BuildContext context, String label, IconData icon, Color color, String route) => InkWell(
        onTap: () => Navigator.of(context).pushNamed(route),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 34, color: color),
            const SizedBox(height: 10),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
      );
}

/// Admin-only "Run reports now" control (testing / recovery). Confirms first,
/// disables while running to avoid rapid re-fires, and relies on the server's
/// per-day upsert so a repeat press cannot create duplicate reports. It only
/// triggers report generation — it performs no operational change.
class _RunNowButton extends ConsumerStatefulWidget {
  const _RunNowButton();
  @override
  ConsumerState<_RunNowButton> createState() => _RunNowButtonState();
}

class _RunNowButtonState extends ConsumerState<_RunNowButton> {
  bool _running = false;

  Future<void> _run() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Run AI staff reports now?'),
        content: const Text(
          'This generates all 24 staff reports and the combined briefing for today, '
          'using AI credits. It records suggestions for review only — it changes '
          'nothing operationally. Runs are de-duplicated per day.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Run now')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _running = true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'ai-staff-daily-report', body: {'run_briefing': true, 'triggered_by': 'admin_manual'});
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      if (mounted) {
        AppSnackbar.success(context, 'Reports generated. Refreshing…');
        ref.invalidate(aiTodayBriefingProvider);
        ref.invalidate(aiLatestReportsProvider);
        ref.invalidate(aiSuggestionsProvider);
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Run failed: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => _running
      ? const Padding(padding: EdgeInsets.all(14),
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
      : IconButton(icon: const Icon(Icons.play_circle_fill_rounded), tooltip: 'Run reports now', onPressed: _run);
}

// ════════════════════════════════════════════════════════════════════════════
// 1. TODAY'S BRIEFING
// ════════════════════════════════════════════════════════════════════════════
class AiBriefingScreen extends ConsumerWidget {
  const AiBriefingScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(aiTodayBriefingProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Briefing"), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(aiTodayBriefingProvider)),
      ]),
      body: async.when(
        loading: () => const AppLoadingIndicator(message: 'Loading briefing...'),
        error: (e, _) => AppErrorState(message: e.toString(), onRetry: () => ref.invalidate(aiTodayBriefingProvider)),
        data: (b) {
          if (b == null) {
            return const AppEmptyState(
              icon: Icons.summarize_rounded, title: 'No briefing yet',
              subtitle: 'The daily briefing runs once the AI staff reports are generated for a business day.');
          }
          final totals = (b.metrics['verified_totals'] as Map?)?.cast<String, dynamic>() ?? {};
          final issues = (b.highlights['top_issues'] as List?) ?? const [];
          final actions = (b.highlights['top_actions'] as List?) ?? const [];
          final approvals = (b.highlights['approvals'] as List?) ?? const [];
          final failures = (b.highlights['failures'] as Map?)?.cast<String, dynamic>() ?? {};
          final failedReports = (failures['failed_reports'] as List?) ?? const [];
          final missing = (failures['missing_data'] as List?) ?? const [];
          final changes = b.highlights['notable_changes']?.toString() ?? '';
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(b.headline ?? 'HotBite daily briefing', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(b.briefingDate, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 6),
            Row(children: [
              _statusPill('${b.rolesReported} roles reported', const Color(0xFF10B981)),
              const SizedBox(width: 6),
              _statusPill('${b.suggestionsCount} suggestions', const Color(0xFFFF6B35)),
              const SizedBox(width: 6),
              _statusPill('${b.urgentCount} alerts', const Color(0xFFDC2626)),
            ]),
            const SizedBox(height: 16),

            // Verified totals
            _sectionHeader('Verified company totals', _Prov.verified),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: totals.entries.map((e) {
              final unavailable = e.value == 'data_unavailable';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.25))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(e.key, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  const SizedBox(height: 2),
                  unavailable
                      ? _provChip(_Prov.insufficient)
                      : Text('${e.value}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ]),
              );
            }).toList()),
            const SizedBox(height: 20),

            if (b.summary != null && b.summary!.isNotEmpty) ...[
              _sectionHeader('Executive summary', _Prov.analysis),
              const SizedBox(height: 6),
              Text(b.summary!),
              const SizedBox(height: 20),
            ],

            _sectionHeader('Top operational issues', _Prov.analysis),
            const SizedBox(height: 8),
            if (issues.isEmpty) Text('None flagged.', style: TextStyle(color: Colors.grey[600])),
            ...issues.map((i) => _issueCard(context, Map<String, dynamic>.from(i as Map))),
            const SizedBox(height: 20),

            _sectionHeader('Top suggested actions', _Prov.suggestion),
            const SizedBox(height: 8),
            if (actions.isEmpty) Text('None.', style: TextStyle(color: Colors.grey[600])),
            ...actions.map((a) => _actionCard(context, Map<String, dynamic>.from(a as Map))),
            const SizedBox(height: 20),

            _sectionHeader('Decisions needing approval', _Prov.suggestion),
            const SizedBox(height: 4),
            Text('${approvals.length} suggestion(s) pending human review.', style: TextStyle(color: Colors.grey[700])),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/admin-ai-staff/suggestions'),
              icon: const Icon(Icons.rule_rounded, size: 16), label: const Text('Open suggestions workflow')),
            const SizedBox(height: 20),

            if (changes.isNotEmpty) ...[
              _sectionHeader('Important changes vs previous day', _Prov.analysis),
              const SizedBox(height: 6),
              Text(changes),
              const SizedBox(height: 20),
            ],

            _sectionHeader('Report status', _Prov.verified),
            const SizedBox(height: 6),
            if (failedReports.isEmpty)
              Text('All AI staff reports generated successfully.', style: TextStyle(color: Colors.grey[700]))
            else
              ...failedReports.map((f) {
                final m = Map<String, dynamic>.from(f as Map);
                return _bullet('Failed: ${m['role']} — ${m['error']}', const Color(0xFFDC2626));
              }),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [const Text('Missing / limited data', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(width: 8), _provChip(_Prov.insufficient)]),
              const SizedBox(height: 4),
              ...missing.take(30).map((s) => _bullet(s.toString(), const Color(0xFF6B7280))),
            ],
            const SizedBox(height: 40),
          ]);
        },
      ),
    );
  }

  Widget _statusPill(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)));

  Widget _sectionHeader(String t, _Prov p) => Row(children: [
        Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8), _provChip(p),
      ]);

  Widget _bullet(String t, Color c) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 6, right: 8), child: Icon(Icons.circle, size: 6, color: c)),
        Expanded(child: Text(t, style: const TextStyle(fontSize: 13))),
      ]));

  Widget _issueCard(BuildContext context, Map<String, dynamic> i) {
    final roles = (i['source_roles'] as List?) ?? const [];
    final refs = (i['metric_references'] as List?) ?? const [];
    final sev = i['severity']?.toString() ?? 'info';
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: _sevColor(sev), width: 4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(i['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(i['detail']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
        if (roles.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Combined from: ${roles.join(', ')}', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
        ],
        if (refs.isNotEmpty) Text('Metrics: ${refs.join(', ')}', style: TextStyle(fontSize: 11, color: const Color(0xFF10B981))),
      ]),
    );
  }

  Widget _actionCard(BuildContext context, Map<String, dynamic> a) => Container(
        margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFF6B35).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(a['why']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
          if (a['role'] != null) Text('From: ${a['role']}${a['priority'] != null ? ' · ${a['priority']}' : ''}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// 2. AI STAFF (24 roles) + role report pages
// ════════════════════════════════════════════════════════════════════════════
class AiRolesScreen extends ConsumerWidget {
  const AiRolesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesA = ref.watch(aiRolesProvider);
    final latest = ref.watch(aiLatestReportsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('AI Staff')),
      body: rolesA.when(
        loading: () => const AppLoadingIndicator(message: 'Loading roles...'),
        error: (e, _) => AppErrorState(message: e.toString(), onRetry: () => ref.invalidate(aiRolesProvider)),
        data: (roles) => ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: roles.length,
          itemBuilder: (context, idx) {
            final r = roles[idx];
            final rep = latest.valueOrNull?[r.id];
            final active = r.status == 'active';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: (active ? const Color(0xFF10B981) : Colors.grey).withValues(alpha: 0.15),
                  child: Icon(Icons.smart_toy_rounded, color: active ? const Color(0xFF10B981) : Colors.grey)),
                title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.jobDescription, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: (active ? const Color(0xFF10B981) : Colors.grey).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(active ? 'Active' : r.status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: active ? const Color(0xFF10B981) : Colors.grey))),
                    const SizedBox(width: 8),
                    Text('Last report: ${rep != null ? '${rep.reportDate} (${_ago(rep.createdAt)})' : 'never'}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ]),
                ]),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiRoleReportsScreen(role: r))),
              ),
            );
          },
        ),
      ),
    );
  }
}

class AiRoleReportsScreen extends ConsumerWidget {
  final AiRole role;
  const AiRoleReportsScreen({super.key, required this.role});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(aiRoleReportsProvider(role.id));
    return Scaffold(
      appBar: AppBar(title: Text(role.title)),
      body: async.when(
        loading: () => const AppLoadingIndicator(message: 'Loading reports...'),
        error: (e, _) => AppErrorState(message: e.toString(), onRetry: () => ref.invalidate(aiRoleReportsProvider(role.id))),
        data: (reports) => ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Job description', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(role.jobDescription, style: const TextStyle(fontSize: 13)),
              if (role.dailyReporting != null) ...[
                const SizedBox(height: 8),
                const Text('Daily reporting', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(role.dailyReporting!, style: const TextStyle(fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          const Text('Reports', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (reports.isEmpty)
            const AppEmptyState(icon: Icons.description_outlined, title: 'No reports yet',
                subtitle: 'This role has not produced a daily report.'),
          ...reports.map((rep) => _reportTile(context, rep)),
        ]),
      ),
    );
  }

  Widget _reportTile(BuildContext context, AiStaffReport rep) {
    final failed = rep.status == 'failed';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Row(children: [
          Text(rep.reportDate, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          if (failed) _provChip(_Prov.insufficient) else _provChip(_Prov.analysis),
        ]),
        subtitle: Text(failed ? 'Report failed' : (rep.summary ?? ''), maxLines: 2, overflow: TextOverflow.ellipsis),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (failed) ...[
                Text('Error: ${rep.error ?? 'unknown'}', style: const TextStyle(color: Color(0xFFDC2626))),
              ] else ...[
                Row(children: [const Text('Summary ', style: TextStyle(fontWeight: FontWeight.w700)), _provChip(_Prov.analysis)]),
                const SizedBox(height: 4),
                Text(rep.summary ?? ''),
                const SizedBox(height: 10),
                const Text('Findings', style: TextStyle(fontWeight: FontWeight.w700)),
                ...rep.findings.map((f) {
                  final m = Map<String, dynamic>.from(f as Map);
                  final refs = (m['metric_references'] as List?) ?? const [];
                  return Padding(padding: const EdgeInsets.only(top: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('• ${m['text']}', style: const TextStyle(fontSize: 13)),
                    if (refs.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 12),
                        child: Text('metrics: ${refs.join(', ')}', style: const TextStyle(fontSize: 11, color: Color(0xFF10B981)))),
                  ]));
                }),
                if (rep.dataLimitations.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: [const Text('Data limitations ', style: TextStyle(fontWeight: FontWeight.w700)), _provChip(_Prov.insufficient)]),
                  Text(rep.dataLimitations, style: const TextStyle(fontSize: 13)),
                ],
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 3. SUGGESTIONS workflow
// ════════════════════════════════════════════════════════════════════════════
class AiSuggestionsScreen extends ConsumerStatefulWidget {
  const AiSuggestionsScreen({super.key});
  @override
  ConsumerState<AiSuggestionsScreen> createState() => _AiSuggestionsScreenState();
}

class _AiSuggestionsScreenState extends ConsumerState<AiSuggestionsScreen> {
  // Label → DB status. "New" == pending.
  final _filters = const {
    'New': 'pending', 'Approved': 'approved', 'Rejected': 'rejected',
    'Assigned': 'assigned', 'In Progress': 'in_progress', 'Completed': 'completed',
  };
  String _sel = 'New';

  @override
  Widget build(BuildContext context) {
    final status = _filters[_sel];
    final async = ref.watch(aiSuggestionsProvider(status));
    return Scaffold(
      appBar: AppBar(title: const Text('Suggestions')),
      body: Column(children: [
        // Human-workflow guardrail banner.
        Container(
          width: double.infinity, color: const Color(0xFFFFF7ED),
          padding: const EdgeInsets.all(10),
          child: const Text(
            'Approving records a decision only. Changes to prices, refunds, payouts, rider restrictions or customer messages still go through their existing authorised workflow — the AI never executes them.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF9A3412))),
        ),
        SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final k in _filters.keys) Padding(padding: const EdgeInsets.only(right: 8, top: 8),
            child: ChoiceChip(label: Text(k), selected: _sel == k, onSelected: (_) => setState(() => _sel = k))),
        ])),
        Expanded(child: async.when(
          loading: () => const AppLoadingIndicator(message: 'Loading...'),
          error: (e, _) => AppErrorState(message: e.toString(), onRetry: () => ref.invalidate(aiSuggestionsProvider(status))),
          data: (list) => list.isEmpty
              ? AppEmptyState(icon: Icons.inbox_rounded, title: 'Nothing in "$_sel"', subtitle: 'No suggestions in this state.')
              : ListView.builder(padding: const EdgeInsets.all(12), itemCount: list.length,
                  itemBuilder: (context, i) => _card(list[i])),
        )),
      ]),
    );
  }

  Widget _card(AiSuggestion s) {
    final actions = ref.read(aiStaffActionsProvider);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: _priorityColor(s.priority).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
            child: Text(s.priority, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _priorityColor(s.priority)))),
        ]),
        const SizedBox(height: 4),
        Row(children: [_provChip(_Prov.suggestion)]),
        const SizedBox(height: 6),
        Text(s.description, style: const TextStyle(fontSize: 13)),
        if (s.rationale != null && s.rationale!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Evidence: ${s.rationale}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
        // ── Action proposal preview ──
        if (s.actionType != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (s.requiresManualAdmin ? const Color(0xFFDC2626) : const Color(0xFF2563EB)).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: (s.requiresManualAdmin ? const Color(0xFFDC2626) : const Color(0xFF2563EB)).withValues(alpha: 0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(s.requiresManualAdmin ? Icons.lock_person_rounded : Icons.bolt_rounded, size: 14,
                    color: s.requiresManualAdmin ? const Color(0xFFDC2626) : const Color(0xFF2563EB)),
                const SizedBox(width: 6),
                Expanded(child: Text('Proposed action: ${s.actionType}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
              ]),
              if (s.actionPayload?['title'] != null)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text('${s.actionPayload!['title']}', style: const TextStyle(fontSize: 12))),
              if (s.hasExternalEffect)
                const Padding(padding: EdgeInsets.only(top: 2),
                    child: Text('⚠ External effect — needs separate confirmation', style: TextStyle(fontSize: 11, color: Color(0xFFEA580C)))),
            ]),
          ),
        ],
        // Pricing/fee proposals are never AI-executable.
        if (s.requiresManualAdmin)
          const Padding(padding: EdgeInsets.only(top: 6),
              child: Text('🔒 Manual admin action required — pricing/fees are never changed by AI.',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)))),
        // Execution status + evidence
        _ExecutionStatus(suggestionId: s.id),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: _buttonsFor(s, actions)),
      ])),
    );
  }

  List<Widget> _buttonsFor(AiSuggestion s, AiStaffActions actions) {
    Future<void> decide(String decision, String label) async {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text('$label?'),
        content: Text(decision == 'execute'
            ? 'The responsible AI role will carry out this approved action and verify the result. It cannot change any price, fee, order, account or send a message.'
            : 'Record this decision.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(label)),
        ]));
      if (ok != true) return;
      try {
        final r = await actions.decideAction(s.id, decision);
        if (mounted) AppSnackbar.success(context, 'Result: ${r['status'] ?? 'done'}');
      } catch (e) { if (mounted) AppSnackbar.error(context, e.toString()); }
    }

    // Terminal / in-flight states: show status, no actions.
    const terminal = {'completed', 'cancelled', 'failed', 'assigned_to_human', 'blocked'};
    if (terminal.contains(s.actionStatus)) {
      return [Text('Status: ${s.actionStatus}', style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600))];
    }
    // New / awaiting: offer decisions appropriate to whether it's executable.
    if (s.status == 'pending' || s.actionStatus == 'awaiting_approval' || s.actionStatus == 'suggested' || s.actionStatus == 'awaiting_more_detail') {
      final btns = <Widget>[];
      if (s.requiresManualAdmin) {
        // Pricing: NO execute option, ever.
        btns.add(ElevatedButton(onPressed: () => decide('assign_human', 'Assign to human'), child: const Text('Assign to human')));
      } else if (s.isExecutable) {
        btns.add(ElevatedButton(onPressed: () => decide('execute', 'Approve & Execute'), child: const Text('Approve & Execute')));
        btns.add(OutlinedButton(onPressed: () => decide('investigate', 'Approve for investigation'), child: const Text('Investigate')));
        btns.add(OutlinedButton(onPressed: () => decide('assign_human', 'Assign to human'), child: const Text('Assign human')));
      } else {
        // Vague: cannot execute — only investigate / assign / reject.
        btns.add(ElevatedButton(onPressed: () => decide('investigate', 'Approve for investigation'), child: const Text('Approve for investigation')));
        btns.add(OutlinedButton(onPressed: () => decide('assign_human', 'Assign to human'), child: const Text('Assign human')));
      }
      btns.add(TextButton(onPressed: () => decide('reject', 'Reject'), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Reject')));
      return btns;
    }
    return [Text('Status: ${s.actionStatus ?? s.status}', style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600))];
  }
}

/// Shows the execution/task evidence for a suggestion (result of AI work).
class _ExecutionStatus extends ConsumerWidget {
  final String suggestionId;
  const _ExecutionStatus({required this.suggestionId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(aiSuggestionWorkProvider(suggestionId));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (w) {
        final execs = (w['executions'] as List);
        final tasks = (w['tasks'] as List);
        if (execs.isEmpty && tasks.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final e in execs) Builder(builder: (_) {
              final m = Map<String, dynamic>.from(e as Map);
              final st = m['status']?.toString() ?? '';
              final color = st == 'completed' ? const Color(0xFF10B981)
                  : st == 'failed' ? const Color(0xFFDC2626)
                  : st == 'waiting_human' ? const Color(0xFFEA580C) : const Color(0xFF6B7280);
              final recs = (m['records_affected'] as List?) ?? const [];
              return Container(
                margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(st == 'completed' ? Icons.check_circle : st == 'failed' ? Icons.error : Icons.hourglass_bottom, size: 14, color: color),
                    const SizedBox(width: 6),
                    Text('Execution: $st', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                  ]),
                  if (m['error'] != null) Text('Error: ${m['error']}', style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
                  if (recs.isNotEmpty) Text('Records affected: ${recs.length}', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                  if (m['verification'] != null) Text('Verified ✓', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                ]),
              );
            }),
            for (final tk in tasks) Builder(builder: (_) {
              final m = Map<String, dynamic>.from(tk as Map);
              return Row(children: [
                const Icon(Icons.assignment_rounded, size: 13, color: Color(0xFF2563EB)),
                const SizedBox(width: 6),
                Expanded(child: Text('Task: ${m['title']} · ${m['status']}', style: const TextStyle(fontSize: 11))),
              ]);
            }),
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 4. ALERTS
// ════════════════════════════════════════════════════════════════════════════
class AiAlertsScreen extends ConsumerWidget {
  const AiAlertsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(aiAlertsProvider);
    final actions = ref.read(aiStaffActionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: async.when(
        loading: () => const AppLoadingIndicator(message: 'Loading alerts...'),
        error: (e, _) => AppErrorState(message: e.toString(), onRetry: () => ref.invalidate(aiAlertsProvider)),
        data: (list) => list.isEmpty
            ? const AppEmptyState(icon: Icons.check_circle_outline, title: 'No alerts', subtitle: 'No urgent conditions have been raised.')
            : ListView.builder(padding: const EdgeInsets.all(12), itemCount: list.length, itemBuilder: (context, i) {
                final a = list[i];
                final refs = (a.evidence['references'] as List?) ?? const [];
                Future<void> run(Future<void> Function() f, String ok) async {
                  try { await f(); if (context.mounted) AppSnackbar.success(context, ok); }
                  catch (e) { if (context.mounted) AppSnackbar.error(context, e.toString()); }
                }
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: _sevColor(a.severity).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                        child: Text(a.severity.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _sevColor(a.severity)))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                      _statusChip(a.status),
                    ]),
                    const SizedBox(height: 6),
                    Text(a.message, style: const TextStyle(fontSize: 13)),
                    if (refs.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [_provChip(_Prov.verified), const SizedBox(width: 6),
                        Expanded(child: Text('Evidence: ${refs.join(', ')}${a.evidence['value'] != null ? ' = ${a.evidence['value']}' : ''}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF10B981))))]),
                    ],
                    Text('${a.reportDate} · ${_ago(a.createdAt)}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    if (a.status != 'resolved' && a.status != 'dismissed') ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        if (a.status == 'open')
                          OutlinedButton(onPressed: () => run(() => actions.acknowledgeAlert(a.id), 'Acknowledged'), child: const Text('Acknowledge')),
                        ElevatedButton(onPressed: () => run(() => actions.resolveAlert(a.id), 'Resolved'), child: const Text('Resolve')),
                      ]),
                    ],
                  ])),
                );
              }),
      ),
    );
  }

  Widget _statusChip(String s) {
    final c = s == 'resolved' ? const Color(0xFF10B981) : s == 'acknowledged' ? const Color(0xFF2563EB) : const Color(0xFFEA580C);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
      child: Text(s, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)));
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 5. HISTORY
// ════════════════════════════════════════════════════════════════════════════
class AiHistoryScreen extends ConsumerStatefulWidget {
  const AiHistoryScreen({super.key});
  @override
  ConsumerState<AiHistoryScreen> createState() => _AiHistoryScreenState();
}

class _AiHistoryScreenState extends ConsumerState<AiHistoryScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(aiBriefingHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Search by date (YYYY-MM-DD)', prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _q = v.trim()))),
        Expanded(child: async.when(
          loading: () => const AppLoadingIndicator(message: 'Loading history...'),
          error: (e, _) => AppErrorState(message: e.toString(), onRetry: () => ref.invalidate(aiBriefingHistoryProvider)),
          data: (list) {
            final filtered = _q.isEmpty ? list : list.where((b) => b.briefingDate.contains(_q)).toList();
            if (filtered.isEmpty) {
              return const AppEmptyState(icon: Icons.history_toggle_off_rounded, title: 'No briefings', subtitle: 'No daily briefings match.');
            }
            return ListView.builder(padding: const EdgeInsets.all(12), itemCount: filtered.length, itemBuilder: (context, i) {
              final b = filtered[i];
              return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
                leading: const Icon(Icons.summarize_rounded),
                title: Text(b.briefingDate, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(b.headline ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text('${b.rolesReported}r · ${b.suggestionsCount}s', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                onTap: () => showModalBottomSheet(context: context, isScrollControlled: true,
                  builder: (_) => _briefingSheet(context, b)),
              ));
            });
          },
        )),
      ]),
    );
  }

  Widget _briefingSheet(BuildContext context, AiBriefing b) {
    final issues = (b.highlights['top_issues'] as List?) ?? const [];
    return DraggableScrollableSheet(initialChildSize: 0.7, maxChildSize: 0.95, expand: false,
      builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
        Text(b.headline ?? 'Briefing', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(b.briefingDate, style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 10),
        if (b.summary != null) Text(b.summary!),
        const SizedBox(height: 12),
        const Text('Top issues', style: TextStyle(fontWeight: FontWeight.w800)),
        ...issues.map((i) {
          final m = Map<String, dynamic>.from(i as Map);
          return Padding(padding: const EdgeInsets.only(top: 6), child: Text('• ${m['title']}', style: const TextStyle(fontSize: 13)));
        }),
      ]),
    );
  }
}
