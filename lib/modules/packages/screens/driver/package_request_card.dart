import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/package_delivery_request.dart';
import '../../providers/package_providers.dart';
import 'active_package_driver_screen.dart';

class PackageRequestCard extends ConsumerStatefulWidget {
  final PackageDeliveryRequest request;
  final VoidCallback onDismiss;

  const PackageRequestCard({
    super.key,
    required this.request,
    required this.onDismiss,
  });

  @override
  ConsumerState<PackageRequestCard> createState() =>
      _PackageRequestCardState();
}

class _PackageRequestCardState extends ConsumerState<PackageRequestCard> {
  bool _accepting = false;

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      await ref
          .read(packageServiceProvider)
          .acceptPackageRequest(widget.request.id);

      // Advance to driver_arriving_warehouse
      await ref.read(packageServiceProvider).updateStatus(
            deliveryRequestId: widget.request.id,
            newStatus: 'driver_arriving_warehouse',
          );

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ActivePackageDriverScreen(deliveryRequestId: widget.request.id),
        ),
      );
      widget.onDismiss();
    } catch (e) {
      if (!mounted) return;
      setState(() => _accepting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not accept: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF7C3AED),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2,
                    color: Colors.white, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('New Package Request',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text('Package delivery available',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: widget.onDismiss,
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Route
                _RouteRow(
                  icon: Icons.warehouse,
                  label: 'Pickup (Warehouse)',
                  address: req.pickupAddress,
                  color: Colors.blue,
                ),
                const SizedBox(height: 8),
                _RouteRow(
                  icon: Icons.home,
                  label: 'Delivery',
                  address: req.destinationAddress,
                  color: Colors.green,
                ),
                const Divider(height: 24),
                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat(
                      label: 'Distance',
                      value: req.estimatedDistanceKm != null
                          ? '${req.estimatedDistanceKm!.toStringAsFixed(1)} km'
                          : '—',
                    ),
                    _Stat(
                      label: 'Est. Time',
                      value: req.estimatedDurationMinutes != null
                          ? '${req.estimatedDurationMinutes} min'
                          : '—',
                    ),
                    _Stat(
                      label: 'Earning',
                      value: '\$${req.driverEarning.toStringAsFixed(0)}',
                      highlight: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onDismiss,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey,
                          side: const BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _accepting ? null : _accept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _accepting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Accept'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
              Text(address,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _Stat(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: highlight ? const Color(0xFF7C3AED) : Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
