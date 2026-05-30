import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/modules/car_services/models/car_service_booking.dart';
import 'package:food_driver/modules/car_services/providers/car_services_providers.dart';
import 'package:food_driver/config/supabase_config.dart';
import 'package:food_driver/providers/wallet_provider.dart';
import 'package:intl/intl.dart';

const _kBlue     = Color(0xFF1D4ED8);
const _kBlueDark = Color(0xFF1E3A8A);

class CarServiceHistoryScreen extends ConsumerStatefulWidget {
  const CarServiceHistoryScreen({super.key});

  @override
  ConsumerState<CarServiceHistoryScreen> createState() =>
      _CarServiceHistoryScreenState();
}

class _CarServiceHistoryScreenState
    extends ConsumerState<CarServiceHistoryScreen> {
  _Filter _filter = _Filter.active;

  static const _activeStatuses = {
    CarServiceBookingStatus.pending,
    CarServiceBookingStatus.confirmed,
    CarServiceBookingStatus.providerEnRoute,
    CarServiceBookingStatus.arrived,
    CarServiceBookingStatus.inProgress,
  };

  List<CarServiceBooking> _apply(List<CarServiceBooking> all) {
    switch (_filter) {
      case _Filter.active:
        return all.where((b) => _activeStatuses.contains(b.status)).toList();
      case _Filter.completed:
        return all.where((b) => b.status == CarServiceBookingStatus.completed).toList();
      case _Filter.cancelled:
        return all.where((b) =>
            b.status == CarServiceBookingStatus.cancelled ||
            b.status == CarServiceBookingStatus.noShow).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(myCarServiceBookingsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 110,
            pinned: true,
            backgroundColor: _kBlueDark,
            foregroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kBlueDark, _kBlue],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Service History',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Your past car care bookings',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          bookingsAsync.when(
            loading: () => SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, __) => const _HistoryCardSkeleton(),
                childCount: 4,
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  Icon(Icons.wifi_off_rounded, size: 48, color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  Text('Could not load history',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.invalidate(myCarServiceBookingsProvider),
                    child: const Text('Retry'),
                  ),
                ]),
              ),
            ),
            data: (all) {
              final filtered = _apply(all);
              final active = all.where((b) => _activeStatuses.contains(b.status)).toList();
              final completed = all.where((b) => b.status == CarServiceBookingStatus.completed).toList();

              return SliverMainAxisGroup(slivers: [
                // Summary strip
                SliverToBoxAdapter(
                  child: _SummaryStrip(
                    activeCount: active.length,
                    completedCount: completed.length,
                  ),
                ),

                // Filter chips
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(children: [
                      _FilterChip(label: 'Active', filter: _Filter.active, current: _filter, onTap: (f) => setState(() => _filter = f)),
                      const SizedBox(width: 8),
                      _FilterChip(label: 'Completed', filter: _Filter.completed, current: _filter, onTap: (f) => setState(() => _filter = f)),
                      const SizedBox(width: 8),
                      _FilterChip(label: 'Cancelled', filter: _Filter.cancelled, current: _filter, onTap: (f) => setState(() => _filter = f)),
                    ]),
                  ),
                ),

                // List
                if (filtered.isEmpty)
                  SliverToBoxAdapter(child: _EmptyState(filter: _filter))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _HistoryCard(
                          booking: filtered[i],
                          onBookAgain: () => Navigator.pushNamed(
                            context,
                            '/car-services',
                          ),
                          onViewDetail: () => _showDetail(context, filtered[i]),
                          onCancel: filtered[i].canBeCancelled
                              ? () => _cancelBooking(context, ref, filtered[i])
                              : null,
                        ),
                        childCount: filtered.length,
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, CarServiceBooking booking) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BookingDetailSheet(booking: booking),
    );
  }

  Future<void> _cancelBooking(BuildContext context, WidgetRef ref, CarServiceBooking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Booking', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (!confirmed) return;

    try {
      final svc = ref.read(carServicesServiceProvider);

      // Fetch fresh booking data to avoid stale cache
      final freshRow = await SupabaseConfig.client
          .from('car_service_bookings')
          .select('payment_method, payment_status, total_amount')
          .eq('id', booking.id)
          .single();

      await svc.updateBookingStatus(booking.id, 'cancelled');

      bool walletRefunded = false;
      if (freshRow['payment_method'] == 'wallet' &&
          freshRow['payment_status'] == 'paid') {
        final userId = SupabaseConfig.client.auth.currentUser?.id;
        final amount = (freshRow['total_amount'] as num?)?.toDouble() ?? booking.totalAmount;
        if (userId != null) {
          await SupabaseConfig.client.rpc('wallet_credit', params: {
            'p_user_id':     userId,
            'p_amount':      amount,
            'p_description': 'Refund: car service booking #${booking.bookingNumber}',
          });
          walletRefunded = true;
          ref.read(walletNotifierProvider.notifier).refresh();
        }
      }

      ref.invalidate(myCarServiceBookingsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(walletRefunded
              ? 'Booking cancelled. Refund sent to your wallet.'
              : 'Booking cancelled.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

enum _Filter { active, completed, cancelled }

// ── Summary strip ──────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final int activeCount;
  final int completedCount;
  const _SummaryStrip({required this.activeCount, required this.completedCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kBlueDark, _kBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Active', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                '$activeCount',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ]),
          ),
          Container(width: 1, height: 40, color: Colors.white24),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
              const Text('Completed', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                '$completedCount',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final _Filter filter;
  final _Filter current;
  final void Function(_Filter) onTap;
  const _FilterChip({required this.label, required this.filter, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = filter == current;
    return GestureDetector(
      onTap: () => onTap(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _kBlue : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _kBlue : Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

// ── History card ───────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final CarServiceBooking booking;
  final VoidCallback onBookAgain;
  final VoidCallback onViewDetail;
  final VoidCallback? onCancel;

  const _HistoryCard({
    required this.booking,
    required this.onBookAgain,
    required this.onViewDetail,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final providerName = booking.provider?.businessName ?? 'Service Provider';
    final serviceName = booking.serviceCount > 1
        ? '${booking.serviceCount} services'
        : (booking.offering?.name ?? 'Car Service');
    final dateStr = DateFormat('EEE, MMM d, y').format(booking.scheduledAt);
    final timeStr = DateFormat('h:mm a').format(booking.scheduledAt);
    final isCompleted = booking.status == CarServiceBookingStatus.completed;
    final (statusColor, statusBg, statusLabel) = _statusStyle(booking.status, context);

    return GestureDetector(
      onTap: onViewDetail,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Top row: provider + status
            Row(children: [
              // Provider avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    providerName.isNotEmpty ? providerName[0].toUpperCase() : 'P',
                    style: const TextStyle(color: _kBlue, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    providerName,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    serviceName,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),

            const SizedBox(height: 12),
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 10),

            // Date / vehicle
            Row(children: [
              Icon(Icons.calendar_today_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('$dateStr · $timeStr', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),

            if (_vehicleLabel(booking).isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.directions_car_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(_vehicleLabel(booking), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                ),
              ]),
            ],

            const SizedBox(height: 12),

            // Bottom row: total + actions
            Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total Paid', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text(
                  '\$${booking.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kBlue),
                ),
              ]),
              const Spacer(),
              TextButton(
                onPressed: onViewDetail,
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant, padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: const Text('Details', style: TextStyle(fontSize: 13)),
              ),
              if (isCompleted) ...[
                const SizedBox(width: 6),
                SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    onPressed: onBookAgain,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: const Text('Book Again', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
              if (onCancel != null) ...[
                const SizedBox(width: 6),
                SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  String _vehicleLabel(CarServiceBooking b) {
    if (b.vehicleCount > 1) return '${b.vehicleCount} vehicles';
    return [b.vehicleMake, b.vehicleModel]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' ');
  }

  (Color, Color, String) _statusStyle(CarServiceBookingStatus status, BuildContext context) {
    switch (status) {
      case CarServiceBookingStatus.completed:
        return (const Color(0xFF065F46), const Color(0xFFD1FAE5), 'Completed');
      case CarServiceBookingStatus.cancelled:
        return (const Color(0xFF7F1D1D), const Color(0xFFFEE2E2), 'Cancelled');
      case CarServiceBookingStatus.noShow:
        return (const Color(0xFF78350F), const Color(0xFFFEF3C7), 'No Show');
      default:
        return (_kBlue, _kBlue.withValues(alpha: 0.1), status.toDisplayString());
    }
  }
}

// ── Booking detail bottom sheet ────────────────────────────────────────────────

class _BookingDetailSheet extends StatelessWidget {
  final CarServiceBooking booking;
  const _BookingDetailSheet({required this.booking});

  @override
  Widget build(BuildContext context) {
    final providerName = booking.provider?.businessName ?? 'Service Provider';
    final serviceName = booking.serviceCount > 1
        ? '${booking.serviceCount} services'
        : (booking.offering?.name ?? 'Car Service');
    final scheduledStr = DateFormat('EEE, MMM d, y · h:mm a').format(booking.scheduledAt);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: _kBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Center(
                  child: Text(
                    providerName.isNotEmpty ? providerName[0].toUpperCase() : 'P',
                    style: const TextStyle(color: _kBlue, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(providerName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                Text('Booking #${booking.bookingNumber}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ])),
              _StatusBadge(status: booking.status),
            ]),
          ),
          const SizedBox(height: 16),
          Divider(color: Theme.of(context).colorScheme.outlineVariant, height: 1),

          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(20),
              children: [
                // Details section
                _SheetSection(title: 'Booking Details', rows: [
                  _SheetRow(icon: Icons.build_circle_outlined, label: 'Service', value: serviceName),
                  _SheetRow(icon: Icons.calendar_today_outlined, label: 'Scheduled', value: scheduledStr),
                  _SheetRow(icon: Icons.location_on_outlined, label: 'Location', value: booking.serviceAddress),
                  if ((booking.vehicleMake ?? '').isNotEmpty || booking.vehicleCount > 1)
                    _SheetRow(
                      icon: Icons.directions_car_outlined,
                      label: 'Vehicle',
                      value: booking.vehicleCount > 1
                          ? '${booking.vehicleCount} vehicles'
                          : [booking.vehicleMake, booking.vehicleModel].whereType<String>().where((s) => s.isNotEmpty).join(' '),
                    ),
                  if ((booking.vehiclePlate ?? '').isNotEmpty)
                    _SheetRow(icon: Icons.badge_outlined, label: 'Plate', value: booking.vehiclePlate!),
                ]),

                const SizedBox(height: 16),

                // Price breakdown
                _SheetSection(title: 'Price Breakdown', rows: [
                  _SheetRow(icon: Icons.receipt_outlined, label: 'Subtotal', value: '\$${booking.subtotal.toStringAsFixed(2)}'),
                  if (booking.mobileFee > 0)
                    _SheetRow(icon: Icons.delivery_dining, label: 'Mobile Fee', value: '\$${booking.mobileFee.toStringAsFixed(2)}'),
                  _SheetRow(icon: Icons.percent_rounded, label: 'Platform Fee', value: '\$${booking.platformFee.toStringAsFixed(2)}'),
                  _SheetRow(icon: Icons.miscellaneous_services_outlined, label: 'Service Fee', value: '\$${booking.serviceFee.toStringAsFixed(2)}'),
                ]),

                // Total
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBlue.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Paid', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kBlue)),
                      Text('\$${booking.totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _kBlue)),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Book again button
                if (booking.status == CarServiceBookingStatus.completed)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/car-services');
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Book Again', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _SheetSection extends StatelessWidget {
  final String title;
  final List<_SheetRow> rows;
  const _SheetSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kBlue)),
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        ...rows.asMap().entries.map((e) => Column(children: [
          e.value,
          if (e.key < rows.length - 1)
            Divider(height: 1, indent: 44, color: Theme.of(context).colorScheme.outlineVariant),
        ])),
      ]),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SheetRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: _kBlue),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
        ])),
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final CarServiceBookingStatus status;
  const _StatusBadge({required this.status});

  (Color, Color) get _colors {
    switch (status) {
      case CarServiceBookingStatus.completed:
        return (const Color(0xFF065F46), const Color(0xFFD1FAE5));
      case CarServiceBookingStatus.cancelled:
        return (const Color(0xFF7F1D1D), const Color(0xFFFEE2E2));
      case CarServiceBookingStatus.noShow:
        return (const Color(0xFF78350F), const Color(0xFFFEF3C7));
      default:
        return (_kBlue, const Color(0xFFEFF6FF));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status.toDisplayString(), style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final _Filter filter;
  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final msg = filter == _Filter.active
        ? 'No active bookings'
        : filter == _Filter.completed
            ? 'No completed bookings'
            : 'No cancelled bookings';

    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(children: [
        Icon(Icons.history_rounded, size: 64, color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(height: 16),
        Text(msg, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 8),
        Text('Your bookings will appear here.',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

// ── Skeleton ───────────────────────────────────────────────────────────────────

class _HistoryCardSkeleton extends StatelessWidget {
  const _HistoryCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final shade = Theme.of(context).colorScheme.surfaceContainerHighest;
    final base = Theme.of(context).colorScheme.surfaceContainerLow;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: shade, borderRadius: BorderRadius.circular(10))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 14, width: 140, decoration: BoxDecoration(color: shade, borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 6),
            Container(height: 11, width: 100, decoration: BoxDecoration(color: shade, borderRadius: BorderRadius.circular(6))),
          ])),
          Container(height: 22, width: 72, decoration: BoxDecoration(color: shade, borderRadius: BorderRadius.circular(20))),
        ]),
        const SizedBox(height: 12),
        Container(height: 1, color: shade),
        const SizedBox(height: 10),
        Container(height: 11, width: double.infinity, decoration: BoxDecoration(color: shade, borderRadius: BorderRadius.circular(6))),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(height: 20, width: 80, decoration: BoxDecoration(color: shade, borderRadius: BorderRadius.circular(6))),
          Container(height: 34, width: 100, decoration: BoxDecoration(color: shade, borderRadius: BorderRadius.circular(8))),
        ]),
      ]),
    );
  }
}
