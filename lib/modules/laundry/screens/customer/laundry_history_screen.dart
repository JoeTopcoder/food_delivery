import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/index.dart';
import '../../providers/laundry_providers.dart';
import '../../../../utils/app_theme.dart';
import '../../../../utils/app_feedback_widgets.dart';
import '../../../../utils/friendly_error.dart';
import '../../../../config/app_constants.dart';

class LaundryHistoryScreen extends ConsumerWidget {
  const LaundryHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myLaundryBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Laundry Orders')),
      body: bookingsAsync.when(
        loading: () => const AppLoadingIndicator(message: 'Loading orders…'),
        error: (e, _) => AppErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(myLaundryBookingsProvider),
        ),
        data: (bookings) {
          if (bookings.isEmpty) {
            return const AppEmptyState(
              icon: Icons.local_laundry_service_outlined,
              title: 'No laundry orders yet',
              subtitle: 'Book a laundry pickup to get started',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myLaundryBookingsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: bookings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) => _LaundryOrderTile(
                booking: bookings[i],
                onTap: () => Navigator.pushNamed(
                  ctx,
                  '/laundry/tracking',
                  arguments: bookings[i].id,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LaundryOrderTile extends StatelessWidget {
  final LaundryBooking booking;
  final VoidCallback onTap;
  const _LaundryOrderTile({required this.booking, required this.onTap});

  Color _statusColor() {
    switch (booking.status) {
      case LaundryBookingStatus.completed:  return AppTheme.successColor;
      case LaundryBookingStatus.cancelled:  return Colors.red;
      case LaundryBookingStatus.disputed:   return Colors.orange;
      default:                              return AppTheme.primaryColor;
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
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF0F4C81).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_laundry_service_rounded,
                  color: Color(0xFF0F4C81), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.providerName ?? 'Laundry Provider',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    booking.bookingNumber,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Pickup: ${booking.pickupDate.day}/${booking.pickupDate.month}/${booking.pickupDate.year}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (booking.displayTotal != null)
                  Text(
                    '${AppConstants.currencySymbol}${booking.displayTotal!.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor().withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    booking.status.displayLabel,
                    style: TextStyle(fontSize: 10, color: _statusColor(), fontWeight: FontWeight.w600),
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
