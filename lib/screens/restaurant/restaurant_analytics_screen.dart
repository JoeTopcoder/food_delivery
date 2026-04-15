import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/friendly_error.dart';
import 'package:food_driver/config/app_constants.dart';

enum _Period { today, week, month, all }

class RestaurantAnalyticsScreen extends ConsumerStatefulWidget {
  const RestaurantAnalyticsScreen({super.key});

  @override
  ConsumerState<RestaurantAnalyticsScreen> createState() =>
      _RestaurantAnalyticsScreenState();
}

class _RestaurantAnalyticsScreenState
    extends ConsumerState<RestaurantAnalyticsScreen> {
  _Period _period = _Period.week;

  List<Order> _filter(List<Order> orders) {
    final now = DateTime.now();
    return switch (_period) {
      _Period.today => orders.where((o) {
        final d = o.orderedAt;
        return d.year == now.year && d.month == now.month && d.day == now.day;
      }).toList(),
      _Period.week =>
        orders
            .where(
              (o) => o.orderedAt.isAfter(now.subtract(const Duration(days: 7))),
            )
            .toList(),
      _Period.month =>
        orders
            .where(
              (o) =>
                  o.orderedAt.isAfter(now.subtract(const Duration(days: 30))),
            )
            .toList(),
      _Period.all => orders,
    };
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    if (currentUserId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(currentUserId));

    return restaurantAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text(friendlyError(e)))),
      data: (restaurant) {
        if (restaurant == null) {
          return const Scaffold(
            body: Center(child: Text('No restaurant found')),
          );
        }
        final ordersAsync = ref.watch(ownerAllOrdersProvider(currentUserId));
        return ordersAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) =>
              Scaffold(body: Center(child: Text(friendlyError(e)))),
          data: (all) {
            final orders = _filter(all);
            return _buildDashboard(context, restaurant.name, orders, all);
          },
        );
      },
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    String restaurantName,
    List<Order> orders,
    List<Order> allOrders,
  ) {
    final totalRevenue = orders.fold<double>(0, (s, o) => s + o.totalAmount);
    final delivered = orders.where((o) => o.status == 'delivered').toList();
    final cancelled = orders.where((o) => o.status == 'cancelled').toList();
    final completionRate = orders.isEmpty
        ? 0.0
        : delivered.length / orders.length * 100;
    final avgOrderValue = delivered.isEmpty
        ? 0.0
        : totalRevenue / delivered.length;

    // Top items
    final itemCounts = <String, int>{};
    for (final o in delivered) {
      for (final item in o.items) {
        itemCounts[item.itemName] =
            (itemCounts[item.itemName] ?? 0) + item.quantity;
      }
    }
    final topItems = itemCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Revenue bar chart — adapts to selected period
    final dailyRevenue = <String, double>{};
    final now = DateTime.now();
    final int chartDays;
    final String Function(DateTime) chartKeyFmt;
    final String chartTitle;

    switch (_period) {
      case _Period.today:
        // Hourly buckets for today
        chartDays = 0;
        chartKeyFmt = (d) => '${d.hour.toString().padLeft(2, '0')}:00';
        chartTitle = 'Revenue — Today (Hourly)';
        for (int h = 0; h < 24; h += 3) {
          dailyRevenue['${h.toString().padLeft(2, '0')}:00'] = 0;
        }
        for (final o in delivered) {
          final hour = (o.orderedAt.hour ~/ 3) * 3;
          final key = '${hour.toString().padLeft(2, '0')}:00';
          dailyRevenue[key] = (dailyRevenue[key] ?? 0) + o.totalAmount;
        }
      case _Period.week:
        chartDays = 7;
        chartKeyFmt = (d) => DateFormat('EEE').format(d);
        chartTitle = 'Revenue — Last 7 Days';
        for (int i = 6; i >= 0; i--) {
          final day = now.subtract(Duration(days: i));
          dailyRevenue[chartKeyFmt(day)] = 0;
        }
        for (final o in delivered) {
          final key = chartKeyFmt(o.orderedAt);
          dailyRevenue[key] = (dailyRevenue[key] ?? 0) + o.totalAmount;
        }
      case _Period.month:
        chartDays = 30;
        chartKeyFmt = (d) => DateFormat('d/M').format(d);
        chartTitle = 'Revenue — Last 30 Days (Weekly)';
        // 5 weekly buckets
        for (int w = 4; w >= 0; w--) {
          final day = now.subtract(Duration(days: w * 7));
          dailyRevenue['Wk ${5 - w}'] = 0;
        }
        for (final o in delivered) {
          final daysAgo = now.difference(o.orderedAt).inDays;
          final weekIdx = 4 - (daysAgo ~/ 7).clamp(0, 4);
          final key = 'Wk ${weekIdx + 1}';
          dailyRevenue[key] = (dailyRevenue[key] ?? 0) + o.totalAmount;
        }
      case _Period.all:
        chartDays = 0;
        chartKeyFmt = (d) => DateFormat('MMM yy').format(d);
        chartTitle = 'Revenue — All Time (Monthly)';
        // Group by month
        for (final o in delivered) {
          final key = chartKeyFmt(o.orderedAt);
          dailyRevenue[key] = (dailyRevenue[key] ?? 0) + o.totalAmount;
        }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(
          'Analytics',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              final uid = ref.read(currentUserIdProvider);
              if (uid != null) {
                ref.invalidate(restaurantByOwnerProvider(uid));
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Period tabs
          Container(
            color: AppTheme.primaryColor,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: _Period.values.map((p) {
                final label = switch (p) {
                  _Period.today => 'Today',
                  _Period.week => '7 Days',
                  _Period.month => '30 Days',
                  _Period.all => 'All Time',
                };
                final active = _period == p;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _period = p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: active ? AppTheme.primaryColor : Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // KPI cards
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.6,
                    children: [
                      _KpiCard(
                        label: 'Revenue',
                        value:
                            '${AppConstants.currencySymbol}${totalRevenue.toStringAsFixed(0)}',
                        icon: Icons.attach_money_rounded,
                        color: const Color(0xFF10B981),
                      ),
                      _KpiCard(
                        label: 'Orders',
                        value: orders.length.toString(),
                        icon: Icons.receipt_long_rounded,
                        color: const Color(0xFF6366F1),
                      ),
                      _KpiCard(
                        label: 'Completion',
                        value: '${completionRate.toStringAsFixed(0)}%',
                        icon: Icons.check_circle_rounded,
                        color: AppTheme.primaryColor,
                      ),
                      _KpiCard(
                        label: 'Avg. Order',
                        value:
                            '${AppConstants.currencySymbol}${avgOrderValue.toStringAsFixed(0)}',
                        icon: Icons.trending_up_rounded,
                        color: const Color(0xFFF59E0B),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Revenue bar chart
                  _SectionCard(
                    title: chartTitle,
                    child: _BarChart(data: dailyRevenue),
                  ),
                  const SizedBox(height: 12),

                  // Order status
                  _SectionCard(
                    title: 'Order Breakdown',
                    child: Column(
                      children: [
                        _StatusRow(
                          label: 'Delivered',
                          count: delivered.length,
                          total: orders.length,
                          color: const Color(0xFF10B981),
                        ),
                        const SizedBox(height: 8),
                        _StatusRow(
                          label: 'Cancelled',
                          count: cancelled.length,
                          total: orders.length,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 8),
                        _StatusRow(
                          label: 'In Progress',
                          count:
                              orders.length -
                              delivered.length -
                              cancelled.length,
                          total: orders.length,
                          color: const Color(0xFF6366F1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Top items
                  if (topItems.isNotEmpty)
                    _SectionCard(
                      title: 'Top Selling Items',
                      child: Column(
                        children: topItems.take(5).map((e) {
                          final pct = topItems.first.value == 0
                              ? 0.0
                              : e.value / topItems.first.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        e.key,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${e.value} sold',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(
                                  value: pct,
                                  backgroundColor: const Color(0xFFE5E7EB),
                                  color: AppTheme.primaryColor,
                                  borderRadius: BorderRadius.circular(4),
                                  minHeight: 6,
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  label,
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

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;
  const _StatusRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: const Color(0xFFE5E7EB),
            color: color,
            borderRadius: BorderRadius.circular(4),
            minHeight: 8,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 30,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _BarChart extends StatelessWidget {
  final Map<String, double> data;
  const _BarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(
        child: Text('No data', style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    final maxVal = data.values.fold<double>(0, (a, b) => a > b ? a : b);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: data.entries.map((e) {
        final pct = maxVal == 0 ? 0.0 : e.value / maxVal;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (e.value > 0)
                  Text(
                    '${AppConstants.currencySymbol}${e.value.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 8,
                      color: Color(0xFF6B7280),
                    ),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 3),
                Container(
                  height: 80 * pct + 4,
                  decoration: BoxDecoration(
                    color: pct > 0
                        ? AppTheme.primaryColor
                        : const Color(0xFFE5E7EB),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  e.key,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
