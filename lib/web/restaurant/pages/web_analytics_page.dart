import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../models/order_model.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';
import '../../../config/app_constants.dart';

enum _Period { today, week, month, all }

class WebAnalyticsPage extends ConsumerStatefulWidget {
  const WebAnalyticsPage({super.key});

  @override
  ConsumerState<WebAnalyticsPage> createState() => _WebAnalyticsPageState();
}

class _WebAnalyticsPageState extends ConsumerState<WebAnalyticsPage> {
  _Period _period = _Period.week;

  List<Order> _filter(List<Order> orders) {
    final now = DateTime.now();
    return switch (_period) {
      _Period.today => orders.where((o) {
          final d = o.orderedAt;
          return d.year == now.year && d.month == now.month && d.day == now.day;
        }).toList(),
      _Period.week => orders.where((o) => o.orderedAt.isAfter(now.subtract(const Duration(days: 7)))).toList(),
      _Period.month => orders.where((o) => o.orderedAt.isAfter(now.subtract(const Duration(days: 30)))).toList(),
      _Period.all => orders,
    };
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = ref.watch(currentUserIdProvider);
    if (ownerId == null) return const AppLoadingIndicator();

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(ownerId));

    return restaurantAsync.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(restaurantByOwnerProvider(ownerId))),
      data: (restaurant) {
        if (restaurant == null) return const AppEmptyState(icon: Icons.storefront_rounded, title: 'No restaurant found');
        final ordersAsync = ref.watch(ownerAllOrdersProvider(ownerId));
        return ordersAsync.when(
          loading: () => const AppLoadingIndicator(),
          error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(ownerAllOrdersProvider(ownerId))),
          data: (all) => _buildContent(restaurant.name, _filter(all), all),
        );
      },
    );
  }

  Widget _buildContent(String restaurantName, List<Order> orders, List<Order> allOrders) {
    final revenue = orders.fold<double>(0, (s, o) => s + o.totalAmount);
    final delivered = orders.where((o) => o.status == 'delivered').length;
    final cancelled = orders.where((o) => o.status == 'cancelled').length;
    final avgOrder = orders.isEmpty ? 0.0 : revenue / orders.length;

    // Top items
    final itemCounts = <String, int>{};
    for (final o in orders) {
      for (final item in o.items) {
        itemCounts[item.itemName] = (itemCounts[item.itemName] ?? 0) + item.quantity;
      }
    }
    final topItems = itemCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header + period picker ─────────────────────────────────
          Row(
            children: [
              const Text('Analytics', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              const Spacer(),
              _PeriodPicker(selected: _period, onChanged: (p) => setState(() => _period = p)),
            ],
          ),
          const SizedBox(height: 24),

          // ── KPI row ────────────────────────────────────────────────
          Row(children: [
            Expanded(child: _StatCard(label: 'Total Orders', value: '${orders.length}', icon: Icons.receipt_long_rounded, color: const Color(0xFF6366F1))),
            const SizedBox(width: 16),
            Expanded(child: _StatCard(label: 'Revenue', value: '${AppConstants.currencySymbol}${revenue.toStringAsFixed(2)}', icon: Icons.attach_money_rounded, color: const Color(0xFF10B981))),
            const SizedBox(width: 16),
            Expanded(child: _StatCard(label: 'Delivered', value: '$delivered', icon: Icons.check_circle_outline_rounded, color: const Color(0xFF0EA5E9))),
            const SizedBox(width: 16),
            Expanded(child: _StatCard(label: 'Avg Order Value', value: '${AppConstants.currencySymbol}${avgOrder.toStringAsFixed(2)}', icon: Icons.trending_up_rounded, color: const Color(0xFFF59E0B))),
          ]),

          const SizedBox(height: 32),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top items ──────────────────────────────────────────
              Expanded(
                child: _WebCard(
                  title: 'Top Items',
                  child: topItems.isEmpty
                      ? const _EmptyHint(text: 'No items in this period')
                      : Column(
                          children: topItems.take(10).toList().asMap().entries.map((e) {
                            final rank = e.key + 1;
                            final item = e.value;
                            return _TopItemRow(rank: rank, name: item.key, count: item.value);
                          }).toList(),
                        ),
                ),
              ),
              const SizedBox(width: 24),
              // ── Status breakdown ───────────────────────────────────
              Expanded(
                child: _WebCard(
                  title: 'Order Status Breakdown',
                  child: orders.isEmpty
                      ? const _EmptyHint(text: 'No orders in this period')
                      : Column(
                          children: [
                            _StatusRow(label: 'Delivered', count: delivered, total: orders.length, color: const Color(0xFF10B981)),
                            _StatusRow(label: 'Cancelled', count: cancelled, total: orders.length, color: Colors.red),
                            _StatusRow(
                              label: 'Other',
                              count: orders.length - delivered - cancelled,
                              total: orders.length,
                              color: const Color(0xFF6366F1),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Recent orders ──────────────────────────────────────────
          _WebCard(
            title: 'Orders in Period',
            child: orders.isEmpty
                ? const _EmptyHint(text: 'No orders in this period')
                : _OrderMiniTable(orders: orders.take(20).toList()),
          ),
        ],
      ),
    );
  }
}

// ─── Period picker ────────────────────────────────────────────────────────────

class _PeriodPicker extends StatelessWidget {
  final _Period selected;
  final ValueChanged<_Period> onChanged;

  const _PeriodPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = [
      (_Period.today, 'Today'),
      (_Period.week, '7 Days'),
      (_Period.month, '30 Days'),
      (_Period.all, 'All Time'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final isSelected = selected == o.$1;
          return GestureDetector(
            onTap: () => onChanged(o.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                o.$2,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Stat card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Generic web card ─────────────────────────────────────────────────────────

class _WebCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _WebCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, style: const TextStyle(color: Color(0xFF94A3B8)))));
}

// ─── Top item row ─────────────────────────────────────────────────────────────

class _TopItemRow extends StatelessWidget {
  final int rank;
  final String name;
  final int count;

  const _TopItemRow({required this.rank, required this.name, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: rank <= 3 ? const Color(0xFF6366F1).withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$rank', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: rank <= 3 ? const Color(0xFF6366F1) : const Color(0xFF94A3B8))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
          Text('$count orders', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─── Status row ──────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _StatusRow({required this.label, required this.count, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF475569), fontWeight: FontWeight.w500)),
            const Spacer(),
            Text('$count (${(pct * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: color.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mini order table ─────────────────────────────────────────────────────────

class _OrderMiniTable extends StatelessWidget {
  final List<Order> orders;
  const _OrderMiniTable({required this.orders});

  static Color _statusColor(String s) => switch (s) {
    'delivered' => const Color(0xFF10B981),
    'cancelled' => Colors.red,
    'preparing' => const Color(0xFF6366F1),
    'pending' => const Color(0xFFF59E0B),
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, h:mm a');
    return Column(
      children: orders.map((o) {
        final color = _statusColor(o.status);
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text('#${o.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
              ),
              Expanded(
                flex: 3,
                child: Text(o.items.map((i) => i.itemName).join(', '), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                flex: 2,
                child: Text('${AppConstants.currencySymbol}${o.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(o.status[0].toUpperCase() + o.status.substring(1), style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(fmt.format(o.orderedAt), style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
