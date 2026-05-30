import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:food_driver/core/utils/responsive.dart';
import 'package:food_driver/modules/car_services/models/index.dart';
import 'package:food_driver/modules/car_services/providers/car_services_providers.dart';

const _kPurple = Color(0xFF7C3AED);

class CarServiceMyBookingsScreen extends ConsumerStatefulWidget {
  const CarServiceMyBookingsScreen({super.key});

  @override
  ConsumerState<CarServiceMyBookingsScreen> createState() =>
      _CarServiceMyBookingsScreenState();
}

class _CarServiceMyBookingsScreenState
    extends ConsumerState<CarServiceMyBookingsScreen>
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

  bool _isUpcoming(CarServiceBooking b) {
    return b.status == CarServiceBookingStatus.pending ||
        b.status == CarServiceBookingStatus.confirmed ||
        b.status == CarServiceBookingStatus.providerEnRoute ||
        b.status == CarServiceBookingStatus.arrived ||
        b.status == CarServiceBookingStatus.inProgress;
  }

  Color _statusColor(CarServiceBookingStatus s) {
    switch (s) {
      case CarServiceBookingStatus.completed:
        return Colors.green;
      case CarServiceBookingStatus.cancelled:
        return Colors.red;
      case CarServiceBookingStatus.inProgress:
        return Colors.blue;
      case CarServiceBookingStatus.confirmed:
        return _kPurple;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hp = Responsive.horizontalPadding(context);
    final bookingsAsync = ref.watch(myCarServiceBookingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        backgroundColor: _kPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Service History',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.pushNamed(context, '/car-services/history'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: 'Upcoming'), Tab(text: 'Past')],
        ),
      ),
      body: bookingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          final upcoming = all.where(_isUpcoming).toList();
          final past = all.where((b) => !_isUpcoming(b)).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _BookingList(
                bookings: upcoming,
                hp: hp,
                statusColor: _statusColor,
                emptyMessage: 'No upcoming bookings',
                onRefresh: () async =>
                    ref.invalidate(myCarServiceBookingsProvider),
              ),
              _BookingList(
                bookings: past,
                hp: hp,
                statusColor: _statusColor,
                emptyMessage: 'No past bookings',
                onRefresh: () async =>
                    ref.invalidate(myCarServiceBookingsProvider),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BookingList extends StatelessWidget {
  final List<CarServiceBooking> bookings;
  final double hp;
  final Color Function(CarServiceBookingStatus) statusColor;
  final String emptyMessage;
  final Future<void> Function() onRefresh;

  const _BookingList({
    required this.bookings,
    required this.hp,
    required this.statusColor,
    required this.emptyMessage,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_car_wash,
                        size: 56,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.25)),
                    const SizedBox(height: 12),
                    Text(emptyMessage,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5))),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: hp, vertical: 12),
        itemCount: bookings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final b = bookings[i];
          final sc = statusColor(b.status);
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pushNamed(
                ctx,
                '/car-services/tracking',
                arguments: b.id,
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            b.provider?.businessName ?? 'Provider',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: sc.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            b.status.toDisplayString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: sc,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(b.offering?.name ?? 'Service',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                          DateFormat('EEE, MMM d · h:mm a')
                              .format(b.scheduledAt),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          b.bookingNumber,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
