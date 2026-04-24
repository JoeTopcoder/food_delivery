import 'dart:async';
import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/analytics_provider.dart';
import '../../services/analytics_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';
import '../../config/app_constants.dart';

class AdminAnalyticsScreen extends ConsumerStatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  ConsumerState<AdminAnalyticsScreen> createState() =>
      _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends ConsumerState<AdminAnalyticsScreen> {
  int _trendDays = 30;
  int _retentionDay = 7;
  bool _refreshing = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(analyticsSummaryProvider);
    ref.invalidate(dauTrendProvider);
    ref.invalidate(retentionProvider);
    ref.invalidate(topRestaurantsProvider);
  }

  Future<void> _triggerRefresh() async {
    setState(() => _refreshing = true);
    try {
      await ref.read(analyticsServiceProvider).refreshMetrics();
      await _refresh();
      if (mounted) AppSnackbar.success(context, 'Metrics refreshed!');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(analyticsSummaryProvider);
    final trendAsync = ref.watch(dauTrendProvider(_trendDays));
    final retentionAsync = ref.watch(retentionProvider(_retentionDay));
    final topAsync = ref.watch(topRestaurantsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Analytics',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Recalculate metrics',
              onPressed: _triggerRefresh,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppTheme.primaryColor,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Summary KPIs ────────────────────────────────────────
            summaryAsync.when(
              data: (s) => _SummarySection(summary: s),
              loading: () => const _SectionSkeleton(height: 220),
              error: (e, _) => _ErrorCard(message: friendlyError(e)),
            ),

            const SizedBox(height: 16),

            // ── DAU / Revenue Trend ──────────────────────────────────
            _SectionCard(
              title: 'Trend',
              trailing: _PeriodToggle(
                selected: _trendDays,
                options: const {7: '7d', 14: '14d', 30: '30d'},
                onChanged: (v) => setState(() => _trendDays = v),
              ),
              child: trendAsync.when(
                data: (points) => points.isEmpty
                    ? const _EmptyState(label: 'No trend data yet')
                    : _TrendChart(points: points),
                loading: () => const _SectionSkeleton(height: 160),
                error: (e, _) => _ErrorCard(message: friendlyError(e)),
              ),
            ),

            const SizedBox(height: 16),

            // ── Retention ────────────────────────────────────────────
            _SectionCard(
              title: 'Retention',
              trailing: _PeriodToggle(
                selected: _retentionDay,
                options: const {1: 'D1', 7: 'D7', 30: 'D30'},
                onChanged: (v) => setState(() => _retentionDay = v),
              ),
              child: retentionAsync.when(
                data: (rows) => rows.isEmpty
                    ? const _EmptyState(label: 'No retention data yet')
                    : _RetentionTable(rows: rows),
                loading: () => const _SectionSkeleton(height: 120),
                error: (e, _) => _ErrorCard(message: friendlyError(e)),
              ),
            ),

            const SizedBox(height: 16),

            // ── Top Restaurants ──────────────────────────────────────
            _SectionCard(
              title: 'Top Restaurants (30d)',
              child: topAsync.when(
                data: (rows) => rows.isEmpty
                    ? const _EmptyState(label: 'No data yet')
                    : _TopRestaurantsTable(rows: rows),
                loading: () => const _SectionSkeleton(height: 200),
                error: (e, _) => _ErrorCard(message: friendlyError(e)),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─── Summary Section ─────────────────────────────────────────────────────────

class _SummarySection extends StatelessWidget {
  final AnalyticsSummary summary;
  const _SummarySection({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cur = AppConstants.currencySymbol;
    final fmt = NumberFormat('#,##0.00');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // AI recommendation banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E293B), Color(0xFF334155)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.smart_toy_outlined,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  summary.recommendation,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Today KPIs row
        Row(
          children: [
            _KpiCard(
              label: 'DAU',
              value: '${summary.dau}',
              icon: Icons.people_alt_rounded,
              color: const Color(0xFF6366F1),
            ),
            const SizedBox(width: 10),
            _KpiCard(
              label: 'New Users',
              value: '${summary.newUsers}',
              icon: Icons.person_add_rounded,
              color: const Color(0xFF10B981),
            ),
            const SizedBox(width: 10),
            _KpiCard(
              label: 'Orders',
              value: '${summary.ordersToday}',
              icon: Icons.receipt_long_rounded,
              color: const Color(0xFFF59E0B),
            ),
          ],
        ),

        const SizedBox(height: 10),

        Row(
          children: [
            _KpiCard(
              label: 'Revenue Today',
              value: '$cur${fmt.format(summary.revenueToday)}',
              icon: Icons.attach_money_rounded,
              color: AppTheme.primaryColor,
            ),
            const SizedBox(width: 10),
            _KpiCard(
              label: 'AOV',
              value: '$cur${fmt.format(summary.aovToday)}',
              icon: Icons.trending_up_rounded,
              color: const Color(0xFF0891B2),
            ),
            const SizedBox(width: 10),
            _KpiCard(
              label: 'Completion',
              value: '${summary.completionRate.toStringAsFixed(1)}%',
              icon: Icons.check_circle_outline_rounded,
              color: const Color(0xFF22C55E),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // 7-day and 30-day condensed
        Row(
          children: [
            _WideKpiCard(
              label: '7d Revenue',
              value: '$cur${fmt.format(summary.revenueWeek)}',
              sub: '${summary.ordersWeek} orders',
              color: const Color(0xFF6366F1),
            ),
            const SizedBox(width: 10),
            _WideKpiCard(
              label: '30d Revenue',
              value: '$cur${fmt.format(summary.revenueMonth)}',
              sub: '${summary.ordersMonth} orders',
              color: const Color(0xFF8B5CF6),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Line Chart (CustomPaint, no dependencies) ────────────────────────────────

class _TrendChart extends StatelessWidget {
  final List<DauDataPoint> points;
  const _TrendChart({required this.points});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Legend
        Row(
          children: [
            _LegendDot(color: AppTheme.primaryColor, label: 'DAU'),
            const SizedBox(width: 16),
            _LegendDot(color: const Color(0xFF10B981), label: 'Orders'),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: CustomPaint(
            size: const Size(double.infinity, 160),
            painter: _LineChartPainter(points: points),
          ),
        ),
        const SizedBox(height: 4),
        // X axis labels (first / mid / last)
        if (points.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('MMMd').format(points.first.date),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                if (points.length > 2)
                  Text(
                    DateFormat('MMMd').format(points[points.length ~/ 2].date),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                Text(
                  DateFormat('MMMd').format(points.last.date),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<DauDataPoint> points;
  _LineChartPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final maxDau = points.map((p) => p.dau).reduce(max).toDouble();
    final maxOrders = points.map((p) => p.orders).reduce(max).toDouble();

    final dauPaint = Paint()
      ..color = AppTheme.primaryColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final orderPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final gridPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..strokeWidth = 0.5;

    // Grid lines
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    double _normX(int i) => points.length == 1
        ? size.width / 2
        : size.width * i / (points.length - 1);
    double _normY(double val, double maxVal) =>
        maxVal == 0 ? size.height : size.height * (1 - val / maxVal);

    // DAU line
    final dauPath = Path();
    for (int i = 0; i < points.length; i++) {
      final x = _normX(i);
      final y = _normY(points[i].dau.toDouble(), maxDau == 0 ? 1 : maxDau);
      if (i == 0)
        dauPath.moveTo(x, y);
      else
        dauPath.lineTo(x, y);
    }
    canvas.drawPath(dauPath, dauPaint);

    // Orders line
    final ordersPath = Path();
    for (int i = 0; i < points.length; i++) {
      final x = _normX(i);
      final y = _normY(
        points[i].orders.toDouble(),
        maxOrders == 0 ? 1 : maxOrders,
      );
      if (i == 0)
        ordersPath.moveTo(x, y);
      else
        ordersPath.lineTo(x, y);
    }
    canvas.drawPath(ordersPath, orderPaint);

    // Data point dots
    final dotDau = Paint()..color = AppTheme.primaryColor;
    final dotOrders = Paint()..color = const Color(0xFF10B981);
    for (int i = 0; i < points.length; i++) {
      final x = _normX(i);
      canvas.drawCircle(
        Offset(x, _normY(points[i].dau.toDouble(), maxDau == 0 ? 1 : maxDau)),
        2.5,
        dotDau,
      );
      canvas.drawCircle(
        Offset(
          x,
          _normY(points[i].orders.toDouble(), maxOrders == 0 ? 1 : maxOrders),
        ),
        2.5,
        dotOrders,
      );
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => old.points != points;
}

// ─── Retention Table ─────────────────────────────────────────────────────────

class _RetentionTable extends StatelessWidget {
  final List<RetentionPoint> rows;
  const _RetentionTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: const [
            Expanded(
              flex: 3,
              child: Text(
                'Cohort',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Size',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Retained',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Rate',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
        const Divider(height: 8),
        ...rows.map((r) {
          final rateColor = r.rate >= 40
              ? const Color(0xFF10B981)
              : r.rate >= 20
              ? const Color(0xFFF59E0B)
              : const Color(0xFFEF4444);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    DateFormat('MMM d').format(r.cohortDate),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${r.cohortSize}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${r.retained}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${r.rate.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: rateColor,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─── Top Restaurants Table ────────────────────────────────────────────────────

class _TopRestaurantsTable extends StatelessWidget {
  final List<TopRestaurant> rows;
  const _TopRestaurantsTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final cur = AppConstants.currencySymbol;
    final fmt = NumberFormat('#,##0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: const [
            Expanded(
              flex: 1,
              child: Text(
                '#',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                'Restaurant',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Orders',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                'Revenue',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
        const Divider(height: 8),
        ...rows.asMap().entries.map((e) {
          final i = e.key;
          final r = e.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: i == 0
                          ? const Color(0xFFF59E0B)
                          : i == 1
                          ? const Color(0xFF9CA3AF)
                          : i == 2
                          ? const Color(0xFFB45309)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    r.name,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${r.orderCount}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    '$cur${fmt.format(r.revenue)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─── Shared small widgets ─────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WideKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;

  const _WideKpiCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              sub,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  final int selected;
  final Map<int, String> options;
  final void Function(int) onChanged;

  const _PeriodToggle({
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.entries.map((e) {
        final isSelected = e.key == selected;
        return GestureDetector(
          onTap: () => onChanged(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryColor
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              e.value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : const Color(0xFF6B7280),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }
}

class _SectionSkeleton extends StatelessWidget {
  final double height;
  const _SectionSkeleton({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFEF4444),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
