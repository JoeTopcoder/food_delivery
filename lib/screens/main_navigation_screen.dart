import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'customer/home_screen.dart';
import 'customer/grocery_screen.dart';
import 'customer/profile_screen.dart';
import '../modules/car_services/screens/customer/car_services_home_screen.dart';
import '../providers/user_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/wallet_provider.dart';
import '../models/order_model.dart';
import '../models/master_order_model.dart';
import '../utils/app_theme.dart';
import '../utils/context_extensions.dart';
import '../utils/friendly_error.dart';
import '../widgets/order_countdown_timer.dart';
import '../widgets/ai_fab.dart';
import 'package:food_driver/config/app_constants.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _selectedIndex = 0;
  bool _redirecting = false;

  /// Tracks which tabs have been visited so we only build them on first access.
  final Set<int> _loadedTabs = {0}; // Home tab loaded immediately

  static const List<Widget> _screens = [
    CustomerHomeScreen(),
    GroceryScreen(),
    OrdersScreen(),
    CarServicesHomeScreen(),
    CustomerProfileScreen(),
  ];

  static String _dashboardRouteForRole(String role) {
    switch (role) {
      case 'driver':
        return '/driver-dashboard';
      case 'restaurant':
        return '/restaurant-dashboard';
      case 'admin':
        return '/admin-dashboard';
      case 'service_provider':
        return '/car-services/provider';
      case 'laundry_provider':
        return '/laundry/provider-dashboard';
      default:
        return '/role-selection';
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    // Only customers (role 'user' or 'customer') belong here.
    // Any other authenticated role is redirected to their own dashboard.
    if (authState.isAuthenticated) {
      final role = authState.user?.role;
      if (role != null && role != 'user' && role != 'customer') {
        if (!_redirecting) {
          _redirecting = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushNamedAndRemoveUntil(
              _dashboardRouteForRole(role),
              (_) => false,
            );
          });
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    }

    final userId = ref.watch(currentUserIdProvider);

    // Keep the customer-orders realtime channel alive for the whole app
    // session (not only when the Orders tab is mounted) so newly placed /
    // cancelled orders show up instantly anywhere — Orders tab, AI FAB
    // active-order context, etc.
    if (userId != null) {
      ref.watch(customerOrderRealtimeProvider(userId));
    }

    // Find active orders to pass as context to the AI
    final ordersAsync = userId != null
        ? ref.watch(userOrdersProvider(userId))
        : null;
    final allActiveOrders =
        ordersAsync?.valueOrNull
            ?.where((o) => o.status != 'delivered' && o.status != 'cancelled')
            .toList() ??
        [];
    final activeOrderId = allActiveOrders.length == 1
        ? allActiveOrders.first.id
        : null;

    return Scaffold(
      floatingActionButton: AiFab(
        role: 'customer',
        orderId: activeOrderId,
        activeOrders: allActiveOrders.isNotEmpty ? allActiveOrders : null,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (int i = 0; i < _screens.length; i++)
            _loadedTabs.contains(i) ? _screens[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          ref.read(currentTabIndexProvider.notifier).state = index;
          setState(() {
            _loadedTabs.add(index);
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: context.theme.cardColor,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: context.colors.onSurfaceVariant,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            activeIcon: const Icon(Icons.home),
            label: context.l10n.home,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.local_grocery_store_outlined),
            activeIcon: const Icon(Icons.local_grocery_store),
            label: context.l10n.grocery,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_outlined),
            activeIcon: const Icon(Icons.receipt),
            label: context.l10n.orders,
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.directions_car_outlined),
            activeIcon: Icon(Icons.directions_car),
            label: 'Car Services',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.account_circle_outlined),
            activeIcon: const Icon(Icons.account_circle),
            label: context.l10n.profile,
          ),
        ],
      ),
    );
  }
}

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(currentUserIdProvider);

    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.orders),
          centerTitle: true,
          elevation: 0,
        ),
        body: const Center(child: Text('Please log in to see your orders')),
      );
    }

    final ordersAsync       = ref.watch(userOrdersProvider(currentUserId));
    final masterOrdersAsync = ref.watch(customerMasterOrdersProvider(currentUserId));

    ref.watch(customerOrderRealtimeProvider(currentUserId));
    ref.watch(masterOrderRealtimeProvider(currentUserId));

    final isLoading = ordersAsync.isLoading || masterOrdersAsync.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.orders),
        centerTitle: true,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(userOrdersProvider(currentUserId));
          ref.invalidate(customerMasterOrdersProvider(currentUserId));
          await Future.wait([
            ref.read(userOrdersProvider(currentUserId).future),
            ref.read(customerMasterOrdersProvider(currentUserId).future),
          ]);
        },
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : ordersAsync.hasError
                ? Center(child: Text(friendlyError(ordersAsync.error!)))
                : _buildBody(
                    context,
                    ref,
                    orders: ordersAsync.valueOrNull ?? [],
                    masterOrders: masterOrdersAsync.valueOrNull ?? [],
                  ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref, {
    required List orders,
    required List<MasterOrder> masterOrders,
  }) {
    final masterOrderIds = masterOrders.map((m) => m.id).toSet();

    // Exclude multi-restaurant sub-orders whose master order is already shown
    final filteredOrders = orders.where((o) {
      return !(o.isMultiRestaurant == true &&
          o.orderGroupId != null &&
          masterOrderIds.contains(o.orderGroupId));
    }).toList();

    final activeSingle = filteredOrders
        .where((o) => !['delivered', 'cancelled'].contains((o as dynamic).status))
        .toList();
    final pastSingle = filteredOrders
        .where((o) => ['delivered', 'cancelled'].contains((o as dynamic).status))
        .toList();

    final activeMaster = masterOrders.where((m) => m.isActive).toList();
    final pastMaster   = masterOrders.where((m) => !m.isActive).toList();

    final hasActive = activeSingle.isNotEmpty || activeMaster.isNotEmpty;
    final hasPast   = pastSingle.isNotEmpty   || pastMaster.isNotEmpty;

    if (!hasActive && !hasPast) {
      return ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No orders yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text('Your order history will appear here', style: TextStyle(color: Colors.grey[700])),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasActive) ...[
            const Text('Active Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...activeMaster.map((m) => _MasterOrderCard(masterOrder: m)),
            ...activeSingle.map((o) {
              final order = o as Order;
              final isCancellable = const {
                'draft', 'pending', 'confirmed', 'accepted', 'preparing'
              }.contains(order.status);
              return _OrderCard(
                orderId: '#${order.id.substring(0, 8)}',
                status: order.status.replaceAll('_', ' '),
                date: DateFormat('MMM d, h:mm a').format(order.orderedAt),
                total: '${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(2)}',
                itemCount: order.items.length,
                statusColor: _getStatusColor(order.status),
                orderedAt: order.orderedAt,
                estimatedPrepMinutes: order.estimatedPrepMinutes,
                isActive: true,
                onTap: () => Navigator.pushNamed(context, '/order-tracking', arguments: order.id),
                onCancel: isCancellable ? () => _confirmCancel(context, ref, order) : null,
              );
            }),
            const SizedBox(height: 24),
          ],
          if (hasPast) ...[
            const Text('Past Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...pastMaster.map((m) => _MasterOrderCard(masterOrder: m)),
            ...pastSingle.map((o) => _OrderCard(
              orderId: '#${(o as dynamic).id.substring(0, 8)}',
              status: o.status.replaceAll('_', ' '),
              date: DateFormat('MMM d, h:mm a').format(o.orderedAt),
              total: '${AppConstants.currencySymbol}${o.totalAmount.toStringAsFixed(2)}',
              itemCount: o.items.length,
              statusColor: _getStatusColor(o.status),
              onTap: () => Navigator.pushNamed(context, '/order-tracking', arguments: o.id),
            )),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'preparing':
        return Colors.orange;
      case 'out_for_delivery':
      case 'picked_up':
        return Colors.blue;
      default:
        return Colors.amber;
    }
  }

  void _confirmCancel(BuildContext context, WidgetRef ref, Order order) {
    final isWalletPayment = order.paymentMethod == 'wallet';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cancellation within 5 minutes is free.\n'
              'After 5 minutes a \$1.00 cancellation fee applies.',
            ),
            if (isWalletPayment) ...[
              const SizedBox(height: 10),
              const Text(
                'Your refund will be returned to your wallet balance.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Order'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final userId = ref.read(currentUserIdProvider);
                await ref.read(walletNotifierProvider.notifier).cancelOrder(
                  order.id,
                  refundMethod: isWalletPayment ? 'wallet' : null,
                );
                if (userId != null) ref.invalidate(userOrdersProvider(userId));
                if (userId != null) ref.invalidate(customerMasterOrdersProvider(userId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isWalletPayment
                        ? 'Order cancelled. Refund sent to your wallet.'
                        : 'Order cancelled.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to cancel: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final String orderId;
  final String status;
  final String date;
  final String total;
  final int itemCount;
  final Color statusColor;
  final VoidCallback onTap;
  final VoidCallback? onCancel;
  final DateTime? orderedAt;
  final int? estimatedPrepMinutes;
  final bool isActive;

  const _OrderCard({
    required this.orderId,
    required this.status,
    required this.date,
    required this.total,
    required this.itemCount,
    required this.statusColor,
    required this.onTap,
    this.onCancel,
    this.orderedAt,
    this.estimatedPrepMinutes,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Main content ──
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      status == 'delivered'
                          ? Icons.check_circle
                          : status == 'cancelled'
                          ? Icons.cancel
                          : Icons.receipt,
                      size: 30,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order $orderId',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('$itemCount items · $date',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(total, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      if (isActive && orderedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: OrderCountdownTimer(
                            orderedAt: orderedAt!,
                            estimatedMinutes: estimatedPrepMinutes,
                            compact: true,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Cancel button ──
            if (onCancel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_outlined, size: 15),
                  label: const Text('Cancel Order'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MasterOrderCard extends StatelessWidget {
  final MasterOrder masterOrder;
  const _MasterOrderCard({required this.masterOrder});

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
      case 'delivered':         return Colors.green;
      case 'cancelled':
      case 'partially_cancelled': return Colors.red;
      case 'out_for_delivery':  return Colors.blue;
      case 'preparing':         return Colors.orange;
      default:                  return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color     = _statusColor;
    final currency  = AppConstants.currencySymbol;
    final date      = DateFormat('MMM d, h:mm a').format(masterOrder.createdAt);
    final itemCount = masterOrder.restaurantOrders
            ?.fold<int>(0, (s, ro) => s + (ro.items?.length ?? 0)) ??
        0;
    final restCount = masterOrder.restaurantCount;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        '/multi-order-detail',
        arguments: masterOrder.id,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.store_mall_directory_rounded, size: 28, color: color),
                  Positioned(
                    bottom: 4, right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$restCount',
                        style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Multi-Restaurant Order',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$itemCount items · $restCount restaurants · $date',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _masterStatusLabel(masterOrder.status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$currency${masterOrder.totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
