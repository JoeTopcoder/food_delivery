import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';

/// Driver Performance Agent — every metric here is computed deterministically
/// from this window's orders (cancellation rate, delivery time); the AI only
/// narrates who's worth a check-in and why. It never recommends deactivation.
class AdminDriverPerformanceScreen extends StatefulWidget {
  const AdminDriverPerformanceScreen({super.key});

  @override
  State<AdminDriverPerformanceScreen> createState() => _AdminDriverPerformanceScreenState();
}

class _AdminDriverPerformanceScreenState extends State<AdminDriverPerformanceScreen> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>>? _metrics;
  String? _narrative;

  Future<void> _generate() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client.functions.invoke('driver-performance-agent');
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() {
        _metrics = List<Map<String, dynamic>>.from(data['metrics'] as List);
        _narrative = data['narrative'] as String?;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _riskColor(num score) {
    if (score >= 30) return const Color(0xFFDC2626);
    if (score >= 15) return const Color(0xFFF59E0B);
    return const Color(0xFF16A34A);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Performance', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), centerTitle: true),
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
              label: Text(_loading ? 'Analyzing…' : 'Generate Report'),
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
            const Text('30-Day Performance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            ..._metrics!.map((m) {
              final score = m['at_risk_score'] as num;
              final color = _riskColor(score);
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(width: 4, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(
                              '${m['order_count']} deliveries · ${m['cancellation_rate_pct']}% cancelled · '
                              '${m['avg_delivery_minutes'] != null ? '${m['avg_delivery_minutes']}m avg' : 'no timing data'}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Text('${m['lifetime_completed_deliveries']} lifetime', style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
