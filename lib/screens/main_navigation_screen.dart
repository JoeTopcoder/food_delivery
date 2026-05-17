import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'customer/home_screen.dart';
import 'customer/grocery_screen.dart';
import 'customer/profile_screen.dart';
import '../providers/user_provider.dart';
import '../providers/auth_provider.dart';
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

  /// Tracks which tabs have been visited so we only build them on first access.
  final Set<int> _loadedTabs = {0}; // Home tab loaded immediately

  static const List<Widget> _screens = [
    CustomerHomeScreen(),
    GroceryScreen(),
    OrdersScreen(),
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil(
            _dashboardRouteForRole(role),
            (_) => false,
          );
        });
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

    final ordersAsync = ref.watch(userOrdersProvider(currentUserId));

    // Realtime subscription is activated app-wide in MainNavigationScreen
    // so updates flow even when the user isn't on this tab. Watching here
    // again is redundant but safe (same provider instance).
    ref.watch(customerOrderRealtimeProvider(currentUserId));

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.orders),
        centerTitle: true,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(userOrdersProvider(currentUserId));
          await ref.read(userOrdersProvider(currentUserId).future);
        },
        child: ordersAsync.when(
          data: (orders) {
            if (orders.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 64,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No orders yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your order history will appear here',
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            final activeOrders = orders
                .where((o) => !['delivered', 'cancelled'].contains(o.status))
                .toList();
            final pastOrders = orders
                .where((o) => ['delivered', 'cancelled'].contains(o.status))
                .toList();

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (activeOrders.isNotEmpty) ...[
                    const Text(
                      'Active Orders',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...activeOrders.map(
                      (order) => _OrderCard(
                        orderId: '#${order.id.substring(0, 8)}',
                        status: order.status.replaceAll('_', ' '),
                        date: DateFormat(
                          'MMM d, h:mm a',
                        ).format(order.orderedAt),
                        total:
                            '${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(2)}',
                        itemCount: order.items.length,
                        statusColor: _getStatusColor(order.status),
                        orderedAt: order.orderedAt,
                        estimatedPrepMinutes: order.estimatedPrepMinutes,
                        isActive: true,
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/order-tracking',
                            arguments: order.id,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (pastOrders.isNotEmpty) ...[
                    const Text(
                      'Past Orders',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...pastOrders.map(
                      (order) => _OrderCard(
                        orderId: '#${order.id.substring(0, 8)}',
                        status: order.status.replaceAll('_', ' '),
                        date: DateFormat(
                          'MMM d, h:mm a',
                        ).format(order.orderedAt),
                        total:
                            '${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(2)}',
                        itemCount: order.items.length,
                        statusColor: _getStatusColor(order.status),
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/order-tracking',
                            arguments: order.id,
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text(friendlyError(err))),
        ),
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
}

class _OrderCard extends StatelessWidget {
  final String orderId;
  final String status;
  final String date;
  final String total;
  final int itemCount;
  final Color statusColor;
  final VoidCallback onTap;
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
    this.orderedAt,
    this.estimatedPrepMinutes,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
            ),
          ],
        ),
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
                  Text(
                    'Order $orderId',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$itemCount items - $date',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  total,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
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
    );
  }
}
