import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../models/order_model.dart';
import '../../../models/master_order_model.dart';
import '../../../config/app_constants.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';
import '../../../config/supabase_config.dart';
import '../../../utils/app_logger.dart';
import '../../../widgets/order_countdown_timer.dart';

class WebOrdersPage extends ConsumerStatefulWidget {
  const WebOrdersPage({super.key});

  @override
  ConsumerState<WebOrdersPage> createState() => _WebOrdersPageState();
}

class _WebOrdersPageState extends ConsumerState<WebOrdersPage> with TickerProviderStateMixin {
  late TabController _topTab;
  late TabController _foodTab;
  late TabController _groceryTab;

  @override
  void initState() {
    super.initState();
    _topTab = TabController(length: 3, vsync: this);
    _foodTab = TabController(length: 4, vsync: this, initialIndex: 1);
    _groceryTab = TabController(length: 4, vsync: this, initialIndex: 1);
  }

  @override
  void dispose() {
    _topTab.dispose();
    _foodTab.dispose();
    _groceryTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = ref.watch(currentUserIdProvider);
    if (ownerId == null) return const AppLoadingIndicator();

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(ownerId));

    return restaurantAsync.when(
      loading: () => const AppLoadingIndicator(message: 'Loading…'),
      error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(restaurantByOwnerProvider(ownerId))),
      data: (restaurant) {
        if (restaurant == null) {
          return const AppEmptyState(icon: Icons.storefront_rounded, title: 'No restaurant found');
        }
        return _buildBody(ownerId);
      },
    );
  }

  Widget _buildBody(String ownerId) {
    final ordersAsync = ref.watch(ownerAllOrdersProvider(ownerId));
    final restaurantsAsync = ref.watch(restaurantsByOwnerProvider(ownerId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
          child: Row(
            children: [
              const Text('Order Management', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                tooltip: 'Refresh',
                onPressed: () {
                  ref.invalidate(ownerAllOrdersProvider(ownerId));
                  ref.invalidate(ownerGroupOrdersProvider(ownerId));
                },
              ),
            ],
          ),
        ),
        // ── Top tabs: Food / Grocery / Group ──────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: TabBar(
              controller: _topTab,
              indicator: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(4),
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF64748B),
              tabs: const [
                Tab(icon: Icon(Icons.restaurant, size: 18), text: 'Food'),
                Tab(icon: Icon(Icons.local_grocery_store, size: 18), text: 'Grocery'),
                Tab(icon: Icon(Icons.store_mall_directory_rounded, size: 18), text: 'Group'),
              ],
            ),
          ),
        ),
        // ── Tab content ───────────────────────────────────────────────
        Expanded(
          child: ordersAsync.when(
            loading: () => const AppLoadingIndicator(message: 'Loading orders…'),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(ownerAllOrdersProvider(ownerId))),
            data: (allOrders) => restaurantsAsync.when(
              loading: () => const AppLoadingIndicator(),
              error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(restaurantsByOwnerProvider(ownerId))),
              data: (restaurants) {
                final groceryIds = restaurants.where((r) => r.storeType == 'grocery').map((r) => r.id).toSet();
                final foodOrders = allOrders.where((o) => !groceryIds.contains(o.restaurantId)).toList();
                final groceryOrders = allOrders.where((o) => groceryIds.contains(o.restaurantId)).toList();

                return TabBarView(
                  controller: _topTab,
                  children: [
                    _StatusSection(tabController: _foodTab, allOrders: foodOrders, ownerId: ownerId, isGrocery: false),
                    _StatusSection(tabController: _groceryTab, allOrders: groceryOrders, ownerId: ownerId, isGrocery: true),
                    _GroupOrdersTab(ownerId: ownerId),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Status sub-tabs ──────────────────────────────────────────────────────────

class _StatusSection extends StatelessWidget {
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

  const _StatusSection({
    required this.tabController,
    required this.allOrders,
    required this.ownerId,
    required this.isGrocery,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
          child: TabBar(
            controller: tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: const Color(0xFF6366F1),
            labelColor: const Color(0xFF6366F1),
            unselectedLabelColor: const Color(0xFF94A3B8),
            tabs: _statusLabels.map((label) {
              final idx = _statusLabels.indexOf(label);
              final count = allOrders.where((o) => o.status == _statusTabs[idx]).length;
              return Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6366F1))),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: _statusTabs.map((status) {
              final filtered = allOrders.where((o) => o.status == status).toList()
                ..sort((a, b) => b.orderedAt.compareTo(a.orderedAt));
              return _OrderGrid(orders: filtered, status: status, ownerId: ownerId, isGrocery: isGrocery);
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ─── Order grid ───────────────────────────────────────────────────────────────

class _OrderGrid extends ConsumerWidget {
  final List<Order> orders;
  final String status;
  final String ownerId;
  final bool isGrocery;

  const _OrderGrid({required this.orders, required this.status, required this.ownerId, required this.isGrocery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (orders.isEmpty) {
      return AppEmptyState(icon: Icons.receipt_long, title: 'No ${status.replaceAll('_', ' ')} orders');
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(ownerAllOrdersProvider(ownerId)),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 480,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.8,
        ),
        itemCount: orders.length,
        itemBuilder: (_, i) => _OrderCard(order: orders[i], ownerId: ownerId, isGrocery: isGrocery),
      ),
    );
  }
}

// ─── Order card ───────────────────────────────────────────────────────────────

class _OrderCard extends ConsumerStatefulWidget {
  final Order order;
  final String ownerId;
  final bool isGrocery;

  const _OrderCard({required this.order, required this.ownerId, this.isGrocery = false});

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _isUpdating = false;
  bool _itemsExpanded = false;

  static Color _statusColor(String status) {
    return switch (status) {
      AppConstants.orderPending => Colors.orange,
      AppConstants.orderConfirmed => Colors.blue,
      AppConstants.orderPreparing => const Color(0xFFD97706),
      AppConstants.orderReady => Colors.green,
      AppConstants.orderDelivered => Colors.teal,
      AppConstants.orderCancelled => Colors.red,
      _ => Colors.grey,
    };
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      final svc = ref.read(orderServiceProvider);
      await svc.updateOrderStatus(widget.order.id, newStatus);
      ref.invalidate(ownerAllOrdersProvider(widget.ownerId));
      if (mounted) AppSnackbar.success(context, 'Order updated to ${newStatus.replaceAll('_', ' ')}');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final fmt = DateFormat('MMM d, hh:mm a');
    final color = _statusColor(order.status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order #${order.restaurantOrderNumber ?? order.id.substring(0, 8).toUpperCase()}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E293B)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    order.status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(fmt.format(order.orderedAt), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),

            if (order.status != AppConstants.orderDelivered && order.status != AppConstants.orderCancelled) ...[
              const SizedBox(height: 8),
              OrderCountdownTimer(orderedAt: order.orderedAt, estimatedMinutes: order.estimatedPrepMinutes),
            ],

            const Divider(height: 20),

            // Items
            InkWell(
              onTap: () => setState(() => _itemsExpanded = !_itemsExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(widget.isGrocery ? Icons.shopping_basket_rounded : Icons.restaurant_menu_rounded,
                        size: 16, color: widget.isGrocery ? Colors.green[700] : Colors.deepOrange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${order.items.length} item${order.items.length == 1 ? '' : 's'}',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                            color: widget.isGrocery ? Colors.green[700] : Colors.deepOrange[700]),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _itemsExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more,
                          color: widget.isGrocery ? Colors.green[700] : Colors.deepOrange[700]),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              crossFadeState: _itemsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: order.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text('${item.quantity}×', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(item.itemName, style: const TextStyle(fontSize: 13))),
                      Text('${AppConstants.currencySymbol}${item.subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ],
                  ),
                )).toList(),
              ),
            ),

            const Divider(height: 20),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total: ${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1E293B)),
                  ),
                ),
                if (order.isPickup)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('PICKUP', style: TextStyle(color: Color(0xFF6366F1), fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),

            const Spacer(),

            if (_isUpdating)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
            else
              _buildActions(order),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(Order order) {
    return switch (order.status) {
      AppConstants.orderPending => Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _showRejectDialog(order),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _updateStatus(AppConstants.orderPreparing),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Accept'),
              ),
            ),
          ],
        ),
      AppConstants.orderPreparing => SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _updateStatus(AppConstants.orderReady),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Mark as Ready'),
          ),
        ),
      _ => const SizedBox.shrink(),
    };
  }

  void _showRejectDialog(Order order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Order?'),
        content: Text('Reject order #${order.id.substring(0, 8).toUpperCase()}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); _updateStatus(AppConstants.orderCancelled); },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}

// ─── Group orders tab ─────────────────────────────────────────────────────────

class _GroupOrdersTab extends ConsumerWidget {
  final String ownerId;
  const _GroupOrdersTab({required this.ownerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(restaurantOrdersRealtimeProvider(ownerId));
    final async = ref.watch(ownerGroupOrdersProvider(ownerId));

    return async.when(
      loading: () => const AppLoadingIndicator(message: 'Loading group orders…'),
      error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(ownerGroupOrdersProvider(ownerId))),
      data: (orders) {
        if (orders.isEmpty) {
          return const AppEmptyState(
            icon: Icons.store_mall_directory_rounded,
            title: 'No group orders yet',
            subtitle: 'Multi-restaurant orders appear here',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 480,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          itemCount: orders.length,
          itemBuilder: (_, i) => _GroupOrderCard(ro: orders[i], ownerId: ownerId),
        );
      },
    );
  }
}

class _GroupOrderCard extends ConsumerStatefulWidget {
  final RestaurantOrder ro;
  final String ownerId;
  const _GroupOrderCard({required this.ro, required this.ownerId});

  @override
  ConsumerState<_GroupOrderCard> createState() => _GroupOrderCardState();
}

class _GroupOrderCardState extends ConsumerState<_GroupOrderCard> {
  bool _updating = false;

  static Color _statusColor(String status) => switch (status) {
    'ready' => const Color(0xFF8B5CF6),
    'preparing' => const Color(0xFFF59E0B),
    'accepted' => const Color(0xFF3B82F6),
    'cancelled' => Colors.red,
    _ => const Color(0xFF9CA3AF),
  };

  Future<void> _updateStatus(String newStatus) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      final now = DateTime.now().toIso8601String();
      final patch = <String, dynamic>{'status': newStatus, 'updated_at': now};
      if (newStatus == 'accepted')  patch['confirmed_at']  = now;
      if (newStatus == 'preparing') patch['preparing_at']  = now;
      if (newStatus == 'ready')     patch['ready_at']      = now;
      if (newStatus == 'cancelled') patch['cancelled_at']  = now;
      await SupabaseConfig.client.from('restaurant_orders').update(patch).eq('id', widget.ro.id);
      ref.invalidate(ownerGroupOrdersProvider(widget.ownerId));
    } catch (e) {
      AppLogger.error('GroupOrderCard: $e');
      if (mounted) AppSnackbar.error(context, 'Update failed: $e');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.ro;
    final color = _statusColor(ro.status);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order #${ro.restaurantOrderNumber ?? ro.id.substring(0, 8).toUpperCase()}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(ro.status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                ),
              ],
            ),
            Text(DateFormat('MMM d, h:mm a').format(ro.createdAt), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            if (ro.deliveryAddress != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 13, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(ro.deliveryAddress!, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ],
            const Divider(height: 16),
            if (ro.items != null)
              ...ro.items!.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text('${item.quantity}×', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(item.itemName, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                    Text('${AppConstants.currencySymbol}${item.subtotal.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
              )),
            const Divider(height: 16),
            Text('Subtotal: ${AppConstants.currencySymbol}${ro.subtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            if (ro.status != 'cancelled' && ro.status != 'ready')
              _updating
                  ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
                  : Wrap(
                      spacing: 8, runSpacing: 6,
                      children: [
                        if (ro.status == 'pending')
                          ElevatedButton(
                            onPressed: () => _updateStatus('accepted'),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Text('Accept'),
                          ),
                        if (ro.status == 'accepted')
                          ElevatedButton(
                            onPressed: () => _updateStatus('preparing'),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Text('Preparing'),
                          ),
                        if (ro.status == 'preparing')
                          ElevatedButton(
                            onPressed: () => _updateStatus('ready'),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Text('Ready'),
                          ),
                        if (ro.status == 'pending' || ro.status == 'accepted')
                          OutlinedButton(
                            onPressed: () => _updateStatus('cancelled'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Text('Cancel'),
                          ),
                      ],
                    ),
          ],
        ),
      ),
    );
  }
}
