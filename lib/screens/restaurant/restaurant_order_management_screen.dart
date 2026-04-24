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
    with TickerProviderStateMixin {
  TabController? _topTabController;
  TabController? _foodStatusTabController;
  TabController? _groceryStatusTabController;

  TabController get topTabController =>
      _topTabController ??= TabController(length: 2, vsync: this);
  TabController get foodStatusTabController => _foodStatusTabController ??=
      TabController(length: _statusTabs.length, vsync: this);
  TabController get groceryStatusTabController =>
      _groceryStatusTabController ??= TabController(
        length: _statusTabs.length,
        vsync: this,
      );

  // Tabs the restaurant owner cares about
  static const _statusTabs = [
    AppConstants.orderPending,
    AppConstants.orderPreparing,
    AppConstants.orderReady,
    AppConstants.orderDelivered,
  ];

  @override
  void dispose() {
    _topTabController?.dispose();
    _foodStatusTabController?.dispose();
    _groceryStatusTabController?.dispose();
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

        return _buildOrderManagementScaffold(currentUserId);
      },
    );
  }

  Widget _buildOrderManagementScaffold(String ownerId) {
    final ordersAsync = ref.watch(ownerAllOrdersProvider(ownerId));
    final restaurantsAsync = ref.watch(restaurantsByOwnerProvider(ownerId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Management'),
        bottom: TabBar(
          controller: topTabController,
          tabs: const [
            Tab(icon: Icon(Icons.restaurant), text: 'Food'),
            Tab(icon: Icon(Icons.local_grocery_store), text: 'Grocery'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh orders',
            onPressed: () => ref.invalidate(ownerAllOrdersProvider(ownerId)),
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const AppLoadingIndicator(message: 'Loading orders...'),
        error: (error, _) => AppErrorState(
          message: friendlyError(error),
          onRetry: () => ref.invalidate(ownerAllOrdersProvider(ownerId)),
        ),
        data: (allOrders) {
          return restaurantsAsync.when(
            loading: () =>
                const AppLoadingIndicator(message: 'Loading orders...'),
            error: (error, _) => AppErrorState(
              message: friendlyError(error),
              onRetry: () =>
                  ref.invalidate(restaurantsByOwnerProvider(ownerId)),
            ),
            data: (restaurants) {
              final groceryIds = restaurants
                  .where((r) => r.storeType == 'grocery')
                  .map((r) => r.id)
                  .toSet();

              final foodOrders = allOrders
                  .where((o) => !groceryIds.contains(o.restaurantId))
                  .toList();
              final groceryOrders = allOrders
                  .where((o) => groceryIds.contains(o.restaurantId))
                  .toList();

              return TabBarView(
                controller: topTabController,
                children: [
                  _StatusTabSection(
                    tabController: foodStatusTabController,
                    allOrders: foodOrders,
                    ownerId: ownerId,
                    isGrocery: false,
                  ),
                  _StatusTabSection(
                    tabController: groceryStatusTabController,
                    allOrders: groceryOrders,
                    ownerId: ownerId,
                    isGrocery: true,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status sub-tabs (Pending / Preparing / Ready / Delivered) for each type
// ---------------------------------------------------------------------------
class _StatusTabSection extends StatelessWidget {
  final TabController tabController;
  final List<Order> allOrders;
  final String ownerId;
  final bool isGrocery;

  static const _statusTabs = [
    AppConstants.orderPending,
    AppConstants.orderPreparing,
    AppConstants.orderReady,
    AppConstants.orderDelivered,
  ];

  static const _statusLabels = ['Pending', 'Preparing', 'Ready', 'Delivered'];

  const _StatusTabSection({
    required this.tabController,
    required this.allOrders,
    required this.ownerId,
    required this.isGrocery,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: tabController,
          isScrollable: true,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Colors.grey[700],
          indicatorSize: TabBarIndicatorSize.label,
          tabs: _statusLabels.map((label) {
            final count = allOrders
                .where(
                  (o) => o.status == _statusTabs[_statusLabels.indexOf(label)],
                )
                .length;
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: _statusTabs.map((status) {
              final filtered =
                  allOrders.where((o) => o.status == status).toList()
                    ..sort((a, b) => b.orderedAt.compareTo(a.orderedAt));
              return _OrderListView(
                orders: filtered,
                status: status,
                ownerId: ownerId,
                isGrocery: isGrocery,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Order list for a single tab
// ---------------------------------------------------------------------------
class _OrderListView extends ConsumerWidget {
  final List<Order> orders;
  final String status;
  final String ownerId;
  final bool isGrocery;

  const _OrderListView({
    required this.orders,
    required this.status,
    required this.ownerId,
    this.isGrocery = false,
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
        ref.invalidate(ownerAllOrdersProvider(ownerId));
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          return _OrderCard(
            order: orders[index],
            ownerId: ownerId,
            isGrocery: isGrocery,
          );
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
  final String ownerId;
  final bool isGrocery;

  const _OrderCard({
    required this.order,
    required this.ownerId,
    this.isGrocery = false,
  });

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _isUpdating = false;
  bool _itemsExpanded = false;

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      final orderService = ref.read(orderServiceProvider);
      await orderService.updateOrderStatus(widget.order.id, newStatus);
      ref.invalidate(ownerAllOrdersProvider(widget.ownerId));
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
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
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

            // Order items — tap to expand
            InkWell(
              onTap: () => setState(() => _itemsExpanded = !_itemsExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      widget.isGrocery
                          ? Icons.shopping_basket_rounded
                          : Icons.restaurant_menu_rounded,
                      size: 18,
                      color: widget.isGrocery
                          ? Colors.green[700]
                          : Colors.deepOrange[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${order.items.length} item${order.items.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: widget.isGrocery
                              ? Colors.green[700]
                              : Colors.deepOrange[700],
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _itemsExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        color: widget.isGrocery
                            ? Colors.green[700]
                            : Colors.deepOrange[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: order.items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              '${item.quantity}x',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(item.itemName)),
                            Text(
                              '${AppConstants.currencySymbol}${item.subtotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
              crossFadeState: _itemsExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
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
                  Icon(Icons.location_on, size: 16, color: Colors.grey[700]),
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
                  Icon(Icons.note, size: 16, color: Colors.grey[700]),
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
                          Text(
                            'Pickup Code: ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
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
            Text(
              'Enter a 4-digit code the customer must provide when picking up their order.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
                ref.invalidate(ownerAllOrdersProvider(widget.ownerId));
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
            Text(
              'Ask the customer for their pickup code and enter it below to complete the order.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
                  ref.invalidate(ownerAllOrdersProvider(widget.ownerId));
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
