import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/supabase_config.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/order_countdown_timer.dart';

/// Provider that fetches all orders with restaurant name joined.
final _adminAllOrdersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final data = await SupabaseConfig.client
          .from('orders')
          .select('*, restaurants(name), users(name, email, phone)')
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

  static const _tabs = ['All', 'Pending', 'Active', 'Delivered', 'Cancelled'];

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
        return ['confirmed', 'preparing', 'ready', 'picked_up', 'on_the_way'];
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
    final ordersAsync = ref.watch(_adminAllOrdersProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Order Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
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
      body: Column(
        children: [
          // Search bar
          Container(
            color: AppTheme.primaryColor,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  prefixIcon: const Icon(
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
                    borderSide: const BorderSide(
                      color: AppTheme.primaryColor,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
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
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      friendlyError(e),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(int tabIdx) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            tabIdx == 4 ? Icons.cancel_outlined : Icons.receipt_long_outlined,
            size: 64,
            color: const Color(0xFFD1D5DB),
          ),
          const SizedBox(height: 12),
          Text(
            tabIdx == 0
                ? 'No orders found'
                : 'No ${_tabs[tabIdx].toLowerCase()} orders',
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
          ),
        ],
      ),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      Text(
                        orderedAt != null ? _formatDate(orderedAt) : 'Date N/A',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: status),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
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
                    driverId != null ? 'Rider assigned' : 'No rider assigned',
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
                    '\$${totalAmount.toStringAsFixed(0)}',
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
      case 'on_the_way':
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
      case 'on_the_way':
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
        return 'on_the_way';
      case 'on_the_way':
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
      case 'on_the_way':
        return 'On the Way';
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
      final updates = <String, dynamic>{
        'status': newStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (newStatus == 'confirmed') {
        updates['confirmed_at'] = DateTime.now().toUtc().toIso8601String();
      } else if (newStatus == 'delivered') {
        updates['completed_at'] = DateTime.now().toUtc().toIso8601String();
      } else if (newStatus == 'cancelled') {
        updates['cancelled_at'] = DateTime.now().toUtc().toIso8601String();
      }

      await SupabaseConfig.client
          .from('orders')
          .update(updates)
          .eq('id', orderId);

      await onUpdated();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'cancelled'
                  ? 'Order cancelled'
                  : 'Order updated to ${_statusLabel(newStatus)}',
            ),
            backgroundColor: newStatus == 'cancelled'
                ? Colors.orange
                : const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name assigned to order'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
                color: const Color(0xFFE5E7EB),
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
                  child: const Icon(
                    Icons.two_wheeler_rounded,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assign Rider',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      Text(
                        'Select an available active rider',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
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
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppTheme.primaryColor,
                  size: 18,
                ),
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
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
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.two_wheeler_outlined,
                          size: 48,
                          color: Color(0xFFD1D5DB),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'No available riders found',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
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
                          border: Border.all(color: const Color(0xFFE5E7EB)),
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
                                style: const TextStyle(
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.two_wheeler_rounded,
                                        size: 12,
                                        color: Color(0xFF6B7280),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        vehicleNum.isNotEmpty
                                            ? '$vehicleLabel · $vehicleNum'
                                            : vehicleLabel,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                      if (phone.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.phone,
                                          size: 11,
                                          color: Color(0xFF6B7280),
                                        ),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: Text(
                                            phone,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF6B7280),
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
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
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
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  friendlyError(e),
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
