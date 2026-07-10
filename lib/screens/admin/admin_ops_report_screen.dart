import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';

/// Generic screen for any read-only "ops-report-agent" report. All metrics
/// are computed deterministically server-side; this just renders whatever
/// shape comes back — a narrative, top-level scalar stats, and (if present)
/// one flagged-items list. Reused across every consolidated report agent —
/// add a new agent server-side (ops-report-agent) and point its ai_agents
/// route at this screen with the right agentSlug/title, no new screen needed.
class AdminOpsReportScreen extends StatefulWidget {
  final String agentSlug;
  final String title;
  final String buttonLabel;

  const AdminOpsReportScreen({
    super.key,
    required this.agentSlug,
    required this.title,
    this.buttonLabel = 'Generate Report',
  });

  @override
  State<AdminOpsReportScreen> createState() => _AdminOpsReportScreenState();
}

class _AdminOpsReportScreenState extends State<AdminOpsReportScreen> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _metrics;
  String? _narrative;

  Future<void> _generate() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'ops-report-agent',
        body: {'agent_slug': widget.agentSlug},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() {
        _metrics = Map<String, dynamic>.from(data['metrics'] as Map);
        _narrative = data['narrative'] as String?;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MapEntry<String, dynamic>> get _scalarStats =>
      _metrics!.entries.where((e) => e.value is num || e.value is String || e.value is bool).toList();

  MapEntry<String, dynamic>? get _listField =>
      _metrics!.entries.where((e) => e.value is List && (e.value as List).isNotEmpty).cast<MapEntry<String, dynamic>?>().firstWhere((e) => true, orElse: () => null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), centerTitle: true),
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
              label: Text(_loading ? 'Working…' : widget.buttonLabel),
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
          if (_metrics != null) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _scalarStats.map((e) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                    child: Text('${_labelize(e.key)}: ${e.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  )).toList(),
            ),
            if (_listField != null) ...[
              const SizedBox(height: 16),
              ...((_listField!.value as List).map((item) {
                final map = item is Map ? Map<String, dynamic>.from(item) : {'value': item};
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: map.entries.map((e) => Text(
                            '${_labelize(e.key)}: ${e.value}',
                            style: const TextStyle(fontSize: 12),
                          )).toList(),
                    ),
                  ),
                );
              })),
            ],
          ],
        ],
      ),
    );
  }

  String _labelize(String key) => key.replaceAll('_', ' ');
}
