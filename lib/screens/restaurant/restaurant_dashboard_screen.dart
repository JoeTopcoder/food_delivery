import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../shared/bank_info_screen.dart';
import '../shared/payout_request_screen.dart';
import '../../utils/friendly_error.dart';

class RestaurantDashboardScreen extends ConsumerStatefulWidget {
  const RestaurantDashboardScreen({super.key});

  @override
  ConsumerState<RestaurantDashboardScreen> createState() =>
      _RestaurantDashboardScreenState();
}

class _RestaurantDashboardScreenState
    extends ConsumerState<RestaurantDashboardScreen> {
  bool _togglingAvailability = false;
  bool _creatingRestaurant = false;

  // Setup form
  final _nameController = TextEditingController();
  final _cuisineController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _setupFormKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _cuisineController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(authNotifierProvider.notifier).signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _createRestaurant(String ownerId) async {
    if (!_setupFormKey.currentState!.validate()) return;
    setState(() => _creatingRestaurant = true);
    try {
      final restaurantService = ref.read(restaurantServiceProvider);
      await restaurantService.createRestaurant(
        ownerId: ownerId,
        name: _nameController.text.trim(),
        cuisineType: _cuisineController.text.trim().isEmpty
            ? null
            : _cuisineController.text.trim(),
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
      );
      ref.invalidate(restaurantByOwnerProvider(ownerId));
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
      if (mounted) setState(() => _creatingRestaurant = false);
    }
  }

  Future<void> _toggleAvailability(
    String restaurantId,
    bool currentIsOpen,
  ) async {
    setState(() => _togglingAvailability = true);
    try {
      final restaurantService = ref.read(restaurantServiceProvider);
      await restaurantService.updateRestaurant(
        restaurantId: restaurantId,
        isOpen: !currentIsOpen,
      );
      // Invalidate to refresh the restaurant data
      final currentUserId = ref.read(currentUserIdProvider);
      if (currentUserId != null) {
        ref.invalidate(restaurantByOwnerProvider(currentUserId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) {
        setState(() => _togglingAvailability = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    if (authState.user == null || currentUserId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(currentUserId));

    return restaurantAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(
        appBar: AppBar(
          title: const Text('Restaurant Dashboard'),
          centerTitle: true,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Failed to load restaurant data',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.invalidate(restaurantByOwnerProvider(currentUserId));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (restaurant) {
        if (restaurant == null) {
          return _buildSetupRestaurant(currentUserId);
        }

        // Keep realtime subscription alive for new order notifications
        ref.watch(restaurantNewOrderRealtimeProvider(restaurant.id));

        final ordersAsync = ref.watch(restaurantOrdersProvider(restaurant.id));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Restaurant Dashboard'),
            centerTitle: true,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sign Out',
                onPressed: _signOut,
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, ${authState.user!.name}!',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(restaurant.name),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              restaurant.isOpen
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: restaurant.isOpen
                                  ? Colors.green
                                  : Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              restaurant.isOpen
                                  ? 'Currently Open'
                                  : 'Currently Closed',
                              style: TextStyle(
                                color: restaurant.isOpen
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            _togglingAvailability
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Switch(
                                    value: restaurant.isOpen,
                                    onChanged: (value) {
                                      _toggleAvailability(
                                        restaurant.id,
                                        restaurant.isOpen,
                                      );
                                    },
                                  ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Quick Actions
                const Text(
                  'Quick Actions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    _DashboardCard(
                      icon: Icons.menu,
                      title: 'Manage Menu',
                      onTap: () {
                        Navigator.of(context).pushNamed('/menu-management');
                      },
                    ),
                    _DashboardCard(
                      icon: Icons.shopping_bag,
                      title: 'Orders',
                      onTap: () {
                        Navigator.of(context).pushNamed('/restaurant-orders');
                      },
                    ),
                    _DashboardCard(
                      icon: Icons.settings,
                      title: 'Settings',
                      onTap: () {
                        Navigator.of(context).pushNamed('/restaurant-settings');
                      },
                    ),
                    _DashboardCard(
                      icon: Icons.analytics,
                      title: 'Analytics',
                      onTap: () {
                        Navigator.of(
                          context,
                        ).pushNamed('/restaurant-analytics');
                      },
                    ),
                    _DashboardCard(
                      icon: Icons.account_balance,
                      title: 'Bank Info',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const BankInfoScreen(role: 'restaurant'),
                          ),
                        );
                      },
                    ),
                    _DashboardCard(
                      icon: Icons.payments_rounded,
                      title: 'Request Payout',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const PayoutRequestScreen(role: 'restaurant'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Key Metrics
                const Text(
                  'Today\'s Metrics',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ordersAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (error, stack) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(height: 8),
                          const Text('Failed to load metrics'),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              ref.invalidate(
                                restaurantOrdersProvider(restaurant.id),
                              );
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (orders) {
                    final totalOrders = orders.length;
                    final pendingOrders = orders
                        .where(
                          (o) =>
                              o.status == 'pending' ||
                              o.status == 'confirmed' ||
                              o.status == 'preparing',
                        )
                        .length;
                    final totalRevenue = orders.fold<double>(
                      0,
                      (sum, order) => sum + order.totalAmount,
                    );

                    return Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            label: 'Total Orders',
                            value: '$totalOrders',
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MetricCard(
                            label: 'Pending',
                            value: '$pendingOrders',
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MetricCard(
                            label: 'Revenue',
                            value: 'JMD\$${totalRevenue.toStringAsFixed(2)}',
                            color: Colors.green,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          bottomNavigationBar: BottomNavigationBar(
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(
                icon: Icon(Icons.shopping_bag),
                label: 'Orders',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
            onTap: (index) {
              if (index == 0) {
                // Stay on dashboard
              } else if (index == 1) {
                Navigator.of(context).pushNamed('/restaurant-orders');
              } else if (index == 2) {
                Navigator.of(context).pushNamed('/restaurant-settings');
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildSetupRestaurant(String ownerId) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Set Up Restaurant'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _setupFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.restaurant,
                    size: 56,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'Create Your Restaurant',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Fill in your restaurant details to get started.',
                  style: TextStyle(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Restaurant Name *',
                  prefixIcon: Icon(Icons.storefront),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cuisineController,
                decoration: const InputDecoration(
                  labelText: 'Cuisine Type (e.g. Pizza, Burger)',
                  prefixIcon: Icon(Icons.local_dining),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _creatingRestaurant
                      ? null
                      : () => _createRestaurant(ownerId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _creatingRestaurant
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Create Restaurant',
                          style: TextStyle(
                            fontSize: 16,
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
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).primaryColor),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
