import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/order_model.dart';
import '../../models/master_order_model.dart';
import '../../models/menu_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/promo_provider.dart';
import '../../providers/loyalty_provider.dart';
import '../../providers/address_provider.dart';
import '../../config/supabase_config.dart';
import '../../widgets/rate_driver_sheet.dart';
import '../../widgets/order_countdown_timer.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';
import '../../core/utils/responsive.dart';
import '../../utils/context_extensions.dart';
import '../../widgets/ai_fab.dart';

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    // Single-restaurant orders (existing table)
    final ordersAsync = ref.watch(userOrdersProvider(userId));
    // Multi-restaurant master orders (new table)
    final masterOrdersAsync = ref.watch(customerMasterOrdersProvider(userId));

    // Real-time subscriptions
    ref.watch(customerOrderRealtimeProvider(userId));
    ref.watch(masterOrderRealtimeProvider(userId));

    // Merge both async states — master orders failure is non-fatal
    final isLoading = ordersAsync.isLoading || masterOrdersAsync.isLoading;
    final hasError  = ordersAsync.hasError;

    final activeOrderId = ordersAsync.valueOrNull
        ?.where((o) => o.status != 'delivered' && o.status != 'cancelled')
        .firstOrNull
        ?.id;

    return Scaffold(
      floatingActionButton: AiFab(role: 'customer', orderId: activeOrderId),
      appBar: AppBar(
        title: Text(
          context.l10n.orderHistory,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: isLoading
          ? const AppLoadingIndicator()
          : hasError
              ? AppErrorState(
                  message: friendlyError(
                    ordersAsync.error ?? masterOrdersAsync.error ?? 'Unknown error',
                  ),
                  onRetry: () {
                    ref.invalidate(userOrdersProvider(userId));
                    ref.invalidate(customerMasterOrdersProvider(userId));
                  },
                )
              : _buildMergedList(
                  context,
                  singleOrders:  ordersAsync.valueOrNull ?? [],
                  masterOrders:  masterOrdersAsync.valueOrNull ?? [],
                  userId:        userId,
                  ref:           ref,
                ),
    );
  }

  Widget _buildMergedList(
    BuildContext context, {
    required List<Order> singleOrders,
    required List<MasterOrder> masterOrders,
    required String userId,
    required WidgetRef ref,
  }) {
    // Unified timeline entry
    final entries = <_HistoryEntry>[];

    // Collect master order IDs so we can skip their sub-orders below
    final masterOrderIds = masterOrders.map((m) => m.id).toSet();

    for (final o in singleOrders) {
      // Skip sub-orders that belong to a master order — they'll appear under the master card
      if (o.isMultiRestaurant &&
          (o.orderGroupId != null && masterOrderIds.contains(o.orderGroupId))) {
        continue;
      }
      entries.add(_HistoryEntry(orderedAt: o.orderedAt, single: o));
    }
    for (final m in masterOrders) {
      entries.add(_HistoryEntry(orderedAt: m.createdAt, master: m));
    }

    entries.sort((a, b) => b.orderedAt.compareTo(a.orderedAt));

    if (entries.isEmpty) {
      return const AppEmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'No orders yet',
        subtitle: 'Your completed orders will appear here',
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context), 16,
        Responsive.horizontalPadding(context), 24,
      ),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        if (e.master != null) {
          return _MasterOrderCard(masterOrder: e.master!, userId: userId);
        }
        return _OrderCard(order: e.single!);
      },
    );
  }
}

// ─── Unified timeline entry ───────────────────────────────────────────────────

class _HistoryEntry {
  final DateTime orderedAt;
  final Order? single;
  final MasterOrder? master;
  const _HistoryEntry({required this.orderedAt, this.single, this.master});
}

// ─── Master Order Card (multi-restaurant) ─────────────────────────────────────

class _MasterOrderCard extends StatelessWidget {
  final MasterOrder masterOrder;
  final String userId;
  const _MasterOrderCard({required this.masterOrder, required this.userId});

  static String _masterStatusLabel(String status) {
    switch (status) {
      case 'partially_cancelled': return 'PART CANCELLED';
      case 'out_for_delivery':    return 'DELIVERING';
      case 'ready_for_pickup':    return 'READY';
      default: return status.replaceAll('_', ' ').toUpperCase();
    }
  }

  Color get _statusColor {
    switch (masterOrder.status) {
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

  @override
  Widget build(BuildContext context) {
    final fmt      = DateFormat('MMM d, y · h:mm a');
    final currency = AppConstants.currencySymbol;
    final color    = _statusColor;
    final isActive = masterOrder.isActive;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color:        Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:        color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _masterStatusLabel(masterOrder.status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Multi badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color:        Colors.deepOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.store_mall_directory_rounded, size: 11, color: Colors.deepOrange),
                      const SizedBox(width: 3),
                      Text(
                        '${masterOrder.restaurantCount} restaurants',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.deepOrange),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '#${masterOrder.masterOrderNumber ?? masterOrder.id.substring(0, 8).toUpperCase()}',
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // ── Amount + date ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currency${masterOrder.totalAmount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: Responsive.headingLarge(context),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    fmt.format(masterOrder.createdAt),
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),

          // ── Per-restaurant summary chips ─────────────────────────────────
          if (masterOrder.restaurantOrders != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Wrap(
                spacing: 6, runSpacing: 4,
                children: masterOrder.restaurantOrders!.map((ro) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:        Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ro.restaurantName ?? 'Restaurant ${ro.sequenceInGroup}',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  );
                }).toList(),
              ),
            ),

          // ── Actions ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                if (isActive)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pushNamed(
                      context, '/multi-order-detail',
                      arguments: masterOrder.id,
                    ),
                    icon: const Icon(Icons.info_outline_rounded, size: 15),
                    label: const Text('View Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6366F1),
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                if (!isActive)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pushNamed(
                      context, '/multi-order-detail',
                      arguments: masterOrder.id,
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 15),
                    label: const Text('View Receipt'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF004E89),
                      side: const BorderSide(color: Color(0xFF004E89)),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    final isPending = const {'draft', 'pending', 'confirmed', 'accepted', 'preparing'}.contains(order.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
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
                Flexible(
                  child: Container(
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
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (isActive)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: OrderCountdownTimer(
                      orderedAt: order.orderedAt,
                      estimatedMinutes: order.estimatedPrepMinutes,
                      compact: true,
                    ),
                  ),
                const Spacer(),
                Text(
                  '#${order.receiptNumber ?? order.id.substring(0, 8).toUpperCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  '${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: Responsive.headingLarge(context),
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    fmt.format(order.orderedAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${item.itemName} ×${item.quantity}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurface,
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
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isActive)
                  OutlinedButton.icon(
                    onPressed: () {
                      if (order.isMultiRestaurant && order.orderGroupId != null) {
                        // Legacy group orders: navigate to tracking which merges items
                        Navigator.pushNamed(
                          context,
                          '/order-tracking',
                          arguments: order.id,
                        );
                      } else {
                        Navigator.pushNamed(
                          context,
                          '/order-tracking',
                          arguments: order.id,
                        );
                      }
                    },
                    icon: const Icon(Icons.location_on_rounded, size: 15),
                    label: const Text('Track'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6366F1),
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                if (isDelivered && order.userRating == null)
                  OutlinedButton.icon(
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
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                // Rate & Tip driver (delivered orders with a driver, not yet driver-rated)
                if (isDelivered &&
                    order.driverId != null &&
                    order.driverRating == null)
                  OutlinedButton.icon(
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
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                if (isDelivered || isCancelled)
                  ElevatedButton.icon(
                    onPressed: () => _reorder(context, ref, order),
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Re-order'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).cardColor,
                      surfaceTintColor: Theme.of(context).cardColor,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                // Post-delivery tip (delivered orders, no tip yet)
                if (isDelivered &&
                    order.driverId != null &&
                    (order.postDeliveryTip == null ||
                        order.postDeliveryTip == 0))
                  OutlinedButton.icon(
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

                // Receipt button (delivered orders)
                if (isDelivered && order.receiptNumber != null)
                  OutlinedButton(
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

                // Chat for active orders with driver
                if (isActive && order.driverId != null)
                  OutlinedButton(
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
                        label: Text(context.l10n.cancel),
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
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
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

  void _reorder(BuildContext context, WidgetRef ref, Order order) async {
    // Show a loading dialog while we fetch live menu items
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Preparing your order...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final menuService = ref.read(menuServiceProvider);
      final cartNotifier = ref.read(cartProvider.notifier);

      // Fetch live menu items in parallel
      final futures = order.items
          .map((item) => menuService.getMenuItemById(item.menuItemId))
          .toList();
      final fetchedItems = await Future.wait(futures);

      // Pair fetched items with the original order items
      final available = <({MenuItem item, OrderItem orderItem})>[];
      final unavailable = <String>[];

      for (int i = 0; i < order.items.length; i++) {
        final live = fetchedItems[i];
        final orig = order.items[i];
        if (live != null && live.isAvailable && live.inStock) {
          available.add((item: live, orderItem: orig));
        } else {
          unavailable.add(orig.itemName);
        }
      }

      if (!context.mounted) return;
      Navigator.pop(context); // close loading dialog

      if (available.isEmpty) {
        AppSnackbar.warning(
          context,
          'None of the items from this order are currently available.',
        );
        return;
      }

      // Clear cart and populate with live items
      cartNotifier.clearCart();
      for (final pair in available) {
        for (int q = 0; q < pair.orderItem.quantity; q++) {
          cartNotifier.addItem(pair.item);
        }
      }

      // Reset checkout-related state so reorder behaves like a fresh
      // cart -> checkout flow every time.
      ref.read(appliedPromoProvider.notifier).clear();
      ref.read(redeemPointsProvider.notifier).state = 0;
      ref.read(groupOrderIdForCheckoutProvider.notifier).state = null;
      ref.read(groupOrderParticipantCountProvider.notifier).state = 0;
      ref.read(isPickupProvider.notifier).state = order.isPickup;
      if (order.isPickup) {
        ref.read(selectedAddressIdProvider.notifier).state = null;
      }

      // Navigate to checkout immediately
      Navigator.pushNamed(context, '/checkout');

      // If some items were unavailable, inform the user after navigation
      if (unavailable.isNotEmpty) {
        // Small delay so the snackbar appears on the checkout screen
        await Future.delayed(const Duration(milliseconds: 400));
        if (context.mounted) {
          AppSnackbar.warning(
            context,
            '${unavailable.length} item(s) unavailable and were skipped: ${unavailable.join(', ')}',
          );
        }
      }
    } catch (e) {
      AppLogger.error('Reorder error: $e');
      if (context.mounted) {
        Navigator.pop(context); // close loading dialog on error
        AppSnackbar.error(context, 'Could not load items. Please try again.');
      }
    }
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
                    label: Text('\$ $amount'),
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
                  labelText: 'Custom amount (\$)',
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
                          try {
                            await SupabaseConfig.client
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
                              AppSnackbar.success(
                                context,
                                '\$ ${selectedTip.toStringAsFixed(0)} tip added!',
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              AppSnackbar.error(
                                context,
                                'Failed to add tip. Please try again.',
                              );
                            }
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
            Center(
              child: Text(
                'MealHub',
                style: TextStyle(
                  fontSize: Responsive.headingLarge(context),
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Receipt #${order.receiptNumber ?? order.id.substring(0, 8)}',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      '\$ ${item.subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 16),
            _ReceiptRow(context, context.l10n.subtotal, order.subtotal),
            if (order.deliveryFee > 0 && _effectiveDeliveryFee(order) > 0)
              _ReceiptRow(context, 'Delivery Fee', order.deliveryFee),
            if (order.deliveryFee > 0 && _effectiveDeliveryFee(order) == 0)
              _ReceiptRow(context, 'Delivery Fee (FREE)', 0.0),
            if (order.taxAmount != null && order.taxAmount! > 0)
              _ReceiptRow(context, context.l10n.tax, order.taxAmount!),
            if (order.discount != null && order.discount! > 0)
              _ReceiptRow(context, 'Discount', -order.discount!),
            if (order.driverTip != null && order.driverTip! > 0)
              _ReceiptRow(context, 'Driver Tip', order.driverTip!),
            if (order.postDeliveryTip != null && order.postDeliveryTip! > 0)
              _ReceiptRow(context, 'Post-Delivery Tip', order.postDeliveryTip!),
            const Divider(height: 16),
            Row(
              children: [
                const Text(
                  'Total',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const Spacer(),
                Text(
                  '\$ ${order.totalAmount.toStringAsFixed(2)}',
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
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat.yMMMd().add_jm().format(order.orderedAt),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Thank you for using MealHub!',
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

  double _effectiveDeliveryFee(Order order) {
    if (order.deliveryFee <= 0) return 0;
    final taxAmount = order.taxAmount ?? 0;
    final discount = order.discount ?? 0;
    final expectedWithFee =
        order.subtotal + taxAmount - discount + order.deliveryFee;
    if (order.totalAmount < expectedWithFee - 0.01) return 0;
    return order.deliveryFee;
  }

  // ignore: non_constant_identifier_names
  Widget _ReceiptRow(BuildContext context, String label, double amount) {
    final isNegative = amount < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            '${isNegative ? '-' : ''}\$ ${amount.abs().toStringAsFixed(2)}',
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
    final isCardPayment   = order.paymentMethod == 'card';
    final isCashPayment   = order.paymentMethod == 'cash';
    final isWalletPayment = order.paymentMethod == 'wallet';
    String selectedRefundMethod = isWalletPayment ? 'wallet' : 'original';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Cancel Order?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cancellation within 5 minutes is free.\n\n'
                'After 5 minutes, a \$1.00 cancellation fee applies.\n'
                'If the restaurant is already preparing, a 15% fee may be charged.',
              ),
              if (isCardPayment) ...[
                const SizedBox(height: 12),
                const Text(
                  'Where should your refund go?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                RadioGroup<String>(
                  groupValue: selectedRefundMethod,
                  onChanged: (v) => setDialogState(
                    () => selectedRefundMethod = v ?? 'original',
                  ),
                  child: Column(
                    children: const [
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: 'original',
                        title: Text('Back to card'),
                      ),
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: 'wallet',
                        title: Text('To wallet balance'),
                      ),
                    ],
                  ),
                ),
              ] else if (isWalletPayment) ...[
                const SizedBox(height: 12),
                const Text(
                  'Your refund will be returned to your wallet balance.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ] else if (isCashPayment) ...[
                const SizedBox(height: 12),
                const Text(
                  'Cash order: no payment refund transfer is needed.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ],
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
                  final result = await ref
                      .read(walletNotifierProvider.notifier)
                      .cancelOrder(
                        order.id,
                        refundMethod: isCardPayment
                            ? selectedRefundMethod
                            : isWalletPayment
                                ? 'wallet'
                                : null,
                      );
                  final userId = ref.read(currentUserIdProvider);
                  if (userId != null) {
                    ref.invalidate(userOrdersProvider(userId));
                  }

                  final refund = (result['refund'] as num?)?.toDouble() ?? 0;
                  final penalty = (result['penalty'] as num?)?.toDouble() ?? 0;
                  final refundMethod =
                      (result['refund_method'] as String?) ??
                      selectedRefundMethod;

                  if (isCardPayment && refundMethod != 'wallet' && refund > 0) {
                    try {
                      await SupabaseConfig.client.functions.invoke(
                        AppConstants.stripePaymentFunction,
                        body: {
                          'action': 'refund',
                          'orderId': order.id,
                          'penalty': penalty,
                        },
                      );
                    } catch (e) {
                      AppLogger.error('Card refund failed: $e');
                    }
                  }

                  if (context.mounted) {
                    String message;
                    if (isCashPayment) {
                      message = 'Order cancelled. Cash payment has no refund transfer.';
                    } else if (refund > 0 && (refundMethod == 'wallet' || isWalletPayment)) {
                      message = 'Order cancelled. \$${refund.toStringAsFixed(2)} refunded to your wallet.';
                    } else if (isCardPayment && refund > 0) {
                      message = 'Order cancelled. Refund of \$${refund.toStringAsFixed(2)} sent to your card.';
                    } else if (penalty > 0) {
                      message = 'Order cancelled. \$${penalty.toStringAsFixed(2)} cancellation fee applied.';
                    } else {
                      message = 'Order cancelled successfully';
                    }

                    AppSnackbar.success(context, message);
                  }
                } catch (e) {
                  if (context.mounted) {
                    final raw = e.toString().replaceFirst(
                      RegExp(r'^Exception:\s*'),
                      '',
                    );
                    AppSnackbar.error(
                      context,
                      raw.toLowerCase() ==
                              'something went wrong. please try again.'
                          ? friendlyError(e)
                          : raw,
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
        AppSnackbar.success(
          context,
          'Issue reported — chat started with restaurant.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
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
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
            Text(
              'Report an Issue',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: Responsive.headingSmall(context)),
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
