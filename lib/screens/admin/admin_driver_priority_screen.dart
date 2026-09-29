import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/driver_priority_provider.dart';
import '../../widgets/driver_priority_card.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

/// 🔥 Driver Priority — admin overview. Lists drivers with their trusted
/// standing/score and key metrics, filterable by standing. Admins can trigger a
/// recompute; scores are never hand-editable here (only via the audited RPCs).
class AdminDriverPriorityScreen extends ConsumerStatefulWidget {
  const AdminDriverPriorityScreen({super.key});

  @override
  ConsumerState<AdminDriverPriorityScreen> createState() =>
      _AdminDriverPriorityScreenState();
}

class _AdminDriverPriorityScreenState
    extends ConsumerState<AdminDriverPriorityScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _filter = 'ALL';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('drivers')
        .select(
            'id, full_name, driver_score, priority_standing, priority_provisional, '
            'rating, on_time_rate, acceptance_rate, completed_deliveries, '
            'cancelled_deliveries, is_online')
        .order('driver_score', ascending: false, nullsFirst: false)
        .limit(200);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _recomputeAll(List<Map<String, dynamic>> drivers) async {
    setState(() => _busy = true);
    try {
      for (final d in drivers) {
        await Supabase.instance.client
            .rpc('compute_driver_priority', params: {'p_driver_id': d['id']});
      }
      if (mounted) AppSnackbar.success(context, 'Recomputed all standings');
      _refresh();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔥 Driver Priority'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(friendlyError(snap.error!)));
          }
          final all = snap.data ?? const [];
          final filtered = _filter == 'ALL'
              ? all
              : all
                  .where((d) => (d['priority_standing'] ?? 'STANDARD') == _filter)
                  .toList();
          return Column(
            children: [
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final f in const [
                      'ALL',
                      'ELITE',
                      'PRIORITY',
                      'GOOD_STANDING',
                      'STANDARD',
                      'NEEDS_IMPROVEMENT'
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 6),
                        child: ChoiceChip(
                          label: Text(f == 'ALL'
                              ? 'All'
                              : DriverStanding.parse(f).label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text('${filtered.length} drivers',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _recomputeAll(all),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Recompute all'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = filtered[i];
                    final standing =
                        DriverStanding.parse(d['priority_standing'] as String?);
                    final score =
                        (d['driver_score'] as num?)?.toDouble() ?? 0;
                    final color = standingColor(standing);
                    double pct(dynamic v) {
                      final n = (v as num?)?.toDouble() ?? 0;
                      return n <= 1 ? n * 100 : n;
                    }

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Text(standing.emoji),
                      ),
                      title: Text(
                        (d['full_name'] as String?)?.trim().isNotEmpty == true
                            ? d['full_name'] as String
                            : 'Driver',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${standing.label}'
                        '${d['priority_provisional'] == true ? ' · provisional' : ''}\n'
                        '⭐ ${((d['rating'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}'
                        '  ⏱ ${pct(d['on_time_rate']).toStringAsFixed(0)}%'
                        '  🤝 ${pct(d['acceptance_rate']).toStringAsFixed(0)}%'
                        '  📦 ${(d['completed_deliveries'] as num?)?.toInt() ?? 0}',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        score.toStringAsFixed(0),
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: color),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
