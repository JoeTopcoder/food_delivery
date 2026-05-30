import 'package:flutter/material.dart';
import 'package:food_driver/modules/car_services/models/car_service_booking.dart';
import 'package:intl/intl.dart';

const _kBlue = Color(0xFF1D4ED8);
const _kBlueDark = Color(0xFF1E3A8A);

class CarServiceBookingSummaryScreen extends StatelessWidget {
  const CarServiceBookingSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final booking =
        ModalRoute.of(context)!.settings.arguments as CarServiceBooking;

    final providerName = booking.provider?.businessName ?? 'Service Provider';
    final scheduledStr =
        DateFormat('EEE, MMM d, y · h:mm a').format(booking.scheduledAt);

    final vehicleCount = booking.vehicleCount > 1 ? booking.vehicleCount : null;
    final serviceCount = booking.serviceCount > 1 ? booking.serviceCount : null;
    final serviceName = serviceCount != null
        ? '$serviceCount services'
        : (booking.offering?.name ?? 'Car Service');
    final vehicleLabel = vehicleCount != null
        ? '$vehicleCount vehicles'
        : [booking.vehicleMake, booking.vehicleModel]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' ');
    final vehicle = vehicleLabel;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Success header ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kBlueDark, _kBlue],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(50),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Booking Confirmed!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Booking #${booking.bookingNumber}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    _StatusChip(status: booking.status),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Booking details ──────────────────────────────────────────
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Label('Booking Details'),
                          const SizedBox(height: 12),
                          _Row(
                              icon: Icons.store_outlined,
                              label: 'Provider',
                              value: providerName),
                          _Div(),
                          _Row(
                              icon: Icons.build_circle_outlined,
                              label: 'Service',
                              value: serviceName),
                          _Div(),
                          _Row(
                              icon: Icons.calendar_today_outlined,
                              label: 'Scheduled',
                              value: scheduledStr),
                          _Div(),
                          _Row(
                              icon: Icons.location_on_outlined,
                              label: 'Location',
                              value: booking.serviceAddress),
                          if (vehicle.isNotEmpty) ...[
                            _Div(),
                            _Row(
                                icon: Icons.directions_car_outlined,
                                label: 'Vehicle',
                                value: vehicle),
                          ],
                          if (booking.vehiclePlate != null &&
                              booking.vehiclePlate!.isNotEmpty) ...[
                            _Div(),
                            _Row(
                                icon: Icons.badge_outlined,
                                label: 'Plate',
                                value: booking.vehiclePlate!),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Price breakdown ──────────────────────────────────────────
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Label('Price Breakdown'),
                          const SizedBox(height: 12),
                          _PriceRow(
                              label: 'Service Price',
                              amount: booking.subtotal),
                          const SizedBox(height: 6),
                          _PriceRow(
                              label: 'Platform Fee',
                              amount: booking.platformFee),
                          const SizedBox(height: 6),
                          _PriceRow(
                              label: 'Service Fee',
                              amount: booking.serviceFee),
                          Divider(height: 20, color: Theme.of(context).colorScheme.outlineVariant),
                          _PriceRow(
                            label: 'Total',
                            amount: booking.totalAmount,
                            isTotal: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Actions ──────────────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pushNamed(
                          context,
                          '/car-services/tracking',
                          arguments: booking.id,
                        ),
                        icon: const Icon(Icons.my_location_rounded),
                        label: const Text('Track Booking'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/car-services/my-bookings',
                          (r) =>
                              r.settings.name == '/car-services' || r.isFirst,
                        ),
                        icon: const Icon(Icons.list_alt_rounded),
                        label: const Text('My Bookings'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kBlue,
                          side: const BorderSide(color: _kBlue),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status chip ────────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final CarServiceBookingStatus status;
  const _StatusChip({required this.status});

  (Color, Color) get _colors {
    switch (status) {
      case CarServiceBookingStatus.confirmed:
      case CarServiceBookingStatus.completed:
        return (const Color(0xFFD1FAE5), const Color(0xFF065F46));
      case CarServiceBookingStatus.pending:
        return (const Color(0xFFFEF3C7), const Color(0xFF78350F));
      case CarServiceBookingStatus.cancelled:
      case CarServiceBookingStatus.noShow:
        return (const Color(0xFFFEE2E2), const Color(0xFF7F1D1D));
      default:
        return (const Color(0xFFEFF6FF), _kBlue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toDisplayString(),
        style: TextStyle(
            color: fg, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}

// ── Reusable widgets ───────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.bold, color: _kBlue),
    );
  }
}

class _Div extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 14, color: Theme.of(context).colorScheme.outlineVariant);
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Row(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: _kBlue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              Text(value,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool isTotal;

  const _PriceRow(
      {required this.label, required this.amount, this.isTotal = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 15 : 13,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        ),
        const SizedBox(width: 8),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: isTotal ? 16 : 13,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
            color: isTotal ? _kBlue : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
