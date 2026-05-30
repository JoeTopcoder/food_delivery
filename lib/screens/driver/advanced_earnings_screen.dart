import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../models/driver_intelligence_models.dart';
import '../../providers/driver_provider.dart';
import '../../providers/driver_intelligence_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_theme.dart';
import '../shared/bank_info_screen.dart';
import '../shared/payout_request_screen.dart';

class AdvancedEarningsScreen extends ConsumerStatefulWidget {
  const AdvancedEarningsScreen({super.key});

  @override
  ConsumerState<AdvancedEarningsScreen> createState() =>
      _AdvancedEarningsScreenState();
}

class _AdvancedEarningsScreenState
    extends ConsumerState<AdvancedEarningsScreen> {
  String _period = 'today';

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: Center(
          child: Text('Not signed in', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final driverAsync = ref.watch(driverProfileProvider(uid));
    final driver = driverAsync.valueOrNull;
    if (driver == null) {
      if (driverAsync.hasError) {
        return Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          body: Center(
            child: Text(
              friendlyError(driverAsync.error),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
      return Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    final earningsAsync = ref.watch(
      earningsSummaryProvider((driverId: driver.id, period: _period)),
    );
    final statsAsync = ref.watch(driverStatsProvider(driver.id));
    final totalPaidOut = driver.totalPaidOut ?? 0.0;
    final totalEarnings = driver.totalEarnings ?? 0.0;
    final availableBalance = (totalEarnings - totalPaidOut).clamp(
      0.0,
      double.infinity,
    );
    final cashFloat = driver.cashFloat ?? 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF0F1117),
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text(
              'Earnings',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 22),
                onPressed: () {
                  ref.invalidate(
                    earningsSummaryProvider((
                      driverId: driver.id,
                      period: _period,
                    )),
                  );
                  ref.invalidate(driverStatsProvider(driver.id));
                  ref.invalidate(driverProfileProvider(uid));
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Balance Hero ──────────────────────────────────────
                  _BalanceHero(
                    availableBalance: availableBalance,
                    totalEarnings: totalEarnings,
                    totalPaidOut: totalPaidOut,
                  ),
                  const SizedBox(height: 14),

                  // ── Hourly Earnings ───────────────────────────────────
                  statsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (stats) {
                      if (stats == null) return const SizedBox.shrink();
                      return _HourlyCard(stats: stats);
                    },
                  ),
                  const SizedBox(height: 14),

                  // ── Cash Float ────────────────────────────────────────
                  _CashFloatCard(cashFloat: cashFloat),
                  const SizedBox(height: 16),

                  // ── Payout Actions ────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const BankInfoScreen(role: 'driver'),
                              ),
                            ),
                            icon: const Icon(Icons.account_balance, size: 18),
                            label: const Text(
                              'Bank Info',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PayoutRequestScreen(role: 'driver'),
                              ),
                            ),
                            icon: const Icon(Icons.payments_rounded, size: 18),
                            label: const Text(
                              'Request Payout',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22C55E),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Period selector ───────────────────────────────────
                  Row(
                    children: ['today', 'week', 'month', 'all'].map((p) {
                      final selected = _period == p;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _period = p),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.primaryColor
                                  : const Color(0xFF1E2030),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.primaryColor
                                    : const Color(0xFF2A2D3E),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                p[0].toUpperCase() + p.substring(1),
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.grey[500],
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // ── Earnings Summary ──────────────────────────────────
                  earningsAsync.when(
                    loading: () => Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        friendlyError(e),
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                    data: (summary) {
                      if (summary == null || summary.deliveryCount == 0) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No earnings for this period.',
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _EarningsSummaryCard(summary: summary),
                          const SizedBox(height: 16),
                          _PayBreakdownCard(summary: summary),
                          const SizedBox(height: 16),
                          _PerformanceMetrics(summary: summary),
                          const SizedBox(height: 20),
                          const Text(
                            'Delivery Log',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...summary.deliveries.map(
                            (d) => _DetailedDeliveryRow(detail: d),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Balance Hero ─────────────────────────────────────────────────────────────

class _BalanceHero extends StatelessWidget {
  final double availableBalance;
  final double totalEarnings;
  final double totalPaidOut;
  const _BalanceHero({
    required this.availableBalance,
    required this.totalEarnings,
    required this.totalPaidOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryColor, Color(0xFFFF8C5A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Balance',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '${AppConstants.currencySymbol}${availableBalance.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (totalPaidOut > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Total earned: ${AppConstants.currencySymbol}${totalEarnings.toStringAsFixed(2)}  •  Paid out: ${AppConstants.currencySymbol}${totalPaidOut.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Hourly Earnings Card ─────────────────────────────────────────────────────

class _HourlyCard extends StatelessWidget {
  final DriverStats stats;
  const _HourlyCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final isAboveFloor = stats.hourlyEarnings >= 20.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAboveFloor
              ? const Color(0xFF22C55E).withValues(alpha: 0.3)
              : const Color(0xFFF59E0B).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color:
                  (isAboveFloor
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFF59E0B))
                      .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.speed_rounded,
              color: isAboveFloor
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFF59E0B),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Hourly Rate',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${AppConstants.currencySymbol}${stats.hourlyEarnings.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isAboveFloor
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFF59E0B),
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                      ),
                    ),
                    const Text(
                      '/hr',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Session',
                style: TextStyle(color: Colors.grey[700], fontSize: 10),
              ),
              Text(
                '${AppConstants.currencySymbol}${stats.sessionEarnings.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Cash Float ───────────────────────────────────────────────────────────────

class _CashFloatCard extends StatelessWidget {
  final double cashFloat;
  const _CashFloatCard({required this.cashFloat});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cashFloat > 0
              ? const Color(0xFFEF4444).withValues(alpha: 0.3)
              : const Color(0xFF22C55E).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color:
                  (cashFloat > 0
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF22C55E))
                      .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              cashFloat > 0
                  ? Icons.account_balance_wallet_rounded
                  : Icons.check_circle_rounded,
              color: cashFloat > 0
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF22C55E),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cash Float',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cashFloat > 0
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF22C55E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cashFloat > 0
                      ? 'Cash collected — hand over to admin'
                      : 'No outstanding cash float',
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          Text(
            '${AppConstants.currencySymbol}${cashFloat.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: cashFloat > 0
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF22C55E),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Earnings Summary Card ────────────────────────────────────────────────────

class _EarningsSummaryCard extends StatelessWidget {
  final EarningsSummary summary;
  const _EarningsSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Earnings',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Text(
                '${summary.deliveryCount} deliveries',
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${AppConstants.currencySymbol}${summary.totalPayout.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Color(0xFF22C55E),
              fontWeight: FontWeight.w800,
              fontSize: 30,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniStat(
                label: 'Avg/delivery',
                value:
                    '${AppConstants.currencySymbol}${summary.avgPerDelivery.toStringAsFixed(2)}',
              ),
              const SizedBox(width: 12),
              _MiniStat(
                label: 'Avg/hour',
                value:
                    '${AppConstants.currencySymbol}${summary.avgPerHour.toStringAsFixed(2)}',
              ),
              const SizedBox(width: 12),
              _MiniStat(
                label: 'Distance',
                value: '${summary.totalDistanceKm.toStringAsFixed(1)} km',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1117),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: Colors.grey[700], fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pay Breakdown Card ───────────────────────────────────────────────────────

class _PayBreakdownCard extends StatelessWidget {
  final EarningsSummary summary;
  const _PayBreakdownCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final items = <_BreakdownItem>[
      _BreakdownItem('Base Pay', summary.basePay, const Color(0xFF3B82F6)),
      _BreakdownItem(
        'Distance Pay',
        summary.distancePay,
        const Color(0xFF22C55E),
      ),
      _BreakdownItem('Time Pay', summary.timePay, const Color(0xFF8B5CF6)),
      if (summary.waitPay > 0)
        _BreakdownItem('Wait Pay', summary.waitPay, const Color(0xFFF97316)),
      if (summary.boostPay > 0)
        _BreakdownItem('Boost Pay', summary.boostPay, const Color(0xFFE879F9)),
      if (summary.surgePay > 0)
        _BreakdownItem('Surge Pay', summary.surgePay, const Color(0xFFEF4444)),
      _BreakdownItem('Tips', summary.tips, const Color(0xFFFBBF24)),
      if (summary.floorTopups > 0)
        _BreakdownItem(
          'Floor Top-ups',
          summary.floorTopups,
          const Color(0xFF06B6D4),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: Colors.white54, size: 18),
              SizedBox(width: 8),
              Text(
                'Pay Breakdown',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: item.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                  ),
                  Text(
                    '${AppConstants.currencySymbol}${item.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: item.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Color(0xFF2A2D3E), height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Text(
                '${AppConstants.currencySymbol}${summary.totalPayout.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFF22C55E),
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BreakdownItem {
  final String label;
  final double amount;
  final Color color;
  const _BreakdownItem(this.label, this.amount, this.color);
}

// ─── Performance Metrics ──────────────────────────────────────────────────────

class _PerformanceMetrics extends StatelessWidget {
  final EarningsSummary summary;
  const _PerformanceMetrics({required this.summary});

  @override
  Widget build(BuildContext context) {
    final hours = summary.totalMinutes / 60;
    return Row(
      children: [
        Expanded(
          child: _MetricBox(
            label: 'Active Time',
            value: hours >= 1
                ? '${hours.toStringAsFixed(1)}h'
                : '${summary.totalMinutes}m',
            icon: Icons.timer_rounded,
            color: const Color(0xFF3B82F6),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricBox(
            label: 'Distance',
            value: '${summary.totalDistanceKm.toStringAsFixed(1)} km',
            icon: Icons.route_rounded,
            color: const Color(0xFF22C55E),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricBox(
            label: 'Deliveries',
            value: summary.deliveryCount.toString(),
            icon: Icons.local_shipping_rounded,
            color: const Color(0xFF8B5CF6),
          ),
        ),
      ],
    );
  }
}

class _MetricBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MetricBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 10)),
        ],
      ),
    );
  }
}

// ─── Detailed Delivery Row ────────────────────────────────────────────────────

class _DetailedDeliveryRow extends StatefulWidget {
  final EarningsDetail detail;
  const _DetailedDeliveryRow({required this.detail});

  @override
  State<_DetailedDeliveryRow> createState() => _DetailedDeliveryRowState();
}

class _DetailedDeliveryRowState extends State<_DetailedDeliveryRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final fmt = DateFormat('MMM d, h:mm a');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: d.isStacked
                        ? const Icon(
                            Icons.layers_rounded,
                            color: Color(0xFF8B5CF6),
                            size: 18,
                          )
                        : const Icon(
                            Icons.check_rounded,
                            color: Color(0xFF22C55E),
                            size: 18,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Order #${(d.orderId ?? d.id).substring(0, 8).toUpperCase()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                            if (d.isStacked) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF8B5CF6,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'STACKED',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF8B5CF6),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              fmt.format(d.earnedAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${d.distanceKm.toStringAsFixed(1)} km',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${d.durationMinutes.toStringAsFixed(0)} min',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${AppConstants.currencySymbol}${d.totalPayout.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFF22C55E),
                        ),
                      ),
                      Text(
                        '${AppConstants.currencySymbol}${d.earningsPerHour.toStringAsFixed(0)}/hr',
                        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.grey[600],
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                children: [
                  const Divider(color: Color(0xFF2A2D3E), height: 16),
                  _BreakdownRow('Base Pay', d.basePay),
                  _BreakdownRow('Distance Pay', d.distancePay),
                  _BreakdownRow('Time Pay', d.timePay),
                  if (d.waitPay > 0) _BreakdownRow('Wait Pay', d.waitPay),
                  if (d.boostPay > 0) _BreakdownRow('Boost Pay', d.boostPay),
                  if (d.surgePay > 0) _BreakdownRow('Surge Pay', d.surgePay),
                  if (d.tip > 0) _BreakdownRow('Tip', d.tip, isHighlight: true),
                  if (d.floorTopup > 0)
                    _BreakdownRow('Floor Top-up', d.floorTopup),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _BreakdownRow(
    String label,
    double amount, {
    bool isHighlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
          Text(
            '${AppConstants.currencySymbol}${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: isHighlight ? const Color(0xFFFBBF24) : Colors.grey[400],
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
