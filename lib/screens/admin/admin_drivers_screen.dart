import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/driver_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/driver_provider.dart';
import '../../config/app_constants.dart';
import '../../config/supabase_config.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class AdminDriversScreen extends ConsumerStatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  ConsumerState<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends ConsumerState<AdminDriversScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(allDriversAdminProvider);
    ref.invalidate(approvedDriversProvider);
    ref.invalidate(rejectedDriversProvider);
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allDriversAdminProvider((0, 200)));
    final approvedAsync = ref.watch(approvedDriversProvider);
    final rejectedAsync = ref.watch(rejectedDriversProvider);
    final verifyAsync = ref.watch(pendingVerificationDriversProvider);

    int allCount = allAsync.valueOrNull?.length ?? 0;
    int approvedCount = approvedAsync.valueOrNull?.length ?? 0;
    int rejectedCount = rejectedAsync.valueOrNull?.length ?? 0;
    int verifyCount = verifyAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Driver Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
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
            _countTab('Approved', approvedCount, color: const Color(0xFFD1FAE5)),
            _countTab('Rejected', rejectedCount, color: const Color(0xFFFEE2E2)),
            _countTab('Review', verifyCount, color: const Color(0xFFE0E7FF)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDriverDialog(context),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text(
          'Add Driver',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DriverList(
            asyncValue: allAsync,
            onRefresh: _refresh,
            ref: ref,
          ),
          _DriverList(
            asyncValue: approvedAsync,
            onRefresh: _refresh,
            ref: ref,
            emptyMessage: 'No approved drivers yet',
            emptyIcon: Icons.verified_rounded,
          ),
          _DriverList(
            asyncValue: rejectedAsync,
            onRefresh: _refresh,
            ref: ref,
            emptyMessage: 'No rejected drivers',
            emptyIcon: Icons.cancel_outlined,
          ),
          _VerificationReviewList(
            asyncValue: verifyAsync,
            onRefresh: () async {
              ref.invalidate(pendingVerificationDriversProvider);
            },
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

  void _showCreateDriverDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _CreateDriverDialog(
        onCreated: () {
          _refresh();
          ref.invalidate(driverStatisticsProvider);
        },
        ref: ref,
      ),
    );
  }
}

class _DriverList extends StatelessWidget {
  final AsyncValue<List<Driver>> asyncValue;
  final Future<void> Function() onRefresh;
  final WidgetRef ref;
  final String emptyMessage;
  final IconData emptyIcon;

  const _DriverList({
    required this.asyncValue,
    required this.onRefresh,
    required this.ref,
    this.emptyMessage = 'No drivers found',
    this.emptyIcon = Icons.directions_bike_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.primaryColor,
      child: asyncValue.when(
        data: (drivers) {
          if (drivers.isEmpty) {
            return AppEmptyState(icon: emptyIcon, title: emptyMessage);
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: drivers.length,
            itemBuilder: (context, index) {
              final driver = drivers[index];
              final isApproved = driver.isApproved;

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
                              color: isApproved
                                  ? const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.12)
                                  : const Color(
                                      0xFFF59E0B,
                                    ).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.directions_bike_rounded,
                              color: isApproved
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Driver name
                                Text(
                                  driver.fullName?.isNotEmpty == true
                                      ? driver.fullName!
                                      : 'Driver',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                // Vehicle make/model line
                                Text(
                                  _vehicleLine(driver),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                // Plate + color line
                                Text(
                                  _vehicleDetail(driver),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _StatusBadge(isApproved: isApproved, status: driver.driverStatus),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.call_rounded,
                              color: Color(0xFF10B981),
                              size: 20,
                            ),
                            tooltip: 'Call driver',
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                            onPressed: () async {
                              final phone = driver.phoneNumber?.isNotEmpty == true
                                  ? driver.phoneNumber
                                  : null;
                              if (phone != null) {
                                launchUrl(Uri(scheme: 'tel', path: phone));
                                return;
                              }
                              try {
                                final userData = await SupabaseConfig.client
                                    .from('users')
                                    .select('phone')
                                    .eq('id', driver.userId)
                                    .maybeSingle();
                                final p = userData?['phone'] as String?;
                                if (p != null && p.isNotEmpty) {
                                  launchUrl(Uri(scheme: 'tel', path: p));
                                } else if (context.mounted) {
                                  AppSnackbar.warning(context, 'No phone number on file');
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  AppSnackbar.error(context, 'Could not retrieve phone number');
                                }
                              }
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                      const SizedBox(height: 10),

                      // Stats row
                      Row(
                        children: [
                          Expanded(
                            child: _DriverStat(
                              icon: Icons.star_rounded,
                              color: const Color(0xFFF59E0B),
                              value: driver.rating?.toStringAsFixed(1) ?? '0.0',
                              label: 'Rating',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DriverStat(
                              icon: Icons.check_circle_rounded,
                              color: const Color(0xFF10B981),
                              value: '${driver.completedDeliveries ?? 0}',
                              label: 'Deliveries',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DriverStat(
                              icon: Icons.badge_rounded,
                              color: const Color(0xFF6366F1),
                              value: driver.licenseNumber?.isNotEmpty == true
                                  ? driver.licenseNumber!
                                  : 'N/A',
                              label: 'License',
                            ),
                          ),
                        ],
                      ),

                      // Cash Float row
                      if ((driver.cashFloat ?? 0) > 0) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFF87171)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.account_balance_wallet_rounded,
                                color: Color(0xFFDC2626),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Cash Float',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF991B1B),
                                      ),
                                    ),
                                    Text(
                                      '${AppConstants.currencySymbol}${driver.cashFloat!.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 34,
                                child: ElevatedButton.icon(
                                  onPressed: () => _showCollectFloatDialog(
                                    context,
                                    driver,
                                    ref,
                                  ),
                                  icon: const Icon(
                                    Icons.payments_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Collect',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFDC2626),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showDriverDetails(context, driver),
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

                      if (!isApproved) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _confirmAction(
                                  context,
                                  driver.id,
                                  driver.vehicleNumber ?? 'this driver',
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
                                  driver.id,
                                  driver.vehicleNumber ?? 'this driver',
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
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => _confirmAction(
                              context,
                              driver.id,
                              driver.vehicleNumber ?? 'this driver',
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
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const AppLoadingIndicator(message: 'Loading drivers…'),
        error: (e, _) =>
            AppErrorState(message: friendlyError(e), onRetry: onRefresh),
      ),
    );
  }

  void _showDriverDetails(BuildContext context, Driver driver) {
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
          final isApproved = driver.isApproved;
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
                              color: isApproved
                                  ? const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.12)
                                  : const Color(
                                      0xFFF59E0B,
                                    ).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.directions_bike_rounded,
                              color: isApproved
                                  ? const Color(0xFF10B981)
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
                                  _vehicleLine(driver),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  () {
                                    final plate = driver.plateNumber ??
                                        driver.licensePlate ??
                                        driver.vehicleNumber;
                                    final color = driver.vehicleColor;
                                    final parts = <String>[
                                      if (plate != null && plate.isNotEmpty)
                                        plate,
                                      if (color != null && color.isNotEmpty)
                                        color,
                                    ];
                                    return parts.isEmpty
                                        ? 'No plate on file'
                                        : parts.join(' · ');
                                  }(),
                                  overflow: TextOverflow.ellipsis,
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
                          _StatusBadge(isApproved: isApproved, status: driver.driverStatus),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _DetailSection(
                        title: 'Driver Info',
                        children: [
                          _DetailItem(label: 'Driver ID', value: driver.id),
                          _DetailItem(label: 'User ID', value: driver.userId),
                          _DetailItem(
                            label: 'License Number',
                            value: driver.licenseNumber ?? 'N/A',
                          ),
                          _DetailItem(
                            label: 'Documents Status',
                            value: driver.documentsStatus ?? 'N/A',
                          ),
                          _DetailItem(
                            label: 'Available',
                            value: driver.isAvailable == true ? 'Yes' : 'No',
                          ),
                          _DetailItem(
                            label: 'Member Since',
                            value: driver.createdAt
                                .toLocal()
                                .toString()
                                .split('.')
                                .first,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _DetailSection(
                        title: 'Performance',
                        children: [
                          _DetailItem(
                            label: 'Rating',
                            value: driver.rating?.toStringAsFixed(2) ?? '0.00',
                          ),
                          _DetailItem(
                            label: 'Completed Deliveries',
                            value: '${driver.completedDeliveries ?? 0}',
                          ),
                          _DetailItem(
                            label: 'Cancelled Deliveries',
                            value: '${driver.cancelledDeliveries ?? 0}',
                          ),
                          _DetailItem(
                            label: 'Total Earnings',
                            value:
                                '${AppConstants.currencySymbol}${driver.totalEarnings?.toStringAsFixed(2) ?? '0.00'}',
                          ),
                          _DetailItem(
                            label: 'Total Paid Out',
                            value:
                                '${AppConstants.currencySymbol}${driver.totalPaidOut?.toStringAsFixed(2) ?? '0.00'}',
                          ),
                          _DetailItem(
                            label: 'Cash Float',
                            value:
                                '${AppConstants.currencySymbol}${driver.cashFloat?.toStringAsFixed(2) ?? '0.00'}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _DetailSection(
                        title: 'Banking',
                        children: [
                          _DetailItem(
                            label: 'Bank Name',
                            value: driver.bankName ?? 'N/A',
                          ),
                          _DetailItem(
                            label: 'Branch',
                            value: driver.bankBranch ?? 'N/A',
                          ),
                          _DetailItem(
                            label: 'Account Holder',
                            value: driver.bankAccountHolder ?? 'N/A',
                          ),
                          _DetailItem(
                            label: 'Account Number',
                            value: driver.bankAccountNumber ?? 'N/A',
                          ),
                          _DetailItem(
                            label: 'Account Type',
                            value: driver.bankAccountType ?? 'N/A',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _DetailSection(
                        title: 'Stripe / Payouts',
                        children: [
                          _DetailItem(
                            label: 'Stripe Account ID',
                            value: driver.stripeAccountId ?? 'N/A',
                          ),
                          _DetailItem(
                            label: 'Stripe Status',
                            value: driver.stripeAccountStatus ?? 'N/A',
                          ),
                          _DetailItem(
                            label: 'Payouts Enabled',
                            value: driver.payoutsEnabled == true ? 'Yes' : 'No',
                          ),
                          _DetailItem(
                            label: 'Debit Card Added',
                            value: driver.stripeDebitCardAdded == true
                                ? 'Yes'
                                : 'No',
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (!isApproved) ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _confirmAction(
                                    context,
                                    driver.id,
                                    driver.vehicleNumber ?? 'this driver',
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
                                    driver.id,
                                    driver.vehicleNumber ?? 'this driver',
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
                                child: const Text('Verify Driver'),
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
                                driver.id,
                                driver.vehicleNumber ?? 'this driver',
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
    String driverId,
    String driverName,
    bool verify,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(verify ? 'Verify Driver?' : 'Reject/Revoke Driver?'),
        content: Text(
          verify
              ? 'Verify "$driverName"? They will be able to accept deliveries.'
              : 'Remove verification from "$driverName"? They won\'t be able to accept deliveries.',
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
                    .verifyDriver(driverId, verify);
                ref.invalidate(allDriversAdminProvider);
                ref.invalidate(pendingDriversProvider);
                ref.invalidate(rejectedDriversProvider);
                ref.invalidate(driverStatisticsProvider);
                ref.invalidate(dashboardSummaryProvider);
                if (context.mounted) {
                  if (verify) {
                    AppSnackbar.success(
                      context,
                      '$driverName verified successfully',
                    );
                  } else {
                    AppSnackbar.warning(
                      context,
                      '$driverName rejected successfully',
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

  void _showCollectFloatDialog(
    BuildContext context,
    Driver driver,
    WidgetRef ref,
  ) {
    final floatAmount = driver.cashFloat ?? 0.0;
    final amountCtrl = TextEditingController(
      text: floatAmount.toStringAsFixed(0),
    );
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Collect Cash Float'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Driver: ${driver.vehicleNumber ?? driver.id.substring(0, 8)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Outstanding Float: \$${floatAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount to collect',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    helperText: 'Enter partial or full amount',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _FloatQuickBtn(
                      label: 'Full',
                      onTap: () {
                        amountCtrl.text = floatAmount.toStringAsFixed(0);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    _FloatQuickBtn(
                      label: 'Half',
                      onTap: () {
                        amountCtrl.text = (floatAmount / 2).toStringAsFixed(0);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    _FloatQuickBtn(
                      label: 'Quarter',
                      onTap: () {
                        amountCtrl.text = (floatAmount / 4).toStringAsFixed(0);
                        setDialogState(() {});
                      },
                    ),
                  ],
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
                  final collectAmt =
                      double.tryParse(amountCtrl.text.trim()) ?? 0;
                  if (collectAmt <= 0) return;
                  if (collectAmt > floatAmount) {
                    AppSnackbar.warning(
                      context,
                      'Amount exceeds outstanding float',
                    );
                    return;
                  }
                  Navigator.of(context).pop();
                  try {
                    final driverService = ref.read(driverServiceProvider);
                    if (collectAmt >= floatAmount) {
                      await driverService.collectFloat(driver.id);
                    } else {
                      await driverService.collectFloat(
                        driver.id,
                        amount: collectAmt,
                      );
                    }
                    ref.invalidate(allDriversAdminProvider);
                    ref.invalidate(pendingDriversProvider);
                    if (context.mounted) {
                      AppSnackbar.success(
                        context,
                        '${AppConstants.currencySymbol}${collectAmt.toStringAsFixed(0)} float collected successfully',
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      AppSnackbar.error(context, friendlyError(e));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Collect'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FloatQuickBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FloatQuickBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isApproved;
  final String? status;
  const _StatusBadge({required this.isApproved, this.status});

  Color get _color {
    switch (status) {
      case 'approved':
        return const Color(0xFF10B981);
      case 'rejected':
        return Colors.red;
      case 'pending_review':
      case 'under_review':
        return const Color(0xFFF59E0B);
      default:
        return isApproved ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    }
  }

  String get _label {
    switch (status) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'pending_review':
        return 'Pending';
      case 'under_review':
        return 'In Review';
      case 'draft':
        return 'Draft';
      default:
        return isApproved ? 'Approved' : 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status == 'approved' || isApproved
                ? Icons.verified_rounded
                : status == 'rejected'
                ? Icons.cancel_rounded
                : Icons.hourglass_top_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            _label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _DriverStat({
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                overflow: TextOverflow.ellipsis,
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
        ),
      ],
    );
  }
}

// ─── Detail Section / Item ────────────────────────────────────────────────────

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _DetailSection({required this.title, required this.children});

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

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;
  const _DetailItem({required this.label, required this.value});

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
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
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

// ─── Create Driver Dialog ─────────────────────────────────────────────────────

class _CreateDriverDialog extends StatefulWidget {
  final VoidCallback onCreated;
  final WidgetRef ref;
  const _CreateDriverDialog({required this.onCreated, required this.ref});

  @override
  State<_CreateDriverDialog> createState() => _CreateDriverDialogState();
}

class _CreateDriverDialogState extends State<_CreateDriverDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _vehicleNumberCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  String _vehicleType = 'motorcycle';
  bool _creating = false;
  bool _obscurePassword = true;

  static const _vehicleTypes = [
    ('motorcycle', 'Motorcycle', Icons.two_wheeler_rounded),
    ('bike', 'Bike', Icons.pedal_bike_rounded),
    ('car', 'Car', Icons.directions_car_rounded),
    ('scooter', 'Scooter', Icons.electric_scooter_rounded),
    ('bicycle', 'Bicycle', Icons.directions_bike_rounded),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _vehicleNumberCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _creating = true);

    try {
      final adminService = widget.ref.read(adminServiceProvider);
      await adminService.createUserWithRole(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        role: AppConstants.roleDriver,
        vehicleType: _vehicleType,
        vehicleNumber: _vehicleNumberCtrl.text.trim(),
        licenseNumber: _licenseCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCreated();

      AppSnackbar.success(
        context,
        'Driver ${_nameCtrl.text.trim()} created successfully',
      );
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.contains('Exception: ')) {
        msg = msg.replaceFirst(RegExp(r'^Exception:\s*'), '');
      }
      AppSnackbar.error(context, 'Error: $msg');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_add_rounded,
                      color: AppTheme.primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Create Driver',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Name
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDecoration('Full Name', Icons.person_outline),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),

              // Email
              TextFormField(
                controller: _emailCtrl,
                decoration: _inputDecoration('Email', Icons.email_outlined),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email is required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Password
              TextFormField(
                controller: _passwordCtrl,
                decoration: _inputDecoration('Password', Icons.lock_outline)
                    .copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                obscureText: _obscurePassword,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 6) return 'Minimum 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Phone
              TextFormField(
                controller: _phoneCtrl,
                decoration: _inputDecoration('Phone', Icons.phone_outlined),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),

              // Vehicle Type
              Text(
                'Vehicle Type',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _vehicleTypes.map((vt) {
                  final selected = _vehicleType == vt.$1;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          vt.$3,
                          size: 16,
                          color: selected
                              ? Colors.white
                              : const Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 4),
                        Text(vt.$2),
                      ],
                    ),
                    selected: selected,
                    selectedColor: AppTheme.primaryColor,
                    backgroundColor: const Color(0xFFF3F4F6),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF374151),
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onSelected: (_) => setState(() => _vehicleType = vt.$1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Vehicle Number
              TextFormField(
                controller: _vehicleNumberCtrl,
                decoration: _inputDecoration(
                  'Vehicle Number',
                  Icons.badge_outlined,
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 14),

              // License
              TextFormField(
                controller: _licenseCtrl,
                decoration: _inputDecoration(
                  'License Number',
                  Icons.card_membership_outlined,
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 24),

              // Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _creating ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _creating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Create Driver',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
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

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

// ─── Verification Review Tab ──────────────────────────────────────────────────

class _VerificationReviewList extends ConsumerWidget {
  final AsyncValue<List<Map<String, dynamic>>> asyncValue;
  final Future<void> Function() onRefresh;

  const _VerificationReviewList({
    required this.asyncValue,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.primaryColor,
      child: asyncValue.when(
        loading: () =>
            const AppLoadingIndicator(message: 'Loading applications…'),
        error: (e, _) =>
            AppErrorState(message: friendlyError(e), onRetry: onRefresh),
        data: (rows) {
          if (rows.isEmpty) {
            return const AppEmptyState(
              icon: Icons.verified_user_outlined,
              title: 'No applications pending review',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: rows.length,
            itemBuilder: (context, i) =>
                _VerificationCard(row: rows[i], onRefresh: onRefresh, ref: ref),
          );
        },
      ),
    );
  }
}

class _VerificationCard extends StatefulWidget {
  final Map<String, dynamic> row;
  final Future<void> Function() onRefresh;
  final WidgetRef ref;
  const _VerificationCard({
    required this.row,
    required this.onRefresh,
    required this.ref,
  });

  @override
  State<_VerificationCard> createState() => _VerificationCardState();
}

class _VerificationCardState extends State<_VerificationCard> {
  bool _loading = false;

  String get _driverId => widget.row['id'] as String? ?? '';
  String get _driverName {
    final users = widget.row['users'] as Map<String, dynamic>?;
    return users?['name'] as String? ?? 'Unknown Driver';
  }

  String get _driverEmail {
    final users = widget.row['users'] as Map<String, dynamic>?;
    return users?['email'] as String? ?? '';
  }

  String get _status =>
      widget.row['driver_status'] as String? ?? 'pending_review';
  String get _serviceType =>
      widget.row['service_type'] as String? ?? 'food_delivery';
  int get _step => (widget.row['onboarding_step'] as num?)?.toInt() ?? 0;
  String? get _submittedAt => widget.row['submitted_at'] as String?;
  bool get _foodApproved =>
      widget.row['is_food_driver_approved'] as bool? ?? false;
  bool get _rideApproved =>
      widget.row['is_ride_driver_approved'] as bool? ?? false;

  Future<void> _review({
    required bool approved,
    String? rejectionReason,
    bool approveFoodDelivery = false,
    bool approveRideSharing = false,
  }) async {
    setState(() => _loading = true);
    try {
      await SupabaseConfig.client.rpc(
        'admin_review_driver_application',
        params: {
          'p_driver_id': _driverId,
          'p_approved': approved,
          'p_approve_food_delivery': approveFoodDelivery,
          'p_approve_ride_sharing': approveRideSharing,
          if (rejectionReason != null && rejectionReason.isNotEmpty)
            'p_rejection_reason': rejectionReason,
        },
      );
      // Fire-and-forget FCM notification via edge function (non-critical)
      SupabaseConfig.client.functions.invoke(
        'admin-review-driver',
        body: {
          'driver_id': _driverId,
          'approved': approved,
          if (rejectionReason != null) 'rejection_reason': rejectionReason,
          'approve_food_delivery': approveFoodDelivery,
          'approve_ride_sharing': approveRideSharing,
          'notify_only': true,
        },
      ).ignore();
      await widget.onRefresh();
      if (mounted) {
        AppSnackbar.success(
          context,
          approved ? '$_driverName approved!' : '$_driverName rejected.',
        );
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showApproveDialog() {
    bool foodEnabled =
        _serviceType == 'food_delivery' || _serviceType == 'both';
    bool rideEnabled = _serviceType == 'ride_sharing' || _serviceType == 'both';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Approve Driver'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Approve $_driverName for:',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Food Delivery'),
                value: foodEnabled,
                onChanged: (v) => setS(() => foodEnabled = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ride Sharing'),
                value: rideEnabled,
                onChanged: (v) => setS(() => rideEnabled = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _review(
                  approved: true,
                  approveFoodDelivery: foodEnabled,
                  approveRideSharing: rideEnabled,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              child: const Text('Approve'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDocumentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DriverDocumentsSheet(
        driverId: _driverId,
        driverName: _driverName,
        driverRow: widget.row,
      ),
    );
  }

  void _showRejectDialog() {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Application'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Provide a reason for rejecting $_driverName:',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'e.g. Documents unclear, expired license, etc.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final reason = reasonCtrl.text.trim();
              Navigator.pop(context);
              _review(
                approved: false,
                rejectionReason: reason.isEmpty ? null : reason,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final submittedDate = _submittedAt != null
        ? DateTime.tryParse(_submittedAt!)
        : null;
    final dateStr = submittedDate != null
        ? '${submittedDate.month.toString().padLeft(2, '0')}/${submittedDate.day.toString().padLeft(2, '0')}/${submittedDate.year}'
        : 'Unknown date';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(
                    0xFF6366F1,
                  ).withValues(alpha: 0.12),
                  child: Text(
                    _driverName.isNotEmpty ? _driverName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _driverName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        _driverEmail,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: _status),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _InfoChip(
                  icon: Icons.swap_horiz,
                  label: _serviceLabel(_serviceType),
                ),
                _InfoChip(icon: Icons.checklist, label: '$_step/8 steps'),
                _InfoChip(
                  icon: Icons.calendar_today,
                  label: 'Submitted $dateStr',
                ),
                if (_foodApproved)
                  _InfoChip(
                    icon: Icons.fastfood,
                    label: 'Food ✓',
                    color: const Color(0xFF10B981),
                  ),
                if (_rideApproved)
                  _InfoChip(
                    icon: Icons.directions_car,
                    label: 'Rides ✓',
                    color: const Color(0xFF10B981),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showDocumentsSheet,
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: const Text('View Documents'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6366F1),
                  side: const BorderSide(color: Color(0xFF6366F1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showRejectDialog,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showApproveDialog,
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _serviceLabel(String t) {
    switch (t) {
      case 'food_delivery':
        return 'Food Delivery';
      case 'ride_sharing':
        return 'Ride Sharing';
      case 'both':
        return 'Food & Rides';
      default:
        return t;
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'pending_review':
        color = Colors.orange;
        label = 'Pending';
        break;
      case 'under_review':
        color = Colors.blue;
        label = 'Reviewing';
        break;
      case 'approved':
        color = const Color(0xFF10B981);
        label = 'Approved';
        break;
      case 'rejected':
        color = Colors.redAccent;
        label = 'Rejected';
        break;
      default:
        color = Colors.grey;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ─── Vehicle helpers ──────────────────────────────────────────────────────────

String _vehicleLine(Driver driver) {
  final parts = <String>[];
  final type = driver.vehicleType;
  if (type != null && type.isNotEmpty) {
    parts.add(type[0].toUpperCase() + type.substring(1));
  }
  final make = driver.vehicleMake ?? driver.vehicleBrand;
  final model = driver.vehicleModel;
  if (make != null && make.isNotEmpty) parts.add(make);
  if (model != null && model.isNotEmpty) parts.add(model);
  return parts.isEmpty ? 'Unknown vehicle' : parts.join(' · ');
}

String _vehicleDetail(Driver driver) {
  final parts = <String>[];
  final plate = driver.plateNumber ?? driver.licensePlate ?? driver.vehicleNumber;
  if (plate != null && plate.isNotEmpty) parts.add('Plate: $plate');
  final color = driver.vehicleColor;
  if (color != null && color.isNotEmpty) parts.add(color);
  return parts.join(' · ');
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _InfoChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 12,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

// ─── Driver Documents Sheet ───────────────────────────────────────────────────

class _DriverDocumentsSheet extends StatefulWidget {
  final String driverId;
  final String driverName;
  final Map<String, dynamic> driverRow;

  const _DriverDocumentsSheet({
    required this.driverId,
    required this.driverName,
    required this.driverRow,
  });

  @override
  State<_DriverDocumentsSheet> createState() => _DriverDocumentsSheetState();
}

class _DriverDocumentsSheetState extends State<_DriverDocumentsSheet> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _identity;
  Map<String, dynamic>? _license;
  Map<String, dynamic>? _vehicle;
  Map<String, dynamic>? _insurance;

  // Resolved (possibly signed) image URLs
  final Map<String, String?> _resolvedUrls = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        SupabaseConfig.client
            .from('driver_identity_documents')
            .select()
            .eq('driver_id', widget.driverId)
            .maybeSingle(),
        SupabaseConfig.client
            .from('driver_licenses')
            .select()
            .eq('driver_id', widget.driverId)
            .maybeSingle(),
        SupabaseConfig.client
            .from('driver_vehicles')
            .select()
            .eq('driver_id', widget.driverId)
            .maybeSingle(),
        SupabaseConfig.client
            .from('driver_insurance')
            .select()
            .eq('driver_id', widget.driverId)
            .maybeSingle(),
      ]);

      _identity = results[0];
      _license = results[1];
      _vehicle = results[2];
      _insurance = results[3];

      // Resolve signed URLs for private-bucket document images
      final privatePaths = <String, String?>{
        'id_front': _identity?['front_photo_url'] as String?,
        'id_back': _identity?['back_photo_url'] as String?,
        'lic_front': _license?['front_photo_url'] as String?,
        'lic_back': _license?['back_photo_url'] as String?,
        'vehicle_reg': _vehicle?['registration_photo_url'] as String?,
        'insurance_doc': _insurance?['document_photo_url'] as String?,
      };

      for (final entry in privatePaths.entries) {
        _resolvedUrls[entry.key] = await _resolveUrl(entry.value);
      }

      // Profile photo is in the public bucket — use as-is
      _resolvedUrls['profile'] =
          widget.driverRow['profile_photo_url'] as String?;

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<String?> _resolveUrl(String? rawUrl) async {
    if (rawUrl == null || rawUrl.isEmpty) return null;
    // driver-documents is a PRIVATE bucket. getPublicUrl() was used during
    // upload which stores URLs like /object/public/driver-documents/... but
    // those 403 because the bucket isn't public. Always generate a signed URL.
    for (final prefix in [
      '/object/public/driver-documents/',
      '/object/driver-documents/',
      '/object/sign/driver-documents/',
    ]) {
      final idx = rawUrl.indexOf(prefix);
      if (idx != -1) {
        var path = rawUrl.substring(idx + prefix.length);
        final qIdx = path.indexOf('?');
        if (qIdx != -1) path = path.substring(0, qIdx);
        try {
          return await SupabaseConfig.client.storage
              .from('driver-documents')
              .createSignedUrl(path, 3600);
        } catch (_) {
          return null; // will show error tile in UI
        }
      }
    }
    // Profile photos or other public-bucket URLs — use as-is
    return rawUrl;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.96,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, sc) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF3F4F6),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.folder_open_rounded, color: Color(0xFF6366F1)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.driverName} — Documents',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Failed to load documents:\n$_error',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        )
                      : ListView(
                          controller: sc,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          children: [
                            _docSection('Personal Info', Icons.person_rounded, [
                              _docRow('Full Name',
                                  widget.driverRow['full_name'] ?? '—'),
                              _docRow('Phone',
                                  widget.driverRow['phone_number'] ?? '—'),
                              _docRow('Date of Birth',
                                  widget.driverRow['date_of_birth'] ?? '—'),
                              _docRow('Home Address',
                                  widget.driverRow['home_address'] ?? '—'),
                              _docRow('Service Type',
                                  widget.driverRow['service_type'] ?? '—'),
                              if (_resolvedUrls['profile'] != null)
                                _photoRow('Profile Photo',
                                    _resolvedUrls['profile']!),
                            ]),
                            const SizedBox(height: 14),
                            _docSection(
                                'Identity Document',
                                Icons.badge_rounded,
                                _identity == null
                                    ? [_docRow('Status', 'Not submitted')]
                                    : [
                                        _docRow(
                                            'Type',
                                            (_identity!['document_type']
                                                        as String? ??
                                                    '')
                                                .replaceAll('_', ' ')
                                                .toUpperCase()),
                                        _docRow('Number',
                                            _identity!['document_number'] ??
                                                '—'),
                                        _docRow(
                                            'Expires',
                                            _identity!['expiry_date'] ?? '—'),
                                        _docRow(
                                            'Status',
                                            _identity![
                                                    'verification_status'] ??
                                                '—'),
                                        if (_resolvedUrls['id_front'] != null)
                                          _photoRow('Front Photo',
                                              _resolvedUrls['id_front']!),
                                        if (_resolvedUrls['id_back'] != null)
                                          _photoRow('Back Photo',
                                              _resolvedUrls['id_back']!),
                                      ]),
                            const SizedBox(height: 14),
                            _docSection(
                                'Driver License',
                                Icons.credit_card_rounded,
                                _license == null
                                    ? [_docRow('Status', 'Not submitted')]
                                    : [
                                        _docRow(
                                            'License #',
                                            _license!['license_number'] ??
                                                '—'),
                                        _docRow(
                                            'Class',
                                            _license!['license_class'] ??
                                                '—'),
                                        _docRow(
                                            'Issued',
                                            _license!['issue_date'] ?? '—'),
                                        _docRow(
                                            'Expires',
                                            _license!['expiry_date'] ?? '—'),
                                        _docRow(
                                            'Status',
                                            _license![
                                                    'verification_status'] ??
                                                '—'),
                                        if (_resolvedUrls['lic_front'] != null)
                                          _photoRow('Front Photo',
                                              _resolvedUrls['lic_front']!),
                                        if (_resolvedUrls['lic_back'] != null)
                                          _photoRow('Back Photo',
                                              _resolvedUrls['lic_back']!),
                                      ]),
                            const SizedBox(height: 14),
                            _docSection(
                                'Vehicle',
                                Icons.directions_car_rounded,
                                _vehicle == null
                                    ? [_docRow('Status', 'Not submitted')]
                                    : [
                                        _docRow(
                                            'Make',
                                            _vehicle!['make'] ?? '—'),
                                        _docRow(
                                            'Model',
                                            _vehicle!['model'] ?? '—'),
                                        _docRow('Year',
                                            '${_vehicle!['year'] ?? '—'}'),
                                        _docRow(
                                            'Color',
                                            _vehicle!['color'] ?? '—'),
                                        _docRow(
                                            'Plate',
                                            _vehicle!['license_plate'] ??
                                                '—'),
                                        _docRow(
                                            'Status',
                                            _vehicle![
                                                    'verification_status'] ??
                                                '—'),
                                        if (_resolvedUrls['vehicle_reg'] !=
                                            null)
                                          _photoRow('Registration',
                                              _resolvedUrls['vehicle_reg']!),
                                      ]),
                            const SizedBox(height: 14),
                            _docSection(
                                'Insurance',
                                Icons.shield_rounded,
                                _insurance == null
                                    ? [_docRow('Status', 'Not submitted')]
                                    : [
                                        _docRow(
                                            'Provider',
                                            _insurance![
                                                    'insurance_provider'] ??
                                                '—'),
                                        _docRow(
                                            'Policy #',
                                            _insurance!['policy_number'] ??
                                                '—'),
                                        _docRow(
                                            'Coverage',
                                            _insurance!['coverage_type'] ??
                                                '—'),
                                        _docRow(
                                            'Expires',
                                            _insurance!['expiry_date'] ??
                                                '—'),
                                        _docRow(
                                            'Status',
                                            _insurance![
                                                    'verification_status'] ??
                                                '—'),
                                        if (_resolvedUrls['insurance_doc'] !=
                                            null)
                                          _photoRow('Document',
                                              _resolvedUrls['insurance_doc']!),
                                      ]),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docSection(String title, IconData icon, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: const Color(0xFF6366F1)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: List.generate(rows.length, (i) {
              return Column(
                children: [
                  rows[i],
                  if (i < rows.length - 1)
                    const Divider(height: 1, indent: 16),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _docRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoRow(String label, String url) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'Unable to load image',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  ),
                ),
              ),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('Open full size', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6366F1),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
