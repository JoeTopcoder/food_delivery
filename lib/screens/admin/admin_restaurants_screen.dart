import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/restaurant_model.dart';
import '../../providers/admin_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'package:food_driver/config/app_constants.dart';

class AdminRestaurantsScreen extends ConsumerStatefulWidget {
  const AdminRestaurantsScreen({super.key});

  @override
  ConsumerState<AdminRestaurantsScreen> createState() =>
      _AdminRestaurantsScreenState();
}

class _AdminRestaurantsScreenState extends ConsumerState<AdminRestaurantsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(allRestaurantsAdminProvider);
    ref.invalidate(pendingRestaurantsProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Restaurant Management',
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
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'All Restaurants'),
            Tab(text: 'Pending'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RestaurantList(
            asyncValue: ref.watch(allRestaurantsAdminProvider((0, 100))),
            onRefresh: _refresh,
            ref: ref,
          ),
          _RestaurantList(
            asyncValue: ref.watch(pendingRestaurantsProvider),
            onRefresh: _refresh,
            ref: ref,
            emptyMessage: 'No restaurants pending verification',
            emptyIcon: Icons.check_circle_outline,
          ),
        ],
      ),
    );
  }
}

class _RestaurantList extends StatelessWidget {
  final AsyncValue<List<Restaurant>> asyncValue;
  final Future<void> Function() onRefresh;
  final WidgetRef ref;
  final String emptyMessage;
  final IconData emptyIcon;

  const _RestaurantList({
    required this.asyncValue,
    required this.onRefresh,
    required this.ref,
    this.emptyMessage = 'No restaurants found',
    this.emptyIcon = Icons.store_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.primaryColor,
      child: asyncValue.when(
        data: (restaurants) {
          if (restaurants.isEmpty) {
            return AppEmptyState(icon: emptyIcon, title: emptyMessage);
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: restaurants.length,
            itemBuilder: (context, index) {
              final restaurant = restaurants[index];
              final isVerified = restaurant.isVerified == true;
              final isOpen = restaurant.isCurrentlyOpen;

              return Container(
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
                      Row(
                        children: [
                          // Icon
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isVerified
                                  ? const Color(
                                      0xFFFF6B35,
                                    ).withValues(alpha: 0.12)
                                  : const Color(
                                      0xFFF59E0B,
                                    ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.store_rounded,
                              color: isVerified
                                  ? AppTheme.primaryColor
                                  : const Color(0xFFF59E0B),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  restaurant.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  restaurant.cuisineType ?? 'Cuisine N/A',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _VerifiedBadge(isVerified: isVerified),
                        ],
                      ),

                      const SizedBox(height: 12),
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                      const SizedBox(height: 10),

                      // Details
                      _DetailRow(
                        icon: Icons.location_on_outlined,
                        text: restaurant.address ?? 'Address N/A',
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: _DetailRow(
                              icon: Icons.phone_outlined,
                              text: restaurant.phone ?? 'Phone N/A',
                            ),
                          ),
                          if (restaurant.phone != null &&
                              restaurant.phone!.isNotEmpty)
                            IconButton(
                              icon: const Icon(
                                Icons.call_rounded,
                                color: Color(0xFF10B981),
                                size: 20,
                              ),
                              tooltip: 'Call ${restaurant.name}',
                              onPressed: () => launchUrl(
                                Uri(scheme: 'tel', path: restaurant.phone!),
                              ),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Stats row
                      Row(
                        children: [
                          _RestaurantStat(
                            icon: Icons.star_rounded,
                            color: const Color(0xFFF59E0B),
                            value:
                                restaurant.rating?.toStringAsFixed(1) ?? '0.0',
                            label: 'Rating',
                          ),
                          const SizedBox(width: 16),
                          _RestaurantStat(
                            icon: Icons.delivery_dining_rounded,
                            color: const Color(0xFF10B981),
                            value:
                                '${AppConstants.currencySymbol}${restaurant.deliveryFee?.toStringAsFixed(0) ?? '0'}',
                            label: 'Delivery',
                          ),
                          const SizedBox(width: 16),
                          _RestaurantStat(
                            icon: Icons.schedule_rounded,
                            color: const Color(0xFF6366F1),
                            value: '${restaurant.estimatedDeliveryTime ?? 30}m',
                            label: 'Est.',
                          ),
                          const SizedBox(width: 16),
                          _RestaurantStat(
                            icon: Icons.percent_rounded,
                            color: const Color(0xFF8B5CF6),
                            value:
                                '${((restaurant.commissionRate ?? 0.15) * 100).toStringAsFixed(0)}%',
                            label: 'Comm.',
                          ),
                          const SizedBox(width: 16),
                          _RestaurantStat(
                            icon: Icons.shopping_bag_rounded,
                            color: const Color(0xFF0EA5E9),
                            value:
                                '${AppConstants.currencySymbol}${restaurant.serviceFee?.toStringAsFixed(0) ?? '25'}',
                            label: 'Svc Fee',
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isOpen
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isOpen ? 'Open' : 'Closed',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isOpen
                                    ? Colors.green[700]
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      if (!isVerified)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _confirmAction(
                                  context,
                                  restaurant.id,
                                  restaurant.name,
                                  false,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _confirmAction(
                                  context,
                                  restaurant.id,
                                  restaurant.name,
                                  true,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text('Verify'),
                              ),
                            ),
                          ],
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => _confirmAction(
                              context,
                              restaurant.id,
                              restaurant.name,
                              false,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Revoke Verification'),
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showCommissionDialog(context, restaurant),
                          icon: const Icon(Icons.percent_rounded, size: 16),
                          label: Text(
                            'Commission: ${((restaurant.commissionRate ?? 0.15) * 100).toStringAsFixed(0)}%',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF8B5CF6),
                            side: const BorderSide(color: Color(0xFF8B5CF6)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showServiceFeeDialog(context, restaurant),
                          icon: const Icon(
                            Icons.shopping_bag_rounded,
                            size: 16,
                          ),
                          label: Text(
                            'Service Fee: \$${restaurant.serviceFee?.toStringAsFixed(0) ?? '25'}',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0EA5E9),
                            side: const BorderSide(color: Color(0xFF0EA5E9)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () =>
            const AppLoadingIndicator(message: 'Loading restaurants…'),
        error: (e, _) =>
            AppErrorState(message: friendlyError(e), onRetry: onRefresh),
      ),
    );
  }

  void _confirmAction(
    BuildContext context,
    String restaurantId,
    String restaurantName,
    bool verify,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          verify ? 'Verify Restaurant?' : 'Reject/Revoke Restaurant?',
        ),
        content: Text(
          verify
              ? 'Verify "$restaurantName"? They will appear to customers on the app.'
              : 'Remove verification from "$restaurantName"? They won\'t be visible to customers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await ref
                    .read(adminServiceProvider)
                    .verifyRestaurant(restaurantId, verify);
                ref.invalidate(allRestaurantsAdminProvider);
                ref.invalidate(pendingRestaurantsProvider);
                ref.invalidate(restaurantStatisticsProvider);
                if (context.mounted) {
                  if (verify) {
                    AppSnackbar.success(
                      context,
                      '"$restaurantName" verified successfully',
                    );
                  } else {
                    AppSnackbar.warning(
                      context,
                      '"$restaurantName" rejected successfully',
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  AppSnackbar.error(context, friendlyError(e));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: verify ? const Color(0xFF10B981) : Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(verify ? 'Verify' : 'Reject'),
          ),
        ],
      ),
    );
  }

  void _showCommissionDialog(BuildContext context, Restaurant restaurant) {
    final raw = restaurant.commissionRate ?? 15;
    double commission = (raw <= 1 ? raw * 100 : raw).clamp(0, 50).toDouble();
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Set Commission: ${restaurant.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${commission.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B5CF6),
                ),
              ),
              Slider(
                value: commission,
                min: 0,
                max: 50,
                divisions: 50,
                activeColor: const Color(0xFF8B5CF6),
                label: '${commission.toStringAsFixed(0)}%',
                onChanged: (val) {
                  setDialogState(() => commission = val);
                },
              ),
              Text(
                'Platform commission on each order',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await ref
                      .read(adminServiceProvider)
                      .updateRestaurantCommission(
                        restaurant.id,
                        commission / 100,
                      );
                  ref.invalidate(allRestaurantsAdminProvider);
                  if (context.mounted) {
                    AppSnackbar.success(
                      context,
                      'Commission for "${restaurant.name}" set to ${commission.toStringAsFixed(0)}%',
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppSnackbar.error(context, friendlyError(e));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showServiceFeeDialog(BuildContext context, Restaurant restaurant) {
    double serviceFee = restaurant.serviceFee ?? 25;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Set Service Fee: ${restaurant.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${AppConstants.currencySymbol}${serviceFee.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0EA5E9),
                ),
              ),
              Slider(
                value: serviceFee,
                min: 0,
                max: 200,
                divisions: 40,
                activeColor: const Color(0xFF0EA5E9),
                label:
                    '${AppConstants.currencySymbol}${serviceFee.toStringAsFixed(0)}',
                onChanged: (val) {
                  setDialogState(() => serviceFee = val);
                },
              ),
              Text(
                'Fee charged to customer for pickup orders',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await ref
                      .read(adminServiceProvider)
                      .updateRestaurantServiceFee(restaurant.id, serviceFee);
                  ref.invalidate(allRestaurantsAdminProvider);
                  if (context.mounted) {
                    AppSnackbar.success(
                      context,
                      'Service fee for "${restaurant.name}" set to \$${serviceFee.toStringAsFixed(0)}',
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppSnackbar.error(context, friendlyError(e));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0EA5E9),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  final bool isVerified;
  const _VerifiedBadge({required this.isVerified});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isVerified
            ? const Color(0xFF10B981).withValues(alpha: 0.1)
            : const Color(0xFFF59E0B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVerified ? Icons.verified_rounded : Icons.hourglass_top_rounded,
            size: 12,
            color: isVerified
                ? const Color(0xFF10B981)
                : const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 4),
          Text(
            isVerified ? 'Verified' : 'Pending',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isVerified
                  ? const Color(0xFF10B981)
                  : const Color(0xFFF59E0B),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: const Color(0xFF9CA3AF)),
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

class _RestaurantStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _RestaurantStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
