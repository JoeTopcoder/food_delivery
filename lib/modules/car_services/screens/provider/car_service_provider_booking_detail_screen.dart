import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/index.dart';
import '../../providers/car_services_providers.dart';
import 'package:food_driver/utils/app_logger.dart';

const _kBlue = Color(0xFF1D4ED8);
const _kBlueDark = Color(0xFF1E3A8A);
const _kBg = Color(0xFFF8FAFC);

class CarServiceProviderBookingDetailScreen extends ConsumerStatefulWidget {
  final CarServiceBooking booking;

  const CarServiceProviderBookingDetailScreen({
    super.key,
    required this.booking,
  });

  @override
  ConsumerState<CarServiceProviderBookingDetailScreen> createState() =>
      _State();
}

class _State extends ConsumerState<CarServiceProviderBookingDetailScreen> {
  late CarServiceBooking _booking;
  bool _isLoading = false;
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
    _notesCtrl.text = _booking.providerNotes ?? '';
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String dbStatus, {String? notes}) async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(carServicesServiceProvider);
      await service.updateBookingStatus(
        _booking.id,
        dbStatus,
        notes: notes?.isNotEmpty == true ? notes : null,
      );
      final updated = await service.getBookingById(_booking.id);
      if (!mounted) return;
      if (updated != null) setState(() => _booking = updated);
      _snack('Status updated successfully', error: false);
    } catch (e) {
      AppLogger.error('updateBookingStatus error', e);
      if (mounted) _snack('Failed to update: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelBooking() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _CancelDialog(),
    );
    if (reason == null) return;
    await _updateStatus('cancelled', notes: reason);
  }

  void _snack(String msg, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : const Color(0xFF059669),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final status = _booking.status;
    final time =
        DateFormat('EEEE, MMMM d, y · h:mm a').format(_booking.scheduledAt);
    final isClosed = status == CarServiceBookingStatus.completed ||
        status == CarServiceBookingStatus.cancelled ||
        status == CarServiceBookingStatus.noShow;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text('Booking #${_booking.bookingNumber}'),
        backgroundColor: _kBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_booking.canBeCancelled)
            TextButton(
              onPressed: _isLoading ? null : _cancelBooking,
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status badge ────────────────────────────────────────────────
            _StatusBanner(status: status),
            const SizedBox(height: 14),

            // ── Service details ─────────────────────────────────────────────
            _SectionCard(
              title: 'Service Details',
              icon: Icons.local_car_wash_rounded,
              children: [
                _Row(label: 'Service',
                    value: _booking.offering?.name ?? 'N/A'),
                _Row(label: 'Category',
                    value: _booking.offering?.category?.name ?? 'N/A'),
                _Row(label: 'Duration',
                    value: '${_booking.offering?.durationMinutes ?? 0} min'),
                _Row(label: 'Scheduled', value: time),
                _Row(label: 'Address', value: _booking.serviceAddress),
              ],
            ),
            const SizedBox(height: 12),

            // ── Vehicle ──────────────────────────────────────────────────────
            if (_hasVehicle) ...[
              _SectionCard(
                title: 'Vehicle',
                icon: Icons.directions_car_rounded,
                children: [
                  if (_booking.vehicleMake != null)
                    _Row(label: 'Make', value: _booking.vehicleMake!),
                  if (_booking.vehicleModel != null)
                    _Row(label: 'Type', value: _booking.vehicleModel!),
                  if (_booking.vehicleColor != null)
                    _Row(label: 'Color', value: _booking.vehicleColor!),
                  if (_booking.vehiclePlate != null)
                    _Row(label: 'Plate', value: _booking.vehiclePlate!),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // ── Payment ──────────────────────────────────────────────────────
            _SectionCard(
              title: 'Payment',
              icon: Icons.payments_rounded,
              children: [
                _Row(label: 'Subtotal',
                    value: '\$${_booking.subtotal.toStringAsFixed(2)}'),
                _Row(label: 'Platform Fee',
                    value: '\$${_booking.platformFee.toStringAsFixed(2)}'),
                _Row(label: 'Service Fee',
                    value: '\$${_booking.serviceFee.toStringAsFixed(2)}'),
                Divider(height: 14, color: Colors.grey.shade100),
                _Row(
                  label: 'Total',
                  value: '\$${_booking.totalAmount.toStringAsFixed(2)}',
                  bold: true,
                ),
                _Row(
                  label: 'You Earn',
                  value:
                      '\$${(_booking.subtotal * 0.80).toStringAsFixed(2)}',
                  bold: true,
                  valueColor: const Color(0xFF059669),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Notes ────────────────────────────────────────────────────────
            _SectionCard(
              title: 'Notes',
              icon: Icons.note_alt_rounded,
              children: [
                if (_booking.customerNotes?.isNotEmpty == true) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Customer Note',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500)),
                        const SizedBox(height: 3),
                        Text(_booking.customerNotes!,
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _notesCtrl,
                  decoration: InputDecoration(
                    hintText: 'Add your notes here…',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: _kBlue, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Action buttons ───────────────────────────────────────────────
            if (isClosed)
              Center(
                child: Text(
                  'This booking is closed.',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              )
            else
              _buildActions(status),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  bool get _hasVehicle =>
      _booking.vehicleMake != null ||
      _booking.vehicleModel != null ||
      _booking.vehicleColor != null ||
      _booking.vehiclePlate != null;

  Widget _buildActions(CarServiceBookingStatus status) {
    _ActionDef? primary;

    switch (status) {
      case CarServiceBookingStatus.pending:
        primary = _ActionDef(
          'Accept Booking',
          'confirmed',
          Icons.check_circle_rounded,
          _kBlue,
        );
        break;
      case CarServiceBookingStatus.confirmed:
        primary = _ActionDef(
          "I'm On My Way",
          'provider_en_route',
          Icons.directions_car_rounded,
          const Color(0xFF0891B2),
        );
        break;
      case CarServiceBookingStatus.providerEnRoute:
        primary = _ActionDef(
          "I've Arrived",
          'arrived',
          Icons.location_on_rounded,
          _kBlue,
        );
        break;
      case CarServiceBookingStatus.arrived:
        primary = _ActionDef(
          'Start Service',
          'in_progress',
          Icons.play_circle_rounded,
          const Color(0xFF7C3AED),
        );
        break;
      case CarServiceBookingStatus.inProgress:
        primary = _ActionDef(
          'Complete Service',
          'completed',
          Icons.task_alt_rounded,
          const Color(0xFF059669),
        );
        break;
      default:
        break;
    }

    if (primary == null) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isLoading
            ? null
            : () => _updateStatus(primary!.dbStatus,
                notes: _notesCtrl.text),
        icon: _isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : Icon(primary.icon, size: 20),
        label: Text(primary.label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: primary.color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _ActionDef {
  final String label;
  final String dbStatus;
  final IconData icon;
  final Color color;
  const _ActionDef(this.label, this.dbStatus, this.icon, this.color);
}

// ── Widgets ────────────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final CarServiceBookingStatus status;
  const _StatusBanner({required this.status});

  (Color, Color) get _colors {
    switch (status) {
      case CarServiceBookingStatus.pending:
        return (const Color(0xFFFEF3C7), const Color(0xFF92400E));
      case CarServiceBookingStatus.confirmed:
        return (const Color(0xFFEFF6FF), _kBlue);
      case CarServiceBookingStatus.providerEnRoute:
        return (const Color(0xFFE0F2FE), const Color(0xFF0891B2));
      case CarServiceBookingStatus.arrived:
      case CarServiceBookingStatus.inProgress:
        return (const Color(0xFFEDE9FE), const Color(0xFF7C3AED));
      case CarServiceBookingStatus.completed:
        return (const Color(0xFFDCFCE7), const Color(0xFF166534));
      case CarServiceBookingStatus.cancelled:
        return (const Color(0xFFFEE2E2), Colors.red);
      default:
        return (const Color(0xFFF1F5F9), Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: fg, size: 18),
          const SizedBox(width: 10),
          Text(
            status.toDisplayString(),
            style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _kBlue, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF0F172A)),
              ),
            ],
          ),
          Divider(height: 16, color: Colors.grey.shade100),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const _Row({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                  color: Colors.grey.shade500, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: valueColor ?? const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CancelDialog extends StatefulWidget {
  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel Booking'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Please provide a reason:'),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              hintText: 'Reason for cancellation',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep Booking'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('Yes, Cancel'),
        ),
      ],
    );
  }
}
