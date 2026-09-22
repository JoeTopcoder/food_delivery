import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/driver_priority_provider.dart';
import '../../widgets/driver_priority_card.dart';

/// 🔥 Driver Performance — full breakdown, transparent "How Priority Works"
/// explanation, and the driver's priority history. All figures are the trusted
/// backend numbers; nothing here is client-computed.
class DriverPriorityScreen extends ConsumerWidget {
  const DriverPriorityScreen({super.key, required this.driverId});

  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(driverPriorityProvider(driverId));
    final history = ref.watch(driverPriorityHistoryProvider(driverId));

    return Scaffold(
      appBar: AppBar(title: const Text('🔥 Driver Performance')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Could not load your performance.')),
        data: (p) {
          if (p == null) {
            return const Center(child: Text('No performance data yet.'));
          }
          final color = standingColor(p.standing);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Standing + score header
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(colors: [
                    color.withValues(alpha: 0.14),
                    color.withValues(alpha: 0.04)
                  ]),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text('${p.standing.emoji}  ${p.standing.label}',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: color)),
                    const SizedBox(height: 6),
                    Text('${p.score.toStringAsFixed(0)} / 100',
                        style: const TextStyle(
                            fontSize: 30, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(
                      p.provisional
                          ? 'Provisional — complete 10 deliveries for full standing.'
                          : p.nextStanding == null
                              ? "You're receiving priority access to eligible orders."
                              : '${p.pointsToNext.toStringAsFixed(0)} points to '
                                  '${DriverStanding.parse(p.nextStanding).label}.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // How to improve
              _Section(
                title: 'How to improve',
                child: Text(
                  'Increase your ${p.improveFactor} to raise your HotBite '
                  'Priority Score.',
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),

              // Performance breakdown
              _Section(
                title: 'Performance',
                child: Column(children: [
                  _statRow('⭐ Customer Rating',
                      '${p.statNum('customer_rating').toStringAsFixed(1)} / 5'),
                  _statRow('⏱ On-Time Delivery',
                      '${p.statNum('on_time').toStringAsFixed(0)}%'),
                  _statRow('✅ Completion Rate',
                      '${p.statNum('completion').toStringAsFixed(0)}%'),
                  _statRow('🤝 Acceptance Rate',
                      '${p.statNum('acceptance').toStringAsFixed(0)}%'),
                  _statRow('📦 Restaurant Pickup',
                      '${p.statNum('pickup').toStringAsFixed(0)}%'),
                  _statRow('📣 Customer Complaints',
                      p.statNum('complaints').toStringAsFixed(0)),
                  _statRow('📦 Completed Deliveries',
                      p.statNum('completed_deliveries').toStringAsFixed(0)),
                ]),
              ),

              // How priority works
              _Section(
                title: 'How Priority Works',
                child: const Text(
                  'Your HotBite Priority Score is based on your recent delivery '
                  'performance.\n\nDrivers who consistently:\n'
                  '✓ Complete orders\n✓ Deliver on time\n'
                  '✓ Maintain good customer ratings\n'
                  '✓ Collect orders professionally\n'
                  '✓ Avoid unnecessary cancellations\n\n'
                  'can receive higher priority for eligible orders. Poor '
                  'performance can reduce priority, and your standing can '
                  'improve again through consistent good deliveries.',
                  style: TextStyle(fontSize: 13.5, height: 1.5),
                ),
              ),

              // History
              _Section(
                title: '🔥 Priority History',
                child: history.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(8),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => const Text('—'),
                  data: (rows) {
                    if (rows.isEmpty) {
                      return const Text('No changes yet.',
                          style: TextStyle(fontSize: 13));
                    }
                    return Column(
                      children: [
                        for (final r in rows) _historyRow(context, r),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _historyRow(BuildContext context, Map<String, dynamic> r) {
    final ts = DateTime.tryParse(r['created_at']?.toString() ?? '');
    final when = ts != null ? DateFormat('MMM d').format(ts) : '';
    final change = (r['score_change'] as num?)?.toDouble() ?? 0;
    final prev = (r['previous_score'] as num?)?.toStringAsFixed(0) ?? '';
    final now = (r['new_score'] as num?)?.toStringAsFixed(0) ?? '';
    final up = change >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
              width: 48,
              child: Text(when,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5)))),
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 15, color: up ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Score $prev → $now',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Text('${up ? '+' : ''}${change.toStringAsFixed(0)}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: up ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
