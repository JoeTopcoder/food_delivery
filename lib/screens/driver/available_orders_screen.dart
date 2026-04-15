import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_constants.dart';
import '../../models/order_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/order_countdown_timer.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/context_extensions.dart';

class AvailableOrdersScreen extends ConsumerWidget {
  const AvailableOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final ordersAsync = ref.watch(availableOrdersProvider);

    if (currentUserId == null) {
      return const Scaffold(body: Center(child: Text('User not found')));
    }

    final driverProfileAsync = ref.watch(driverProfileProvider(currentUserId));

    return driverProfileAsync.when(
      data: (driver) {
        if (driver == null) {
          return const Scaffold(
            body: Center(child: Text('Driver profile not found')),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F1117),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              context.l10n.availableOrders,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2030),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2A2D3E)),
                ),
                child: IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  color: const Color(0xFF9CA3AF),
                  onPressed: () => ref.invalidate(availableOrdersProvider),
                ),
              ),
            ],
          ),
          body: ordersAsync.when(
            data: (orders) {
              if (orders.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'No Orders Available',
                  subtitle: 'Pull down to refresh for new orders',
                );
              }

              return RefreshIndicator(
                color: AppTheme.primaryColor,
                backgroundColor: const Color(0xFF1E2030),
                onRefresh: () async => ref.invalidate(availableOrdersProvider),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return _OrderCard(
                      order: order,
                      driverId: driver.id,
                      ref: ref,
                    );
                  },
                ),
              );
            },
            loading: () => const Center(
              child: AppLoadingIndicator(message: 'Loading orders...'),
            ),
            error: (error, stackTrace) => AppErrorState(
              message: 'Something went wrong. Please try again.',
              onRetry: () => ref.invalidate(availableOrdersProvider),
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: AppLoadingIndicator(message: 'Loading driver profile...'),
      ),
      error: (error, stackTrace) => Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        body: AppErrorState(message: friendlyError(error)),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  final String driverId;
  final WidgetRef ref;

  const _OrderCard({
    required this.order,
    required this.driverId,
    required this.ref,
  });

  bool get _isReady => order.status == AppConstants.orderReady;

  String get _waitTime {
    final diff = DateTime.now().difference(order.orderedAt);
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m ago';
    return '${diff.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Order ID + Status + Time
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Text(
                  '#${order.id.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _isReady
                        ? const Color(0xFF22C55E).withValues(alpha: 0.12)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _isReady ? 'READY' : 'PENDING',
                    style: TextStyle(
                      color: _isReady
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFF59E0B),
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Time
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: Color(0xFF6B7280),
                ),
                const SizedBox(width: 4),
                Text(
                  'Ordered $_waitTime',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Countdown timer
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OrderCountdownTimer(
              orderedAt: order.orderedAt,
              estimatedMinutes: order.estimatedPrepMinutes,
            ),
          ),

          // Items
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: order.items
                  .map(
                    (item) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2D3E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${item.itemName} x${item.quantity}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

          // Total + badges
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text(
                  '${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: Color(0xFF22C55E),
                  ),
                ),
                if (order.contactlessDelivery == true) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.contactless_rounded,
                          size: 12,
                          color: Color(0xFF818CF8),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Contactless',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF818CF8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Address
          if (order.deliveryAddress != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    size: 14,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.deliveryAddress!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Notes
          if (order.notes != null && order.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.sticky_note_2_rounded,
                    size: 14,
                    color: Color(0xFFFBBF24),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.notes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 14),

          // Divider
          Container(height: 1, color: const Color(0xFF2A2D3E)),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () => _declineOrder(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFF3A2020)),
                        backgroundColor: const Color(
                          0xFFEF4444,
                        ).withValues(alpha: 0.06),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Decline',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () => _acceptOrder(context),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text(
                        'Accept Order',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _declineOrder(BuildContext context) {
    AppSnackbar.info(context, 'Order declined');
    ref.invalidate(availableOrdersProvider);
  }

  void _acceptOrder(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _isReady
                    ? const Color(0xFF22C55E).withValues(alpha: 0.12)
                    : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _isReady ? 'READY' : 'PENDING',
                style: TextStyle(
                  color: _isReady
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFF59E0B),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Accept Order?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...order.items.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${item.itemName} x${item.quantity}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            Text(
              '${AppConstants.currencySymbol}${order.totalAmount.toStringAsFixed(0)}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: Color(0xFF22C55E),
              ),
            ),
            if (order.notes != null && order.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Note: ${order.notes}',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
            if (!_isReady) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_rounded,
                      color: Color(0xFFF59E0B),
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This order has been pending 30+ minutes. '
                        'The restaurant may still be preparing it.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final driverService = ref.read(driverServiceProvider);
                await driverService.acceptDelivery(order.id, driverId);
                ref.invalidate(availableOrdersProvider);
                if (context.mounted) {
                  AppSnackbar.success(context, 'Order accepted!');
                }
              } catch (e) {
                if (context.mounted) {
                  AppSnackbar.error(context, friendlyError(e));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Accept',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
