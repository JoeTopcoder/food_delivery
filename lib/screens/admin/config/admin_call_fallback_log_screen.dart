import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/supabase_config.dart';
import '../../../utils/app_theme.dart';

/// Admin call-log for the private telephone fallback. Shows order, driver,
/// reason, outcome, duration, time, sanitized provider error and cost.
/// NO phone numbers (the backend RPC never returns them).
final _callFallbackLogProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await SupabaseConfig.client
      .rpc('admin_call_fallback_log', params: {'p_limit': 200});
  return (res as List).cast<Map<String, dynamic>>();
});

class AdminCallFallbackLogScreen extends ConsumerWidget {
  const AdminCallFallbackLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logAsync = ref.watch(_callFallbackLogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Phone Fallback Log')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(_callFallbackLogProvider.future),
        child: logAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 80),
            Center(child: Text('Could not load log\n$e', textAlign: TextAlign.center)),
          ]),
          data: (rows) {
            if (rows.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Icon(Icons.phone_disabled_rounded, size: 48, color: Colors.black26),
                SizedBox(height: 12),
                Center(child: Text('No phone fallbacks yet')),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _tile(rows[i]),
            );
          },
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString();
    final dur = r['duration_seconds'];
    final cost = r['cost_amount'];
    Color c = switch (status) {
      'completed' => const Color(0xFF22C55E),
      'failed' => Colors.red,
      'no_answer' => Colors.orange,
      'cancelled' => Colors.grey,
      _ => AppTheme.primaryColor,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(status, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const Spacer(),
            Text('${r['reason'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
          const SizedBox(height: 8),
          Text('Driver: ${r['driver_name'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Order: ${(r['order_id'] ?? '').toString().substring(0, 8).toUpperCase()}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          Row(children: [
            if (dur != null) Text('⏱ ${dur}s  ', style: const TextStyle(fontSize: 12)),
            if (cost != null) Text('💵 $cost  ', style: const TextStyle(fontSize: 12)),
            if (r['failure_code'] != null)
              Expanded(child: Text('⚠ ${r['failure_code']}', style: const TextStyle(fontSize: 12, color: Colors.red))),
          ]),
          const SizedBox(height: 2),
          Text('${r['created_at'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.black38)),
        ],
      ),
    );
  }
}
