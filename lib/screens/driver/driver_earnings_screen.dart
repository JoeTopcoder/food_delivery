import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/driver_model.dart';
import '../../models/order_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/auth_provider.dart';
import '../shared/bank_info_screen.dart';
import '../shared/payout_request_screen.dart';
import '../../utils/friendly_error.dart';
import 'package:food_driver/config/app_constants.dart';
import '../../core/utils/responsive.dart';

class DriverEarningsScreen extends ConsumerStatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  ConsumerState<DriverEarningsScreen> createState() =>
      _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends ConsumerState<DriverEarningsScreen> {
  // Cache last-known good values so the UI never flashes blank on refresh
  Driver? _lastDriver;
  List<Order>? _lastDeliveries;

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    if (currentUserId == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: Center(
          child: Text('Not signed in', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final driverAsync = ref.watch(driverProfileProvider(currentUserId));
    final driver = driverAsync.valueOrNull ?? _lastDriver;
    if (driverAsync.hasValue && driverAsync.valueOrNull != null) {
      _lastDriver = driverAsync.valueOrNull;
    }

    // Show loading only on very first load when we have no cached data
    if (driver == null) {
      if (driverAsync.hasError) {
        return Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          body: Center(
            child: Text(
              friendlyError(driverAsync.error),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
      return Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    // Activate realtime updates
    ref.watch(driverEarningsRealtimeProvider(driver.id));

    final historyAsync = ref.watch(deliveryHistoryProvider(driver.id));
    final deliveries = historyAsync.valueOrNull ?? _lastDeliveries ?? [];
    if (historyAsync.hasValue) {
      _lastDeliveries = historyAsync.valueOrNull;
    }
    final isRefreshing = driverAsync.isLoading || historyAsync.isLoading;

    final now = DateTime.now();
    final thisWeek = deliveries
        .where(
          (d) => d.orderedAt.isAfter(now.subtract(const Duration(days: 7))),
        )
        .toList();
    final thisMonth = deliveries
        .where(
          (d) => d.orderedAt.isAfter(now.subtract(const Duration(days: 30))),
        )
        .toList();

    double earningsFor(List<Order> orders) {
      double total = 0;
      for (final d in orders) {
        total += (d.deliveryFee) * AppConstants.driverPayPercent;
        total += d.driverTip ?? 0.0;
      }
      return total;
    }

    // Use server-calculated total (updates in real-time via driver profile)
    final totalEarnings = driver.totalEarnings ?? earningsFor(deliveries);
    final weekEarnings = earningsFor(thisWeek);
    final monthEarnings = earningsFor(thisMonth);
    final totalTips = deliveries.fold<double>(
      0.0,
      (s, d) => s + (d.driverTip ?? 0.0),
    );
    final avgRating = driver.rating ?? 0.0;
    final cashFloat = driver.cashFloat ?? 0.0;
    final totalPaidOut = driver.totalPaidOut ?? 0.0;
    final completedCount = driver.completedDeliveries ?? deliveries.length;
    final availableBalance = (totalEarnings - totalPaidOut).clamp(
      0.0,
      double.infinity,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF0F1117),
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text(
              'My Earnings',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 22,
                ),
                tooltip: 'Instant Payout',
                onPressed: () => Navigator.pushNamed(context, '/driver-wallet'),
              ),
              if (isRefreshing)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 22),
                  onPressed: () {
                    ref.invalidate(driverProfileProvider(currentUserId));
                    ref.invalidate(deliveryHistoryProvider(driver.id));
                  },
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context), 8, Responsive.horizontalPadding(context), 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero earnings card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.primaryColor, Color(0xFFFF8C5A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Available Balance',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${AppConstants.currencySymbol}${availableBalance.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (totalPaidOut > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Total earned: ${AppConstants.currencySymbol}${totalEarnings.toStringAsFixed(2)}  •  Paid out: ${AppConstants.currencySymbol}${totalPaidOut.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _EarnChip(
                              label: 'This Week',
                              value:
                                  '${AppConstants.currencySymbol}${weekEarnings.toStringAsFixed(2)}',
                            ),
                            const SizedBox(width: 10),
                            _EarnChip(
                              label: 'This Month',
                              value:
                                  '${AppConstants.currencySymbol}${monthEarnings.toStringAsFixed(2)}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Stats row
                  Row(
                    children: [
                      Expanded(
                        child: _StatBox(
                          label: 'Deliveries',
                          value: completedCount.toString(),
                          icon: Icons.local_shipping_rounded,
                          color: const Color(0xFF6366F1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatBox(
                          label: 'Rating',
                          value: avgRating.toStringAsFixed(1),
                          icon: Icons.star_rounded,
                          color: const Color(0xFFFBBF24),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatBox(
                          label: 'Tips',
                          value:
                              '${AppConstants.currencySymbol}${totalTips.toStringAsFixed(2)}',
                          icon: Icons.volunteer_activism_rounded,
                          color: const Color(0xFF22C55E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Cash Float card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2030),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: cashFloat > 0
                            ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                            : const Color(0xFF22C55E).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color:
                                (cashFloat > 0
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFF22C55E))
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            cashFloat > 0
                                ? Icons.account_balance_wallet_rounded
                                : Icons.check_circle_rounded,
                            color: cashFloat > 0
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF22C55E),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cash Float',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: cashFloat > 0
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFF22C55E),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                cashFloat > 0
                                    ? 'Cash collected — hand over to admin'
                                    : 'No outstanding cash float',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${AppConstants.currencySymbol}${cashFloat.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: cashFloat > 0
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF22C55E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Payout actions
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const BankInfoScreen(role: 'driver'),
                              ),
                            ),
                            icon: const Icon(Icons.account_balance, size: 18),
                            label: const Text(
                              'Bank Info',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PayoutRequestScreen(role: 'driver'),
                              ),
                            ),
                            icon: const Icon(Icons.payments_rounded, size: 18),
                            label: const Text(
                              'Request Payout',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22C55E),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Delivery Log header
                  Text(
                    'Delivery Log',
                    style: TextStyle(
                      fontSize: Responsive.headingSmall(context),
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Tips summary
                  if (totalTips > 0) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFBBF24).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.volunteer_activism_rounded,
                            color: Color(0xFFFBBF24),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Total Tips: \$${totalTips.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFBBF24),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (deliveries.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No completed deliveries yet.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    ...deliveries.map(
                      (d) => _DeliveryRow(
                        delivery: d,
                        earning:
                            d.deliveryFee * AppConstants.driverPayPercent +
                            (d.driverTip ?? 0.0),
                        tip: d.driverTip,
                        isCash: d.paymentMethod == 'cash',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _EarnChip extends StatelessWidget {
  final String label;
  final String value;
  const _EarnChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: Responsive.headingSmall(context),
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  final dynamic delivery;
  final double earning;
  final double? tip;
  final bool isCash;
  const _DeliveryRow({
    required this.delivery,
    required this.earning,
    this.tip,
    this.isCash = false,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, h:mm a');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Color(0xFF22C55E),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order #${(delivery.id as String).substring(0, 8).toUpperCase()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                Text(
                  fmt.format(delivery.orderedAt as DateTime),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${AppConstants.currencySymbol}${earning.toStringAsFixed(2)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: Responsive.headingSmall(context),
                  color: const Color(0xFF22C55E),
                ),
              ),
              if (isCash)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'CASH',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFBBF24),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
