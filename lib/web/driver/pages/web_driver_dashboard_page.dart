import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/app_constants.dart';
import '../../../models/order_model.dart';
import '../../../providers/driver_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebDriverDashboardPage extends ConsumerWidget {
  final String userId;
  final String driverId;
  const WebDriverDashboardPage({super.key, required this.userId, required this.driverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driverAsync  = ref.watch(driverProfileProvider(userId));
    final historyAsync = ref.watch(deliveryHistoryProvider(driverId));
    final activeAsync  = ref.watch(activeDeliveriesProvider(driverId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dashboard', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Your delivery overview', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
              onPressed: () {
                ref.invalidate(driverProfileProvider(userId));
                ref.invalidate(deliveryHistoryProvider(driverId));
                ref.invalidate(activeDeliveriesProvider(driverId));
              },
            ),
          ]),
          const SizedBox(height: 24),

          // Stats
          driverAsync.when(
            loading: () => const SizedBox(height: 120, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e)),
            data: (driver) {
              if (driver == null) return const SizedBox();
              return Row(children: [
                Expanded(child: _StatCard(
                  icon: Icons.local_shipping_rounded,
                  label: 'Total Deliveries',
                  value: '${driver.completedDeliveries ?? 0}',
                  color: const Color(0xFF6366F1),
                )),
                const SizedBox(width: 16),
                Expanded(child: _StatCard(
                  icon: Icons.star_rounded,
                  label: 'Rating',
                  value: driver.rating != null ? driver.rating!.toStringAsFixed(1) : '—',
                  color: const Color(0xFFF59E0B),
                )),
                const SizedBox(width: 16),
                Expanded(child: _StatCard(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Total Paid Out',
                  value: '${AppConstants.currencySymbol}${(driver.totalPaidOut ?? 0).toStringAsFixed(2)}',
                  color: const Color(0xFF10B981),
                )),
                const SizedBox(width: 16),
                Expanded(child: _StatCard(
                  icon: Icons.radio_button_checked_rounded,
                  label: 'Status',
                  value: driver.isAvailable ? 'Online' : 'Offline',
                  color: driver.isAvailable ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                )),
              ]);
            },
          ),
          const SizedBox(height: 28),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active deliveries
              Expanded(
                flex: 2,
                child: _Card(
                  title: 'Active Deliveries',
                  trailing: activeAsync.maybeWhen(
                    data: (list) => _CountBadge(list.length, const Color(0xFF6366F1)),
                    orElse: () => null,
                  ),
                  child: activeAsync.when(
                    loading: () => const SizedBox(height: 80, child: AppLoadingIndicator()),
                    error: (e, _) => AppErrorState(message: friendlyError(e)),
                    data: (list) => list.isEmpty
                        ? _Empty(Icons.electric_scooter_rounded, 'No active deliveries right now')
                        : Column(
                            children: list.map((o) => _OrderRow(order: o)).toList(),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Recent history
              Expanded(
                flex: 3,
                child: _Card(
                  title: 'Recent Deliveries',
                  trailing: historyAsync.maybeWhen(
                    data: (list) => _CountBadge(list.length, const Color(0xFF10B981)),
                    orElse: () => null,
                  ),
                  child: historyAsync.when(
                    loading: () => const SizedBox(height: 80, child: AppLoadingIndicator()),
                    error: (e, _) => AppErrorState(message: friendlyError(e)),
                    data: (list) {
                      final recent = list.take(8).toList();
                      return recent.isEmpty
                          ? _Empty(Icons.history_rounded, 'No deliveries yet')
                          : Column(children: recent.map((o) => _HistoryRow(order: o)).toList());
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 12),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  const _Card({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
          child: Row(children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
            const Spacer(),
            if (trailing != null) trailing!,
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ]),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;
  const _CountBadge(this.count, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
    child: Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
  );
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String message;
  const _Empty(this.icon, this.message);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 36, color: const Color(0xFFE2E8F0)),
      const SizedBox(height: 8),
      Text(message, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
    ])),
  );
}

class _OrderRow extends StatelessWidget {
  final Order order;
  const _OrderRow({required this.order});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.electric_scooter_rounded, size: 18, color: Color(0xFF6366F1)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(order.deliveryAddress ?? 'Delivery address', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis),
          Text(order.status.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 11, color: Color(0xFF6366F1), fontWeight: FontWeight.w600)),
        ])),
        Text('${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
      ]),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Order order;
  const _HistoryRow({required this.order});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(order.deliveryAddress ?? 'Delivered', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis),
          Text(DateFormat('MMM d, h:mm a').format(order.orderedAt), style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          if (order.driverTip != null && order.driverTip! > 0)
            Text('+${AppConstants.currencySymbol}${order.driverTip!.toStringAsFixed(2)} tip', style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}
