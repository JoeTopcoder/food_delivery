import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_constants.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../models/order_model.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebCustomerOrdersPage extends ConsumerWidget {
  const WebCustomerOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const AppLoadingIndicator();

    final ordersAsync = ref.watch(userOrdersProvider(userId));

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('My Orders', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Track and review your order history', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () => ref.invalidate(userOrdersProvider(userId))),
          ]),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: ordersAsync.when(
                loading: () => const AppLoadingIndicator(),
                error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(userOrdersProvider(userId))),
                data: (orders) {
                  if (orders.isEmpty) {
                    return const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.receipt_long_rounded, size: 56, color: Color(0xFFE2E8F0)),
                        SizedBox(height: 12),
                        Text('No orders yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                        SizedBox(height: 4),
                        Text('Place your first order from the Home tab', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                      ]),
                    );
                  }
                  return Column(children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                      ),
                      child: const Row(children: [
                        Expanded(flex: 2, child: _Th('Order')),
                        SizedBox(width: 90, child: _Th('Status')),
                        SizedBox(width: 100, child: _Th('Total')),
                        SizedBox(width: 130, child: _Th('Date')),
                        SizedBox(width: 48),
                      ]),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    Expanded(
                      child: ListView.separated(
                        itemCount: orders.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        itemBuilder: (_, i) => _OrderRow(order: orders[i], onTap: () => _showDetails(context, orders[i])),
                      ),
                    ),
                  ]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context, Order order) {
    showDialog(
      context: context,
      builder: (_) => _OrderDetailDialog(order: order),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;
  const _OrderRow({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = order.items;
    final summary = items.map((i) => '${i.itemName} ×${i.quantity}').take(2).join(', ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Expanded(
            flex: 2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('#${order.receiptNumber ?? order.id.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
              const SizedBox(height: 2),
              Text(summary.isEmpty ? '—' : summary,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)), overflow: TextOverflow.ellipsis),
            ]),
          ),
          SizedBox(width: 90, child: _OrderStatusBadge(status: order.status)),
          SizedBox(
            width: 100,
            child: Text(
              '${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              _formatDate(order.orderedAt),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ),
          const SizedBox(width: 48, child: Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF94A3B8))),
        ]),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _OrderStatusBadge extends StatelessWidget {
  final String status;
  const _OrderStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'delivered'        => ('Delivered', const Color(0xFF10B981)),
      'out_for_delivery' => ('On the Way', const Color(0xFF6366F1)),
      'preparing'        => ('Preparing', const Color(0xFFF59E0B)),
      'confirmed'        => ('Confirmed', const Color(0xFF0EA5E9)),
      'cancelled'        => ('Cancelled', const Color(0xFFEF4444)),
      'pending'          => ('Pending', const Color(0xFFF59E0B)),
      _                  => (status, const Color(0xFF94A3B8)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _OrderDetailDialog extends StatelessWidget {
  final Order order;
  const _OrderDetailDialog({required this.order});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
              child: Row(children: [
                const Expanded(
                  child: Text('Order Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                ),
                _OrderStatusBadge(status: order.status),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _row('Order #', order.receiptNumber ?? order.id.substring(0, 8).toUpperCase()),
                  _row('Date', _formatDate(order.orderedAt)),
                  _row('Delivery Address', order.deliveryAddress ?? 'N/A'),
                  _row('Payment', order.paymentMethod ?? 'N/A'),
                  const SizedBox(height: 12),
                  const Text('Items', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  const SizedBox(height: 6),
                  ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text('${item.itemName} ×${item.quantity}', style: const TextStyle(fontSize: 13, color: Color(0xFF475569)))),
                      Text('${AppConstants.currencySymbol}${item.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                    ]),
                  )),
                  const Divider(height: 20),
                  _row('Subtotal', '${AppConstants.currencySymbol}${order.subtotal.toStringAsFixed(2)}'),
                  _row('Delivery Fee', '${AppConstants.currencySymbol}${order.deliveryFee.toStringAsFixed(2)}'),
                  if (order.discount != null && order.discount! > 0)
                    _row('Discount', '-${AppConstants.currencySymbol}${order.discount!.toStringAsFixed(2)}', valueColor: const Color(0xFF10B981)),
                  if (order.taxAmount != null && order.taxAmount! > 0)
                    _row('Tax', '${AppConstants.currencySymbol}${order.taxAmount!.toStringAsFixed(2)}'),
                  const Divider(height: 12),
                  Row(children: [
                    const Expanded(child: Text('Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)))),
                    Text('${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFFF6B35))),
                  ]),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor ?? const Color(0xFF1E293B)), textAlign: TextAlign.end)),
      ]),
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _Th extends StatelessWidget {
  final String text;
  const _Th(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.5));
}
