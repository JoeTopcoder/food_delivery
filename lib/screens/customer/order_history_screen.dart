import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/order_model.dart';
import '../../models/menu_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../config/supabase_config.dart';
import '../../widgets/rate_driver_sheet.dart';
import '../../utils/friendly_error.dart';

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }
    final ordersAsync = ref.watch(userOrdersProvider(userId));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Order History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 56,
                    color: Color(0xFFD1D5DB),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No orders yet',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Your completed orders will appear here',
                    style: TextStyle(color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: orders.length,
            itemBuilder: (_, i) => _OrderCard(order: orders[i]),
          );
        },
      ),
    );
  }
}

// ─── Order Card ────────────────────────────────────────────────────────────────

class _OrderCard extends ConsumerWidget {
  final Order order;
  const _OrderCard({required this.order});

  Color get _statusColor {
    switch (order.status) {
      case 'delivered':
        return const Color(0xFF10B981);
      case 'cancelled':
        return Colors.red;
      case 'out_for_delivery':
      case 'picked_up':
        return const Color(0xFF6366F1);
      case 'preparing':
        return const Color(0xFFF59E0B);
      default:
        return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('MMM d, y · h:mm a');
    final isDelivered = order.status == 'delivered';
    final isCancelled = order.status == 'cancelled';
    final isActive = !isDelivered && !isCancelled;
    final isPending = order.status == 'pending' || order.status == 'confirmed';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '#${order.id.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Amount + date
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'JMD\$${order.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    fmt.format(order.orderedAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Items
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children:
                  order.items.take(3).map((item) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${item.itemName} ×${item.quantity}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                    );
                  }).toList()..addAll(
                    order.items.length > 3
                        ? [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '+${order.items.length - 3} more',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          ]
                        : [],
                  ),
            ),
          ),

          // Rating (if delivered and rated)
          if (isDelivered && order.userRating != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < (order.userRating ?? 0).round()
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 15,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    order.userRating!.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),

          // Driver rating + tip (if driver-rated)
          if (isDelivered && order.driverRating != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.delivery_dining,
                    size: 15,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(width: 4),
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < (order.driverRating ?? 0)
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 13,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                  if (order.driverTip != null && order.driverTip! > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Tipped \$${order.driverTip!.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (isActive)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        '/order-tracking',
                        arguments: order.id,
                      ),
                      icon: const Icon(Icons.location_on_rounded, size: 15),
                      label: const Text('Track Order'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6366F1),
                        side: const BorderSide(color: Color(0xFF6366F1)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                if (isActive) const SizedBox(width: 10),
                if (isDelivered && order.userRating == null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        '/review',
                        arguments: order,
                      ),
                      icon: const Icon(Icons.star_rounded, size: 15),
                      label: const Text('Rate'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF59E0B),
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                if (isDelivered && order.userRating == null)
                  const SizedBox(width: 10),
                // Rate & Tip driver (delivered orders with a driver, not yet driver-rated)
                if (isDelivered &&
                    order.driverId != null &&
                    order.driverRating == null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final result = await RateAndTipDriverSheet.show(
                          context,
                          order,
                        );
                        if (result == true) {
                          final userId = ref.read(currentUserIdProvider);
                          if (userId != null) {
                            ref.invalidate(userOrdersProvider(userId));
                          }
                        }
                      },
                      icon: const Icon(Icons.delivery_dining, size: 15),
                      label: const Text('Rate Driver'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF10B981),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                if (isDelivered &&
                    order.driverId != null &&
                    order.driverRating == null)
                  const SizedBox(width: 10),
                if (isDelivered || isCancelled)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _reorder(context, ref, order),
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text('Re-order'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        surfaceTintColor: Colors.white,
                        foregroundColor: AppTheme.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                // Post-delivery tip (delivered orders, no tip yet)
                if (isDelivered &&
                    order.driverId != null &&
                    (order.postDeliveryTip == null ||
                        order.postDeliveryTip == 0))
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: OutlinedButton.icon(
                      onPressed: () => _showPostTipSheet(context, ref, order),
                      icon: const Icon(Icons.volunteer_activism, size: 15),
                      label: const Text('Tip'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF59E0B),
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                // Receipt button (delivered orders)
                if (isDelivered && order.receiptNumber != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: OutlinedButton(
                      onPressed: () => _showReceipt(context, order),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF004E89),
                        side: const BorderSide(color: Color(0xFF004E89)),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Icon(Icons.receipt_long_outlined, size: 18),
                    ),
                  ),

                // Chat for active orders with driver
                if (isActive && order.driverId != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: OutlinedButton(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        '/chat',
                        arguments: {
                          'orderId': order.id,
                          'otherPartyName': 'Driver',
                        },
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF10B981),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Cancel + Report row
          if (isPending || !isCancelled)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  // Cancel button (only for pending/confirmed)
                  if (isPending)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmCancel(context, ref, order),
                        icon: const Icon(Icons.cancel_outlined, size: 15),
                        label: const Text('Cancel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  if (isPending && !isCancelled) const SizedBox(width: 10),
                  // Report issue (any non-cancelled order)
                  if (!isCancelled)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showReportSheet(context, order.id),
                        icon: const Icon(Icons.flag_outlined, size: 15),
                        label: const Text('Report Issue'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6B7280),
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _reorder(BuildContext context, WidgetRef ref, Order order) {
    final cartNotifier = ref.read(cartProvider.notifier);
    cartNotifier.clearCart();

    for (final item in order.items) {
      // Build a synthetic MenuItem from order item data
      final menuItem = MenuItem(
        id: item.menuItemId,
        restaurantId: order.restaurantId,
        name: item.itemName,
        price: item.price,
        category: 'Re-order',
        isAvailable: true,
        createdAt: DateTime.now(),
      );
      for (int i = 0; i < item.quantity; i++) {
        cartNotifier.addItem(menuItem);
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${order.items.length} item(s) added to cart'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF10B981),
        action: SnackBarAction(
          label: 'Checkout',
          textColor: Colors.white,
          onPressed: () => Navigator.pushNamed(context, '/checkout'),
        ),
      ),
    );
  }

  void _showPostTipSheet(BuildContext context, WidgetRef ref, Order order) {
    double selectedTip = 0;
    final customCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add a Tip for Your Driver',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [100, 200, 500, 1000].map((amount) {
                  final isSelected = selectedTip == amount.toDouble();
                  return ChoiceChip(
                    label: Text('JMD\$ $amount'),
                    selected: isSelected,
                    selectedColor: const Color(0xFFFFA630),
                    onSelected: (s) => setSheetState(() {
                      selectedTip = s ? amount.toDouble() : 0;
                      customCtrl.clear();
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: customCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Custom amount (JMD\$)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setSheetState(() {
                  selectedTip = double.tryParse(v) ?? 0;
                }),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                  ),
                  onPressed: selectedTip > 0
                      ? () async {
                          final supabase = SupabaseConfig.client;
                          await supabase
                              .from('orders')
                              .update({
                                'post_delivery_tip': selectedTip,
                                'tip_updated_at': DateTime.now()
                                    .toIso8601String(),
                              })
                              .eq('id', order.id);
                          final userId = ref.read(currentUserIdProvider);
                          if (userId != null) {
                            ref.invalidate(userOrdersProvider(userId));
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'JMD\$ ${selectedTip.toStringAsFixed(0)} tip added!',
                                ),
                                backgroundColor: const Color(0xFF10B981),
                              ),
                            );
                          }
                        }
                      : null,
                  child: const Text(
                    'Send Tip',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReceipt(BuildContext context, Order order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(24),
          children: [
            const Center(
              child: Text(
                'FoodDriver',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Receipt #${order.receiptNumber ?? order.id.substring(0, 8)}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ),
            const Divider(height: 24),
            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.quantity}x ${item.itemName}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      'JMD\$ ${item.subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 16),
            _ReceiptRow('Subtotal', order.subtotal),
            if (order.deliveryFee > 0)
              _ReceiptRow('Delivery Fee', order.deliveryFee),
            if (order.taxAmount != null && order.taxAmount! > 0)
              _ReceiptRow('Tax', order.taxAmount!),
            if (order.discount != null && order.discount! > 0)
              _ReceiptRow('Discount', -order.discount!),
            if (order.driverTip != null && order.driverTip! > 0)
              _ReceiptRow('Driver Tip', order.driverTip!),
            if (order.postDeliveryTip != null && order.postDeliveryTip! > 0)
              _ReceiptRow('Post-Delivery Tip', order.postDeliveryTip!),
            const Divider(height: 16),
            Row(
              children: [
                const Text(
                  'Total',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const Spacer(),
                Text(
                  'JMD\$ ${order.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Paid via ${order.paymentMethod?.toUpperCase() ?? 'CASH'}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat.yMMMd().add_jm().format(order.orderedAt),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Thank you for using FoodDriver!',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: non_constant_identifier_names
  Widget _ReceiptRow(String label, double amount) {
    final isNegative = amount < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
          const Spacer(),
          Text(
            '${isNegative ? '-' : ''}JMD\$ ${amount.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 13,
              color: isNegative ? const Color(0xFF10B981) : null,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmCancel(BuildContext context, WidgetRef ref, Order order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Order?'),
        content: const Text(
          'Are you sure you want to cancel this order? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No, Keep Order'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(orderServiceProvider).cancelOrder(order.id);
                final userId = ref.read(currentUserIdProvider);
                if (userId != null) {
                  ref.invalidate(userOrdersProvider(userId));
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Order cancelled successfully'),
                      backgroundColor: Color(0xFF10B981),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to cancel: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  void _showReportSheet(BuildContext context, String orderId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReportIssueSheet(orderId: orderId),
    );
  }
}

// ─── Report Issue Sheet ───────────────────────────────────────────────────────

class _ReportIssueSheet extends ConsumerStatefulWidget {
  final String orderId;
  const _ReportIssueSheet({required this.orderId});

  @override
  ConsumerState<_ReportIssueSheet> createState() => _ReportIssueSheetState();
}

class _ReportIssueSheetState extends ConsumerState<_ReportIssueSheet> {
  final _descCtrl = TextEditingController();
  String _type = 'missing_item';
  bool _loading = false;

  static const _types = [
    ('missing_item', 'Missing Item'),
    ('wrong_order', 'Wrong Order'),
    ('late_delivery', 'Late Delivery'),
    ('quality_issue', 'Quality Issue'),
    ('other', 'Other'),
  ];

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_descCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final userId = ref.read(currentUserIdProvider) ?? '';
      final chatService = ref.read(chatServiceProvider);
      await chatService.reportIssue(
        orderId: widget.orderId,
        userId: userId,
        issueType: _type,
        description: _descCtrl.text.trim(),
      );

      // Auto-send first chat message with the issue details
      final typeLabel = _types
          .firstWhere((t) => t.$1 == _type, orElse: () => ('other', 'Other'))
          .$2;
      await chatService.sendMessage(
        orderId: widget.orderId,
        senderId: userId,
        senderRole: 'user',
        message: '⚠️ Issue Reported: $typeLabel\n${_descCtrl.text.trim()}',
      );

      if (mounted) {
        Navigator.pop(context); // close sheet
        Navigator.pushNamed(
          context,
          '/chat',
          arguments: {
            'orderId': widget.orderId,
            'otherPartyName': 'Restaurant Support',
          },
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Issue reported — chat started with restaurant.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Report an Issue',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _types.map((t) {
                final selected = _type == t.$1;
                return ChoiceChip(
                  label: Text(t.$2),
                  selected: selected,
                  onSelected: (_) => setState(() => _type = t.$1),
                  selectedColor: Colors.red.withValues(alpha: 0.12),
                  labelStyle: TextStyle(
                    color: selected ? Colors.red : const Color(0xFF6B7280),
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Describe the issue...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      )
                    : const Text(
                        'Submit Report',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
