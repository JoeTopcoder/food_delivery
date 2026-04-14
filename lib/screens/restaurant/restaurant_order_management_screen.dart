import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../models/order_model.dart';
import '../../config/app_constants.dart';
import '../../widgets/order_countdown_timer.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

class RestaurantOrderManagementScreen extends ConsumerStatefulWidget {
  const RestaurantOrderManagementScreen({super.key});

  @override
  ConsumerState<RestaurantOrderManagementScreen> createState() =>
      _RestaurantOrderManagementScreenState();
}

class _RestaurantOrderManagementScreenState
    extends ConsumerState<RestaurantOrderManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Tabs the restaurant owner cares about
  static const _tabs = [
    AppConstants.orderPending,
    AppConstants.orderPreparing,
    AppConstants.orderReady,
    AppConstants.orderDelivered,
  ];

  static const _tabLabels = ['Pending', 'Preparing', 'Ready', 'Delivered'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);

    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order Management')),
        body: const Center(child: Text('Please log in to manage orders.')),
      );
    }

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(currentUserId));

    return restaurantAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Order Management')),
        body: const AppLoadingIndicator(message: 'Loading restaurant...'),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Order Management')),
        body: AppErrorState(
          message: friendlyError(error),
          onRetry: () =>
              ref.invalidate(restaurantByOwnerProvider(currentUserId)),
        ),
      ),
      data: (restaurant) {
        if (restaurant == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Order Management')),
            body: const AppEmptyState(
              icon: Icons.storefront_rounded,
              title: 'No restaurant found',
              subtitle: 'No restaurant found for your account.',
            ),
          );
        }

        return _buildOrderManagementScaffold(restaurant.id);
      },
    );
  }

  Widget _buildOrderManagementScaffold(String restaurantId) {
    final ordersAsync = ref.watch(restaurantOrdersProvider(restaurantId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Management'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabLabels.map((label) => Tab(text: label)).toList(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh orders',
            onPressed: () =>
                ref.invalidate(restaurantOrdersProvider(restaurantId)),
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const AppLoadingIndicator(message: 'Loading orders...'),
        error: (error, _) => AppErrorState(
          message: friendlyError(error),
          onRetry: () => ref.invalidate(restaurantOrdersProvider(restaurantId)),
        ),
        data: (allOrders) {
          return TabBarView(
            controller: _tabController,
            children: _tabs.map((status) {
              final filtered =
                  allOrders.where((o) => o.status == status).toList()
                    ..sort((a, b) => b.orderedAt.compareTo(a.orderedAt));
              return _OrderListView(
                orders: filtered,
                status: status,
                restaurantId: restaurantId,
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order list for a single tab
// ---------------------------------------------------------------------------
class _OrderListView extends ConsumerWidget {
  final List<Order> orders;
  final String status;
  final String restaurantId;

  const _OrderListView({
    required this.orders,
    required this.status,
    required this.restaurantId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (orders.isEmpty) {
      return AppEmptyState(
        icon: Icons.receipt_long,
        title: 'No ${status.replaceAll('_', ' ')} orders',
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(restaurantOrdersProvider(restaurantId));
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          return _OrderCard(order: orders[index], restaurantId: restaurantId);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual order card
// ---------------------------------------------------------------------------
class _OrderCard extends ConsumerStatefulWidget {
  final Order order;
  final String restaurantId;

  const _OrderCard({required this.order, required this.restaurantId});

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _isUpdating = false;

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      final orderService = ref.read(orderServiceProvider);
      await orderService.updateOrderStatus(widget.order.id, newStatus);
      ref.invalidate(restaurantOrdersProvider(widget.restaurantId));
      if (mounted) {
        AppSnackbar.success(
          context,
          'Order #${widget.order.id.substring(0, 8)} updated to ${newStatus.replaceAll('_', ' ')}',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case AppConstants.orderPending:
        return Colors.orange;
      case AppConstants.orderConfirmed:
        return Colors.blue;
      case AppConstants.orderPreparing:
        return Colors.amber.shade700;
      case AppConstants.orderReady:
        return Colors.green;
      case AppConstants.orderDelivered:
        return Colors.teal;
      case AppConstants.orderCancelled:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final timeFormat = DateFormat('hh:mm a');
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: order id + time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Order #${order.id.substring(0, 8).toUpperCase()}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (order.isPickup) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF6366F1,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shopping_bag_rounded,
                                size: 12,
                                color: Color(0xFF6366F1),
                              ),
                              SizedBox(width: 3),
                              Text(
                                'PICKUP',
                                style: TextStyle(
                                  color: Color(0xFF6366F1),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    order.status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      color: _statusColor(order.status),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),
            Text(
              '${dateFormat.format(order.orderedAt)} at ${timeFormat.format(order.orderedAt)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),

            // Countdown timer (active orders only)
            if (order.status != AppConstants.orderDelivered &&
                order.status != AppConstants.orderCancelled) ...[
              const SizedBox(height: 8),
              OrderCountdownTimer(
                orderedAt: order.orderedAt,
                estimatedMinutes: order.estimatedPrepMinutes,
              ),
            ],

            const Divider(height: 20),

            // Order items
            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text(
                      '${item.quantity}x',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.itemName)),
                    Text(
                      '\$${item.subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 20),

            // Total + payment
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total: \$${order.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (order.paymentMethod != null)
                  Chip(
                    label: Text(
                      order.paymentMethod!,
                      style: const TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),

            // Delivery address
            if (order.deliveryAddress != null &&
                order.deliveryAddress!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.deliveryAddress!,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ],

            // Notes
            if (order.notes != null && order.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.note, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.notes!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Pickup order notice
            if (order.isPickup) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.directions_walk_rounded,
                          size: 18,
                          color: Color(0xFF6366F1),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Customer is coming to pick up this order',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (order.pickupCode != null &&
                        order.pickupCode!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text(
                            'Pickup Code: ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF374151),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              order.pickupCode!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Action buttons based on current status
            if (_isUpdating)
              const Center(child: CircularProgressIndicator())
            else
              _buildActionButtons(order),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(Order order) {
    switch (order.status) {
      case AppConstants.orderPending:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _confirmReject(order),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _updateStatus(AppConstants.orderPreparing),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Accept'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        );

      case AppConstants.orderPreparing:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _updateStatus(AppConstants.orderReady),
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Mark as Ready'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        );

      case AppConstants.orderReady:
        if (order.isPickup) {
          // Pickup order: set code or verify customer code
          if (order.pickupCode == null || order.pickupCode!.isEmpty) {
            return SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showSetPickupCodeDialog(order),
                icon: const Icon(Icons.pin_rounded, size: 18),
                label: const Text('Set Pickup Code'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                ),
              ),
            );
          } else {
            return SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showVerifyPickupCodeDialog(order),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Verify Code & Complete'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            );
          }
        }
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: null, // driver picks up; restaurant just waits
            icon: const Icon(Icons.delivery_dining, size: 18),
            label: const Text('Waiting for driver pickup'),
          ),
        );

      case AppConstants.orderDelivered:
        return const SizedBox.shrink(); // no action needed

      default:
        return const SizedBox.shrink();
    }
  }

  void _showSetPickupCodeDialog(Order order) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Pickup Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter a 4-digit code the customer must provide when picking up their order.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                hintText: '0000',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF6366F1),
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.length != 4) {
                AppSnackbar.error(ctx, 'Please enter a 4-digit code');
                return;
              }
              Navigator.of(ctx).pop();
              setState(() => _isUpdating = true);
              try {
                final orderService = ref.read(orderServiceProvider);
                await orderService.setPickupCode(order.id, code);
                ref.invalidate(restaurantOrdersProvider(widget.restaurantId));
                if (mounted) {
                  AppSnackbar.success(context, 'Pickup code set to $code');
                }
              } catch (e) {
                if (mounted) {
                  AppSnackbar.error(context, friendlyError(e));
                }
              } finally {
                if (mounted) setState(() => _isUpdating = false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
            child: const Text('Set Code'),
          ),
        ],
      ),
    );
  }

  void _showVerifyPickupCodeDialog(Order order) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify Pickup Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ask the customer for their pickup code and enter it below to complete the order.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                hintText: '0000',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.green, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.length != 4) {
                AppSnackbar.error(ctx, 'Please enter a 4-digit code');
                return;
              }
              Navigator.of(ctx).pop();
              setState(() => _isUpdating = true);
              try {
                final orderService = ref.read(orderServiceProvider);
                final verified = await orderService.verifyPickupCode(
                  order.id,
                  code,
                );
                if (verified) {
                  ref.invalidate(restaurantOrdersProvider(widget.restaurantId));
                  if (mounted) {
                    AppSnackbar.success(
                      context,
                      'Pickup verified! Order completed.',
                    );
                  }
                } else {
                  if (mounted) {
                    AppSnackbar.error(
                      context,
                      'Invalid pickup code. Please try again.',
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  AppSnackbar.error(context, friendlyError(e));
                }
              } finally {
                if (mounted) setState(() => _isUpdating = false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Verify & Complete'),
          ),
        ],
      ),
    );
  }

  void _confirmReject(Order order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Order?'),
        content: Text(
          'Are you sure you want to reject order #${order.id.substring(0, 8).toUpperCase()}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _updateStatus(AppConstants.orderCancelled);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}
