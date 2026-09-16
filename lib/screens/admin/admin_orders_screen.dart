import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../config/supabase_config.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/order_countdown_timer.dart';
import '../../widgets/order_status_timeline.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';

/// Realtime listener that auto-refreshes admin orders on any change.
final _adminOrderRealtimeProvider = Provider.autoDispose<void>((ref) {
  final channel = SupabaseConfig.client
      .channel('admin_all_orders')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        callback: (_) => ref.invalidate(_adminAllOrdersProvider),
      )
      .subscribe();
  ref.onDispose(() => SupabaseConfig.client.removeChannel(channel));
});

/// Provider that fetches all orders with restaurant name joined.
final _adminAllOrdersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final data = await SupabaseConfig.client
          .from('orders')
          // Disambiguate the users embed: `orders` has two FKs to `users`
          // (user_id = customer, student_id = student-verification link), so
          // PostgREST needs the explicit relationship or the query errors.
          .select(
            '*, restaurants(name, store_type), '
            'users!orders_user_id_fkey(name, email, phone), '
            // Assigned rider: orders.driver_id -> drivers -> users(name, phone)
            'driver:drivers!orders_driver_id_fkey(id, vehicle_type, '
            'user:users(name, phone))',
          )
          // `*` already includes the stage timestamp columns (confirmed_at,
          // preparing_started_at, ready_at, picked_up_at, on_the_way_at,
          // delivered_at, cancelled_at) used by the status timeline.
          .order('ordered_at', ascending: false)
          .limit(200);
      return List<Map<String, dynamic>>.from(data as List);
    });

/// Provider for available verified drivers (used by assign-rider sheet).
final _availableDriversProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final rawDrivers = await SupabaseConfig.client
          .from('drivers')
          .select(
            'id, user_id, vehicle_type, vehicle_number, rating, completed_deliveries',
          )
          .eq('is_available', true)
          .eq('is_verified', true)
          .order('rating', ascending: false);
      final drivers = List<Map<String, dynamic>>.from(rawDrivers as List);
      if (drivers.isEmpty) return drivers;
      final userIds = drivers
          .map((d) => d['user_id'] as String?)
          .whereType<String>()
          .toList();
      final rawUsers = await SupabaseConfig.client
          .from('users')
          .select('id, name, phone')
          .inFilter('id', userIds);
      final userMap = <String, Map<String, dynamic>>{
        for (final u in (rawUsers as List))
          (u as Map<String, dynamic>)['id'] as String: u,
      };
      return drivers
          .map(
            (d) => <String, dynamic>{
              ...d,
              'user': userMap[d['user_id'] as String? ?? ''],
            },
          )
          .toList();
    });

class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  // Vertical filter: 'all' | 'food' | 'grocery'. Separates grocery orders from
  // regular food orders on top of the status tabs.
  String _typeFilter = 'all';

  static const _tabs = ['All', 'Pending', 'Active', 'Delivered', 'Cancelled'];

  /// Whether an order belongs to the grocery vertical (its store is a grocery
  /// store). Non-grocery = regular food order.
  static bool _isGroceryOrder(Map<String, dynamic> o) {
    final st = (o['restaurants'] as Map?)?['store_type']?.toString();
    return st == 'grocery' || st == 'both';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(_adminAllOrdersProvider);
  }

  List<String> _statusesForTab(int index) {
    switch (index) {
      case 1:
        return ['pending'];
      case 2:
        return ['confirmed', 'preparing', 'ready', 'picked_up', 'out_for_delivery'];
      case 3:
        return ['delivered'];
      case 4:
        return ['cancelled'];
      default:
        return [];
    }
  }

  List<Map<String, dynamic>> _filter(
    List<Map<String, dynamic>> orders,
    int tabIndex,
  ) {
    var filtered = orders;

    // Vertical filter: food vs grocery
    if (_typeFilter == 'grocery') {
      filtered = filtered.where(_isGroceryOrder).toList();
    } else if (_typeFilter == 'food') {
      filtered = filtered.where((o) => !_isGroceryOrder(o)).toList();
    }

    // Tab filter
    final statuses = _statusesForTab(tabIndex);
    if (statuses.isNotEmpty) {
      filtered = filtered.where((o) => statuses.contains(o['status'])).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((o) {
        final id = (o['id'] ?? '').toString().toLowerCase();
        final userName = ((o['users'] as Map?)?['name'] ?? '')
            .toString()
            .toLowerCase();
        final userEmail = ((o['users'] as Map?)?['email'] ?? '')
            .toString()
            .toLowerCase();
        final restaurant = ((o['restaurants'] as Map?)?['name'] ?? '')
            .toString()
            .toLowerCase();
        final status = (o['status'] ?? '').toString().toLowerCase();
        return id.contains(q) ||
            userName.contains(q) ||
            userEmail.contains(q) ||
            restaurant.contains(q) ||
            status.contains(q);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(_adminOrderRealtimeProvider);
    final ordersAsync = ref.watch(_adminAllOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Order Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: ordersAsync.when(
          data: (allOrders) {
            final counts = List.generate(
              _tabs.length,
              (i) => _filter(allOrders, i).length,
            );
            return TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              isScrollable: true,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              tabs: List.generate(_tabs.length, (i) {
                final count = counts[i];
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_tabs[i]),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            );
          },
          loading: () => TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            isScrollable: true,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
          error: (_, __) => TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            isScrollable: true,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: AppTheme.primaryColor,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by ID, customer, restaurant…',
                  hintStyle: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                            color: Color(0xFF9CA3AF),
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppTheme.primaryColor,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Vertical filter: All / Food / Grocery
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                for (final t in const [
                  ('all', 'All'),
                  ('food', 'Food'),
                  ('grocery', 'Grocery'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t.$2),
                      selected: _typeFilter == t.$1,
                      onSelected: (_) => setState(() => _typeFilter = t.$1),
                      selectedColor: AppTheme.primaryColor.withValues(
                        alpha: 0.15,
                      ),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: _typeFilter == t.$1
                            ? AppTheme.primaryColor
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Orders list
          Expanded(
            child: ordersAsync.when(
              data: (allOrders) {
                return TabBarView(
                  controller: _tabController,
                  children: List.generate(_tabs.length, (tabIdx) {
                    final orders = _filter(allOrders, tabIdx);
                    if (orders.isEmpty) {
                      return _emptyState(tabIdx);
                    }
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      color: AppTheme.primaryColor,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: orders.length,
                        itemBuilder: (_, i) =>
                            _OrderCard(order: orders[i], onRefresh: _refresh),
                      ),
                    );
                  }),
                );
              },
              loading: () =>
                  const AppLoadingIndicator(message: 'Loading orders…'),
              error: (e, _) =>
                  AppErrorState(message: friendlyError(e), onRetry: _refresh),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(int tabIdx) {
    return AppEmptyState(
      icon: tabIdx == 4 ? Icons.cancel_outlined : Icons.receipt_long_outlined,
      title: tabIdx == 0
          ? 'No orders found'
          : 'No ${_tabs[tabIdx].toLowerCase()} orders',
    );
  }
}

// ─── Order Card ─────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final Future<void> Function() onRefresh;

  const _OrderCard({required this.order, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final id = (order['id'] ?? '').toString();
    final shortId = id.length > 8 ? id.substring(0, 8) : id;
    final status = (order['status'] ?? 'unknown').toString();
    final totalAmount = (order['total_amount'] ?? 0).toDouble();
    final paymentStatus = (order['payment_status'] ?? 'pending').toString();
    final paymentMethod = (order['payment_method'] ?? 'N/A').toString();
    final deliveryAddress = (order['delivery_address'] ?? '').toString();
    final orderedAt = DateTime.tryParse(order['ordered_at'] ?? '');
    final restaurant = order['restaurants'] as Map?;
    final user = order['users'] as Map?;
    final restaurantName = (restaurant?['name'] ?? 'Unknown Restaurant')
        .toString();
    final customerName = (user?['name'] ?? user?['email'] ?? 'Customer')
        .toString();
    final driverId = order['driver_id']?.toString();
    final riderName =
        ((order['driver'] as Map?)?['user'] as Map?)?['name']?.toString();

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _OrderDetailSheet(order: order),
      ),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: Order ID + status badge
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _statusIcon(status),
                    color: _statusColor(status),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#$shortId',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        orderedAt != null ? _formatDate(orderedAt) : 'Date N/A',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _showTimeline(context, id),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusBadge(status: status),
                      const SizedBox(width: 4),
                      Icon(Icons.history_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            const SizedBox(height: 10),

            // Countdown timer (active orders only)
            if (orderedAt != null &&
                status != 'delivered' &&
                status != 'cancelled') ...[
              OrderCountdownTimer(
                orderedAt: orderedAt,
                estimatedMinutes:
                    (order['estimated_prep_minutes'] as int?) ?? 45,
              ),
              const SizedBox(height: 10),
            ],

            // Customer & Restaurant
            _DetailRow(icon: Icons.person_outline, text: customerName),
            const SizedBox(height: 4),
            _DetailRow(icon: Icons.store_outlined, text: restaurantName),
            if (deliveryAddress.isNotEmpty) ...[
              const SizedBox(height: 4),
              _DetailRow(
                icon: Icons.location_on_outlined,
                text: deliveryAddress,
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.two_wheeler_rounded,
                  size: 14,
                  color: Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    driverId != null
                        ? (riderName != null && riderName.isNotEmpty
                              ? 'Rider: $riderName'
                              : 'Rider assigned')
                        : 'No rider assigned',
                    style: TextStyle(
                      fontSize: 12,
                      color: driverId != null
                          ? const Color(0xFF10B981)
                          : const Color(0xFF9CA3AF),
                      fontStyle: driverId == null
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
                if (status != 'delivered' && status != 'cancelled')
                  TextButton(
                    onPressed: () => _showAssignSheet(context, id),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      driverId != null ? 'Reassign' : 'Assign Rider',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Amount + Payment row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${AppConstants.currencySymbol}${totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _PaymentBadge(status: paymentStatus, method: paymentMethod),
                const Spacer(),
                // Update status button for non-terminal orders
                if (status != 'delivered' && status != 'cancelled')
                  _UpdateStatusButton(
                    orderId: id,
                    currentStatus: status,
                    onUpdated: onRefresh,
                  ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _showTimeline(BuildContext context, String orderId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('Order status timeline',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            OrderStatusTimeline(orderId: orderId),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'confirmed':
      case 'preparing':
        return const Color(0xFF6366F1);
      case 'ready':
      case 'picked_up':
      case 'out_for_delivery':
        return const Color(0xFF3B82F6);
      case 'delivered':
        return const Color(0xFF10B981);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  static IconData _statusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_top_rounded;
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'preparing':
        return Icons.restaurant_rounded;
      case 'ready':
        return Icons.takeout_dining_rounded;
      case 'picked_up':
      case 'out_for_delivery':
        return Icons.delivery_dining_rounded;
      case 'delivered':
        return Icons.check_circle_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }

  void _showAssignSheet(BuildContext context, String orderId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _AssignDriverSheet(orderId: orderId, onAssigned: onRefresh),
    );
  }
}

// ─── Update Status Button ───────────────────────────────────────────────────

class _UpdateStatusButton extends StatelessWidget {
  final String orderId;
  final String currentStatus;
  final Future<void> Function() onUpdated;

  const _UpdateStatusButton({
    required this.orderId,
    required this.currentStatus,
    required this.onUpdated,
  });

  String? get _nextStatus {
    switch (currentStatus) {
      case 'pending':
        return 'confirmed';
      case 'confirmed':
        return 'preparing';
      case 'preparing':
        return 'ready';
      case 'ready':
        return 'picked_up';
      case 'picked_up':
        return 'out_for_delivery';
      case 'out_for_delivery':
        return 'delivered';
      default:
        return null;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'confirmed':
        return 'Confirm';
      case 'preparing':
        return 'Preparing';
      case 'ready':
        return 'Ready';
      case 'picked_up':
        return 'Picked Up';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = _nextStatus;
    if (next == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cancel button
        SizedBox(
          height: 30,
          child: OutlinedButton(
            onPressed: () => _updateStatus(context, 'cancelled'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 11)),
          ),
        ),
        const SizedBox(width: 6),
        // Next status button
        SizedBox(
          height: 30,
          child: ElevatedButton(
            onPressed: () => _updateStatus(context, next),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(
              _statusLabel(next),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _updateStatus(BuildContext context, String newStatus) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          newStatus == 'cancelled' ? 'Cancel Order?' : 'Update Status?',
        ),
        content: Text(
          newStatus == 'cancelled'
              ? 'Are you sure you want to cancel this order?'
              : 'Move order to "${_statusLabel(newStatus)}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == 'cancelled'
                  ? Colors.red
                  : AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (newStatus == 'delivered') {
        // Route through the Edge Function so driver stats, cash float,
        // customer notification and referral earnings all fire correctly.
        final res = await SupabaseConfig.client.functions.invoke(
          'complete-delivery',
          body: {'order_id': orderId},
        );
        if (res.status != 200) {
          final err = (res.data is Map ? res.data['error'] : null)
              ?? 'Failed to mark as delivered (${res.status})';
          throw Exception(err);
        }
        final data = res.data as Map?;
        if (data?['success'] != true) {
          throw Exception(data?['error'] ?? 'Delivery completion failed');
        }
      } else {
        final updates = <String, dynamic>{
          'status': newStatus,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        if (newStatus == 'confirmed') {
          updates['confirmed_at'] = DateTime.now().toUtc().toIso8601String();
        } else if (newStatus == 'cancelled') {
          updates['cancelled_at'] = DateTime.now().toUtc().toIso8601String();
        }
        await SupabaseConfig.client
            .from('orders')
            .update(updates)
            .eq('id', orderId);
      }

      await onUpdated();
      if (context.mounted) {
        if (newStatus == 'cancelled') {
          AppSnackbar.warning(context, 'Order cancelled');
        } else {
          AppSnackbar.success(
            context,
            'Order updated to ${_statusLabel(newStatus)}',
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }
}

// ─── Status Badge ───────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _OrderCard._statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1).replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ─── Payment Badge ──────────────────────────────────────────────────────────

class _PaymentBadge extends StatelessWidget {
  final String status;
  final String method;
  const _PaymentBadge({required this.status, required this.method});

  @override
  Widget build(BuildContext context) {
    final isPaid = status == 'completed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPaid
            ? const Color(0xFF10B981).withValues(alpha: 0.08)
            : const Color(0xFFF59E0B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPaid ? Icons.check_circle : Icons.pending,
            size: 12,
            color: isPaid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 4),
          Text(
            method,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isPaid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detail Row ─────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─── Assign Driver Sheet ─────────────────────────────────────────────────────

class _AssignDriverSheet extends ConsumerStatefulWidget {
  final String orderId;
  final Future<void> Function() onAssigned;

  const _AssignDriverSheet({required this.orderId, required this.onAssigned});

  @override
  ConsumerState<_AssignDriverSheet> createState() => _AssignDriverSheetState();
}

class _AssignDriverSheetState extends ConsumerState<_AssignDriverSheet> {
  String _search = '';
  final _searchCtrl = TextEditingController();
  bool _assigning = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _assign(Map<String, dynamic> driver) async {
    if (_assigning) return;
    setState(() => _assigning = true);
    try {
      await SupabaseConfig.client
          .from('orders')
          .update({
            'driver_id': driver['id'] as String,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.orderId);
      await widget.onAssigned();
      if (mounted) {
        Navigator.pop(context);
        final user = driver['user'] as Map?;
        final name = (user?['name'] ?? 'Rider').toString();
        AppSnackbar.success(context, '$name assigned to order');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driversAsync = ref.watch(_availableDriversProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.two_wheeler_rounded,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assign Rider',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Select an available active rider',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF9CA3AF)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) =>
                  setState(() => _search = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search riders…',
                hintStyle: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: AppTheme.primaryColor,
                  size: 18,
                ),
                filled: true,
                fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Drivers list
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: driversAsync.when(
              data: (drivers) {
                final filtered = _search.isEmpty
                    ? drivers
                    : drivers.where((d) {
                        final user = d['user'] as Map?;
                        final name = (user?['name'] ?? '')
                            .toString()
                            .toLowerCase();
                        final phone = (user?['phone'] ?? '')
                            .toString()
                            .toLowerCase();
                        final vehicle = (d['vehicle_type'] ?? '')
                            .toString()
                            .toLowerCase();
                        return name.contains(_search) ||
                            phone.contains(_search) ||
                            vehicle.contains(_search);
                      }).toList();

                if (filtered.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.two_wheeler_outlined,
                    title: 'No available riders found',
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final d = filtered[i];
                    final user = d['user'] as Map?;
                    final name = (user?['name'] ?? 'Unknown Rider').toString();
                    final phone = (user?['phone'] ?? '').toString();
                    final vehicle = (d['vehicle_type'] ?? 'vehicle').toString();
                    final vehicleNum = (d['vehicle_number'] ?? '').toString();
                    final rating = (d['rating'] as num?)?.toDouble() ?? 0.0;
                    final deliveries = (d['completed_deliveries'] as int?) ?? 0;
                    final vehicleLabel = vehicle.isEmpty
                        ? 'Vehicle'
                        : vehicle[0].toUpperCase() + vehicle.substring(1);

                    return InkWell(
                      onTap: _assigning ? null : () => _assign(d),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: AppTheme.primaryColor.withValues(
                                alpha: 0.12,
                              ),
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.two_wheeler_rounded,
                                        size: 12,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        vehicleNum.isNotEmpty
                                            ? '$vehicleLabel · $vehicleNum'
                                            : vehicleLabel,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (phone.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.phone,
                                          size: 11,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: Text(
                                            phone,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: Color(0xFFF59E0B),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      rating > 0
                                          ? rating.toStringAsFixed(1)
                                          : 'N/A',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$deliveries trips',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: AppLoadingIndicator(fullScreen: false),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: AppErrorState(message: friendlyError(e)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Order Detail Sheet ─────────────────────────────────────────────────────
// Full detail view for a single order, opened when an admin taps an order card.
// Shows the vertical (Food/Grocery), customer, store, address, payment, totals,
// and the itemised line items (fetched on open).

class _OrderDetailSheet extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderDetailSheet({required this.order});

  bool get _isGrocery {
    final st = (order['restaurants'] as Map?)?['store_type']?.toString();
    return st == 'grocery' || st == 'both';
  }

  String _money(dynamic v) =>
      '${AppConstants.currencySymbol}${(v ?? 0).toDouble().toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = (order['id'] ?? '').toString();
    final shortId = id.length > 8 ? id.substring(0, 8) : id;
    final receipt = (order['receipt_number'] ?? '').toString();
    final status = (order['status'] ?? 'unknown').toString();
    final user = order['users'] as Map?;
    final restaurant = order['restaurants'] as Map?;
    final address = (order['delivery_address'] ?? '').toString();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header: type badge + status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_isGrocery
                          ? const Color(0xFF059669)
                          : const Color(0xFFFF6B35))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isGrocery
                          ? Icons.local_grocery_store_rounded
                          : Icons.fastfood_rounded,
                      size: 15,
                      color: _isGrocery
                          ? const Color(0xFF059669)
                          : const Color(0xFFFF6B35),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isGrocery ? 'Grocery' : 'Food',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _isGrocery
                            ? const Color(0xFF059669)
                            : const Color(0xFFFF6B35),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            receipt.isNotEmpty ? receipt : 'Order #$shortId',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),

          _detailRow(context, Icons.storefront_rounded,
              _isGrocery ? 'Store' : 'Restaurant',
              (restaurant?['name'] ?? 'Unknown').toString()),
          _detailRow(context, Icons.person_rounded, 'Customer',
              (user?['name'] ?? user?['email'] ?? 'Customer').toString()),
          if (user?['phone'] != null)
            _detailRow(context, Icons.phone_rounded, 'Phone',
                user!['phone'].toString()),
          if (user?['email'] != null)
            _detailRow(context, Icons.email_rounded, 'Email',
                user!['email'].toString()),
          if (address.isNotEmpty)
            _detailRow(context, Icons.location_on_rounded, 'Delivery',
                address),
          _detailRow(context, Icons.payment_rounded, 'Payment',
              '${order['payment_method'] ?? 'N/A'} · ${order['payment_status'] ?? 'pending'}'),
          _detailRow(
            context,
            Icons.two_wheeler_rounded,
            'Rider',
            () {
              final drv = order['driver'] as Map?;
              final name = (drv?['user'] as Map?)?['name']?.toString();
              if (order['driver_id'] == null) return 'Not assigned';
              final veh = drv?['vehicle_type']?.toString();
              return [
                if (name != null && name.isNotEmpty) name else 'Assigned',
                if (veh != null && veh.isNotEmpty) '($veh)',
              ].join(' ');
            }(),
          ),

          const SizedBox(height: 20),
          Text('Status timeline',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          OrderStatusTimeline(
            orderId: id,
            extraTimestamps: _stageTimestamps(),
          ),

          const SizedBox(height: 18),
          Text('Items',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _fetchItems(id),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return Text('No line items recorded.',
                    style: TextStyle(color: scheme.onSurfaceVariant));
              }
              return Column(
                children: [
                  for (final it in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${it['quantity'] ?? 1}×',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                (it['item_name'] ?? 'Item').toString(),
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Text(_money(it['subtotal'] ?? it['price']),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),

          const Divider(height: 28),
          ..._buildTotals(context),
        ],
      ),
    );
  }

  /// Canonical stage timestamps from the order row's own *_at columns, merged
  /// into the timeline for stages that have no explicit status event.
  Map<String, DateTime> _stageTimestamps() {
    final map = <String, DateTime>{};
    void add(String stage, String col) {
      final v = order[col];
      if (v == null) return;
      final t = DateTime.tryParse(v.toString());
      if (t != null) map[stage] = t;
    }

    add('pending', 'ordered_at');
    add('confirmed', 'confirmed_at');
    add('preparing', 'preparing_started_at');
    add('ready', 'ready_at');
    add('picked_up', 'picked_up_at');
    add('out_for_delivery', 'on_the_way_at');
    add('delivered', 'delivered_at');
    add('cancelled', 'cancelled_at');
    return map;
  }

  /// Builds the totals breakdown. The grocery/food order flows charge a service
  /// fee into the total but don't always persist it to `platform_service_fee`,
  /// so when it's missing we derive it as the residual that reconciles the
  /// stored total — otherwise the breakdown wouldn't add up to the total.
  List<Widget> _buildTotals(BuildContext context) {
    double d(String k) => (order[k] ?? 0).toDouble();
    final subtotal = d('subtotal');
    final delivery = d('delivery_fee');
    final tax = d('tax_amount');
    final discount = d('discount');
    final tip = d('driver_tip');
    final total = d('total_amount');
    var service = d('platform_service_fee');

    // Derive the service fee from the residual when it isn't stored.
    if (service == 0) {
      final residual = total - subtotal - delivery - tax - tip + discount;
      if (residual > 0.009) service = residual;
    }

    return [
      _totalRow(context, 'Subtotal', _money(subtotal)),
      if (delivery != 0) _totalRow(context, 'Delivery fee', _money(delivery)),
      if (service != 0) _totalRow(context, 'Service fee', _money(service)),
      if (tax != 0) _totalRow(context, 'Tax', _money(tax)),
      if (tip != 0) _totalRow(context, 'Driver tip', _money(tip)),
      if (discount != 0)
        _totalRow(context, 'Discount', '-${_money(discount)}'),
      const SizedBox(height: 4),
      _totalRow(context, 'Total', _money(total), bold: true),
    ];
  }

  Future<List<Map<String, dynamic>>> _fetchItems(String orderId) async {
    final rows = await SupabaseConfig.client
        .from('order_items')
        .select('item_name, quantity, price, subtotal, special_instructions')
        .eq('order_id', orderId);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Widget _detailRow(
      BuildContext context, IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 78,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5, color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(BuildContext context, String label, String value,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: bold ? AppTheme.primaryColor : null)),
        ],
      ),
    );
  }
}
