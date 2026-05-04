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
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(allRestaurantsAdminProvider);
    ref.invalidate(pendingRestaurantsProvider);
    ref.invalidate(rejectedRestaurantsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allRestaurantsAdminProvider((0, 200)));
    final pendingAsync = ref.watch(pendingRestaurantsProvider);
    final rejectedAsync = ref.watch(rejectedRestaurantsProvider);

    int allCount = allAsync.valueOrNull?.length ?? 0;
    int pendingCount = pendingAsync.valueOrNull?.length ?? 0;
    int rejectedCount = rejectedAsync.valueOrNull?.length ?? 0;

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
            fontSize: 13,
          ),
          tabs: [
            _countTab('All', allCount),
            _countTab('Pending', pendingCount, color: const Color(0xFFFEF3C7)),
            _countTab(
              'Rejected',
              rejectedCount,
              color: const Color(0xFFFEE2E2),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RestaurantList(asyncValue: allAsync, onRefresh: _refresh, ref: ref),
          _RestaurantList(
            asyncValue: pendingAsync,
            onRefresh: _refresh,
            ref: ref,
            emptyMessage: 'No restaurants pending verification',
            emptyIcon: Icons.check_circle_outline,
          ),
          _RestaurantList(
            asyncValue: rejectedAsync,
            onRefresh: _refresh,
            ref: ref,
            emptyMessage: 'No rejected restaurants',
            emptyIcon: Icons.cancel_outlined,
          ),
        ],
      ),
    );
  }

  Tab _countTab(String label, int count, {Color? color}) {
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
                color: color ?? Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color != null ? const Color(0xFF92400E) : Colors.white,
                ),
              ),
            ),
          ],
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
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _RestaurantStat(
                                    icon: Icons.star_rounded,
                                    color: const Color(0xFFF59E0B),
                                    value:
                                        restaurant.rating?.toStringAsFixed(
                                          1,
                                        ) ??
                                        '0.0',
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
                                    value:
                                        '${restaurant.estimatedDeliveryTime ?? 30}m',
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
                                  const SizedBox(width: 12),
                                ],
                              ),
                            ),
                          ),
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
                              _showRestaurantDetails(context, restaurant),
                          icon: const Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                          ),
                          label: const Text('View Full Details'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6366F1),
                            side: const BorderSide(color: Color(0xFF6366F1)),
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

  void _showRestaurantDetails(BuildContext context, Restaurant restaurant) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollController) {
          final isVerified = restaurant.isVerified == true;
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: isVerified
                                  ? const Color(
                                      0xFFFF6B35,
                                    ).withValues(alpha: 0.12)
                                  : const Color(
                                      0xFFF59E0B,
                                    ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.store_rounded,
                              color: isVerified
                                  ? AppTheme.primaryColor
                                  : const Color(0xFFF59E0B),
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  restaurant.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  restaurant.cuisineType ?? 'Cuisine N/A',
                                  style: TextStyle(
                                    fontSize: 13,
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
                      const SizedBox(height: 20),
                      _RestDetailSection(
                        title: 'General Info',
                        children: [
                          _RestDetailItem(
                            label: 'Restaurant ID',
                            value: restaurant.id,
                          ),
                          _RestDetailItem(
                            label: 'Owner ID',
                            value: restaurant.ownerId,
                          ),
                          _RestDetailItem(
                            label: 'Store Type',
                            value: restaurant.storeType,
                          ),
                          _RestDetailItem(
                            label: 'Status',
                            value: restaurant.status,
                          ),
                          _RestDetailItem(
                            label: 'Description',
                            value: restaurant.description ?? 'N/A',
                          ),
                          _RestDetailItem(
                            label: 'Address',
                            value: restaurant.address ?? 'N/A',
                          ),
                          _RestDetailItem(
                            label: 'Phone',
                            value: restaurant.phone ?? 'N/A',
                          ),
                          _RestDetailItem(
                            label: 'Email',
                            value: restaurant.email ?? 'N/A',
                          ),
                          _RestDetailItem(
                            label: 'Tags',
                            value: restaurant.tags?.join(', ') ?? 'N/A',
                          ),
                          _RestDetailItem(
                            label: 'Member Since',
                            value: restaurant.createdAt
                                .toLocal()
                                .toString()
                                .split('.')
                                .first,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _RestDetailSection(
                        title: 'Operations',
                        children: [
                          _RestDetailItem(
                            label: 'Opening Time',
                            value: restaurant.openingTime ?? 'N/A',
                          ),
                          _RestDetailItem(
                            label: 'Closing Time',
                            value: restaurant.closingTime ?? 'N/A',
                          ),
                          _RestDetailItem(
                            label: 'Est. Delivery Time',
                            value:
                                '${restaurant.estimatedDeliveryTime ?? 30} min',
                          ),
                          _RestDetailItem(
                            label: 'Delivery Fee',
                            value:
                                '${AppConstants.currencySymbol}${restaurant.deliveryFee?.toStringAsFixed(2) ?? '0.00'}',
                          ),
                          _RestDetailItem(
                            label: 'Service Fee',
                            value:
                                '${AppConstants.currencySymbol}${restaurant.serviceFee?.toStringAsFixed(2) ?? '25.00'}',
                          ),
                          _RestDetailItem(
                            label: 'Commission Rate',
                            value:
                                '${((restaurant.commissionRate ?? 0.15) * 100).toStringAsFixed(0)}%',
                          ),
                          _RestDetailItem(
                            label: 'Rating',
                            value:
                                restaurant.rating?.toStringAsFixed(2) ?? '0.00',
                          ),
                          _RestDetailItem(
                            label: 'Review Count',
                            value: '${restaurant.reviewCount ?? 0}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _RestDetailSection(
                        title: 'Financials',
                        children: [
                          _RestDetailItem(
                            label: 'Total Earnings',
                            value:
                                '${AppConstants.currencySymbol}${restaurant.totalEarnings?.toStringAsFixed(2) ?? '0.00'}',
                          ),
                          _RestDetailItem(
                            label: 'Total Paid Out',
                            value:
                                '${AppConstants.currencySymbol}${restaurant.totalPaidOut?.toStringAsFixed(2) ?? '0.00'}',
                          ),
                          _RestDetailItem(
                            label: 'Stripe Account ID',
                            value: restaurant.stripeAccountId ?? 'N/A',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _RestDetailSection(
                        title: 'Banking',
                        children: [
                          _RestDetailItem(
                            label: 'Bank Name',
                            value: restaurant.bankName ?? 'N/A',
                          ),
                          _RestDetailItem(
                            label: 'Branch',
                            value: restaurant.bankBranch ?? 'N/A',
                          ),
                          _RestDetailItem(
                            label: 'Account Holder',
                            value: restaurant.bankAccountHolder ?? 'N/A',
                          ),
                          _RestDetailItem(
                            label: 'Account Number',
                            value: restaurant.bankAccountNumber ?? 'N/A',
                          ),
                          _RestDetailItem(
                            label: 'Account Type',
                            value: restaurant.bankAccountType ?? 'N/A',
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (!isVerified) ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _confirmAction(
                                    context,
                                    restaurant.id,
                                    restaurant.name,
                                    false,
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _confirmAction(
                                    context,
                                    restaurant.id,
                                    restaurant.name,
                                    true,
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text('Verify Restaurant'),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _confirmAction(
                                context,
                                restaurant.id,
                                restaurant.name,
                                false,
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Revoke Verification'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
                ref.invalidate(rejectedRestaurantsProvider);
                ref.invalidate(restaurantStatisticsProvider);
                ref.invalidate(dashboardSummaryProvider);
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

class _RestDetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _RestDetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: List.generate(children.length, (i) {
              return Column(
                children: [
                  children[i],
                  if (i < children.length - 1)
                    Divider(
                      height: 1,
                      color: Theme.of(context).dividerColor,
                      indent: 16,
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _RestDetailItem extends StatelessWidget {
  final String label;
  final String value;
  const _RestDetailItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
