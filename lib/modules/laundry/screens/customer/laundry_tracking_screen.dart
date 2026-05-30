import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/index.dart';
import '../../providers/laundry_providers.dart';
import '../../../../utils/app_theme.dart';
import '../../../../utils/app_feedback_widgets.dart';
import '../../../../utils/friendly_error.dart';
import '../../../../config/app_constants.dart';

const _kNavy = Color(0xFF0B3D6B);
const _kBlue = Color(0xFF1565C0);

class LaundryTrackingScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const LaundryTrackingScreen({super.key, required this.bookingId});

  @override
  ConsumerState<LaundryTrackingScreen> createState() =>
      _LaundryTrackingScreenState();
}

class _LaundryTrackingScreenState extends ConsumerState<LaundryTrackingScreen> {
  StreamSubscription? _bookingSub;

  @override
  void initState() {
    super.initState();
    // Subscribe to realtime changes on this booking row so the screen updates
    // automatically when the provider changes the status (completed, etc.).
    _bookingSub = Supabase.instance.client
        .from('laundry_bookings')
        .stream(primaryKey: ['id'])
        .eq('id', widget.bookingId)
        .listen((_) {
          if (mounted) {
            ref.invalidate(laundryBookingDetailProvider(widget.bookingId));
          }
        });
  }

  @override
  void dispose() {
    _bookingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(
      laundryBookingDetailProvider(widget.bookingId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laundry Tracking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                ref.invalidate(laundryBookingDetailProvider(widget.bookingId)),
          ),
        ],
      ),
      body: bookingAsync.when(
        loading: () => const AppLoadingIndicator(message: 'Loading booking…'),
        error: (e, _) => AppErrorState(
          message: friendlyError(e),
          onRetry: () =>
              ref.invalidate(laundryBookingDetailProvider(widget.bookingId)),
        ),
        data: (booking) {
          if (booking == null) {
            return const AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Booking not found',
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(laundryBookingDetailProvider(widget.bookingId)),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BookingHeader(booking: booking),
                  const SizedBox(height: 16),

                  // ── Top-up required banners ────────────────────────────
                  if (booking.status ==
                      LaundryBookingStatus.returnPaymentRequired) ...[
                    _TopUpBanner(
                      title: 'Return Delivery Payment Required',
                      body:
                          'Please top up your wallet so we can assign a return delivery driver.',
                      onTopUp: () => Navigator.pushNamed(context, '/wallet'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (booking.status == LaundryBookingStatus.weighed &&
                      !booking.priceApprovedByCustomer) ...[
                    _PriceApprovalBanner(
                      booking: booking,
                      onApprove: () => _approvePrice(booking),
                    ),
                    const SizedBox(height: 16),
                  ],

                  _StatusTimeline(booking: booking),
                  const SizedBox(height: 16),

                  // ── Driver job cards ───────────────────────────────────
                  _DriverJobsCard(bookingId: booking.id),
                  const SizedBox(height: 16),

                  _PricingCard(booking: booking),

                  // ── Payment split (completed) ──────────────────────────
                  if (booking.status == LaundryBookingStatus.completed) ...[
                    const SizedBox(height: 16),
                    _PaymentSplitCard(bookingId: booking.id),
                  ],

                  if (booking.items != null && booking.items!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _ItemsList(items: booking.items!),
                  ],
                  if (booking.photos != null && booking.photos!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _PhotosSection(photos: booking.photos!),
                  ],
                  if (booking.status == LaundryBookingStatus.completed &&
                      booking.customerRatingProvider == null) ...[
                    const SizedBox(height: 16),
                    _RateProviderCard(
                      booking: booking,
                      onRate: (rating, review) =>
                          _submitReview(booking, rating, review),
                    ),
                  ],
                  // Only allow cancellation before driver picks up the laundry.
                  // Once picked up, the order is in progress and cannot be cancelled.
                  if (_canCancel(booking.status)) ...[
                    const SizedBox(height: 16),
                    _CancelButton(onTap: () => _showCancelDialog(booking)),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _approvePrice(LaundryBooking booking) async {
    try {
      await ref.read(laundryServiceProvider).approvePrice(booking.id);
      ref.invalidate(laundryBookingDetailProvider(widget.bookingId));
      if (mounted) AppSnackbar.success(context, 'Price approved!');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _submitReview(
    LaundryBooking booking,
    int rating,
    String review,
  ) async {
    try {
      await ref
          .read(laundryServiceProvider)
          .submitReview(
            LaundryReview(
              id: '',
              bookingId: booking.id,
              customerId: booking.customerId,
              providerId: booking.providerId,
              providerRating: rating,
              reviewText: review.isEmpty ? null : review,
              createdAt: DateTime.now(),
            ),
          );
      ref.invalidate(laundryBookingDetailProvider(widget.bookingId));
      if (mounted) AppSnackbar.success(context, 'Review submitted!');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  /// Free cancellation is allowed up to (but not including) the point where
  /// the driver has physically collected the laundry.
  bool _canCancel(LaundryBookingStatus status) {
    const cancellableStatuses = {
      LaundryBookingStatus.newRequest,
      LaundryBookingStatus.accepted,
      LaundryBookingStatus.pickupDriverSearching,
      LaundryBookingStatus.pickupDriverAssigned,
      LaundryBookingStatus.waitingForPickup,
    };
    return cancellableStatuses.contains(status);
  }

  Future<void> _showCancelDialog(LaundryBooking booking) async {
    final reasonCtrl = TextEditingController();
    final hasReserved = booking.reservedAmount > 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancel Booking',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Refund notice
            if (hasReserved)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.green.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Full refund of \$${booking.reservedAmount.toStringAsFixed(2)} '
                        'will be returned to your wallet.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (hasReserved) const SizedBox(height: 14),
            const Text(
              'Why are you cancelling?',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                hintText: 'Reason (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Booking'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Cancel Booking',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    // Capture text before disposing the controller
    final reason = reasonCtrl.text;
    reasonCtrl.dispose();
    if (confirmed == true && mounted) {
      try {
        await ref
            .read(laundryServiceProvider)
            .cancelBooking(booking.id, reason);
        ref.invalidate(myLaundryBookingsProvider);
        if (mounted) {
          AppSnackbar.success(
            context,
            hasReserved
                ? 'Booking cancelled — refund returned to your wallet'
                : 'Booking cancelled',
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) AppSnackbar.error(context, friendlyError(e));
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _BookingHeader extends StatelessWidget {
  final LaundryBooking booking;
  const _BookingHeader({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F4C81),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.confirmation_number_rounded,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                booking.bookingNumber,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              _StatusChip(status: booking.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            booking.providerName ?? 'Laundry Provider',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                color: Colors.white60,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                'Pickup: ${booking.pickupDate.day}/${booking.pickupDate.month}/${booking.pickupDate.year}'
                '  ${booking.pickupTimeSlot}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final LaundryBookingStatus status;
  const _StatusChip({required this.status});

  Color get _color {
    switch (status) {
      case LaundryBookingStatus.completed:
        return AppTheme.successColor;
      case LaundryBookingStatus.cancelled:
        return Colors.red;
      case LaundryBookingStatus.disputed:
        return Colors.orange;
      default:
        return Colors.white.withValues(alpha: 0.2);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: _color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      status.displayLabel,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _StatusTimeline extends StatelessWidget {
  final LaundryBooking booking;
  const _StatusTimeline({required this.booking});

  static const _milestones = [
    LaundryBookingStatus.newRequest,
    LaundryBookingStatus.accepted,
    LaundryBookingStatus.pickupDriverSearching,
    LaundryBookingStatus.pickupDriverAssigned,
    LaundryBookingStatus.waitingForPickup,
    LaundryBookingStatus.pickedUpFromCustomer,
    LaundryBookingStatus.receivedAtLaundry,
    LaundryBookingStatus.weighed,
    LaundryBookingStatus.priceConfirmed,
    LaundryBookingStatus.washingCleaning,
    LaundryBookingStatus.qualityCheck,
    LaundryBookingStatus.readyForDelivery,
    LaundryBookingStatus.returnPaymentRequired,
    LaundryBookingStatus.returnDriverSearching,
    LaundryBookingStatus.returnDriverAssigned,
    LaundryBookingStatus.pickedUpForReturn,
    LaundryBookingStatus.outForDelivery,
    LaundryBookingStatus.completed,
  ];

  @override
  Widget build(BuildContext context) {
    // indexOf returns -1 for cancelled/disputed — treat as "before start"
    final currentIdx = _milestones.indexOf(booking.status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status Timeline',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 16),
          ..._milestones.asMap().entries.map((e) {
            final idx = e.key;
            final status = e.value;
            // currentIdx == -1 when status is cancelled/disputed (not in list).
            // In that case show no step as active and nothing as done.
            final done = currentIdx >= 0 &&
                (idx < currentIdx ||
                    booking.status == LaundryBookingStatus.completed);
            final active = currentIdx >= 0 && idx == currentIdx;
            final last = idx == _milestones.length - 1;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: done
                            ? AppTheme.successColor
                            : active
                            ? AppTheme.primaryColor
                            : Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: done
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 14,
                            )
                          : active
                          ? const Icon(
                              Icons.circle,
                              color: Colors.white,
                              size: 10,
                            )
                          : null,
                    ),
                    if (!last)
                      Container(
                        width: 2,
                        height: 28,
                        color: done
                            ? AppTheme.successColor
                            : Colors.grey.shade200,
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    status.displayLabel,
                    style: TextStyle(
                      fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                      fontSize: 13,
                      color: active
                          ? AppTheme.primaryColor
                          : done
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.grey,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  final LaundryBooking booking;
  const _PricingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final displayTotal = booking.displayTotal;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pricing',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 12),
          if (booking.actualWeightKg != null)
            _PriceRow(
              'Actual weight',
              '${booking.actualWeightKg!.toStringAsFixed(2)} kg',
            ),
          if (booking.estimatedWeightKg != null &&
              booking.actualWeightKg == null)
            _PriceRow(
              'Est. weight',
              '~${booking.estimatedWeightKg!.toStringAsFixed(2)} kg',
            ),
          _PriceRow(
            'Pickup fee',
            '${AppConstants.currencySymbol}${booking.pickupFee.toStringAsFixed(2)}',
          ),
          _PriceRow(
            'Delivery fee',
            '${AppConstants.currencySymbol}${booking.deliveryFee.toStringAsFixed(2)}',
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                booking.actualTotal != null ? 'Final Total' : 'Estimated Total',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Text(
                displayTotal != null
                    ? '${AppConstants.currencySymbol}${displayTotal.toStringAsFixed(2)}'
                    : 'TBD',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  const _PriceRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _PriceApprovalBanner extends StatelessWidget {
  final LaundryBooking booking;
  final VoidCallback onApprove;
  const _PriceApprovalBanner({required this.booking, required this.onApprove});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            const Text(
              'Price Approval Required',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Your laundry has been weighed. Final price: '
          '${AppConstants.currencySymbol}${booking.actualTotal?.toStringAsFixed(2) ?? "—"}',
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onApprove,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Approve Price',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ItemsList extends StatelessWidget {
  final List<LaundryBookingItem> items;
  const _ItemsList({required this.items});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Services',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 10),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.local_laundry_service_outlined,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.serviceName,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  '${AppConstants.currencySymbol}${item.totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

class _PhotosSection extends StatelessWidget {
  final List<LaundryPhoto> photos;
  const _PhotosSection({required this.photos});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Photos',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) => GestureDetector(
              onTap: () => _showPhoto(ctx, photos[i].url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  photos[i].url,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 80,
                    height: 80,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  void _showPhoto(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _RateProviderCard extends StatefulWidget {
  final LaundryBooking booking;
  final void Function(int rating, String review) onRate;

  const _RateProviderCard({required this.booking, required this.onRate});

  @override
  State<_RateProviderCard> createState() => _RateProviderCardState();
}

class _RateProviderCardState extends State<_RateProviderCard> {
  int _rating = 0;
  final _reviewCtrl = TextEditingController();

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rate Your Experience',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (i) => GestureDetector(
              onTap: () => setState(() => _rating = i + 1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  i < _rating ? Icons.star_rounded : Icons.star_border_rounded,
                  color: Colors.amber,
                  size: 36,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reviewCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Leave a review (optional)',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _rating == 0
                ? null
                : () => widget.onRate(_rating, _reviewCtrl.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Submit Review',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CancelButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CancelButton({required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
    label: const Text('Cancel Booking', style: TextStyle(color: Colors.red)),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: Colors.red),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      minimumSize: const Size(double.infinity, 44),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Top-up required banner
// ─────────────────────────────────────────────────────────────────────────────

class _TopUpBanner extends StatelessWidget {
  final String title;
  final String body;
  final VoidCallback onTopUp;
  const _TopUpBanner({
    required this.title,
    required this.body,
    required this.onTopUp,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.orange.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_rounded,
              color: Colors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.orange,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onTopUp,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              'Top Up Wallet',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Driver jobs card
// ─────────────────────────────────────────────────────────────────────────────

class _DriverJobsCard extends ConsumerWidget {
  final String bookingId;
  const _DriverJobsCard({required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(laundryDriverJobsProvider(bookingId));
    return jobsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (jobs) {
        if (jobs.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Delivery Jobs',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 12),
              ...jobs.map((job) => _JobTile(job: job)),
            ],
          ),
        );
      },
    );
  }
}

class _JobTile extends StatelessWidget {
  final LaundryDriverJob job;
  const _JobTile({required this.job});

  Color get _statusColor {
    switch (job.status) {
      case LaundryJobStatus.completed:
        return Colors.green;
      case LaundryJobStatus.cancelled:
        return Colors.red;
      case LaundryJobStatus.searching:
        return Colors.orange;
      default:
        return _kBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              job.jobType == LaundryJobType.pickup
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: _kBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.jobType.displayLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (job.driverName != null)
                  Text(
                    'Driver: ${job.driverName}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    job.status.displayLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: _statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${AppConstants.currencySymbol}${job.driverPayout.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payment split card (shown after completion)
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentSplitCard extends ConsumerWidget {
  final String bookingId;
  const _PaymentSplitCard({required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final splitAsync = ref.watch(laundryPaymentSplitProvider(bookingId));
    return splitAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (split) {
        if (split == null) return const SizedBox.shrink();
        final c = AppConstants.currencySymbol;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.receipt_long_rounded,
                    color: Colors.green,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Payment Receipt',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              _SplitRow(
                'Laundry Services',
                '$c${split.finalLaundryAmount.toStringAsFixed(2)}',
              ),
              _SplitRow(
                'Pickup Fee',
                '$c${split.pickupDeliveryFee.toStringAsFixed(2)}',
              ),
              _SplitRow(
                'Return Delivery Fee',
                '$c${split.returnDeliveryFee.toStringAsFixed(2)}',
              ),
              _SplitRow(
                'Service Fee',
                '$c${split.customerServiceFee.toStringAsFixed(2)}',
              ),
              const Divider(height: 16),
              _SplitRow(
                'Total Paid',
                '$c${split.finalTotal.toStringAsFixed(2)}',
                bold: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SplitRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _SplitRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
