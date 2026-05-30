import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:food_driver/modules/car_services/models/index.dart';
import 'package:food_driver/modules/car_services/providers/car_services_providers.dart';
import 'package:food_driver/utils/app_logger.dart';
import 'package:food_driver/config/supabase_config.dart';
import 'package:food_driver/providers/wallet_provider.dart';

const _kBlue = Color(0xFF1D4ED8);
const _kBlueDark = Color(0xFF1E3A8A);
const _kAmber = Color(0xFFF59E0B);
const _kBg = Color(0xFFF8FAFC);

class CarServiceTrackingScreen extends ConsumerStatefulWidget {
  const CarServiceTrackingScreen({super.key});

  @override
  ConsumerState<CarServiceTrackingScreen> createState() =>
      _CarServiceTrackingScreenState();
}

class _CarServiceTrackingScreenState
    extends ConsumerState<CarServiceTrackingScreen> {
  int _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _reviewSubmitted = false;
  bool _submittingReview = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitReview(String bookingId) async {
    if (_rating == 0) return;
    setState(() => _submittingReview = true);
    try {
      await ref.read(carServicesServiceProvider).submitReview(
            bookingId: bookingId,
            rating: _rating,
            comment: _commentCtrl.text.trim().isEmpty
                ? null
                : _commentCtrl.text.trim(),
          );
      setState(() => _reviewSubmitted = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Review submitted — thank you!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      AppLogger.error('Error submitting review', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _submittingReview = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingId =
        ModalRoute.of(context)!.settings.arguments as String? ?? '';
    final bookingStream = ref.watch(watchCarServiceBookingProvider(bookingId));

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Track Booking'),
        backgroundColor: _kBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: bookingStream.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _kBlue)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (booking) => _buildBody(booking),
      ),
    );
  }

  Widget _buildBody(CarServiceBooking booking) {
    final isCancelled = booking.status == CarServiceBookingStatus.cancelled ||
        booking.status == CarServiceBookingStatus.noShow;
    final isCompleted = booking.status == CarServiceBookingStatus.completed;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        children: [
          // ── Map placeholder ────────────────────────────────────────────────
          _MapPlaceholder(status: booking.status),
          const SizedBox(height: 16),

          // ── Timeline ──────────────────────────────────────────────────────
          if (!isCancelled)
            _StatusTimeline(status: booking.status),

          if (isCancelled) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel_rounded, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    'This booking has been cancelled',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // ── Washer info ────────────────────────────────────────────────────
          if (booking.provider != null)
            _WasherCard(provider: booking.provider!),

          const SizedBox(height: 14),

          // ── Booking details ────────────────────────────────────────────────
          _BookingDetailsCard(booking: booking),

          const SizedBox(height: 14),

          // ── Cancel button ──────────────────────────────────────────────────
          if (booking.canBeCancelled)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _showCancelDialog(booking),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel Booking'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

          // ── Review section ─────────────────────────────────────────────────
          if (isCompleted && !_reviewSubmitted) ...[
            const SizedBox(height: 16),
            _ReviewCard(
              rating: _rating,
              controller: _commentCtrl,
              submitting: _submittingReview,
              onRating: (r) => setState(() => _rating = r),
              onSubmit: () => _submitReview(booking.id),
            ),
          ] else if (isCompleted && _reviewSubmitted) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Review submitted — thank you!'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showCancelDialog(CarServiceBooking booking) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Booking'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed != true) return;
      try {
        // Fetch fresh booking data to avoid stale cache
        final freshRow = await SupabaseConfig.client
            .from('car_service_bookings')
            .select('payment_method, payment_status, total_amount')
            .eq('id', booking.id)
            .single();

        await ref.read(carServicesServiceProvider).updateBookingStatus(booking.id, 'cancelled');

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

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(walletRefunded
                ? 'Booking cancelled. Refund sent to your wallet.'
                : 'Booking cancelled.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    });
  }
}

// ── Map placeholder ────────────────────────────────────────────────────────────

class _MapPlaceholder extends StatelessWidget {
  final CarServiceBookingStatus status;
  const _MapPlaceholder({required this.status});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 180,
        width: double.infinity,
        color: const Color(0xFFE0E7F5),
        child: Stack(
          children: [
            // Grid lines to look like a map
            CustomPaint(
              size: const Size(double.infinity, 180),
              painter: _MapGridPainter(),
            ),
            // Center pin
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kBlue,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _kBlue.withAlpha(100),
                          blurRadius: 16,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.local_car_wash_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(25),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Text(
                      _statusLabel(status),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(CarServiceBookingStatus s) {
    switch (s) {
      case CarServiceBookingStatus.pending:
        return 'Awaiting confirmation…';
      case CarServiceBookingStatus.confirmed:
        return 'Booking confirmed';
      case CarServiceBookingStatus.providerEnRoute:
        return 'Washer on the way';
      case CarServiceBookingStatus.arrived:
        return 'Washer has arrived';
      case CarServiceBookingStatus.inProgress:
        return 'Service in progress';
      case CarServiceBookingStatus.completed:
        return 'Service completed';
      default:
        return 'Booking cancelled';
    }
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFBFCCE8)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Timeline ───────────────────────────────────────────────────────────────────

class _StatusTimeline extends StatelessWidget {
  final CarServiceBookingStatus status;
  const _StatusTimeline({required this.status});

  static const _steps = [
    _Step('Accepted', Icons.check_circle_outline_rounded,
        CarServiceBookingStatus.confirmed),
    _Step('On the Way', Icons.directions_car_rounded,
        CarServiceBookingStatus.providerEnRoute),
    _Step('In Progress', Icons.auto_fix_high_rounded,
        CarServiceBookingStatus.inProgress),
    _Step('Completed', Icons.task_alt_rounded,
        CarServiceBookingStatus.completed),
  ];

  int get _currentIndex {
    switch (status) {
      case CarServiceBookingStatus.pending:
        return -1;
      case CarServiceBookingStatus.confirmed:
        return 0;
      case CarServiceBookingStatus.providerEnRoute:
        return 1;
      case CarServiceBookingStatus.arrived:
        return 1;
      case CarServiceBookingStatus.inProgress:
        return 2;
      case CarServiceBookingStatus.completed:
        return 3;
      default:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex;

    return Container(
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
      child: Row(
        children: List.generate(_steps.length, (i) {
          final isDone = i <= current;
          final isActive = i == current;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone ? _kBlue : Colors.grey.shade100,
                          border: isActive
                              ? Border.all(color: _kBlue, width: 2)
                              : null,
                          boxShadow: isDone
                              ? [
                                  BoxShadow(
                                    color: _kBlue.withAlpha(80),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  )
                                ]
                              : null,
                        ),
                        child: Icon(
                          _steps[i].icon,
                          size: 20,
                          color: isDone ? Colors.white : Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _steps[i].label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isDone
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isDone ? _kBlue : Colors.grey.shade400,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (i < _steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 22),
                      color: i < current
                          ? _kBlue
                          : Colors.grey.shade200,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _Step {
  final String label;
  final IconData icon;
  final CarServiceBookingStatus status;
  const _Step(this.label, this.icon, this.status);
}

// ── Washer card ────────────────────────────────────────────────────────────────

class _WasherCard extends StatelessWidget {
  final CarServiceProvider provider;
  const _WasherCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFFEFF6FF),
            backgroundImage: provider.profileImageUrl != null
                ? NetworkImage(provider.profileImageUrl!)
                : null,
            child: provider.profileImageUrl == null
                ? const Icon(Icons.person, color: _kBlue, size: 28)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        provider.businessName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (provider.isVerified)
                      const Icon(Icons.verified_rounded,
                          size: 16, color: _kBlue),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 14, color: _kAmber),
                    const SizedBox(width: 3),
                    Text(
                      provider.rating.toStringAsFixed(1),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      ' · ${provider.totalBookings} jobs',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Action buttons
          Row(
            children: [
              _ActionBtn(
                icon: Icons.phone_rounded,
                color: _kBlue,
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _ActionBtn(
                icon: Icons.chat_bubble_outline_rounded,
                color: const Color(0xFF059669),
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          shape: BoxShape.circle,
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

// ── Booking details card ───────────────────────────────────────────────────────

class _BookingDetailsCard extends StatelessWidget {
  final CarServiceBooking booking;
  const _BookingDetailsCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          const Text(
            'Booking Details',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _kBlue),
          ),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.confirmation_number_outlined,
            label: 'Booking',
            value: '#${booking.bookingNumber}',
          ),
          _DetailRow(
            icon: Icons.build_circle_outlined,
            label: 'Service',
            value: booking.offering?.name ?? 'N/A',
          ),
          _DetailRow(
            icon: Icons.calendar_today_outlined,
            label: 'Scheduled',
            value: DateFormat('EEE, MMM d · h:mm a')
                .format(booking.scheduledAt),
          ),
          _DetailRow(
            icon: Icons.location_on_outlined,
            label: 'Location',
            value: booking.serviceAddress,
          ),
          if (booking.vehicleMake != null)
            _DetailRow(
              icon: Icons.directions_car_outlined,
              label: 'Vehicle',
              value:
                  '${booking.vehicleMake} ${booking.vehicleModel ?? ''}'.trim(),
            ),
          Divider(height: 20, color: Colors.grey.shade100),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              Text(
                '\$${booking.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: _kBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(label,
                style: TextStyle(
                    color: Colors.grey.shade500, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Review card ────────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final int rating;
  final TextEditingController controller;
  final bool submitting;
  final ValueChanged<int> onRating;
  final VoidCallback onSubmit;

  const _ReviewCard({
    required this.rating,
    required this.controller,
    required this.submitting,
    required this.onRating,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Rate Your Experience',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              return GestureDetector(
                onTap: () => onRating(i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                    color: _kAmber,
                    size: 36,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Leave a comment (optional)',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBlue, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: rating == 0 || submitting ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Submit Review',
                    style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
