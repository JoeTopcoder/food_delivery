// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../models/master_order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../core/utils/responsive.dart';

class MultiRestaurantOrderDetailScreen extends ConsumerWidget {
  final String masterOrderId;
  const MultiRestaurantOrderDetailScreen({super.key, required this.masterOrderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(masterOrderDetailProvider(masterOrderId));

    // Real-time: invalidate whenever any restaurant_order changes
    ref.listen(masterOrderRealtimeProvider(
      ref.watch(currentUserIdProvider) ?? '',
    ), (_, __) {});

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(masterOrderDetailProvider(masterOrderId)),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const AppLoadingIndicator(message: 'Loading order…'),
        error:   (e, _) => AppErrorState(
          message:  friendlyError(e),
          onRetry:  () => ref.invalidate(masterOrderDetailProvider(masterOrderId)),
        ),
        data: (order) {
          if (order == null) {
            return const AppEmptyState(
              icon:     Icons.receipt_long_rounded,
              title:    'Order not found',
              subtitle: 'This order could not be loaded.',
            );
          }
          return _DetailBody(order: order, masterOrderId: masterOrderId);
        },
      ),
    );
  }
}

// ─── Detail body ─────────────────────────────────────────────────────────────

class _DetailBody extends ConsumerStatefulWidget {
  final MasterOrder order;
  final String masterOrderId;
  const _DetailBody({required this.order, required this.masterOrderId});

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  bool _cancelling = false;

  static Color _statusColor(String status) {
    switch (status) {
      case 'delivered':            return const Color(0xFF10B981);
      case 'cancelled':
      case 'partially_cancelled':  return Colors.red;
      case 'out_for_delivery':     return const Color(0xFF6366F1);
      case 'ready_for_pickup':     return const Color(0xFF8B5CF6);
      case 'preparing':            return const Color(0xFFF59E0B);
      case 'accepted':             return const Color(0xFF3B82F6);
      default:                     return AppTheme.primaryColor;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'partially_cancelled': return 'PART CANCELLED';
      case 'out_for_delivery':    return 'DELIVERING';
      case 'ready_for_pickup':    return 'READY';
      default: return status.replaceAll('_', ' ').toUpperCase();
    }
  }

  bool get _canCancelOrder =>
      widget.order.status != 'cancelled' &&
      widget.order.status != 'delivered';

  Future<void> _cancelEntireOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Entire Order?'),
        content: const Text(
          'All restaurant orders in this group will be cancelled. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Order'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await ref.read(orderServiceProvider).cancelMasterOrder(widget.masterOrderId);
      // Invalidate both the detail view and the orders list so all screens
      // immediately reflect the cancellation without waiting for realtime.
      ref.invalidate(masterOrderDetailProvider(widget.masterOrderId));
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) ref.invalidate(customerMasterOrdersProvider(userId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order cancelled successfully'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Cancel Failed'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order    = widget.order;
    final fmt      = DateFormat('MMM d, y · h:mm a');
    final currency = AppConstants.currencySymbol;
    final color    = _statusColor(order.status);

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context), 16,
        Responsive.horizontalPadding(context), 32,
      ),
      children: [
        // ── Master order header ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:        color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border:       Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.store_mall_directory_rounded, size: 18, color: color),
                  const SizedBox(width: 8),
                  Text(
                    'Multi-Restaurant Order',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize:   Responsive.headingSmall(context),
                      color:      color,
                    ),
                  ),
                  const Spacer(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color:        color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _statusLabel(order.status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '#${order.masterOrderNumber ?? order.id.substring(0, 8).toUpperCase()}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                  Text(
                    fmt.format(order.createdAt),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (order.deliveryAddress.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.deliveryAddress,
                        style: TextStyle(fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (order.restaurantCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '${order.restaurantCount} restaurant${order.restaurantCount > 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Per-restaurant sub-order cards ────────────────────────────────
        if (order.restaurantOrders == null || order.restaurantOrders!.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No restaurant orders found.')),
          )
        else
          ...order.restaurantOrders!.map(
            (ro) => _RestaurantOrderCard(
              ro:           ro,
              masterOrderId: widget.masterOrderId,
              masterStatus:  order.status,
            ),
          ),

        const SizedBox(height: 16),

        // ── Payment summary ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:        Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color:      Colors.black.withValues(alpha: 0.05),
                blurRadius: 8, offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Payment Summary',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Divider(height: 20),
              if (order.restaurantOrders != null)
                ...order.restaurantOrders!.map((ro) => Column(
                  children: [
                    _SummaryRow(
                      label: ro.restaurantName ?? 'Restaurant ${ro.sequenceInGroup}',
                      value: '$currency${ro.subtotal.toStringAsFixed(2)}',
                      light: true,
                    ),
                    if (ro.deliveryFee > 0)
                      _SummaryRow(
                        label: '  └ Delivery',
                        value: '$currency${ro.deliveryFee.toStringAsFixed(2)}',
                        light: true,
                      ),
                  ],
                )),
              const Divider(height: 16),
              if (order.deliveryFee > 0 && (order.restaurantOrders == null || order.restaurantOrders!.isEmpty))
                _SummaryRow(label: 'Delivery Fee', value: '$currency${order.deliveryFee.toStringAsFixed(2)}', light: true),
              if (order.extraStopFee > 0)
                _SummaryRow(label: 'Multi-Stop Fee', value: '$currency${order.extraStopFee.toStringAsFixed(0)}', light: true),
              if (order.platformFee > 0)
                _SummaryRow(label: 'Service Fee',   value: '$currency${order.platformFee.toStringAsFixed(0)}', light: true),
              if (order.taxAmount > 0)
                _SummaryRow(label: 'Tax',           value: '$currency${order.taxAmount.toStringAsFixed(0)}', light: true),
              if (order.discount > 0)
                _SummaryRow(label: 'Discount',      value: '-$currency${order.discount.toStringAsFixed(0)}', light: true),
              if (order.driverTip != null && order.driverTip! > 0)
                _SummaryRow(label: 'Driver Tip',    value: '$currency${order.driverTip!.toStringAsFixed(0)}', light: true),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(
                    '$currency${order.totalAmount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Paid via ${order.paymentMethod.toUpperCase()}',
                style: TextStyle(fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),

        // ── Cancel entire order ───────────────────────────────────────────
        if (_canCancelOrder) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cancelling ? null : _cancelEntireOrder,
              icon: _cancelling
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                    )
                  : const Icon(Icons.cancel_outlined, color: Colors.red),
              label: Text(
                _cancelling ? 'Cancelling…' : 'Cancel Entire Order',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Restaurant sub-order card ────────────────────────────────────────────────

class _RestaurantOrderCard extends ConsumerStatefulWidget {
  final RestaurantOrder ro;
  final String masterOrderId;
  final String masterStatus;
  const _RestaurantOrderCard({
    required this.ro,
    required this.masterOrderId,
    required this.masterStatus,
  });

  @override
  ConsumerState<_RestaurantOrderCard> createState() => _RestaurantOrderCardState();
}

class _RestaurantOrderCardState extends ConsumerState<_RestaurantOrderCard> {
  bool _cancelling = false;

  static Color _statusColor(String status) {
    switch (status) {
      case 'ready':      return const Color(0xFF8B5CF6);
      case 'preparing':  return const Color(0xFFF59E0B);
      case 'accepted':   return const Color(0xFF3B82F6);
      case 'cancelled':  return Colors.red;
      case 'picked_up':  return const Color(0xFF10B981);
      default:           return const Color(0xFF9CA3AF);
    }
  }

  // Can cancel as long as the restaurant hasn't already picked it up / cancelled it
  // and the master order hasn't been delivered.
  bool get _canCancel =>
      widget.ro.status != 'cancelled' &&
      widget.ro.status != 'picked_up' &&
      widget.masterStatus != 'delivered' &&
      widget.masterStatus != 'cancelled';

  Future<void> _cancelSubOrder() async {
    final ro = widget.ro;
    final restaurantName = ro.restaurantName ?? 'this restaurant';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Restaurant Order?'),
        content: Text(
          'Only the order from $restaurantName will be cancelled. '
          'Other restaurant orders in this group remain active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep It'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await ref.read(orderServiceProvider).cancelRestaurantSubOrder(
        restaurantOrderId: ro.id,
        masterOrderId: ro.masterOrderId,
      );
      ref.invalidate(masterOrderDetailProvider(widget.masterOrderId));
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) ref.invalidate(customerMasterOrdersProvider(userId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$restaurantName order cancelled'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Cancel Failed'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ro       = widget.ro;
    final color    = _statusColor(ro.status);
    final currency = AppConstants.currencySymbol;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color:        Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Restaurant header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color:        color.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_rounded, size: 16, color: Color(0xFF6B7280)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ro.restaurantName ?? 'Restaurant ${ro.sequenceInGroup}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        '#${ro.restaurantOrderNumber ?? ro.id.substring(0, 8).toUpperCase()}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:        color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ro.status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ],
            ),
          ),

          // Items
          if (ro.items != null && ro.items!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: ro.items!.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        Text('${item.quantity}×',
                            style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            )),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.itemName,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                              if (item.sides != null && item.sides!.isNotEmpty)
                                Text(
                                  item.sides!.map((s) => s.sideName).join(', '),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '$currency${item.subtotal.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          // Per-restaurant financials + OTP
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Subtotal',
                      style: TextStyle(fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    Text(
                      '$currency${ro.subtotal.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                if (ro.deliveryFee > 0) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Delivery',
                        style: TextStyle(fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      Text(
                        '$currency${ro.deliveryFee.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Restaurant Total',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(
                      '$currency${(ro.subtotal + ro.deliveryFee).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                if (ro.deliveryOtp != null && ro.status != 'cancelled') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:        const Color(0xFF6366F1).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Pickup PIN: ${ro.deliveryOtp}',
                      style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Cancel sub-order button
          if (_canCancel)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _cancelling ? null : _cancelSubOrder,
                  icon: _cancelling
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                        )
                      : const Icon(Icons.remove_circle_outline, size: 16, color: Colors.red),
                  label: Text(
                    _cancelling ? 'Cancelling…' : 'Cancel This Order',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 14),
        ],
      ),
    );
  }
}

// ─── Summary row helper ───────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool light;
  const _SummaryRow({required this.label, required this.value, this.light = false});

  @override
  Widget build(BuildContext context) {
    final color = light
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(fontSize: 13, color: color))),
          Text(value, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}
