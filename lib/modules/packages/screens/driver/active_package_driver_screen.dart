import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/package_delivery_request.dart';
import '../../providers/package_providers.dart';
import 'package_scan_screen.dart';

class ActivePackageDriverScreen extends ConsumerStatefulWidget {
  final String deliveryRequestId;
  const ActivePackageDriverScreen({super.key, required this.deliveryRequestId});

  @override
  ConsumerState<ActivePackageDriverScreen> createState() =>
      _ActivePackageDriverScreenState();
}

class _ActivePackageDriverScreenState
    extends ConsumerState<ActivePackageDriverScreen> {
  bool _isUpdating = false;

  Future<void> _advance(
      PackageDeliveryRequest delivery, String newStatus) async {
    setState(() => _isUpdating = true);
    try {
      await ref.read(packageServiceProvider).updateStatus(
            deliveryRequestId: delivery.id,
            newStatus: newStatus,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _scanAndPickup(PackageDeliveryRequest delivery) async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PackageScanScreen(
          expectedHint: delivery.pickupAddress,
        ),
      ),
    );
    if (scanned == null || !mounted) return;

    setState(() => _isUpdating = true);
    try {
      await ref.read(packageServiceProvider).confirmPickup(
            deliveryRequestId: delivery.id,
            scannedBarcode: scanned,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _completeDelivery(PackageDeliveryRequest delivery) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delivery'),
        content: const Text(
            'Confirm that you have delivered the package to the recipient?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isUpdating = true);
    try {
      final result = await ref
          .read(packageServiceProvider)
          .completeDelivery(deliveryRequestId: delivery.id);
      if (!mounted) return;
      final earning = result['earnings'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Delivery completed! Earning: JMD ${earning ?? delivery.driverEarning}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final streamAsync = ref.watch(
        activePackageDeliveryStreamProvider(widget.deliveryRequestId));

    ref.listen(
        activePackageDeliveryStreamProvider(widget.deliveryRequestId),
        (_, next) {
      next.whenData((d) {
        if (d.deliveryStatus == 'cancelled' ||
            d.deliveryStatus == 'failed') {
          Navigator.of(context).popUntil((r) => r.isFirst);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Delivery was cancelled.')),
          );
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Package Delivery'),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
      ),
      body: streamAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (delivery) => Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _StatusBanner(status: delivery.deliveryStatus),
                    const SizedBox(height: 16),
                    _RouteCard(delivery: delivery),
                    const SizedBox(height: 16),
                    _EarningCard(delivery: delivery),
                  ],
                ),
              ),
            ),
            _ActionBar(
              delivery: delivery,
              isUpdating: _isUpdating,
              onAdvance: _advance,
              onScanPickup: _scanAndPickup,
              onComplete: _completeDelivery,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;
  const _StatusBanner({required this.status});

  static const _labels = {
    'driver_assigned': ('Driver Assigned', Colors.blue, Icons.person),
    'driver_arriving_warehouse':
        ('Heading to Warehouse', Colors.orange, Icons.directions_car),
    'driver_at_warehouse':
        ('At Warehouse — Scan Package', Colors.purple, Icons.warehouse),
    'package_picked_up':
        ('Package Picked Up', Colors.teal, Icons.inventory_2),
    'in_transit': ('In Transit', Colors.indigo, Icons.local_shipping),
    'arriving_destination':
        ('Arriving at Destination', Colors.green, Icons.location_on),
    'delivered': ('Delivered', Colors.green, Icons.check_circle),
  };

  @override
  Widget build(BuildContext context) {
    final info = _labels[status];
    final label = info?.$1 ?? status;
    final color = info?.$2 ?? Colors.grey;
    final icon = info?.$3 ?? Icons.info;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final PackageDeliveryRequest delivery;
  const _RouteCard({required this.delivery});

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
            const SizedBox(height: 8),
            _RouteRow(
              icon: Icons.home,
              label: 'Delivery',
              address: delivery.destinationAddress,
              color: Colors.green,
            ),
            if (delivery.estimatedDistanceKm != null) ...[
              const Divider(height: 20),
              Row(children: [
                const Icon(Icons.straighten, size: 15, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                    '${delivery.estimatedDistanceKm!.toStringAsFixed(1)} km',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(width: 16),
                const Icon(Icons.access_time, size: 15, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                    '~${delivery.estimatedDurationMinutes ?? "?"} min',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
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
  const _RouteRow(
      {required this.icon,
      required this.label,
      required this.address,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(address, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

class _EarningCard extends StatelessWidget {
  final PackageDeliveryRequest delivery;
  const _EarningCard({required this.delivery});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your Earning',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                Text('Payment Method',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'JMD ${delivery.driverEarning.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF7C3AED)),
                ),
                Text(
                  delivery.paymentMethod == 'cash'
                      ? 'Cash on Delivery'
                      : 'Card',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final PackageDeliveryRequest delivery;
  final bool isUpdating;
  final Future<void> Function(PackageDeliveryRequest, String) onAdvance;
  final Future<void> Function(PackageDeliveryRequest) onScanPickup;
  final Future<void> Function(PackageDeliveryRequest) onComplete;

  const _ActionBar({
    required this.delivery,
    required this.isUpdating,
    required this.onAdvance,
    required this.onScanPickup,
    required this.onComplete,
  });

  String? get _label {
    switch (delivery.deliveryStatus) {
      case 'driver_assigned':
      case 'driver_arriving_warehouse':
        return 'I Have Arrived at Warehouse';
      case 'driver_at_warehouse':
        return 'Scan & Pick Up Package';
      case 'package_picked_up':
        return 'Start Delivery';
      case 'in_transit':
        return 'Arriving at Destination';
      case 'arriving_destination':
        return 'Mark as Delivered';
      default:
        return null;
    }
  }

  String? get _nextStatus {
    switch (delivery.deliveryStatus) {
      case 'driver_assigned':
      case 'driver_arriving_warehouse':
        return 'driver_at_warehouse';
      case 'package_picked_up':
        return 'in_transit';
      case 'in_transit':
        return 'arriving_destination';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    if (label == null ||
        delivery.deliveryStatus == 'delivered' ||
        delivery.deliveryStatus == 'cancelled') {
      return const SizedBox.shrink();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isUpdating
                ? null
                : () {
                    if (delivery.deliveryStatus == 'driver_at_warehouse') {
                      onScanPickup(delivery);
                    } else if (delivery.deliveryStatus ==
                        'arriving_destination') {
                      onComplete(delivery);
                    } else if (_nextStatus != null) {
                      onAdvance(delivery, _nextStatus!);
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: isUpdating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(label, style: const TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
