import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/package_delivery_request.dart';
import '../../providers/package_providers.dart';
import 'active_package_delivery_screen.dart';

class PackageSearchingScreen extends ConsumerStatefulWidget {
  final PackageDeliveryRequest deliveryRequest;

  const PackageSearchingScreen({super.key, required this.deliveryRequest});

  @override
  ConsumerState<PackageSearchingScreen> createState() =>
      _PackageSearchingScreenState();
}

class _PackageSearchingScreenState
    extends ConsumerState<PackageSearchingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
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

    // Navigate to active tracking when driver is assigned
    ref.listen(
      activePackageDeliveryStreamProvider(widget.deliveryRequest.id),
      (_, next) {
        next.whenData((delivery) {
          if (delivery.deliveryStatus == 'driver_assigned' ||
              delivery.deliveryStatus == 'driver_arriving_warehouse') {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    ActivePackageDeliveryScreen(deliveryRequest: delivery),
              ),
            );
          } else if (delivery.deliveryStatus == 'cancelled' ||
              delivery.deliveryStatus == 'failed') {
            Navigator.of(context).popUntil((r) => r.isFirst);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Delivery ${delivery.deliveryStatus}.')),
            );
          }
        });
      },
    );

    return Scaffold(
      backgroundColor: const Color(0xFF7C3AED),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Pulse animation
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, child) {
                  final scale = 1.0 + (_pulseCtrl.value * 0.3);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                Colors.white.withValues(alpha: 0.15 * (1 - _pulseCtrl.value)),
                          ),
                        ),
                      ),
                      Container(
                        width: 90,
                        height: 90,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: const Icon(Icons.local_shipping,
                            color: Color(0xFF7C3AED), size: 44),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 40),
              const Text(
                'Finding a Driver',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'We\'re connecting you with a nearby driver for your package delivery.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
              ),
              const SizedBox(height: 32),
              // Status card
              streamAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (delivery) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          delivery.statusLabel,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Delivery fee info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Delivery Fee',
                        style: TextStyle(color: Colors.white70)),
                    Text(
                      widget.deliveryRequest.displayFee,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _cancelling ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _cancelling
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Cancel Request'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
