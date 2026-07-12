import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';

/// Unified Escalation Queue — one screen aggregating everything across the
/// platform that's currently flagged for a human: support tickets an AI
/// agent escalated, open customer disputes, users Fraud & Risk flagged, and
/// drivers with expired documents. Nothing here is a new data source — it's
/// a triage view over tables/agent runs that already exist, so an admin
/// doesn't have to check five separate screens to know what needs attention
/// right now. Tapping an item opens the screen that actually handles it.
class AdminEscalationQueueScreen extends StatefulWidget {
  const AdminEscalationQueueScreen({super.key});

  @override
  State<AdminEscalationQueueScreen> createState() => _AdminEscalationQueueScreenState();
}

class _AdminEscalationQueueScreenState extends State<AdminEscalationQueueScreen> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _escalatedTickets = [];
  List<Map<String, dynamic>> _openDisputes = [];
  List<dynamic> _fraudFlaggedUsers = [];
  List<dynamic> _expiredDrivers = [];

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
            .from('support_requests')
            .select()
            .neq('status', 'resolved')
            .or('status.eq.reviewing,ai_suggested_action.eq.escalate')
            .order('created_at', ascending: false)
            .limit(25),
        _client.from('disputes').select().neq('status', 'resolved').order('created_at', ascending: true).limit(25),
        _client
            .from('ai_agent_runs')
            .select('output')
            .eq('agent_name', 'fraud_risk')
            .eq('status', 'completed')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        _client
            .from('ai_agent_runs')
            .select('output')
            .eq('agent_name', 'driver_compliance')
            .eq('status', 'completed')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
      ]);

      final fraudRun = results[2] as Map<String, dynamic>?;
      final fraudMetrics = (fraudRun?['output'] as Map?)?['metrics'] as Map?;
      final flaggedUsers = (fraudMetrics?['flagged_users'] as List?) ?? [];

      final complianceRun = results[3] as Map<String, dynamic>?;
      final complianceMetrics = (complianceRun?['output'] as Map?)?['metrics'] as Map?;
      final flaggedDrivers = ((complianceMetrics?['flagged_drivers'] as List?) ?? [])
          .where((d) => (d as Map)['status'] == 'expired')
          .toList();

      if (mounted) {
        setState(() {
          _escalatedTickets = List<Map<String, dynamic>>.from(results[0] as List);
          _openDisputes = List<Map<String, dynamic>>.from(results[1] as List);
          _fraudFlaggedUsers = flaggedUsers;
          _expiredDrivers = flaggedDrivers;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _fmt(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('MMM d, h:mm a').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  int get _totalCount => _escalatedTickets.length + _openDisputes.length + _fraudFlaggedUsers.length + _expiredDrivers.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escalation Queue', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _totalCount == 0
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Column(
                                children: [
                                  Icon(Icons.check_circle_outline, size: 56, color: Color(0xFF16A34A)),
                                  SizedBox(height: 12),
                                  Text('Nothing needs attention right now', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_escalatedTickets.isNotEmpty) ...[
                              _SectionHeader(title: 'Escalated Support Tickets', count: _escalatedTickets.length, color: const Color(0xFFDC2626)),
                              ..._escalatedTickets.map((t) => _EscalationCard(
                                    icon: Icons.support_agent,
                                    title: t['name'] ?? 'Unknown',
                                    subtitle: '${t['category'] ?? ''} · ${t['ai_suggested_action'] == 'escalate' ? 'AI escalated' : 'Under review'}',
                                    trailingLabel: _fmt(t['created_at'] as String?),
                                    onTap: () => Navigator.of(context).pushNamed('/admin-support-requests'),
                                  )),
                              const SizedBox(height: 20),
                            ],
                            if (_openDisputes.isNotEmpty) ...[
                              _SectionHeader(title: 'Open Disputes', count: _openDisputes.length, color: const Color(0xFFB45309)),
                              ..._openDisputes.map((d) => _EscalationCard(
                                    icon: Icons.gavel_outlined,
                                    title: d['type'] ?? 'Dispute',
                                    subtitle: (d['description'] as String?) ?? '',
                                    trailingLabel: _fmt(d['created_at'] as String?),
                                    onTap: () => Navigator.of(context).pushNamed('/admin-disputes'),
                                  )),
                              const SizedBox(height: 20),
                            ],
                            if (_fraudFlaggedUsers.isNotEmpty) ...[
                              _SectionHeader(title: 'Fraud & Risk Flags', count: _fraudFlaggedUsers.length, color: const Color(0xFF7C3AED)),
                              ..._fraudFlaggedUsers.map((u) {
                                final user = u as Map;
                                return _EscalationCard(
                                  icon: Icons.warning_amber_rounded,
                                  title: user['user']?.toString() ?? 'Unknown',
                                  subtitle: '${user['disputes_last_30_days'] ?? 0} disputes · ${user['support_credits_last_30_days'] ?? 0} credits (30d)',
                                  trailingLabel: '',
                                  onTap: () => Navigator.of(context).pushNamed('/admin-ai/fraud-risk'),
                                );
                              }),
                              const SizedBox(height: 20),
                            ],
                            if (_expiredDrivers.isNotEmpty) ...[
                              _SectionHeader(title: 'Expired Driver Documents', count: _expiredDrivers.length, color: const Color(0xFFDC2626)),
                              ..._expiredDrivers.map((d) {
                                final driver = d as Map;
                                return _EscalationCard(
                                  icon: Icons.badge_outlined,
                                  title: driver['driver']?.toString() ?? 'Unknown',
                                  subtitle: 'License expired ${(-(driver['days_remaining'] as num? ?? 0)).round()} day(s) ago',
                                  trailingLabel: '',
                                  onTap: () => Navigator.of(context).pushNamed('/admin-ai/driver-compliance'),
                                );
                              }),
                            ],
                          ],
                        ),
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _SectionHeader({required this.title, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text('($count)', style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _EscalationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailingLabel;
  final VoidCallback onTap;

  const _EscalationCard({required this.icon, required this.title, required this.subtitle, required this.trailingLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1), child: Icon(icon, color: AppTheme.primaryColor, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: subtitle.isNotEmpty ? Text(subtitle, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis) : null,
        trailing: trailingLabel.isNotEmpty ? Text(trailingLabel, style: const TextStyle(fontSize: 11, color: Colors.grey)) : const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}
