import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/index.dart';
import '../../providers/laundry_providers.dart';
import '../../../../utils/app_theme.dart';
import '../../../../utils/app_feedback_widgets.dart';
import '../../../../utils/friendly_error.dart';
import '../../../../config/app_constants.dart';

class LaundryProviderOrdersScreen extends ConsumerWidget {
  final LaundryProvider provider;
  final List<String>? statuses;

  const LaundryProviderOrdersScreen({
    super.key,
    required this.provider,
    this.statuses,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = LaundryProviderBookingParams(provider.id, statuses: statuses);
    final bookingsAsync = ref.watch(providerLaundryBookingsProvider(params));

    return bookingsAsync.when(
      loading: () => const AppLoadingIndicator(message: 'Loading orders…'),
      error: (e, _) => AppErrorState(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(providerLaundryBookingsProvider(params)),
      ),
      data: (bookings) {
        if (bookings.isEmpty) {
          return const AppEmptyState(
            icon: Icons.inbox_outlined,
            title: 'No orders here',
            subtitle: 'Orders will appear here when customers book.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(providerLaundryBookingsProvider(params)),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _ProviderOrderCard(
              booking: bookings[i],
              onTap: () => showModalBottomSheet(
                context: ctx,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => _OrderActionsSheet(
                  booking: bookings[i],
                  onActionDone: () {
                    ref.invalidate(providerLaundryBookingsProvider(params));
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order card
// ─────────────────────────────────────────────────────────────────────────────

class _ProviderOrderCard extends StatelessWidget {
  final LaundryBooking booking;
  final VoidCallback onTap;
  const _ProviderOrderCard({required this.booking, required this.onTap});

  Color _statusColor() {
    switch (booking.status) {
      case LaundryBookingStatus.newRequest:   return Colors.orange;
      case LaundryBookingStatus.completed:    return AppTheme.successColor;
      case LaundryBookingStatus.cancelled:    return Colors.red;
      default:                                return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: booking.status == LaundryBookingStatus.newRequest
                ? Colors.orange.withValues(alpha: 0.5)
                : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: booking.status == LaundryBookingStatus.newRequest ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    booking.customerName ?? booking.bookingNumber,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor().withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    booking.status.displayLabel,
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: _statusColor(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _InfoRow(Icons.confirmation_number_outlined, booking.bookingNumber),
            _InfoRow(
              Icons.calendar_today_rounded,
              '${booking.pickupDate.day}/${booking.pickupDate.month}/${booking.pickupDate.year}  '
              '${booking.pickupTimeSlot}',
            ),
            _InfoRow(Icons.location_on_outlined, booking.pickupAddress),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (booking.estimatedBags > 0)
                  _Pill('${booking.estimatedBags} bag${booking.estimatedBags == 1 ? '' : 's'}',
                      Icons.shopping_bag_outlined),
                if (booking.estimatedWeightKg != null)
                  _Pill('~${booking.estimatedWeightKg!.toStringAsFixed(1)} kg',
                      Icons.scale_rounded),
                const Spacer(),
                if (booking.displayTotal != null)
                  Text(
                    '${AppConstants.currencySymbol}${booking.displayTotal!.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppTheme.primaryColor,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Tap for actions →',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 13, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Pill(this.label, this.icon);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _OrderActionsSheet extends ConsumerStatefulWidget {
  final LaundryBooking booking;
  final VoidCallback onActionDone;

  const _OrderActionsSheet({required this.booking, required this.onActionDone});

  @override
  ConsumerState<_OrderActionsSheet> createState() => _OrderActionsSheetState();
}

class _OrderActionsSheetState extends ConsumerState<_OrderActionsSheet> {
  bool _loading = false;
  final _weightCtrl = TextEditingController();
  final _priceCtrl  = TextEditingController();
  final _noteCtrl   = TextEditingController();

  @override
  void dispose() {
    _weightCtrl.dispose();
    _priceCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _doStatus(LaundryBookingStatus next, {String? note}) async {
    setState(() => _loading = true);
    try {
      await ref.read(laundryServiceProvider).updateBookingStatus(
        widget.booking.id,
        next,
        note:       note,
        customerId: widget.booking.customerId,
      );
      widget.onActionDone();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doWeighIn() async {
    final kg    = double.tryParse(_weightCtrl.text.trim());
    final price = double.tryParse(_priceCtrl.text.trim());
    if (kg == null || kg <= 0) {
      AppSnackbar.warning(context, 'Enter a valid weight greater than 0');
      return;
    }
    if (price == null || price <= 0) {
      AppSnackbar.warning(context, 'Enter a valid price greater than 0');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(laundryServiceProvider).recordWeight(
        widget.booking.id,
        weightKg: kg,
        actualTotal: price,
        notes: _noteCtrl.text.isEmpty ? null : _noteCtrl.text,
      );
      widget.onActionDone();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final actions = _actionsFor(booking.status);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              booking.customerName ?? booking.bookingNumber,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            Text(
              booking.status.displayLabel,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // Weigh-in form (shown when received at laundry)
            if (booking.status == LaundryBookingStatus.receivedAtLaundry) ...[
              const Text('Record Weight & Price',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 12),
              TextField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Weight (kg)',
                  prefixIcon: const Icon(Icons.scale_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Final Price (${AppConstants.currencySymbol})',
                  prefixIcon: const Icon(Icons.attach_money_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _doWeighIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Weight & Price',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Waiting for customer to approve the weighed price
            if (booking.status == LaundryBookingStatus.weighed &&
                !booking.priceApprovedByCustomer) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Waiting for customer to approve the price.\n'
                        'You can start washing once they confirm.',
                        style: TextStyle(fontSize: 13, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (actions.isNotEmpty) ...[
              const Text('Actions',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 12),
              ...actions.map((a) => _ActionButton(
                    label: a.label,
                    icon: a.icon,
                    color: a.color,
                    loading: _loading,
                    onTap: () => _doStatus(a.next),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  List<_Action> _actionsFor(LaundryBookingStatus status) {
    switch (status) {
      case LaundryBookingStatus.newRequest:
        return [
          _Action('Accept Booking',  Icons.check_circle_rounded,
              Colors.green, LaundryBookingStatus.accepted),
          _Action('Reject Booking',  Icons.cancel_rounded,
              Colors.red,   LaundryBookingStatus.cancelled),
        ];
      case LaundryBookingStatus.accepted:
        return [_Action('Confirm Pickup Arranged', Icons.local_shipping_outlined,
            Colors.orange, LaundryBookingStatus.waitingForPickup)];
      // Pickup driver states — provider can manually advance if no driver app
      case LaundryBookingStatus.pickupDriverSearching:
      case LaundryBookingStatus.pickupDriverAssigned:
      case LaundryBookingStatus.waitingForPickup:
        return [_Action('Mark Laundry Collected', Icons.shopping_bag_rounded,
            Colors.blue, LaundryBookingStatus.pickedUpFromCustomer)];
      case LaundryBookingStatus.pickedUpFromCustomer:
        return [_Action('Mark Received at Laundry', Icons.store_rounded,
            AppTheme.primaryColor, LaundryBookingStatus.receivedAtLaundry)];
      // receivedAtLaundry: handled by the weigh-in form above, no button needed
      case LaundryBookingStatus.weighed:
        // Customer must approve the price first — provider cannot skip this step
        return [];
      case LaundryBookingStatus.priceConfirmed:
        return [_Action('Start Washing / Cleaning', Icons.wash_rounded,
            AppTheme.primaryColor, LaundryBookingStatus.washingCleaning)];
      case LaundryBookingStatus.washingCleaning:
        return [_Action('Quality Check Done', Icons.fact_check_rounded,
            Colors.purple, LaundryBookingStatus.qualityCheck)];
      case LaundryBookingStatus.qualityCheck:
        return [_Action('Ready for Delivery', Icons.inventory_2_rounded,
            Colors.teal, LaundryBookingStatus.readyForDelivery)];
      // Return delivery states — provider/driver advances through these
      case LaundryBookingStatus.readyForDelivery:
      case LaundryBookingStatus.returnPaymentRequired:
      case LaundryBookingStatus.returnDriverSearching:
      case LaundryBookingStatus.returnDriverAssigned:
        return [_Action('Out for Delivery', Icons.local_shipping_rounded,
            Colors.indigo, LaundryBookingStatus.outForDelivery)];
      case LaundryBookingStatus.pickedUpForReturn:
      case LaundryBookingStatus.outForDelivery:
        return [_Action('Mark Delivered ✓', Icons.check_circle_rounded,
            Colors.green, LaundryBookingStatus.completed)];
      default:
        return [];
    }
  }
}

class _Action {
  final String label;
  final IconData icon;
  final Color color;
  final LaundryBookingStatus next;
  const _Action(this.label, this.icon, this.color, this.next);
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: loading ? null : onTap,
            icon: Icon(icon, color: color, size: 18),
            label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: color.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      );
}
