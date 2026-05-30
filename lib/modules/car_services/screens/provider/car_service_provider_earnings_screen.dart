import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:food_driver/core/utils/responsive.dart';
import 'package:food_driver/modules/car_services/models/index.dart';
import 'package:food_driver/modules/car_services/providers/car_services_providers.dart';

const _kPurple = Color(0xFF7C3AED);
const _platformFeeRate = 0.20;

class CarServiceProviderEarningsScreen extends ConsumerStatefulWidget {
  const CarServiceProviderEarningsScreen({super.key});

  @override
  ConsumerState<CarServiceProviderEarningsScreen> createState() =>
      _CarServiceProviderEarningsScreenState();
}

class _CarServiceProviderEarningsScreenState
    extends ConsumerState<CarServiceProviderEarningsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String get _providerId =>
      ModalRoute.of(context)!.settings.arguments as String? ?? '';

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

  List<CarServiceBooking> _filterByPeriod(
      List<CarServiceBooking> all, bool thisWeek) {
    final now = DateTime.now();
    final cutoff = thisWeek
        ? now.subtract(Duration(days: now.weekday))
        : DateTime(now.year, now.month, 1);
    return all
        .where((b) =>
            b.status == CarServiceBookingStatus.completed &&
            b.completedAt != null &&
            b.completedAt!.isAfter(cutoff))
        .toList();
  }

  double _netEarning(CarServiceBooking b) =>
      b.subtotal - (b.subtotal * _platformFeeRate);

  @override
  Widget build(BuildContext context) {
    final hp = Responsive.horizontalPadding(context);
    final bookingsAsync =
        ref.watch(providerBookingsProvider(_providerId));
    final currency = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        backgroundColor: _kPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: 'This Week'), Tab(text: 'This Month')],
        ),
      ),
      body: bookingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          return TabBarView(
            controller: _tabController,
            children: [
              _EarningsTab(
                bookings: _filterByPeriod(all, true),
                netEarning: _netEarning,
                currency: currency,
                hp: hp,
                providerId: _providerId,
              ),
              _EarningsTab(
                bookings: _filterByPeriod(all, false),
                netEarning: _netEarning,
                currency: currency,
                hp: hp,
                providerId: _providerId,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EarningsTab extends StatelessWidget {
  final List<CarServiceBooking> bookings;
  final double Function(CarServiceBooking) netEarning;
  final NumberFormat currency;
  final double hp;
  final String providerId;

  const _EarningsTab({
    required this.bookings,
    required this.netEarning,
    required this.currency,
    required this.hp,
    required this.providerId,
  });

  @override
  Widget build(BuildContext context) {
    final totalNet = bookings.fold(0.0, (s, b) => s + netEarning(b));
    final totalGross = bookings.fold(0.0, (s, b) => s + b.subtotal);

    return RefreshIndicator(
      onRefresh: () async {},
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 20, hp, 8),
              child: Card(
                color: _kPurple,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text('Net Earnings',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        currency.format(totalNet),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _StatChip(
                              label: 'Jobs',
                              value: '${bookings.length}')),
                          Expanded(child: _StatChip(
                              label: 'Gross',
                              value: currency.format(totalGross))),
                          Expanded(child: _StatChip(
                              label: 'Platform Fee',
                              value: currency.format(
                                  totalGross * _platformFeeRate))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (bookings.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No completed jobs this period',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: hp),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final b = bookings[i];
                    final gross = b.subtotal;
                    final fee = gross * _platformFeeRate;
                    final net = gross - fee;
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 4),
                      title: Text(b.offering?.name ?? 'Service',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        b.completedAt != null
                            ? DateFormat('MMM d, h:mm a')
                                .format(b.completedAt!)
                            : '',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            currency.format(net),
                            style: const TextStyle(
                                color: _kPurple,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '−${currency.format(fee)} fee',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                  childCount: bookings.length,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 12, hp, 32),
              child: OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Stripe payouts — coming soon!')),
                  );
                },
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Request Payout'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: _kPurple,
                    side: const BorderSide(color: _kPurple),
                    minimumSize: const Size(double.infinity, 48)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
        Text(label,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}
