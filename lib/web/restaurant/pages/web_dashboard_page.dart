import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../models/order_model.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';
import '../../../config/app_constants.dart';
import '../../../features/auth/services/delayed_stripe_connect_service.dart';

class WebDashboardPage extends ConsumerStatefulWidget {
  const WebDashboardPage({super.key});

  @override
  ConsumerState<WebDashboardPage> createState() => _WebDashboardPageState();
}

class _WebDashboardPageState extends ConsumerState<WebDashboardPage> {
  bool _togglingAvailability = false;

  Future<void> _toggleAvailability(String restaurantId, bool currentIsOpen) async {
    setState(() => _togglingAvailability = true);
    try {
      final restaurantService = ref.read(restaurantServiceProvider);
      await restaurantService.updateRestaurant(
        restaurantId: restaurantId,
        isOpen: !currentIsOpen,
      );
      final uid = ref.read(currentUserIdProvider);
      if (uid != null) ref.invalidate(restaurantByOwnerProvider(uid));
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _togglingAvailability = false);
    }
  }

  Future<void> _startStripeSetup() async {
    try {
      final launched = await DelayedStripeConnectService().ensureConnectedForDriverPayout();
      if (!launched && mounted) {
        AppSnackbar.error(context, 'Could not open Stripe setup. Please try again.');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    if (currentUserId == null) return const SizedBox.shrink();

    final restaurantAsync = ref.watch(restaurantByOwnerProvider(currentUserId));
    final ordersAsync = ref.watch(ownerAllOrdersProvider(currentUserId));
    ref.watch(ownerOrderRealtimeProvider(currentUserId));

    return restaurantAsync.when(
      loading: () => const AppLoadingIndicator(message: 'Loading…'),
      error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(restaurantByOwnerProvider(currentUserId))),
      data: (restaurant) {
        if (restaurant == null) {
          return const AppEmptyState(icon: Icons.storefront_rounded, title: 'No restaurant found');
        }
        return _buildContent(currentUserId, restaurant, ordersAsync);
      },
    );
  }

  Widget _buildContent(String ownerId, dynamic restaurant, AsyncValue<List<Order>> ordersAsync) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page title ────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dashboard',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                    ),
                    Text(
                      restaurant.name,
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                    ),
                  ],
                ),
              ),
              // Open/Close toggle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: restaurant.isOpen ? const Color(0xFF10B981) : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      restaurant.isOpen ? 'Open' : 'Closed',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: restaurant.isOpen ? const Color(0xFF10B981) : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _togglingAvailability
                        ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
                        : Switch(
                            value: restaurant.isOpen,
                            activeThumbColor: const Color(0xFF10B981),
                            onChanged: (_) => _toggleAvailability(restaurant.id, restaurant.isOpen),
                          ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Stripe setup banner ───────────────────────────────────────
          ordersAsync.whenData((orders) {
            final needsStripe = orders.isNotEmpty &&
                (restaurant.stripeAccountId == null || restaurant.stripeAccountId!.isEmpty);
            if (!needsStripe) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEDD5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFB923C)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFC2410C)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'You received your first order. Complete payout setup to receive funds.',
                      style: TextStyle(color: Color(0xFF9A3412), fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(onPressed: _startStripeSetup, child: const Text('Set up')),
                ],
              ),
            );
          }).valueOrNull ?? const SizedBox.shrink(),

          const SizedBox(height: 24),

          // ── KPI cards ────────────────────────────────────────────────
          ordersAsync.when(
            loading: () => const SizedBox(height: 120),
            error: (_, __) => const SizedBox(height: 120),
            data: (orders) {
              final total = orders.length;
              final pending = orders.where((o) => o.status == 'pending' || o.status == 'confirmed' || o.status == 'preparing').length;
              final delivered = orders.where((o) => o.status == 'delivered').length;
              final revenue = orders.fold<double>(0, (s, o) => s + o.totalAmount);
              return Row(
                children: [
                  Expanded(child: _KpiCard(label: 'Total Orders', value: '$total', icon: Icons.receipt_long_rounded, color: const Color(0xFF6366F1))),
                  const SizedBox(width: 16),
                  Expanded(child: _KpiCard(label: 'Pending', value: '$pending', icon: Icons.pending_actions_rounded, color: const Color(0xFFF59E0B))),
                  const SizedBox(width: 16),
                  Expanded(child: _KpiCard(label: 'Delivered', value: '$delivered', icon: Icons.check_circle_outline_rounded, color: const Color(0xFF10B981))),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _KpiCard(
                      label: 'Revenue',
                      value: '${AppConstants.currencySymbol}${revenue.toStringAsFixed(2)}',
                      icon: Icons.attach_money_rounded,
                      color: const Color(0xFF8B5CF6),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 32),

          // ── Recent orders table ──────────────────────────────────────
          Row(
            children: [
              const Text('Recent Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
              const Spacer(),
              Text(
                'Last 10 orders',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ordersAsync.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.read(currentUserIdProvider) != null ? ref.invalidate(ownerAllOrdersProvider(ref.read(currentUserIdProvider)!)) : null),
            data: (orders) {
              if (orders.isEmpty) {
                return _emptyOrdersCard();
              }
              final recent = orders.take(10).toList();
              return _OrdersTable(orders: recent);
            },
          ),
        ],
      ),
    );
  }

  Widget _emptyOrdersCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No orders yet', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
          const SizedBox(height: 4),
          Text('Orders will appear here once customers start placing them.', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── KPI Card ─────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Orders Table ─────────────────────────────────────────────────────────────

class _OrdersTable extends StatelessWidget {
  final List<Order> orders;
  const _OrdersTable({required this.orders});

  static Color _statusColor(String status) {
    return switch (status) {
      'pending' => const Color(0xFFF59E0B),
      'confirmed' || 'preparing' => const Color(0xFF6366F1),
      'ready' => const Color(0xFF0EA5E9),
      'delivered' => const Color(0xFF10B981),
      'cancelled' => Colors.red,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(3),
            2: FlexColumnWidth(1.5),
            3: FlexColumnWidth(1.5),
            4: FlexColumnWidth(1.5),
          },
          children: [
            // Header
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
              children: ['Order #', 'Items', 'Total', 'Status', 'Time']
                  .map((h) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Text(h, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF64748B), letterSpacing: 0.5)),
                      ))
                  .toList(),
            ),
            // Rows
            ...orders.map((order) {
              final color = _statusColor(order.status);
              return TableRow(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: const Color(0xFFF1F5F9))),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Text(
                      '#${(order.restaurantOrderNumber ?? order.id.substring(0, 8)).toUpperCase()}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Text(
                      order.items.map((i) => '${i.quantity}× ${i.itemName}').join(', '),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Text(
                      '${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        order.status[0].toUpperCase() + order.status.substring(1),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Text(
                      _formatTime(order.orderedAt),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day}';
  }
}
