import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/index.dart';
import '../../providers/car_services_providers.dart';
import 'package:food_driver/utils/app_logger.dart';

const _kBlue = Color(0xFF1D4ED8);
const _kBlueDark = Color(0xFF1E3A8A);
const _kBg = Color(0xFFF8FAFC);
const _kAmber = Color(0xFFF59E0B);

class CarServiceProviderBookingsScreen extends ConsumerStatefulWidget {
  const CarServiceProviderBookingsScreen({super.key});

  @override
  ConsumerState<CarServiceProviderBookingsScreen> createState() =>
      _CarServiceProviderBookingsScreenState();
}

class _CarServiceProviderBookingsScreenState
    extends ConsumerState<CarServiceProviderBookingsScreen>
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

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myCarServiceProviderProfileProvider);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('My Bookings'),
        backgroundColor: _kBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'New'),
            Tab(text: 'Upcoming'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _kBlue)),
        error: (e, _) {
          AppLogger.error('Bookings screen profile error', e);
          return Center(child: Text('Error: $e'));
        },
        data: (provider) {
          if (provider == null) {
            return const Center(child: Text('No provider profile found.'));
          }
          final bookingsAsync =
              ref.watch(providerBookingsProvider(provider.id));

          return bookingsAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: _kBlue)),
            error: (e, _) {
              AppLogger.error('Bookings load error', e);
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text('Failed to load bookings.\n$e',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref
                          .invalidate(providerBookingsProvider(provider.id)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            },
            data: (bookings) {
              final newBookings = bookings
                  .where((b) =>
                      b.status == CarServiceBookingStatus.pending)
                  .toList();
              final upcoming = bookings
                  .where((b) =>
                      b.status == CarServiceBookingStatus.confirmed ||
                      b.status == CarServiceBookingStatus.providerEnRoute ||
                      b.status == CarServiceBookingStatus.arrived ||
                      b.status == CarServiceBookingStatus.inProgress)
                  .toList();
              final completed = bookings
                  .where((b) =>
                      b.status == CarServiceBookingStatus.completed ||
                      b.status == CarServiceBookingStatus.cancelled ||
                      b.status == CarServiceBookingStatus.noShow)
                  .toList();

              return TabBarView(
                controller: _tabController,
                children: [
                  _NewBookingsList(
                      bookings: newBookings, providerId: provider.id),
                  _StandardBookingsList(
                      bookings: upcoming, providerId: provider.id),
                  _StandardBookingsList(
                      bookings: completed, providerId: provider.id),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ── New bookings list (with Reject/Accept) ─────────────────────────────────────

class _NewBookingsList extends ConsumerWidget {
  final List<CarServiceBooking> bookings;
  final String providerId;

  const _NewBookingsList(
      {required this.bookings, required this.providerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bookings.isEmpty) {
      return const _EmptyState(
        icon: Icons.inbox_outlined,
        message: 'No new booking requests',
      );
    }

    return RefreshIndicator(
      color: _kBlue,
      onRefresh: () async =>
          ref.invalidate(providerBookingsProvider(providerId)),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: bookings.length,
        itemBuilder: (ctx, i) =>
            _NewBookingCard(booking: bookings[i], providerId: providerId),
      ),
    );
  }
}

class _NewBookingCard extends ConsumerStatefulWidget {
  final CarServiceBooking booking;
  final String providerId;

  const _NewBookingCard(
      {required this.booking, required this.providerId});

  @override
  ConsumerState<_NewBookingCard> createState() => _NewBookingCardState();
}

class _NewBookingCardState extends ConsumerState<_NewBookingCard> {
  bool _isLoading = false;

  Future<void> _updateStatus(String status) async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(carServicesServiceProvider)
          .updateBookingStatus(widget.booking.id, status);
      ref.invalidate(providerBookingsProvider(widget.providerId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final time = DateFormat('EEE, MMM d · h:mm a').format(b.scheduledAt);
    final vehicleInfo = [b.vehicleMake, b.vehicleModel, b.vehicleColor]
        .where((v) => v != null && v.isNotEmpty)
        .join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEFF6FF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Card header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _kAmber.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_car_wash_rounded,
                      color: _kAmber, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.offering?.name ?? 'Service',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '#${b.bookingNumber}',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  '\$${b.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF059669),
                  ),
                ),
              ],
            ),
          ),

          // Details
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(
              children: [
                _InfoRow(
                    icon: Icons.access_time_rounded,
                    text: time,
                    color: Colors.grey.shade600),
                if (vehicleInfo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _InfoRow(
                      icon: Icons.directions_car_rounded,
                      text: vehicleInfo,
                      color: Colors.grey.shade600),
                ],
                const SizedBox(height: 4),
                _InfoRow(
                    icon: Icons.location_on_rounded,
                    text: b.serviceAddress,
                    color: Colors.grey.shade600),
              ],
            ),
          ),

          Divider(
              height: 20,
              color: Colors.grey.shade100,
              indent: 14,
              endIndent: 14),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: CircularProgressIndicator(
                          color: _kBlue, strokeWidth: 2),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _updateStatus('cancelled'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(
                                color: Color(0xFFFCA5A5)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Reject',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => _updateStatus('confirmed'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Accept',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Standard bookings list ─────────────────────────────────────────────────────

class _StandardBookingsList extends ConsumerWidget {
  final List<CarServiceBooking> bookings;
  final String providerId;

  const _StandardBookingsList(
      {required this.bookings, required this.providerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bookings.isEmpty) {
      return const _EmptyState(
        icon: Icons.inbox_outlined,
        message: 'No bookings in this category',
      );
    }

    return RefreshIndicator(
      color: _kBlue,
      onRefresh: () async =>
          ref.invalidate(providerBookingsProvider(providerId)),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: bookings.length,
        itemBuilder: (ctx, i) => _StandardBookingCard(booking: bookings[i]),
      ),
    );
  }
}

class _StandardBookingCard extends StatelessWidget {
  final CarServiceBooking booking;
  const _StandardBookingCard({required this.booking});

  Color get _statusColor {
    switch (booking.status) {
      case CarServiceBookingStatus.confirmed:
        return _kBlue;
      case CarServiceBookingStatus.providerEnRoute:
        return const Color(0xFF0891B2);
      case CarServiceBookingStatus.arrived:
      case CarServiceBookingStatus.inProgress:
        return const Color(0xFF7C3AED);
      case CarServiceBookingStatus.completed:
        return const Color(0xFF059669);
      case CarServiceBookingStatus.cancelled:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final time =
        DateFormat('EEE, MMM d · h:mm a').format(booking.scheduledAt);
    final color = _statusColor;

    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(
        '/car-services/provider/booking-detail',
        arguments: booking,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.local_car_wash_rounded,
                  color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.offering?.name ?? 'Service',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    time,
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    booking.status.toDisplayString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${booking.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF059669)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared ─────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(
                  color: Colors.grey.shade500, fontSize: 15)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoRow(
      {required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
