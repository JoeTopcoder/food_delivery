import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/app_constants.dart';
import '../../../models/order_model.dart';
import '../../../providers/driver_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebDriverOrdersPage extends ConsumerWidget {
  final String driverId;
  const WebDriverOrdersPage({super.key, required this.driverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = (driverId: driverId, lat: null, lng: null);
    final ordersAsync = ref.watch(availableOrdersProvider(params));

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Available Orders', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Orders waiting for a driver — accept to start delivery', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
              onPressed: () => ref.invalidate(availableOrdersProvider(params)),
            ),
          ]),
          const SizedBox(height: 24),
          Expanded(
            child: ordersAsync.when(
              loading: () => const AppLoadingIndicator(),
              error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(availableOrdersProvider(params))),
              data: (orders) {
                if (orders.isEmpty) {
                  return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_shipping_outlined, size: 64, color: Color(0xFFE2E8F0)),
                    SizedBox(height: 12),
                    Text('No orders available right now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                    SizedBox(height: 4),
                    Text('New orders will appear here automatically', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                  ]));
                }
                return ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _OrderCard(order: orders[i], driverId: driverId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  final Order order;
  final String driverId;
  const _OrderCard({required this.order, required this.driverId});

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _loading = false;

  Future<void> _accept() async {
    setState(() => _loading = true);
    try {
      final svc = ref.read(driverServiceProvider);
      final ok = await svc.acceptDelivery(widget.order.id, widget.driverId);
      if (!mounted) return;
      if (ok) {
        AppSnackbar.success(context, 'Order accepted! Head to the restaurant.');
        final params = (driverId: widget.driverId, lat: null, lng: null);
        ref.invalidate(availableOrdersProvider(params));
        ref.invalidate(activeDeliveriesProvider(widget.driverId));
      } else {
        AppSnackbar.error(context, 'Order already taken. Refreshing...');
        ref.invalidate(availableOrdersProvider((driverId: widget.driverId, lat: null, lng: null)));
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final itemCount = o.items.fold<int>(0, (s, i) => s + i.quantity);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Row(children: [
        // Icon
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF6366F1), size: 26),
        ),
        const SizedBox(width: 16),
        // Info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Order #${o.id.substring(0, 8).toUpperCase()}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFFFF3ED), borderRadius: BorderRadius.circular(8)),
              child: Text('${AppConstants.currencySymbol}${o.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFFF6B35))),
            ),
          ]),
          const SizedBox(height: 4),
          Text('$itemCount item${itemCount == 1 ? '' : 's'} · ${o.paymentMethod ?? 'Cash'} · ${DateFormat('h:mm a').format(o.orderedAt)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          if (o.deliveryAddress != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on_rounded, size: 13, color: Color(0xFF94A3B8)),
              const SizedBox(width: 3),
              Expanded(child: Text(o.deliveryAddress!, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)), overflow: TextOverflow.ellipsis)),
            ]),
          ],
          if ((o.driverTip ?? 0) > 0) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.payments_rounded, size: 13, color: Color(0xFF10B981)),
              const SizedBox(width: 3),
              Text('${AppConstants.currencySymbol}${o.driverTip!.toStringAsFixed(2)} tip included',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
            ]),
          ],
        ])),
        const SizedBox(width: 16),
        // Accept button
        SizedBox(
          width: 110,
          child: ElevatedButton(
            onPressed: _loading ? null : _accept,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Accept', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}
