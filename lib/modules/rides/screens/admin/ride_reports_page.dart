import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

const _kPurple = Color(0xFF7C3AED);

// ── Data model ────────────────────────────────────────────────────────────────

class _ReportData {
  final double grossRevenue;
  final double platformFees;
  final double driverEarnings;
  final int totalRides;
  final int completedRides;
  final int cancelledRides;
  final double avgFare;
  final List<Map<String, dynamic>> recentCompleted;

  const _ReportData({
    required this.grossRevenue,
    required this.platformFees,
    required this.driverEarnings,
    required this.totalRides,
    required this.completedRides,
    required this.cancelledRides,
    required this.avgFare,
    required this.recentCompleted,
  });
}

// ── Provider ──────────────────────────────────────────────────────────────────

enum _Period { today, week, month }

final _reportPeriodProvider = StateProvider<_Period>((ref) => _Period.today);

final _rideReportsProvider = FutureProvider.family<_ReportData, _Period>((ref, period) async {
  final client = Supabase.instance.client;
  final now = DateTime.now();

  final DateTime since = switch (period) {
    _Period.today  => DateTime(now.year, now.month, now.day),
    _Period.week   => now.subtract(const Duration(days: 7)),
    _Period.month  => DateTime(now.year, now.month, 1),
  };

  final sinceIso = since.toIso8601String();

  final rows = await client
      .from('ride_requests')
      .select('ride_status, final_fare, platform_fee, driver_earning, completed_at, pickup_address, destination_address, created_at')
      .gte('created_at', sinceIso)
      .order('created_at', ascending: false);

  final list = List<Map<String, dynamic>>.from(rows as List);

  double grossRevenue = 0;
  double platformFees = 0;
  double driverEarnings = 0;
  int completedRides = 0;
  int cancelledRides = 0;
  final recentCompleted = <Map<String, dynamic>>[];

  for (final row in list) {
    final status = row['ride_status'] as String? ?? '';
    if (status == 'ride_completed' || status == 'completed') {
      final fare = ((row['final_fare'] as num?) ?? 0).toDouble();
      final fee = ((row['platform_fee'] as num?) ?? 0).toDouble();
      final earning = ((row['driver_earning'] as num?) ?? 0).toDouble();
      grossRevenue += fare;
      platformFees += fee;
      driverEarnings += earning;
      completedRides++;
      if (recentCompleted.length < 10) recentCompleted.add(row);
    } else if (status == 'cancelled') {
      cancelledRides++;
    }
  }

  final avgFare = completedRides > 0 ? grossRevenue / completedRides : 0.0;

  return _ReportData(
    grossRevenue: grossRevenue,
    platformFees: platformFees,
    driverEarnings: driverEarnings,
    totalRides: list.length,
    completedRides: completedRides,
    cancelledRides: cancelledRides,
    avgFare: avgFare,
    recentCompleted: recentCompleted,
  );
});

// ── Screen ────────────────────────────────────────────────────────────────────

class RideReportsPage extends ConsumerWidget {
  const RideReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(_reportPeriodProvider);
    final async = ref.watch(_rideReportsProvider(period));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Reports', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _kPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_rideReportsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          _PeriodSelector(
            selected: period,
            onChanged: (p) => ref.read(_reportPeriodProvider.notifier).state = p,
          ),
          Expanded(
            child: RefreshIndicator(
              color: _kPurple,
              onRefresh: () async => ref.invalidate(_rideReportsProvider),
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator(color: _kPurple)),
                error: (e, _) => _ErrorRetry(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(_rideReportsProvider),
                ),
                data: (data) => _ReportBody(data: data),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Period selector ───────────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  final _Period selected;
  final ValueChanged<_Period> onChanged;

  const _PeriodSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kPurple.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _PeriodChip(label: 'Today',      period: _Period.today, selected: selected, onTap: onChanged),
          const SizedBox(width: 8),
          _PeriodChip(label: 'This Week',  period: _Period.week,  selected: selected, onTap: onChanged),
          const SizedBox(width: 8),
          _PeriodChip(label: 'This Month', period: _Period.month, selected: selected, onTap: onChanged),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final _Period period;
  final _Period selected;
  final ValueChanged<_Period> onTap;

  const _PeriodChip({
    required this.label,
    required this.period,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = period == selected;
    return GestureDetector(
      onTap: () => onTap(period),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? _kPurple : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kPurple, width: 1.2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : _kPurple,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ── Report body ───────────────────────────────────────────────────────────────

class _ReportBody extends StatelessWidget {
  final _ReportData data;
  const _ReportBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Revenue section
        _SectionHeader(title: 'Revenue'),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.55,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _MetricCard(
              label: 'Gross Revenue',
              value: 'J\$${fmt.format(data.grossRevenue)}',
              icon: Icons.attach_money_rounded,
              color: const Color(0xFFF59E0B),
            ),
            _MetricCard(
              label: 'Platform Fees',
              value: 'J\$${fmt.format(data.platformFees)}',
              icon: Icons.account_balance_rounded,
              color: _kPurple,
            ),
            _MetricCard(
              label: 'Driver Earnings',
              value: 'J\$${fmt.format(data.driverEarnings)}',
              icon: Icons.person_rounded,
              color: const Color(0xFF0EA5E9),
            ),
            _MetricCard(
              label: 'Avg Fare',
              value: data.avgFare > 0 ? 'J\$${fmt.format(data.avgFare)}' : '—',
              icon: Icons.bar_chart_rounded,
              color: Colors.green,
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Ride counts section
        _SectionHeader(title: 'Ride Counts'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Total Rides',
                value: '${data.totalRides}',
                icon: Icons.directions_car_rounded,
                color: _kPurple,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: 'Completed',
                value: '${data.completedRides}',
                icon: Icons.check_circle_rounded,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: 'Cancelled',
                value: '${data.cancelledRides}',
                icon: Icons.cancel_rounded,
                color: Colors.red,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Completion rate
        if (data.totalRides > 0) ...[
          _SectionHeader(title: 'Completion Rate'),
          const SizedBox(height: 10),
          _CompletionBar(
            completed: data.completedRides,
            cancelled: data.cancelledRides,
            total: data.totalRides,
          ),
          const SizedBox(height: 24),
        ],

        // Recent completed rides
        _SectionHeader(title: 'Recent Completed Rides'),
        const SizedBox(height: 10),
        if (data.recentCompleted.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No completed rides for this period.', style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          ...data.recentCompleted.map((ride) => _CompletedRideRow(ride: ride)),
      ],
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1E293B),
        letterSpacing: 0.3,
      ),
    );
  }
}

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
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletionBar extends StatelessWidget {
  final int completed;
  final int cancelled;
  final int total;

  const _CompletionBar({
    required this.completed,
    required this.cancelled,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (completed / total * 100).toStringAsFixed(1);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$pct% completion',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  '$completed / $total',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? completed / total : 0,
                minHeight: 8,
                backgroundColor: Colors.red.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation(Colors.green),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedRideRow extends StatelessWidget {
  final Map<String, dynamic> ride;
  const _CompletedRideRow({required this.ride});

  @override
  Widget build(BuildContext context) {
    final fare = ((ride['final_fare'] as num?) ?? 0).toDouble();
    final pickup = _truncate(ride['pickup_address'] as String? ?? '', 30);
    final dest = _truncate(ride['destination_address'] as String? ?? '', 30);
    final completedAt = _formatDate(ride['completed_at'] as String?);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$pickup → $dest',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    completedAt,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Text(
              'J\$${fare.toStringAsFixed(0)}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
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

String _formatDate(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('MMM d, h:mm a').format(dt);
  } catch (_) {
    return '—';
  }
}
