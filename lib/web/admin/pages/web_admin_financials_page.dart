import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/app_constants.dart';
import '../../../providers/admin_provider.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

class WebAdminFinancialsPage extends ConsumerWidget {
  const WebAdminFinancialsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financialsAsync = ref.watch(financialStatisticsProvider);
    final fmt = NumberFormat('#,##0.00');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Financials', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Platform revenue, commissions, and payout overview', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                onPressed: () => ref.invalidate(financialStatisticsProvider),
              ),
            ],
          ),
          const SizedBox(height: 24),

          financialsAsync.when(
            loading: () => const SizedBox(height: 300, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(financialStatisticsProvider)),
            data: (data) {
              final sym = AppConstants.currencySymbol;
              final totalSales = (data['total_sales'] ?? 0).toDouble();
              final totalCommission = (data['total_commission'] ?? 0).toDouble();
              final totalRestaurantPayout = (data['total_restaurant_payout'] ?? 0).toDouble();
              final totalDriverPayout = (data['total_driver_payout'] ?? 0).toDouble();
              final monthlySales = (data['monthly_sales'] ?? 0).toDouble();
              final monthlyCommission = (data['monthly_commission'] ?? 0).toDouble();
              final orderCount = data['order_count'] ?? 0;
              final grossRevenue = (data['gross_revenue'] ?? totalSales).toDouble();
              final stripeFeesCollected = (data['stripe_fees_collected'] ?? 0).toDouble();
              final platformServiceFeesCollected = (data['platform_service_fees_collected'] ?? 0).toDouble();
              final netRevenue = (data['net_revenue'] ?? (grossRevenue - stripeFeesCollected)).toDouble();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Overview banner ─────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1F2937), Color(0xFF374151)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.analytics_rounded, color: Colors.white70, size: 20),
                          const SizedBox(width: 8),
                          const Text('All-Time Overview', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                            child: Text('$orderCount orders', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        Text('$sym${fmt.format(grossRevenue)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1)),
                        const Text('Gross Revenue', style: TextStyle(color: Colors.white54, fontSize: 13)),
                        const SizedBox(height: 20),
                        Row(children: [
                          _BannerStat(label: 'Net Revenue', value: '$sym${fmt.format(netRevenue)}', color: const Color(0xFF34D399)),
                          const SizedBox(width: 32),
                          _BannerStat(label: 'Commission', value: '$sym${fmt.format(totalCommission)}', color: const Color(0xFF60A5FA)),
                          const SizedBox(width: 32),
                          _BannerStat(label: 'Stripe Fees', value: '$sym${fmt.format(stripeFeesCollected)}', color: const Color(0xFFA78BFA)),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── This month ─────────────────────────────────────
                  const Text('This Month', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _KpiCard(label: 'Monthly Sales', value: '$sym${fmt.format(monthlySales)}', icon: Icons.trending_up_rounded, color: const Color(0xFF6366F1))),
                    const SizedBox(width: 14),
                    Expanded(child: _KpiCard(label: 'Monthly Commission', value: '$sym${fmt.format(monthlyCommission)}', icon: Icons.percent_rounded, color: const Color(0xFF10B981))),
                    const SizedBox(width: 14),
                    Expanded(child: _KpiCard(label: 'Platform Service Fees', value: '$sym${fmt.format(platformServiceFeesCollected)}', icon: Icons.handshake_rounded, color: const Color(0xFFF59E0B))),
                  ]),
                  const SizedBox(height: 20),

                  // ── Payouts ────────────────────────────────────────
                  const Text('Payouts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _KpiCard(label: 'Restaurant Payouts', value: '$sym${fmt.format(totalRestaurantPayout)}', icon: Icons.storefront_rounded, color: const Color(0xFF0EA5E9))),
                    const SizedBox(width: 14),
                    Expanded(child: _KpiCard(label: 'Driver Payouts', value: '$sym${fmt.format(totalDriverPayout)}', icon: Icons.delivery_dining_rounded, color: const Color(0xFF8B5CF6))),
                    const SizedBox(width: 14),
                    Expanded(child: _KpiCard(label: 'Total Sales', value: '$sym${fmt.format(totalSales)}', icon: Icons.receipt_long_rounded, color: const Color(0xFF14B8A6))),
                  ]),
                  const SizedBox(height: 20),

                  // ── Revenue breakdown table ────────────────────────
                  Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Text('Revenue Breakdown', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                        ),
                        const Divider(height: 1),
                        ...[
                          ('Gross Revenue', grossRevenue, Icons.attach_money_rounded, const Color(0xFF6366F1)),
                          ('Platform Service Fees', platformServiceFeesCollected, Icons.handshake_rounded, const Color(0xFFF59E0B)),
                          ('Stripe Fees Collected', stripeFeesCollected, Icons.credit_card_rounded, const Color(0xFFA78BFA)),
                          ('Net Revenue', netRevenue, Icons.account_balance_rounded, const Color(0xFF10B981)),
                          ('Restaurant Payouts', totalRestaurantPayout, Icons.storefront_rounded, const Color(0xFF0EA5E9)),
                          ('Driver Payouts', totalDriverPayout, Icons.delivery_dining_rounded, const Color(0xFF8B5CF6)),
                        ].map((row) => _BreakdownRow(label: row.$1, value: '$sym${fmt.format(row.$2)}', icon: row.$3, color: row.$4)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BannerStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _BannerStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ],
  );
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _KpiCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Row(
      children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
        ])),
      ],
    ),
  );
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _BreakdownRow({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    child: Row(children: [
      Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 16)),
      const SizedBox(width: 14),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF374151)))),
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
    ]),
  );
}
