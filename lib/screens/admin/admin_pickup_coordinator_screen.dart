import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin view of the AI Restaurant Pickup Coordinator: the 15-minute follow-up
/// calls, their outcomes, and any scheduled restaurant-authorized auto-Ready.
class AdminPickupCoordinatorScreen extends ConsumerStatefulWidget {
  const AdminPickupCoordinatorScreen({super.key});
  @override
  ConsumerState<AdminPickupCoordinatorScreen> createState() => _S();
}

class _S extends ConsumerState<AdminPickupCoordinatorScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client.rpc('admin_pickup_overview', params: {'p_limit': 100});
    return (res is List) ? res.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
  }

  void _reload() => setState(() => _future = _load());

  Color _outcomeColor(String? o) => switch (o) {
        'ready_now' || 'scheduled_auto' => Colors.green,
        'preparing' || 'expected_only' => Colors.blue,
        'delay' || 'unfulfillable' || 'no_prep' => Colors.red,
        'conditions_changed' => Colors.grey,
        _ => Colors.orange,
      };

  String _fmt(dynamic ts) => (ts is String && ts.length >= 16) ? ts.substring(0, 16).replaceAll('T', ' ') : '—';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pickup Coordinator'),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24),
                child: Text('Error: ${snap.error}', textAlign: TextAlign.center)));
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const Center(child: Text('No follow-up calls yet.'));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = rows[i];
                final outcome = r['outcome'] as String?;
                final color = _outcomeColor(outcome);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Order #${r['order_ref'] ?? ''} · ${r['restaurant_name'] ?? ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Text(outcome ?? r['call_status'] ?? '—',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(spacing: 14, runSpacing: 4, children: [
                          _kv('Order status', '${r['order_status'] ?? '—'}'),
                          _kv('Prep underway', r['prep_underway'] == null ? '—' : (r['prep_underway'] == true ? 'Yes' : 'No')),
                          _kv('Confirmed ready', _fmt(r['confirmed_ready_at'])),
                          _kv('Auto-Ready auth', r['auto_ready_authorized'] == true ? 'Yes' : 'No'),
                          if (r['scheduled_ready_at'] != null)
                            _kv('Scheduled Ready', '${_fmt(r['scheduled_ready_at'])} (${r['scheduled_job_status'] ?? ''})'),
                          if (r['delay_reported'] == true) _kv('Delay', 'reported'),
                        ]),
                        if ((r['notes'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          Text(r['notes'] as String,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(k, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      );
}
