import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'customer/home_screen.dart';
import 'customer/grocery_screen.dart';
import 'customer/profile_screen.dart';
import '../providers/user_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/app_theme.dart';
import '../utils/friendly_error.dart';
import '../widgets/restaurant_card.dart';
import '../widgets/order_countdown_timer.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const CustomerHomeScreen(),
    const GroceryScreen(),
    const SearchScreen(),
    const OrdersScreen(),
    const CustomerProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_grocery_store_outlined),
            activeIcon: Icon(Icons.local_grocery_store),
            label: 'Grocery',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_outlined),
            activeIcon: Icon(Icons.receipt),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle_outlined),
            activeIcon: Icon(Icons.account_circle),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final resultsAsync = _query.isEmpty
        ? ref.watch(allRestaurantsProvider)
        : ref.watch(restaurantSearchProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search restaurants or food...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ),
          Expanded(
            child: resultsAsync.when(
              data: (restaurants) {
                if (restaurants.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _query.isEmpty
                              ? 'No restaurants available'
                              : 'No results for "$_query"',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: restaurants.length,
                  itemBuilder: (context, index) {
                    return RestaurantCard(
                      restaurant: restaurants[index],
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          '/restaurant-detail',
                          arguments: restaurants[index],
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text(friendlyError(err))),
            ),
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
          title: const Text('My Orders'),
          centerTitle: true,
          elevation: 0,
        ),
        body: const Center(child: Text('Please log in to see your orders')),
      );
    }

    final ordersAsync = ref.watch(userOrdersProvider(currentUserId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        centerTitle: true,
        elevation: 0,
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return Center(
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
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          final activeOrders = orders
              .where((o) => !['delivered', 'cancelled'].contains(o.status))
              .toList();
          final pastOrders = orders
              .where((o) => ['delivered', 'cancelled'].contains(o.status))
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activeOrders.isNotEmpty) ...[
                  const Text(
                    'Active Orders',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...activeOrders.map(
                    (order) => _OrderCard(
                      orderId: '#${order.id.substring(0, 8)}',
                      status: order.status.replaceAll('_', ' '),
                      date: DateFormat('MMM d, h:mm a').format(order.orderedAt),
                      total: '\$${order.totalAmount.toStringAsFixed(2)}',
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...pastOrders.map(
                    (order) => _OrderCard(
                      orderId: '#${order.id.substring(0, 8)}',
                      status: order.status.replaceAll('_', ' '),
                      date: DateFormat('MMM d, h:mm a').format(order.orderedAt),
                      total: '\$${order.totalAmount.toStringAsFixed(2)}',
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
          color: Colors.white,
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
