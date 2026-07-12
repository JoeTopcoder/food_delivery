import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';
import 'admin_agent_coming_soon_screen.dart';

/// AI Operations hub — the "app inside the app" for 7Dash's AI agents.
/// Lists every registered agent (ai_agents) with a live pause/resume control,
/// and a cross-agent audit trail (ai_agent_runs). New agents plug into this
/// same screen by adding a row to ai_agents — no new UI required.
class AdminAiOperationsScreen extends StatefulWidget {
  const AdminAiOperationsScreen({super.key});

  @override
  State<AdminAiOperationsScreen> createState() => _AdminAiOperationsScreenState();
}

class _AdminAiOperationsScreenState extends State<AdminAiOperationsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _agents = [];
  List<Map<String, dynamic>> _runs = [];
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
      // status ascending sorts active, paused, planned — built agents surface first.
      final agents = await _client.from('ai_agents').select().order('status').order('name');
      final runs = await _client
          .from('ai_agent_runs')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _agents = List<Map<String, dynamic>>.from(agents);
          _runs = List<Map<String, dynamic>>.from(runs);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  int _runsToday(String slug) {
    final today = DateTime.now();
    return _runs.where((r) {
      if (r['agent_name'] == null || !(r['agent_name'] as String).startsWith(slug)) return false;
      final created = DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
      return created != null &&
          created.year == today.year &&
          created.month == today.month &&
          created.day == today.day;
    }).length;
  }

  Future<void> _toggleStatus(Map<String, dynamic> agent) async {
    final newStatus = agent['status'] == 'active' ? 'paused' : 'active';
    try {
      await _client.from('ai_agents').update({'status': newStatus}).eq('id', agent['id']);
      setState(() => agent['status'] = newStatus);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e'), backgroundColor: AppTheme.errorColor),
      );
    }
  }

  void _showRunDetail(Map<String, dynamic> run) {
    const encoder = JsonEncoder.withIndent('  ');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Text(run['agent_name'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${run['entity_type']} · ${run['entity_id']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            _StatusChip(status: run['status'] as String? ?? 'pending'),
            const SizedBox(height: 16),
            const Text('Input', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            SelectableText(
              encoder.convert(run['input'] ?? {}),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            if (run['output'] != null) ...[
              const SizedBox(height: 16),
              const Text('Output', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              SelectableText(
                encoder.convert(run['output']),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ],
            if (run['error'] != null) ...[
              const SizedBox(height: 16),
              const Text('Error', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
              const SizedBox(height: 4),
              SelectableText(run['error'], style: const TextStyle(fontSize: 12, color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Operations', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.priority_high_rounded),
            tooltip: 'Escalation Queue',
            onPressed: () => Navigator.of(context).pushNamed('/admin-escalation-queue'),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
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
                      const Text('Agents', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (_agents.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('No agents registered yet.', style: TextStyle(color: Colors.grey))),
                        )
                      else
                        ..._agents.map((a) => _AgentCard(
                              agent: a,
                              runsToday: _runsToday(a['slug'] as String),
                              onToggle: () => _toggleStatus(a),
                              // Active/paused agents have a real screen registered in
                              // main.dart. Planned agents' routes are destinations, not
                              // live links yet — open an honest "not built" page instead
                              // of pushNamed()'ing a route nothing handles.
                              onOpen: () {
                                if (a['status'] != 'planned' && a['route'] != null) {
                                  Navigator.of(context).pushNamed(a['route'] as String);
                                } else {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => AdminAgentComingSoonScreen(agent: a)),
                                  );
                                }
                              },
                            )),
                      const SizedBox(height: 24),
                      const Text('Recent Activity', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (_runs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('No agent runs logged yet.', style: TextStyle(color: Colors.grey))),
                        )
                      else
                        ..._runs.map((r) => _RunTile(run: r, onTap: () => _showRunDetail(r))),
                    ],
                  ),
                ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final Map<String, dynamic> agent;
  final int runsToday;
  final VoidCallback onToggle;
  final VoidCallback? onOpen;

  const _AgentCard({required this.agent, required this.runsToday, required this.onToggle, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final status = agent['status'] as String? ?? 'planned';
    final planned = status == 'planned';
    final active = status == 'active';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Opacity(
        opacity: planned ? 0.75 : 1,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (planned ? Colors.grey : const Color(0xFF7C3AED)).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      planned ? Icons.hourglass_empty_rounded : Icons.auto_awesome,
                      color: planned ? Colors.grey[600] : const Color(0xFF7C3AED),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(agent['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(agent['department'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  if (!planned)
                    Switch(value: active, onChanged: (_) => onToggle(), activeThumbColor: AppTheme.primaryColor),
                ],
              ),
              if (agent['description'] != null) ...[
                const SizedBox(height: 8),
                Text(agent['description'], style: const TextStyle(fontSize: 12, height: 1.4)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: planned
                          ? const Color(0xFFF3F4F6)
                          : (active ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      planned ? 'Not Built Yet' : (active ? 'Active' : 'Paused'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: planned ? Colors.grey[700] : (active ? const Color(0xFF16A34A) : const Color(0xFFB45309)),
                      ),
                    ),
                  ),
                  if (!planned) ...[
                    const SizedBox(width: 8),
                    Text('$runsToday run${runsToday == 1 ? '' : 's'} today', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                  const Spacer(),
                  if (onOpen != null)
                    TextButton(onPressed: onOpen, child: const Text('Open', style: TextStyle(fontSize: 12))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  final Map<String, dynamic> run;
  final VoidCallback onTap;

  const _RunTile({required this.run, required this.onTap});

  String _fmt(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('MMM d, h:mm a').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _StatusChip(status: run['status'] as String? ?? 'pending', compact: true),
      title: Text(run['agent_name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text('${run['entity_type'] ?? ''} · ${_fmt(run['created_at'] as String?)}', style: const TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, size: 18),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final bool compact;
  const _StatusChip({required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'completed' => const Color(0xFF16A34A),
      'failed' => const Color(0xFFDC2626),
      _ => const Color(0xFFF59E0B),
    };
    if (compact) {
      return Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
