import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/app_theme.dart';
import '../shared/bank_info_screen.dart';
import '../shared/payout_request_screen.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';
import '../../features/auth/services/delayed_stripe_connect_service.dart';
import 'restaurant_offer_screen.dart';

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
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
        AppSnackbar.error(context, friendlyError(e));
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
        AppSnackbar.error(context, friendlyError(e));
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
      final currentUserId = ref.read(currentUserIdProvider);
      if (currentUserId != null) {
        ref.invalidate(restaurantByOwnerProvider(currentUserId));
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _togglingAvailability = false);
      }
    }
  }

  Future<void> _refresh() async {
    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId != null) {
      ref.invalidate(restaurantByOwnerProvider(currentUserId));
      ref.invalidate(ownerAllOrdersProvider(currentUserId));
    }
  }

  Future<void> _startRestaurantStripeSetup() async {
    try {
      final launched = await DelayedStripeConnectService()
          .ensureConnectedForDriverPayout();
      if (!launched && mounted) {
        AppSnackbar.error(
          context,
          'Could not open Stripe setup. Please try again.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    if (authState.user == null || currentUserId == null) {
      if (!authState.isAuthenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/signin', (_) => false);
          }
        });
      }
      return const Scaffold(body: AppLoadingIndicator());
    }

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(currentUserId));

    return restaurantAsync.when(
      loading: () => const Scaffold(
        body: AppLoadingIndicator(message: 'Loading restaurant...'),
      ),
      error: (error, stack) => Scaffold(
        body: AppErrorState(
          message: friendlyError(error),
          onRetry: () {
            ref.invalidate(restaurantByOwnerProvider(currentUserId));
          },
        ),
      ),
      data: (restaurant) {
        if (restaurant == null) {
          return _buildSetupRestaurant(currentUserId);
        }

        ref.watch(ownerOrderRealtimeProvider(currentUserId));
        final ordersAsync = ref.watch(ownerAllOrdersProvider(currentUserId));

        return Scaffold(
          body: RefreshIndicator(
            onRefresh: _refresh,
            color: AppTheme.primaryColor,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── Hero Header ──────────────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1E293B), Color(0xFF334155)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        AppTheme.primaryColor,
                                        Color(0xFFFF8C5A),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.storefront_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Welcome, ${authState.user!.name?.split(' ').first ?? 'User'}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        restaurant.name,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.6,
                                          ),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Material(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: _signOut,
                                    child: const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Icon(
                                        Icons.logout_rounded,
                                        color: Colors.white70,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // ── Status toggle banner ──
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: restaurant.isOpen
                                    ? const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.15)
                                    : Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: restaurant.isOpen
                                      ? const Color(
                                          0xFF10B981,
                                        ).withValues(alpha: 0.3)
                                      : Colors.red.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: restaurant.isOpen
                                          ? const Color(0xFF10B981)
                                          : Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      restaurant.isOpen
                                          ? 'Your restaurant is OPEN'
                                          : 'Your restaurant is CLOSED',
                                      style: TextStyle(
                                        color: restaurant.isOpen
                                            ? const Color(0xFF10B981)
                                            : Colors.red.shade300,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  _togglingAvailability
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white70,
                                          ),
                                        )
                                      : Switch(
                                          value: restaurant.isOpen,
                                          activeThumbColor: const Color(
                                            0xFF10B981,
                                          ),
                                          onChanged: (_) => _toggleAvailability(
                                            restaurant.id,
                                            restaurant.isOpen,
                                          ),
                                        ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            ordersAsync.when(
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                              data: (orders) {
                                final needsStripeSetup =
                                    orders.isNotEmpty &&
                                    (restaurant.stripeAccountId == null ||
                                        restaurant.stripeAccountId!.isEmpty);
                                if (!needsStripeSetup) {
                                  return const SizedBox.shrink();
                                }
                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEDD5),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFFB923C),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.account_balance_wallet_rounded,
                                        color: Color(0xFFC2410C),
                                      ),
                                      const SizedBox(width: 10),
                                      const Expanded(
                                        child: Text(
                                          'You received your first order. Complete payout setup to receive funds.',
                                          style: TextStyle(
                                            color: Color(0xFF9A3412),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _startRestaurantStripeSetup,
                                        child: const Text('Set up'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── KPI Cards ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: const Offset(0, -16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ordersAsync.when(
                        loading: () => const SizedBox(height: 100),
                        error: (_, _) => const SizedBox(height: 100),
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
                          final deliveredOrders = orders
                              .where((o) => o.status == 'delivered')
                              .length;
                          orders.fold<double>(
                            0,
                            (sum, order) => sum + order.totalAmount,
                          );

                          return Row(
                            children: [
                              Expanded(
                                child: _KpiCard(
                                  label: 'Orders',
                                  value: '$totalOrders',
                                  icon: Icons.receipt_long_rounded,
                                  color: const Color(0xFF6366F1),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _KpiCard(
                                  label: 'Pending',
                                  value: '$pendingOrders',
                                  icon: Icons.pending_actions_rounded,
                                  color: const Color(0xFFF59E0B),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _KpiCard(
                                  label: 'Delivered',
                                  value: '$deliveredOrders',
                                  icon: Icons.check_circle_outline_rounded,
                                  color: const Color(0xFF10B981),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // ── Revenue banner ───────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ordersAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (orders) {
                        final totalRevenue = orders.fold<double>(
                          0,
                          (sum, order) => sum + order.totalAmount,
                        );
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.attach_money_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total Revenue',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${AppConstants.currencySymbol}${totalRevenue.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.of(
                                  context,
                                ).pushNamed('/restaurant-analytics'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Details',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        color: Colors.white,
                                        size: 12,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),

                // ── Quick Actions ────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.95,
                      children: [
                        _QuickAction(
                          icon: Icons.receipt_long_rounded,
                          label: 'Orders',
                          color: const Color(0xFF6366F1),
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed('/restaurant-orders'),
                        ),
                        _QuickAction(
                          icon: Icons.restaurant_menu_rounded,
                          label: 'Menu',
                          color: const Color(0xFFEC4899),
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed('/menu-management'),
                        ),
                        _QuickAction(
                          icon: Icons.local_grocery_store_rounded,
                          label: 'Grocery',
                          color: const Color(0xFF14B8A6),
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed('/grocery-management'),
                        ),
                        _QuickAction(
                          icon: Icons.analytics_rounded,
                          label: 'Analytics',
                          color: const Color(0xFF10B981),
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed('/restaurant-analytics'),
                        ),
                        _QuickAction(
                          icon: Icons.settings_rounded,
                          label: 'Settings',
                          color: const Color(0xFF8B5CF6),
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed('/restaurant-settings'),
                        ),
                        _QuickAction(
                          icon: Icons.account_balance_rounded,
                          label: 'Bank Info',
                          color: const Color(0xFF0EA5E9),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const BankInfoScreen(role: 'restaurant'),
                            ),
                          ),
                        ),
                        _QuickAction(
                          icon: Icons.payments_rounded,
                          label: 'Payout',
                          color: const Color(0xFFF59E0B),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const PayoutRequestScreen(role: 'restaurant'),
                            ),
                          ),
                        ),
                        _QuickAction(
                          icon: Icons.loyalty_rounded,
                          label: 'Loyalty',
                          color: const Color(0xFF7C3AED),
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed('/restaurant-loyalty'),
                        ),
                        _QuickAction(
                          icon: Icons.local_fire_department_rounded,
                          label: 'Our Offer',
                          color: const Color(0xFFEF4444),
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed('/restaurant-offer'),
                        ),
                        _QuickAction(
                          icon: Icons.description_rounded,
                          label: 'Contract',
                          color: const Color(0xFF0891B2),
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed('/restaurant-contract'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),

                // ── Recent Orders ────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          'Recent Orders',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.of(
                            context,
                          ).pushNamed('/restaurant-orders'),
                          child: Text(
                            'See all',
                            style: TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ordersAsync.when(
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (error, _) => Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: AppErrorState(
                          message: 'Failed to load orders',
                          onRetry: () => ref.invalidate(
                            ownerAllOrdersProvider(currentUserId),
                          ),
                        ),
                      ),
                      data: (orders) {
                        if (orders.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Column(
                              children: [
                                Icon(
                                  Icons.receipt_long_rounded,
                                  size: 48,
                                  color: Color(0xFFD1D5DB),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'No orders yet',
                                  style: TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        final recent = orders.take(5).toList();
                        return Column(
                          children: recent
                              .map((order) => _RecentOrderTile(order: order))
                              .toList(),
                        );
                      },
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSetupRestaurant(String ownerId) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _setupFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primaryColor, Color(0xFFFF8C5A)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Create Your Restaurant',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Fill in your restaurant details to get started',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                // ── See Our Offer link ──
                Center(
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const RestaurantOfferScreen(showGetStarted: true),
                      ),
                    ),
                    icon: const Icon(
                      Icons.local_fire_department_rounded,
                      size: 18,
                      color: Color(0xFFEF4444),
                    ),
                    label: const Text(
                      'See Why Restaurants Love MealHub',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSetupField(
                  controller: _nameController,
                  label: 'Restaurant Name',
                  icon: Icons.storefront_rounded,
                  required: true,
                ),
                const SizedBox(height: 16),
                _buildSetupField(
                  controller: _cuisineController,
                  label: 'Cuisine Type (e.g. Pizza, Burger)',
                  icon: Icons.local_dining_rounded,
                ),
                const SizedBox(height: 16),
                _buildSetupField(
                  controller: _addressController,
                  label: 'Address',
                  icon: Icons.location_on_rounded,
                ),
                const SizedBox(height: 16),
                _buildSetupField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _creatingRestaurant
                        ? null
                        : () => _createRestaurant(ownerId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _creatingRestaurant
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Create Restaurant',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetupField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool required = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(
        fontSize: 15,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        prefixIcon: Icon(icon, color: AppTheme.primaryColor, size: 20),
        filled: true,
        fillColor: Theme.of(context).inputDecorationTheme.fillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
      ),
      validator: required
          ? (v) => v == null || v.isEmpty ? 'Required' : null
          : null,
    );
  }
}

// ─── KPI Card ──────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick Action ──────────────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Recent Order Tile ─────────────────────────────────────────────────────────

class _RecentOrderTile extends StatelessWidget {
  final dynamic order;
  const _RecentOrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order.status as String;
    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'pending':
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.hourglass_top_rounded;
        break;
      case 'confirmed':
      case 'preparing':
        statusColor = const Color(0xFF6366F1);
        statusIcon = Icons.local_fire_department_rounded;
        break;
      case 'ready':
        statusColor = const Color(0xFF0EA5E9);
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'delivered':
        statusColor = const Color(0xFF10B981);
        statusIcon = Icons.done_all_rounded;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusIcon = Icons.cancel_rounded;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.info_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(statusIcon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order #${order.id.toString().substring(0, 8)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status[0].toUpperCase() + status.substring(1),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
