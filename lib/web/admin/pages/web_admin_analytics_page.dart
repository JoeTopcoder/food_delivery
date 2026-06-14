import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/admin_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';
import '../../../config/app_constants.dart';

class WebAdminAnalyticsPage extends ConsumerWidget {
  const WebAdminAnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revenueAsync = ref.watch(revenueStatisticsProvider);
    final orderAsync = ref.watch(orderStatisticsProvider);
    final financialAsync = ref.watch(financialStatisticsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Analytics', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Platform performance metrics', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                onPressed: () {
                  ref.invalidate(revenueStatisticsProvider);
                  ref.invalidate(orderStatisticsProvider);
                  ref.invalidate(financialStatisticsProvider);
                },
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Revenue ───────────────────────────────────────────────
          _SectionHeader(title: 'Revenue', icon: Icons.attach_money_rounded, color: const Color(0xFF8B5CF6)),
          const SizedBox(height: 12),
          revenueAsync.when(
            loading: () => const SizedBox(height: 100, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(revenueStatisticsProvider)),
            data: (d) => _StatsGrid(stats: [
              _Stat('Total Revenue', '${AppConstants.currencySymbol}${_fmt(d['total_revenue'])}', const Color(0xFF8B5CF6), Icons.attach_money_rounded),
              _Stat('Platform Fees', '${AppConstants.currencySymbol}${_fmt(d['platform_fees'])}', const Color(0xFFEC4899), Icons.account_balance_rounded),
              _Stat('Delivery Fees', '${AppConstants.currencySymbol}${_fmt(d['delivery_fees'])}', const Color(0xFF0EA5E9), Icons.delivery_dining_rounded),
              _Stat('Avg Order Value', '${AppConstants.currencySymbol}${_fmt(d['avg_order_value'])}', const Color(0xFF10B981), Icons.receipt_long_rounded),
            ]),
          ),

          const SizedBox(height: 24),

          // ── Orders ────────────────────────────────────────────────
          _SectionHeader(title: 'Orders', icon: Icons.receipt_long_rounded, color: const Color(0xFFF59E0B)),
          const SizedBox(height: 12),
          orderAsync.when(
            loading: () => const SizedBox(height: 100, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(orderStatisticsProvider)),
            data: (d) => Column(
              children: [
                _StatsGrid(stats: [
                  _Stat('Total Orders', '${d['total_orders'] ?? 0}', const Color(0xFFF59E0B), Icons.receipt_long_rounded),
                  _Stat('Delivered', '${d['delivered_orders'] ?? 0}', const Color(0xFF10B981), Icons.check_circle_rounded),
                  _Stat('Cancelled', '${d['cancelled_orders'] ?? 0}', const Color(0xFFEF4444), Icons.cancel_rounded),
                  _Stat('Active', '${d['active_orders'] ?? 0}', const Color(0xFF6366F1), Icons.pending_rounded),
                ]),
                const SizedBox(height: 16),
                _StatusBreakdown(data: d),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Financial ─────────────────────────────────────────────
          _SectionHeader(title: 'Financials', icon: Icons.account_balance_rounded, color: const Color(0xFF14B8A6)),
          const SizedBox(height: 12),
          financialAsync.when(
            loading: () => const SizedBox(height: 100, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(financialStatisticsProvider)),
            data: (d) => _StatsGrid(stats: [
              _Stat('Total Payouts', '${AppConstants.currencySymbol}${_fmt(d['total_payouts'])}', const Color(0xFF14B8A6), Icons.payments_rounded),
              _Stat('Pending Payouts', '${AppConstants.currencySymbol}${_fmt(d['pending_payouts'])}', const Color(0xFFF59E0B), Icons.hourglass_empty_rounded),
              _Stat('Net Profit', '${AppConstants.currencySymbol}${_fmt(d['net_profit'])}', const Color(0xFF10B981), Icons.trending_up_rounded),
              _Stat('Disputes Cost', '${AppConstants.currencySymbol}${_fmt(d['disputes_cost'])}', const Color(0xFFEF4444), Icons.gavel_rounded),
            ]),
          ),
        ],
      ),
    );
  }

  static String _fmt(dynamic v) => (v as num? ?? 0).toStringAsFixed(2);
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionHeader({required this.title, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final List<_Stat> stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: stats.expand((s) => [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: s.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(s.icon, color: s.color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                      Text(s.label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
      ]).toList()..removeLast(),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  final Map<String, dynamic> data;
  const _StatusBreakdown({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = (data['total_orders'] as num? ?? 1).toDouble();
    final statuses = [
      ('Delivered', data['delivered_orders'], const Color(0xFF10B981)),
      ('Cancelled', data['cancelled_orders'], const Color(0xFFEF4444)),
      ('Pending', data['pending_orders'], const Color(0xFFF59E0B)),
      ('Active', data['active_orders'], const Color(0xFF6366F1)),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Order Status Breakdown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          ...statuses.map((s) {
            final count = (s.$2 as num? ?? 0).toDouble();
            final pct = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(width: 80, child: Text(s.$1, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            backgroundColor: const Color(0xFFF1F5F9),
                            valueColor: AlwaysStoppedAnimation(s.$3),
                            minHeight: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(width: 36, child: Text('${count.toInt()}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: s.$3))),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _Stat {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _Stat(this.label, this.value, this.color, this.icon);
}
