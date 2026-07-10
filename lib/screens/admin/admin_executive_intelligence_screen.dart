import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';

/// Executive Intelligence Agent — read-only. Every figure shown here is
/// computed with plain SQL in executive-agent-brief; the AI only narrates
/// the numbers it's given. No approval queue needed — nothing here can send
/// a message, move money, or change any record.
class AdminExecutiveIntelligenceScreen extends StatefulWidget {
  const AdminExecutiveIntelligenceScreen({super.key});

  @override
  State<AdminExecutiveIntelligenceScreen> createState() => _AdminExecutiveIntelligenceScreenState();
}

class _AdminExecutiveIntelligenceScreenState extends State<AdminExecutiveIntelligenceScreen> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _metrics;
  String? _narrative;

  Future<void> _generate() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client.functions.invoke('executive-agent-brief');
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

  @override
  Widget build(BuildContext context) {
    final m = _metrics;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Executive Intelligence', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
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
              label: Text(_loading ? 'Generating briefing…' : 'Generate Briefing'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (m != null) ...[
            const SizedBox(height: 20),
            if (_narrative != null && _narrative!.isNotEmpty) ...[
              Card(
                elevation: 0,
                color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFEDE9FE))),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_narrative!, style: const TextStyle(fontSize: 14, height: 1.5)),
                ),
              ),
              const SizedBox(height: 20),
            ],
            const Text('Today', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            _MetricGrid(items: [
              _Metric('Revenue', '\$${(m['today']['revenue'] as num).toStringAsFixed(2)}'),
              _Metric('Orders', '${m['today']['order_count']}'),
              _Metric('Avg Order Value', '\$${(m['today']['avg_order_value'] as num).toStringAsFixed(2)}'),
              _Metric('Cancel Rate', '${m['today']['cancel_rate_pct']}%'),
            ]),
            const SizedBox(height: 16),
            const Text('7-Day Trend', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            _MetricGrid(items: [
              _Metric('Orders', '${m['last_7_days']['order_count']}'),
              _Metric('Refund Rate', '${m['last_7_days']['refund_rate_pct']}%'),
              _Metric('Cancel Rate', '${m['last_7_days']['cancel_rate_pct']}%'),
              _Metric(
                'vs Yesterday',
                m['revenue_change_vs_yesterday_pct'] != null ? '${m['revenue_change_vs_yesterday_pct']}%' : 'N/A',
              ),
            ]),
            const SizedBox(height: 16),
            const Text('Network', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            _MetricGrid(items: [
              _Metric('Active Restaurants', '${m['active_restaurants']}'),
              _Metric('Active Drivers', '${m['active_drivers']}'),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Metric {
  final String label;
  final String value;
  _Metric(this.label, this.value);
}

class _MetricGrid extends StatelessWidget {
  final List<_Metric> items;
  const _MetricGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: items.map((m) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(m.label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(m.value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
      )).toList(),
    );
  }
}
