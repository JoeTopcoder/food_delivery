import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/location_service.dart';
import '../../widgets/sos_button.dart';
import 'delivery_proof_screen.dart';
import '../../utils/friendly_error.dart';

class ActiveDeliveriesScreen extends ConsumerStatefulWidget {
  const ActiveDeliveriesScreen({super.key});

  @override
  ConsumerState<ActiveDeliveriesScreen> createState() =>
      _ActiveDeliveriesScreenState();
}

class _ActiveDeliveriesScreenState
    extends ConsumerState<ActiveDeliveriesScreen> {
  String? _trackingOrderId;
  LocationService? _locationService;

  @override
  void initState() {
    super.initState();
    _locationService = ref.read(locationServiceProvider);
  }

  @override
  void dispose() {
    _locationService?.stopTracking();
    super.dispose();
  }

  Future<void> _toggleTracking(
    LocationService locationService,
    String driverId,
    String orderId,
  ) async {
    final isTracking = ref.read(isTrackingProvider);
    if (isTracking && _trackingOrderId == orderId) {
      locationService.stopTracking();
      ref.read(isTrackingProvider.notifier).state = false;
      setState(() => _trackingOrderId = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('GPS tracking stopped'),
            backgroundColor: const Color(0xFF1E2030),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } else {
      final hasPermission = await locationService.requestPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permission required for tracking'),
              backgroundColor: const Color(0xFFF59E0B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
        return;
      }
      await locationService.startTracking(driverId: driverId, orderId: orderId);
      ref.read(isTrackingProvider.notifier).state = true;
      setState(() => _trackingOrderId = orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('GPS tracking started'),
            backgroundColor: const Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    if (currentUserId == null) {
      return const Scaffold(body: Center(child: Text('User not found')));
    }

    final driverProfileAsync = ref.watch(driverProfileProvider(currentUserId));
    return driverProfileAsync.when(
      data: (driver) {
        if (driver == null) {
          return const Scaffold(
            body: Center(child: Text('Driver profile not found')),
          );
        }

        final deliveriesAsync = ref.watch(activeDeliveriesProvider(driver.id));
        final locationService = ref.read(locationServiceProvider);
        final isTracking = ref.watch(isTrackingProvider);

        return Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── App Bar ────────────────────────────────────────────
              SliverAppBar(
                pinned: true,
                backgroundColor: const Color(0xFF0F1117),
                foregroundColor: Colors.white,
                elevation: 0,
                title: const Text(
                  'Active Deliveries',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                actions: [
                  const SosButton(),
                  if (isTracking)
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF22C55E),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'GPS Live',
                            style: TextStyle(
                              color: Color(0xFF22C55E),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              // ── Body ──────────────────────────────────────────────
              deliveriesAsync.when(
                data: (deliveries) {
                  if (deliveries.isEmpty) {
                    return SliverFillRemaining(child: _EmptyState());
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final delivery = deliveries[index];
                        final isThisTracked =
                            isTracking && _trackingOrderId == delivery.id;
                        return _DeliveryCard(
                          delivery: delivery,
                          isTracking: isThisTracked,
                          onToggleGps: () => _toggleTracking(
                            locationService,
                            driver.id,
                            delivery.id,
                          ),
                          onNavigate: () => _navigateToCustomer(delivery),
                          onChat: () {
                            Navigator.pushNamed(
                              context,
                              '/chat',
                              arguments: {
                                'orderId': delivery.id,
                                'otherPartyName': 'Customer',
                                'receiverId': delivery.userId,
                              },
                            );
                          },
                          onMarkDelivered: () =>
                              _confirmDelivered(context, delivery, driver.id),
                          onVerifyPin: delivery.contactlessDelivery
                              ? () async {
                                  final completed = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          DeliveryProofScreen(order: delivery),
                                    ),
                                  );
                                  if (completed == true) {
                                    ref.invalidate(
                                      activeDeliveriesProvider(driver.id),
                                    );
                                  }
                                }
                              : null,
                        );
                      }, childCount: deliveries.length),
                    ),
                  );
                },
                loading: () => const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                error: (err, _) => SliverFillRemaining(
                  child: Center(
                    child: Text(
                      friendlyError(err),
                      style: const TextStyle(color: Color(0xFF9CA3AF)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        body: Center(
          child: Text(
            friendlyError(err),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }

  void _navigateToCustomer(Order delivery) async {
    final lat = delivery.deliveryLatitude;
    final lng = delivery.deliveryLongitude;
    if (lat != null && lng != null) {
      final googleMapsUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
      final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
      if (await canLaunchUrl(googleMapsUri)) {
        await launchUrl(googleMapsUri);
      } else if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri);
      } else {
        await launchUrl(
          Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
          ),
          mode: LaunchMode.externalApplication,
        );
      }
    } else if (delivery.deliveryAddress != null) {
      final encoded = Uri.encodeComponent(delivery.deliveryAddress!);
      await launchUrl(
        Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$encoded',
        ),
        mode: LaunchMode.externalApplication,
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No delivery address available'),
            backgroundColor: const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  void _confirmDelivered(
    BuildContext context,
    Order delivery,
    String driverId,
  ) {
    if (delivery.contactlessDelivery && delivery.deliveryOtpVerified != true) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E2030),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.lock_rounded, color: Color(0xFF818CF8)),
              SizedBox(width: 8),
              Text(
                'PIN Required',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: const Text(
            'This is a contactless delivery. You must verify the customer\'s 4-digit PIN before marking it as delivered.',
            style: TextStyle(color: Color(0xFF9CA3AF)),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('OK, Verify PIN'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Mark as Delivered?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Confirm delivery of Order #${delivery.id.substring(0, 8).toUpperCase()}?',
          style: const TextStyle(color: Color(0xFF9CA3AF)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final driverService = ref.read(driverServiceProvider);

                if (_trackingOrderId == delivery.id) {
                  ref.read(locationServiceProvider).stopTracking();
                  ref.read(isTrackingProvider.notifier).state = false;
                  setState(() => _trackingOrderId = null);
                }

                await driverService.completeDelivery(delivery.id);
                ref.invalidate(activeDeliveriesProvider(driverId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Delivery completed!'),
                      backgroundColor: const Color(0xFF22C55E),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(friendlyError(e)),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Yes, Delivered'),
          ),
        ],
      ),
    );
  }
}

// ─── Delivery Card ─────────────────────────────────────────────────────────────

class _DeliveryCard extends StatelessWidget {
  final Order delivery;
  final bool isTracking;
  final VoidCallback onToggleGps;
  final VoidCallback onNavigate;
  final VoidCallback onMarkDelivered;
  final VoidCallback? onVerifyPin;
  final VoidCallback onChat;

  bool get _contactlessPinPending =>
      delivery.contactlessDelivery && delivery.deliveryOtpVerified != true;

  const _DeliveryCard({
    required this.delivery,
    required this.isTracking,
    required this.onToggleGps,
    required this.onNavigate,
    required this.onMarkDelivered,
    required this.onChat,
    this.onVerifyPin,
  });

  Color get _statusColor {
    switch (delivery.status) {
      case 'out_for_delivery':
      case 'picked_up':
        return const Color(0xFF818CF8);
      case 'ready':
        return const Color(0xFFFBBF24);
      default:
        return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isTracking
              ? const Color(0xFF22C55E).withValues(alpha: 0.4)
              : const Color(0xFF2A2D3E),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    delivery.status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _statusColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '#${delivery.id.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Total & items count
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Text(
                  'JMD\$${delivery.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '· ${delivery.items.length} item(s)',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),

          // Address
          if (delivery.deliveryAddress != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    size: 15,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      delivery.deliveryAddress!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Items chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: delivery.items
                  .map(
                    (item) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2D3E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${item.itemName} ×${item.quantity}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

          // Badges row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // Contactless badge
                if (delivery.contactlessDelivery)
                  _StatusBadge(
                    icon: _contactlessPinPending
                        ? Icons.contactless_rounded
                        : Icons.check_circle_rounded,
                    text: _contactlessPinPending
                        ? 'PIN verification required'
                        : 'PIN verified',
                    color: _contactlessPinPending
                        ? const Color(0xFF818CF8)
                        : const Color(0xFF22C55E),
                  ),
                // GPS tracking badge
                if (isTracking)
                  const _StatusBadge(
                    icon: Icons.gps_fixed_rounded,
                    text: 'Broadcasting live location',
                    color: Color(0xFF22C55E),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Divider
          Container(height: 1, color: const Color(0xFF2A2D3E)),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _CardAction(
                  icon: isTracking
                      ? Icons.gps_off_rounded
                      : Icons.gps_fixed_rounded,
                  label: isTracking ? 'Stop' : 'GPS',
                  color: isTracking
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF818CF8),
                  isOutlined: true,
                  onTap: onToggleGps,
                ),
                const SizedBox(width: 8),
                _CardAction(
                  icon: Icons.call_rounded,
                  label: 'Call',
                  color: const Color(0xFF22C55E),
                  onTap: onChat,
                ),
                const SizedBox(width: 8),
                _CardAction(
                  icon: Icons.navigation_rounded,
                  label: 'Navigate',
                  color: const Color(0xFF3B82F6),
                  onTap: onNavigate,
                ),
                if (delivery.contactlessDelivery && onVerifyPin != null) ...[
                  const SizedBox(width: 8),
                  _CardAction(
                    icon: Icons.pin_rounded,
                    label: 'PIN',
                    color: const Color(0xFF818CF8),
                    onTap: onVerifyPin!,
                  ),
                ],
                const SizedBox(width: 8),
                _CardAction(
                  icon: _contactlessPinPending
                      ? Icons.lock_rounded
                      : Icons.check_circle_rounded,
                  label: _contactlessPinPending ? 'Locked' : 'Done',
                  color: _contactlessPinPending
                      ? const Color(0xFF6B7280)
                      : const Color(0xFF22C55E),
                  onTap: onMarkDelivered,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status Badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _StatusBadge({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Card Action Button ────────────────────────────────────────────────────────

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isOutlined;

  const _CardAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isOutlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: isOutlined ? Colors.transparent : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: isOutlined
                  ? Border.all(color: color.withValues(alpha: 0.3))
                  : null,
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_shipping_outlined,
              size: 40,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Active Deliveries',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Accept an order to start delivering.',
            style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}
