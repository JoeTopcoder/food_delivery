import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/app_constants.dart';
import '../../../providers/driver_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebDriverEarningsPage extends ConsumerWidget {
  final String userId;
  final String driverId;
  const WebDriverEarningsPage({super.key, required this.userId, required this.driverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driverAsync  = ref.watch(driverProfileProvider(userId));
    final historyAsync = ref.watch(deliveryHistoryProvider(driverId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Earnings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Your delivery income and payment history', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
              onPressed: () {
                ref.invalidate(driverProfileProvider(userId));
                ref.invalidate(deliveryHistoryProvider(driverId));
              },
            ),
          ]),
          const SizedBox(height: 24),

          // Summary cards
          driverAsync.when(
            loading: () => const SizedBox(height: 120, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e)),
            data: (driver) {
              if (driver == null) return const SizedBox();
              return historyAsync.when(
                loading: () => const SizedBox(height: 120, child: AppLoadingIndicator()),
                error: (e, _) => AppErrorState(message: friendlyError(e)),
                data: (history) {
                  final totalTips = history.fold<double>(0, (s, o) => s + (o.driverTip ?? 0));
                  final totalDeliveries = driver.completedDeliveries ?? history.length;
                  return Row(children: [
                    Expanded(child: _EarningCard(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'Total Paid Out',
                      value: '${AppConstants.currencySymbol}${(driver.totalPaidOut ?? 0).toStringAsFixed(2)}',
                      color: const Color(0xFF10B981),
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _EarningCard(
                      icon: Icons.payments_rounded,
                      label: 'Total Tips',
                      value: '${AppConstants.currencySymbol}${totalTips.toStringAsFixed(2)}',
                      color: const Color(0xFFF59E0B),
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _EarningCard(
                      icon: Icons.local_shipping_rounded,
                      label: 'Completed Deliveries',
                      value: '$totalDeliveries',
                      color: const Color(0xFF6366F1),
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _EarningCard(
                      icon: Icons.money_rounded,
                      label: 'Cash Float',
                      value: '${AppConstants.currencySymbol}${(driver.cashFloat ?? 0).toStringAsFixed(2)}',
                      color: const Color(0xFF3B82F6),
                    )),
                  ]);
                },
              );
            },
          ),
          const SizedBox(height: 28),

          // Delivery history table
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text('Delivery History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
              ),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              // Table header
              Container(
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: const Row(children: [
                  Expanded(flex: 2, child: Text('ORDER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)))),
                  Expanded(flex: 3, child: Text('DELIVERY ADDRESS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)))),
                  Expanded(child: Text('DATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)))),
                  Expanded(child: Text('AMOUNT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)))),
                  Expanded(child: Text('TIP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)))),
                ]),
              ),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              historyAsync.when(
                loading: () => const Padding(padding: EdgeInsets.all(32), child: AppLoadingIndicator()),
                error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: AppErrorState(message: friendlyError(e))),
                data: (history) {
                  if (history.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.history_rounded, size: 40, color: Color(0xFFE2E8F0)),
                        SizedBox(height: 8),
                        Text('No deliveries yet', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                      ])),
                    );
                  }
                  return Column(
                    children: history.map((o) => Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Row(children: [
                          Expanded(flex: 2, child: Text('#${o.id.substring(0, 8).toUpperCase()}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)))),
                          Expanded(flex: 3, child: Text(o.deliveryAddress ?? '—',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis)),
                          Expanded(child: Text(DateFormat('MMM d').format(o.orderedAt),
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
                          Expanded(child: Text('${AppConstants.currencySymbol}${o.totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)))),
                          Expanded(child: (o.driverTip ?? 0) > 0
                              ? Text('+${AppConstants.currencySymbol}${o.driverTip!.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.w600))
                              : const Text('—', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))),
                        ]),
                      ),
                      const Divider(height: 1, color: Color(0xFFF8FAFC)),
                    ])).toList(),
                  );
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _EarningCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _EarningCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
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
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
    ]),
  );
}
