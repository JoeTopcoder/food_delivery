import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/app_constants.dart';
import '../../../models/order_model.dart';
import '../../../providers/driver_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebDriverDeliveriesPage extends ConsumerWidget {
  final String driverId;
  const WebDriverDeliveriesPage({super.key, required this.driverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesAsync = ref.watch(activeDeliveriesProvider(driverId));

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Active Deliveries', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Orders you have accepted and are delivering', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
              onPressed: () => ref.invalidate(activeDeliveriesProvider(driverId)),
            ),
          ]),
          const SizedBox(height: 24),
          Expanded(
            child: deliveriesAsync.when(
              loading: () => const AppLoadingIndicator(),
              error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(activeDeliveriesProvider(driverId))),
              data: (deliveries) {
                if (deliveries.isEmpty) {
                  return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.electric_scooter_rounded, size: 64, color: Color(0xFFE2E8F0)),
                    SizedBox(height: 12),
                    Text('No active deliveries', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                    SizedBox(height: 4),
                    Text('Accept an order from "Available Orders" to start delivering', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                  ]));
                }
                return ListView.separated(
                  itemCount: deliveries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (_, i) => _DeliveryCard(order: deliveries[i], driverId: driverId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryCard extends ConsumerStatefulWidget {
  final Order order;
  final String driverId;
  const _DeliveryCard({required this.order, required this.driverId});

  @override
  ConsumerState<_DeliveryCard> createState() => _DeliveryCardState();
}

class _DeliveryCardState extends ConsumerState<_DeliveryCard> {
  bool _loading = false;

  Future<void> _complete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark as Delivered?'),
        content: const Text('Confirm that this order has been successfully delivered to the customer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Confirm Delivered'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final svc = ref.read(driverServiceProvider);
      await svc.completeDelivery(widget.order.id);
      if (!mounted) return;
      AppSnackbar.success(context, 'Delivery marked as complete!');
      ref.invalidate(activeDeliveriesProvider(widget.driverId));
      ref.invalidate(deliveryHistoryProvider(widget.driverId));
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final statusColor = _statusColor(o.status);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(o.status.replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
            ]),
          ),
          const Spacer(),
          Text('${AppConstants.currencySymbol}${o.totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
        ]),
        const SizedBox(height: 14),
        // Order ID + time
        Row(children: [
          const Icon(Icons.receipt_rounded, size: 14, color: Color(0xFF94A3B8)),
          const SizedBox(width: 5),
          Text('Order #${o.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
          const Spacer(),
          Text(DateFormat('MMM d, h:mm a').format(o.orderedAt), style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ]),
        const SizedBox(height: 8),
        // Items
        Row(children: [
          const Icon(Icons.fastfood_rounded, size: 14, color: Color(0xFF94A3B8)),
          const SizedBox(width: 5),
          Expanded(child: Text(o.items.map((i) => '${i.quantity}x ${i.itemName}').join(', '),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis)),
        ]),
        if (o.deliveryAddress != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFF94A3B8)),
            const SizedBox(width: 5),
            Expanded(child: Text(o.deliveryAddress!, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis)),
          ]),
        ],
        if ((o.driverTip ?? 0) > 0) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.payments_rounded, size: 14, color: Color(0xFF10B981)),
            const SizedBox(width: 5),
            Text('${AppConstants.currencySymbol}${o.driverTip!.toStringAsFixed(2)} tip',
                style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
          ]),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _complete,
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text('Mark as Delivered', style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ),
      ]),
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      'out_for_delivery' => const Color(0xFF6366F1),
      'confirmed'        => const Color(0xFF3B82F6),
      'preparing'        => const Color(0xFFF59E0B),
      'ready'            => const Color(0xFF10B981),
      _                  => const Color(0xFF64748B),
    };
  }
}
