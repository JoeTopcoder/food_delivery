import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/driver_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';
import '../../utils/context_extensions.dart';

class DeliveryHistoryScreen extends ConsumerWidget {
  const DeliveryHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(currentUserIdProvider);

    if (currentUserId == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: AppErrorState(message: 'User not found'),
      );
    }

    final driverProfileAsync = ref.watch(driverProfileProvider(currentUserId));

    return driverProfileAsync.when(
      data: (driver) {
        if (driver == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F1117),
            body: AppErrorState(message: 'Driver profile not found'),
          );
        }

        final historyAsync = ref.watch(deliveryHistoryProvider(driver.id));

        return Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: const Color(0xFF0F1117),
                foregroundColor: Colors.white,
                elevation: 0,
                title: Text(
                  context.l10n.deliveryHistory,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              historyAsync.when(
                data: (deliveries) {
                  if (deliveries.isEmpty) {
                    return const SliverFillRemaining(
                      child: AppEmptyState(
                        icon: Icons.history_rounded,
                        title: 'No Delivery History',
                        subtitle: 'Completed deliveries will appear here.',
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final delivery = deliveries[index];
                        final fmt = DateFormat('MMM d, h:mm a');

                        return GestureDetector(
                          onTap: () => _showOrderDetail(context, delivery),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E2030),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF2A2D3E),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Check icon
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF22C55E,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF22C55E),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Order info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Order #${delivery.id.substring(0, 8).toUpperCase()}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${delivery.items.length} item(s) · ${fmt.format(delivery.orderedAt)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (delivery.userRating != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              ...List.generate(5, (i) {
                                                return Icon(
                                                  i <
                                                          delivery.userRating!
                                                              .toInt()
                                                      ? Icons.star_rounded
                                                      : Icons
                                                            .star_border_rounded,
                                                  size: 14,
                                                  color: const Color(
                                                    0xFFFBBF24,
                                                  ),
                                                );
                                              }),
                                              const SizedBox(width: 4),
                                              Text(
                                                delivery.userRating!
                                                    .toStringAsFixed(1),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFFFBBF24),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // Amount
                                Text(
                                  '${AppConstants.currencySymbol}${delivery.totalAmount.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF22C55E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }, childCount: deliveries.length),
                    ),
                  );
                },
                loading: () => SliverFillRemaining(
                  child: AppLoadingIndicator(
                    message: 'Loading history...',
                    color: AppTheme.primaryColor,
                  ),
                ),
                error: (err, _) => SliverFillRemaining(
                  child: AppErrorState(message: friendlyError(err)),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: AppLoadingIndicator(
          message: 'Loading driver...',
          color: AppTheme.primaryColor,
        ),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        body: AppErrorState(message: friendlyError(err)),
      ),
    );
  }

  void _showOrderDetail(BuildContext context, dynamic delivery) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Order #${delivery.id.substring(0, 8).toUpperCase()}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Items',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              ...delivery.items.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF6B7280),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${item.itemName} × ${item.quantity}',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${AppConstants.currencySymbol}${delivery.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF22C55E),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              if (delivery.userReview != null) ...[
                const SizedBox(height: 14),
                const Text(
                  'Customer Review',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFBBF24),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2D3E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    delivery.userReview!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Close',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
