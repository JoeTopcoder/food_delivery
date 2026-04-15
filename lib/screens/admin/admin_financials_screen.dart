import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/admin_provider.dart';
import '../../utils/friendly_error.dart';
import 'package:food_driver/config/app_constants.dart';
import '../../utils/context_extensions.dart';

class AdminFinancialsScreen extends ConsumerWidget {
  const AdminFinancialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financialsAsync = ref.watch(financialStatisticsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(
          context.l10n.financials,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(financialStatisticsProvider),
        color: AppTheme.primaryColor,
        child: financialsAsync.when(
          data: (data) {
            final totalSales = (data['total_sales'] ?? 0).toDouble();
            final totalCommission = (data['total_commission'] ?? 0).toDouble();
            final totalRestaurantPayout = (data['total_restaurant_payout'] ?? 0)
                .toDouble();
            final totalDriverPayout = (data['total_driver_payout'] ?? 0)
                .toDouble();
            final monthlySales = (data['monthly_sales'] ?? 0).toDouble();
            final monthlyCommission = (data['monthly_commission'] ?? 0)
                .toDouble();
            final orderCount = data['order_count'] ?? 0;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Overview Card ──
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1F2937), Color(0xFF374151)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.analytics_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Overview',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$orderCount orders',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${AppConstants.currencySymbol}${totalSales.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Total Sales (Delivered)',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This Month: \$${monthlySales.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFFFF8C42),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Commission Earnings ──
                _FinancialCard(
                  title: 'Commission Earnings',
                  icon: Icons.percent_rounded,
                  color: const Color(0xFF8B5CF6),
                  mainValue: totalCommission,
                  subLabel: 'This Month',
                  subValue: monthlyCommission,
                ),

                const SizedBox(height: 12),

                // ── Overall Sales ──
                _FinancialCard(
                  title: 'Overall Sales',
                  icon: Icons.trending_up_rounded,
                  color: const Color(0xFF10B981),
                  mainValue: totalSales,
                  subLabel: 'This Month',
                  subValue: monthlySales,
                ),

                const SizedBox(height: 12),

                // ── Restaurant Payouts ──
                _FinancialCard(
                  title: 'Restaurant Payouts Due',
                  icon: Icons.store_rounded,
                  color: AppTheme.primaryColor,
                  mainValue: totalRestaurantPayout,
                  subLabel: 'Total owed to restaurants',
                  subValue: null,
                ),

                const SizedBox(height: 12),

                // ── Driver Payouts ──
                _FinancialCard(
                  title: 'Driver Payouts Due',
                  icon: Icons.directions_bike_rounded,
                  color: const Color(0xFF3B82F6),
                  mainValue: totalDriverPayout,
                  subLabel: 'Delivery fees + tips owed',
                  subValue: null,
                ),

                const SizedBox(height: 24),

                // ── Summary breakdown ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Breakdown',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const Divider(height: 20),
                      _BreakdownRow(
                        label: 'Total Sales',
                        value: totalSales,
                        color: const Color(0xFF10B981),
                      ),
                      _BreakdownRow(
                        label: 'Platform Commission',
                        value: totalCommission,
                        color: const Color(0xFF8B5CF6),
                      ),
                      _BreakdownRow(
                        label: 'Restaurant Payouts',
                        value: totalRestaurantPayout,
                        color: AppTheme.primaryColor,
                      ),
                      _BreakdownRow(
                        label: 'Driver Payouts',
                        value: totalDriverPayout,
                        color: const Color(0xFF3B82F6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryColor),
          ),
          error: (e, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 8),
                Text(
                  friendlyError(e),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(financialStatisticsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FinancialCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final double mainValue;
  final String subLabel;
  final double? subValue;

  const _FinancialCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.mainValue,
    required this.subLabel,
    this.subValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppConstants.currencySymbol}${mainValue.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                if (subValue != null)
                  Text(
                    '$subLabel: \$${subValue!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  )
                else
                  Text(
                    subLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            '${AppConstants.currencySymbol}${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
