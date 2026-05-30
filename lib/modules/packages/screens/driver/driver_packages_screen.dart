import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/package_delivery_request.dart';
import '../../providers/package_providers.dart';
import 'active_package_driver_screen.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/driver_provider.dart';

class DriverPackagesScreen extends ConsumerStatefulWidget {
  const DriverPackagesScreen({super.key});

  @override
  ConsumerState<DriverPackagesScreen> createState() =>
      _DriverPackagesScreenState();
}

class _DriverPackagesScreenState extends ConsumerState<DriverPackagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final driverAsync = currentUserId != null
        ? ref.watch(driverProfileProvider(currentUserId))
        : null;
    final driver = driverAsync?.valueOrNull;
    final activeServices = driver?.activeServices ?? ['food_delivery'];
    final packageEnabled = activeServices.contains('package_delivery');

    if (driver != null && !packageEnabled) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF7C3AED),
          foregroundColor: Colors.white,
          title: const Text('Package Delivery'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 40,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Package Delivery Disabled',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Enable Package Delivery in Active Services on your dashboard to receive courier jobs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text(
                      'Go to Dashboard',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Package Delivery'),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Available'),
            Tab(text: 'My Active'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _AvailablePackagesTab(),
          _ActivePackageTab(),
        ],
      ),
    );
  }
}

// ── Available packages tab ────────────────────────────────────────────────────

class _AvailablePackagesTab extends ConsumerWidget {
  const _AvailablePackagesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(availablePackageRequestsProvider);

    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(availablePackageRequestsProvider),
      child: requestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('$e'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(availablePackageRequestsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (requests) {
          if (requests.isEmpty) {
            return const _EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'No package requests available right now.',
              sub: 'Pull down to refresh.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, i) =>
                _AvailablePackageCard(request: requests[i]),
          );
        },
      ),
    );
  }
}

class _AvailablePackageCard extends ConsumerStatefulWidget {
  final PackageDeliveryRequest request;
  const _AvailablePackageCard({required this.request});

  @override
  ConsumerState<_AvailablePackageCard> createState() =>
      _AvailablePackageCardState();
}

class _AvailablePackageCardState
    extends ConsumerState<_AvailablePackageCard> {
  bool _accepting = false;

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      // Edge function atomically assigns driver + sets driver_assigned
      await ref
          .read(packageServiceProvider)
          .acceptPackageRequest(widget.request.id);

      // Now advance to driver_arriving_warehouse (valid: driver_assigned → driver_arriving_warehouse)
      await ref.read(packageServiceProvider).updateStatus(
            deliveryRequestId: widget.request.id,
            newStatus: 'driver_arriving_warehouse',
          );

      ref.invalidate(availablePackageRequestsProvider);
      ref.invalidate(myActivePackageDeliveryAsDriverProvider);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActivePackageDriverScreen(
              deliveryRequestId: widget.request.id),
        ),
      );
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
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: req.companyLogoUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            req.companyLogoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              width: 40,
                              height: 40,
                              color: Colors.grey[200],
                              child: const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Colors.grey),
                            ),
                          ),
                        )
                      : const Icon(Icons.local_shipping,
                          color: Color(0xFF7C3AED), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.companyName ?? 'Package Request',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        req.paymentMethod == 'cash'
                            ? 'Cash on Delivery'
                            : 'Card Payment',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'JMD ${req.driverEarning.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            // Route
            _RouteRow(
              icon: Icons.warehouse,
              color: Colors.blue,
              label: 'Pickup',
              address: req.pickupAddress,
            ),
            const SizedBox(height: 6),
            _RouteRow(
              icon: Icons.home,
              color: Colors.green,
              label: 'Delivery',
              address: req.destinationAddress,
            ),
            const SizedBox(height: 12),
            // Stats
            Row(
              children: [
                if (req.estimatedDistanceKm != null) ...[
                  const Icon(Icons.straighten, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${req.estimatedDistanceKm!.toStringAsFixed(1)} km',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(width: 16),
                ],
                if (req.estimatedDurationMinutes != null) ...[
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '~${req.estimatedDurationMinutes} min',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
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
                    : const Text('Accept Delivery'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Active package tab ────────────────────────────────────────────────────────

class _ActivePackageTab extends ConsumerWidget {
  const _ActivePackageTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(myActivePackageDeliveryAsDriverProvider);

    return activeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (delivery) {
        if (delivery == null) {
          return const _EmptyState(
            icon: Icons.check_circle_outline,
            message: 'No active package delivery.',
            sub: 'Accept a request from the Available tab.',
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.inventory_2,
                              color: Color(0xFF7C3AED)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (delivery.companyName != null)
                                  Text(
                                    delivery.companyName!,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                  ),
                                Text(
                                  delivery.statusLabel,
                                  style: TextStyle(
                                    fontSize:
                                        delivery.companyName != null ? 12 : 15,
                                    color: delivery.companyName != null
                                        ? Colors.grey
                                        : Colors.black,
                                    fontWeight: delivery.companyName != null
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      _RouteRow(
                        icon: Icons.warehouse,
                        color: Colors.blue,
                        label: 'Pickup',
                        address: delivery.pickupAddress,
                      ),
                      const SizedBox(height: 8),
                      _RouteRow(
                        icon: Icons.home,
                        color: Colors.green,
                        label: 'Delivery',
                        address: delivery.destinationAddress,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Your Earning',
                              style: TextStyle(color: Colors.grey)),
                          Text(
                            'JMD ${delivery.driverEarning.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF7C3AED)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ActivePackageDriverScreen(
                          deliveryRequestId: delivery.id),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Continue Delivery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String address;
  const _RouteRow(
      {required this.icon,
      required this.color,
      required this.label,
      required this.address});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: Colors.grey)),
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String sub;
  const _EmptyState(
      {required this.icon, required this.message, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(sub,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
