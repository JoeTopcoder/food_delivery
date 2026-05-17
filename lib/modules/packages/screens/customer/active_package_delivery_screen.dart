import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/package_delivery_request.dart';
import '../../providers/package_providers.dart';

class ActivePackageDeliveryScreen extends ConsumerStatefulWidget {
  final PackageDeliveryRequest deliveryRequest;

  const ActivePackageDeliveryScreen({super.key, required this.deliveryRequest});

  @override
  ConsumerState<ActivePackageDeliveryScreen> createState() =>
      _ActivePackageDeliveryScreenState();
}

class _ActivePackageDeliveryScreenState
    extends ConsumerState<ActivePackageDeliveryScreen> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Delivery?'),
        content: const Text(
            'Are you sure you want to cancel this delivery request?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Yes', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _cancelling = true);
    try {
      await ref.read(packageServiceProvider).updateStatus(
            deliveryRequestId: widget.deliveryRequest.id,
            newStatus: 'cancelled',
            note: 'Cancelled by customer',
          );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final streamAsync = ref.watch(
        activePackageDeliveryStreamProvider(widget.deliveryRequest.id));

    ref.listen(
        activePackageDeliveryStreamProvider(widget.deliveryRequest.id),
        (_, next) {
      next.whenData((delivery) {
        if (delivery.deliveryStatus == 'delivered') {
          Navigator.of(context).popUntil((r) => r.isFirst);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Package delivered successfully!'),
                backgroundColor: Colors.green),
          );
        } else if (delivery.deliveryStatus == 'cancelled' ||
            delivery.deliveryStatus == 'failed') {
          Navigator.of(context).popUntil((r) => r.isFirst);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delivery ${delivery.deliveryStatus}.')),
          );
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracking Delivery'),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        actions: [
          streamAsync.maybeWhen(
            data: (d) => !['delivered', 'cancelled', 'failed',
                    'package_picked_up', 'in_transit',
                    'arriving_destination']
                .contains(d.deliveryStatus)
                ? IconButton(
                    icon: const Icon(Icons.cancel_outlined),
                    onPressed: _cancelling ? null : _cancel,
                    tooltip: 'Cancel',
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: streamAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (delivery) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _StatusTimeline(status: delivery.deliveryStatus),
              const SizedBox(height: 20),
              _DeliveryInfoCard(delivery: delivery),
              const SizedBox(height: 20),
              _FeeCard(delivery: delivery),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  final String status;
  const _StatusTimeline({required this.status});

  static const _steps = [
    ('searching_driver', 'Finding Driver', Icons.search),
    ('driver_assigned', 'Driver Assigned', Icons.person),
    ('driver_arriving_warehouse', 'Heading to Warehouse', Icons.directions_car),
    ('driver_at_warehouse', 'At Warehouse', Icons.warehouse),
    ('package_picked_up', 'Package Picked Up', Icons.inventory_2),
    ('in_transit', 'In Transit', Icons.local_shipping),
    ('arriving_destination', 'Arriving', Icons.location_on),
    ('delivered', 'Delivered', Icons.check_circle),
  ];

  int get _currentIndex {
    for (int i = 0; i < _steps.length; i++) {
      if (_steps[i].$1 == status) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Delivery Status',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 16),
            ...List.generate(_steps.length, (i) {
              final done = i < current;
              final active = i == current;
              final (_, label, icon) = _steps[i];
              return Row(
                children: [
                  Column(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done || active
                              ? const Color(0xFF7C3AED)
                              : Colors.grey.shade200,
                        ),
                        child: Icon(
                          done ? Icons.check : icon,
                          size: 16,
                          color: done || active
                              ? Colors.white
                              : Colors.grey,
                        ),
                      ),
                      if (i < _steps.length - 1)
                        Container(
                          width: 2,
                          height: 28,
                          color: done
                              ? const Color(0xFF7C3AED)
                              : Colors.grey.shade200,
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: active
                            ? const Color(0xFF7C3AED)
                            : done
                                ? Colors.black87
                                : Colors.grey,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _DeliveryInfoCard extends StatelessWidget {
  final PackageDeliveryRequest delivery;
  const _DeliveryInfoCard({required this.delivery});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Route',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            _RouteRow(
              icon: Icons.warehouse,
              label: 'Pickup',
              address: delivery.pickupAddress,
              color: Colors.blue,
            ),
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: SizedBox(
                height: 20,
                child: VerticalDivider(color: Colors.grey),
              ),
            ),
            _RouteRow(
              icon: Icons.home,
              label: 'Delivery',
              address: delivery.destinationAddress,
              color: Colors.green,
            ),
            if (delivery.estimatedDistanceKm != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.straighten,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    '${delivery.estimatedDistanceKm!.toStringAsFixed(1)} km',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  if (delivery.estimatedDurationMinutes != null) ...[
                    const SizedBox(width: 16),
                    const Icon(Icons.access_time,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      '~${delivery.estimatedDurationMinutes} min',
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String address;
  final Color color;

  const _RouteRow({
    required this.icon,
    required this.label,
    required this.address,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500)),
              Text(address, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeeCard extends StatelessWidget {
  final PackageDeliveryRequest delivery;
  const _FeeCard({required this.delivery});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Payment',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Delivery Fee',
                    style: TextStyle(color: Colors.grey)),
                Text(delivery.displayFee,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Method',
                    style: TextStyle(color: Colors.grey)),
                Text(
                  delivery.paymentMethod == 'cash'
                      ? 'Cash on Delivery'
                      : 'Card',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Status',
                    style: TextStyle(color: Colors.grey)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: delivery.paymentStatus == 'paid'
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    delivery.paymentStatus.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: delivery.paymentStatus == 'paid'
                          ? Colors.green
                          : Colors.orange,
                    ),
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
