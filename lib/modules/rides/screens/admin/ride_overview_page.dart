import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kPurple = Color(0xFF7C3AED);

// ── Provider ──────────────────────────────────────────────────────────────────

final _rideOverviewStandaloneProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final client = Supabase.instance.client;
  final todayMidnight =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
          .toIso8601String();

  final totalTodayRes = await client
      .from('ride_requests')
      .select('id')
      .gte('created_at', todayMidnight);
  final totalToday = (totalTodayRes as List).length;

  final activeRes = await client
      .from('ride_requests')
      .select('id')
      .not('ride_status', 'in', '("completed","cancelled","failed")');
  final activeCount = (activeRes as List).length;

  final driversOnlineRes = await client
      .from('drivers')
      .select('id')
      .eq('is_available', true);
  final driversOnline = (driversOnlineRes as List).length;

  final revenueRes = await client
      .from('ride_requests')
      .select('fare_amount')
      .eq('ride_status', 'completed')
      .gte('completed_at', todayMidnight);
  double revenueToday = 0.0;
  for (final row in (revenueRes as List)) {
    revenueToday += ((row['fare_amount'] as num?) ?? 0).toDouble();
  }

  final recentActiveRes = await client
      .from('ride_requests')
      .select()
      .not('ride_status', 'in', '("completed","cancelled","failed")')
      .order('created_at', ascending: false)
      .limit(5);
  final recentActive =
      List<Map<String, dynamic>>.from(recentActiveRes as List);

  return {
    'total_today': totalToday,
    'active_count': activeCount,
    'drivers_online': driversOnline,
    'revenue_today': revenueToday,
    'recent_active': recentActive,
  };
});

// ── Screen ────────────────────────────────────────────────────────────────────

class RideOverviewPage extends ConsumerWidget {
  const RideOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_rideOverviewStandaloneProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rides Overview', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _kPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_rideOverviewStandaloneProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _kPurple,
        onRefresh: () async => ref.invalidate(_rideOverviewStandaloneProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: _kPurple)),
          error: (e, _) => _ErrorRetry(
            message: e.toString(),
            onRetry: () => ref.invalidate(_rideOverviewStandaloneProvider),
          ),
          data: (data) {
            final recentActive =
                data['recent_active'] as List<Map<String, dynamic>>;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Metrics grid
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _MetricCard(
                      label: 'Rides Today',
                      value: '${data['total_today']}',
                      icon: Icons.directions_car_rounded,
                      color: _kPurple,
                    ),
                    _MetricCard(
                      label: 'Active Now',
                      value: '${data['active_count']}',
                      icon: Icons.radio_button_checked_rounded,
                      color: Colors.green,
                    ),
                    _MetricCard(
                      label: 'Drivers Online',
                      value: '${data['drivers_online']}',
                      icon: Icons.person_pin_rounded,
                      color: const Color(0xFF0EA5E9),
                    ),
                    _MetricCard(
                      label: 'Revenue Today',
                      value: 'J\$${(data['revenue_today'] as double).toStringAsFixed(0)}',
                      icon: Icons.attach_money_rounded,
                      color: const Color(0xFFF59E0B),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                const Text(
                  'Active Rides',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 10),

                if (recentActive.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Center(
                      child: Text(
                        'No active rides right now.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ...recentActive.map((ride) => _ActiveRideCard(ride: ride)),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const Spacer(),
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
            ),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _ActiveRideCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  const _ActiveRideCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    final id = (ride['id'] as String?)?.substring(0, 8) ?? '—';
    final status = ride['ride_status'] as String? ?? 'unknown';
    final pickup = _truncate(ride['pickup_address'] as String? ?? '', 35);
    final dest = _truncate(ride['destination_address'] as String? ?? '', 35);
    final createdAt = _relativeTime(ride['created_at'] as String?);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.directions_car, color: _kPurple, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#$id',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(status: status),
                      const Spacer(),
                      Text(
                        createdAt,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$pickup → $dest',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  Color get _color {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
      case 'failed':
        return Colors.red;
      case 'accepted':
      case 'en_route':
      case 'arrived':
        return const Color(0xFF0EA5E9);
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(color: _color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _truncate(String s, int max) =>
    s.length > max ? '${s.substring(0, max)}…' : s;

String _relativeTime(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  } catch (_) {
    return '—';
  }
}
