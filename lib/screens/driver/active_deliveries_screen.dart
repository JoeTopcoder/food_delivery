import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_constants.dart';
import '../../models/order_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/driver_intelligence_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/driver/delivery_fee_service.dart';
import '../../services/location_service.dart';
import '../../widgets/sos_button.dart';
import '../../widgets/order_countdown_timer.dart';
import 'delivery_proof_screen.dart';
import 'multi_stop_delivery_screen.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import '../../utils/context_extensions.dart';
import '../../core/utils/responsive.dart';

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
        AppSnackbar.info(context, 'GPS tracking stopped');
      }
    } else {
      final hasPermission = await locationService.requestPermission();
      if (!hasPermission) {
        if (mounted) {
          AppSnackbar.warning(
            context,
            'Location permission required for tracking',
          );
        }
        return;
      }
      await locationService.startTracking(driverId: driverId, orderId: orderId);
      ref.read(isTrackingProvider.notifier).state = true;
      setState(() => _trackingOrderId = orderId);
      if (mounted) {
        AppSnackbar.success(context, 'GPS tracking started');
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
        final multiTasksAsync = ref.watch(activeDeliveryTasksProvider(driver.id));
        ref.watch(deliveryTaskRealtimeProvider(driver.id)); // keep realtime alive
        final locationService = ref.read(locationServiceProvider);
        final isTracking = ref.watch(isTrackingProvider);

        return Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // ── App Bar ────────────────────────────────────────────
              SliverAppBar(
                pinned: true,
                backgroundColor: const Color(0xFF0F1117),
                foregroundColor: Colors.white,
                elevation: 0,
                title: Text(
                  context.l10n.activeDeliveries,
                  style: const TextStyle(
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
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PulsingDot(),
                          SizedBox(width: 5),
                          Text(
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

              // ── Multi-stop delivery tasks ──────────────────────────
              if (multiTasksAsync.valueOrNull?.isNotEmpty == true)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          Responsive.horizontalPadding(context), 12,
                          Responsive.horizontalPadding(context), 6,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.route_rounded,
                                color: AppTheme.primaryColor, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Multi-Stop Deliveries',
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w700,
                                fontSize: Responsive.smallText(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...multiTasksAsync.valueOrNull!.map((task) {
                        final stops = ((task['delivery_stops'] as List?) ?? [])
                            .cast<Map<String, dynamic>>();
                        final completedStops =
                            stops.where((s) => s['status'] == 'completed').length;
                        final earning =
                            (task['driver_earning'] as num?)?.toDouble() ?? 0.0;
                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MultiStopDeliveryScreen(
                                deliveryTaskId: task['id'] as String,
                                driverId: driver.id,
                              ),
                            ),
                          ),
                          child: Container(
                            margin: EdgeInsets.fromLTRB(
                              Responsive.horizontalPadding(context), 0,
                              Responsive.horizontalPadding(context), 8,
                            ),
                            padding: EdgeInsets.all(Responsive.cardPadding(context)),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E2030),
                              borderRadius: BorderRadius.circular(
                                  Responsive.cardRadius(context)),
                              border: Border.all(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.route_rounded,
                                      color: AppTheme.primaryColor, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${stops.length - 1} Pickup${stops.length - 1 != 1 ? "s" : ""} + 1 Drop-off',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$completedStops/${stops.length} stops done · ${AppConstants.currencySymbol}${earning.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded,
                                    color: Colors.white38),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

              // ── Body ──────────────────────────────────────────────
              deliveriesAsync.when(
                data: (deliveries) {
                  if (deliveries.isEmpty) {
                    return const SliverFillRemaining(
                      child: AppEmptyState(
                        icon: Icons.local_shipping_outlined,
                        title: 'No Active Deliveries',
                        subtitle: 'Accept an order to start delivering.',
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context), 8, Responsive.horizontalPadding(context), 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final delivery = deliveries[index];
                        final isThisTracked =
                            isTracking && _trackingOrderId == delivery.id;
                        return _DeliveryCard(
                          delivery: delivery,
                          driverId: driver.id,
                          driverLat: driver.currentLatitude,
                          driverLng: driver.currentLongitude,
                          isTracking: isThisTracked,
                          onToggleGps: () => _toggleTracking(
                            locationService,
                            driver.id,
                            delivery.id,
                          ),
                          onNavigateToRestaurant: null, // set below via card
                          onNavigateToCustomer: () =>
                              _navigateToCustomer(delivery),
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
                  child: AppLoadingIndicator(message: 'Loading deliveries...'),
                ),
                error: (err, _) => SliverFillRemaining(
                  child: AppErrorState(message: friendlyError(err)),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: AppLoadingIndicator(message: 'Loading driver profile...'),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        body: AppErrorState(message: friendlyError(err)),
      ),
    );
  }

  void _navigateToCustomer(Order delivery) async {
    final lat = delivery.deliveryLatitude;
    final lng = delivery.deliveryLongitude;
    if (lat != null && lng != null) {
      _openNavigation(lat, lng);
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
        AppSnackbar.warning(context, 'No delivery address available');
      }
    }
  }

  void _openNavigation(double lat, double lng) async {
    final googleUrl = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final fallbackUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    if (await canLaunchUrl(googleUrl)) {
      await launchUrl(googleUrl);
    } else {
      await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
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
          content: Text(
            'This is a contactless delivery. You must verify the customer\'s 4-digit PIN before marking it as delivered.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
                ref.invalidate(deliveryHistoryProvider(driverId));
                ref.invalidate(driverStatsProvider(driverId));
                final userId = ref.read(currentUserIdProvider);
                if (userId != null) {
                  ref.invalidate(driverProfileProvider(userId));
                }
                if (context.mounted) {
                  AppSnackbar.success(context, 'Delivery completed!');
                }
              } catch (e) {
                if (context.mounted) {
                  AppSnackbar.error(context, friendlyError(e));
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

// ─── Delivery Card (matches Available Orders design) ───────────────────────────

class _DeliveryCard extends ConsumerWidget {
  final Order delivery;
  final String driverId;
  final double? driverLat;
  final double? driverLng;
  final bool isTracking;
  final VoidCallback onToggleGps;
  final VoidCallback? onNavigateToRestaurant;
  final VoidCallback onNavigateToCustomer;
  final VoidCallback onChat;
  final VoidCallback onMarkDelivered;
  final VoidCallback? onVerifyPin;

  const _DeliveryCard({
    required this.delivery,
    required this.driverId,
    required this.isTracking,
    required this.onToggleGps,
    required this.onNavigateToCustomer,
    required this.onChat,
    required this.onMarkDelivered,
    this.onNavigateToRestaurant,
    this.onVerifyPin,
    this.driverLat,
    this.driverLng,
  });

  bool get _contactlessPinPending =>
      delivery.contactlessDelivery && delivery.deliveryOtpVerified != true;

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
  Widget build(BuildContext context, WidgetRef ref) {
    // Fetch restaurant info
    final restAsync = ref.watch(restaurantByIdProvider(delivery.restaurantId));
    final restaurant = restAsync.valueOrNull;

    final restLat = restaurant?.latitude;
    final restLng = restaurant?.longitude;
    final dropLat = delivery.deliveryLatitude;
    final dropLng = delivery.deliveryLongitude;

    double? driverToRestKm;
    double? restToDropKm;
    double? totalKm;
    int? estMinutes;

    if (restLat != null &&
        restLng != null &&
        dropLat != null &&
        dropLng != null) {
      restToDropKm = DeliveryFeeService.haversineKm(
        restLat,
        restLng,
        dropLat,
        dropLng,
      );
      if (driverLat != null && driverLng != null) {
        driverToRestKm = DeliveryFeeService.haversineKm(
          driverLat!,
          driverLng!,
          restLat,
          restLng,
        );
        totalKm = driverToRestKm + restToDropKm;
      } else {
        totalKm = restToDropKm;
      }
      estMinutes = (totalKm * 3 + 5).round();
    }

    // Driver pay = $1.50/mile × distance (minimum $3)
    final distanceMiles = (restToDropKm ?? 0) * AppConstants.kmToMiles;
    final driverPay = (distanceMiles * AppConstants.driverRatePerMile).clamp(
      AppConstants.driverMinBasePay,
      double.infinity,
    );
    final tipAmount = delivery.driverTip ?? 0;
    final totalPay = driverPay + tipAmount;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isTracking
              ? const Color(0xFF22C55E).withValues(alpha: 0.4)
              : const Color(0xFF2A2D3E),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Map ──────────────────────────────────────────────────
          if (restLat != null && restLng != null)
            _DeliveryMap(
              driverLat: driverLat,
              driverLng: driverLng,
              restLat: restLat,
              restLng: restLng,
              dropLat: dropLat,
              dropLng: dropLng,
            ),

          // ── Pay + status banner ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF162016),
              border: Border(bottom: BorderSide(color: Color(0xFF2A2D3E))),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            delivery.status.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              color: _statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '#${delivery.id.substring(0, 8).toUpperCase()}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${AppConstants.currencySymbol}${totalPay.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: Colors.white,
                      ),
                    ),
                    if (tipAmount > 0)
                      Text(
                        'Includes ${AppConstants.currencySymbol}${tipAmount.toStringAsFixed(2)} tip',
                        style: const TextStyle(
                          color: Color(0xFF22C55E),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (estMinutes != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$estMinutes min',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    if (totalKm != null)
                      Text(
                        '${(totalKm * AppConstants.kmToMiles).toStringAsFixed(1)} mi',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── Route details ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                // Restaurant pickup
                _RouteRow(
                  icon: Icons.store_rounded,
                  iconColor: const Color(0xFF22C55E),
                  label: restaurant?.name ?? 'Restaurant',
                  subtitle: driverToRestKm != null
                      ? '${driverToRestKm.toStringAsFixed(1)} km from you'
                      : null,
                  onNavigate: restLat != null && restLng != null
                      ? () => _openNav(restLat, restLng)
                      : null,
                ),
                // Connector line
                Padding(
                  padding: const EdgeInsets.only(left: 15),
                  child: Row(
                    children: [
                      Container(
                        width: 2,
                        height: 24,
                        color: const Color(0xFF2A2D3E),
                      ),
                      if (restToDropKm != null) ...[
                        const SizedBox(width: 16),
                        Text(
                          '${restToDropKm.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Drop-off
                _RouteRow(
                  icon: Icons.location_on_rounded,
                  iconColor: const Color(0xFFEF4444),
                  label: delivery.deliveryAddress ?? 'Drop-off',
                  onNavigate: dropLat != null && dropLng != null
                      ? () => _openNav(dropLat, dropLng)
                      : null,
                ),
              ],
            ),
          ),

          // ── Countdown timer ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: OrderCountdownTimer(
              orderedAt: delivery.orderedAt,
              estimatedMinutes: delivery.estimatedPrepMinutes,
            ),
          ),

          // ── Item chips ──────────────────────────────────────────
          if (delivery.items.isNotEmpty)
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
                          '${item.itemName} x${item.quantity}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

          // ── Badges ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
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
          Container(height: 1, color: const Color(0xFF2A2D3E)),

          // ── Action buttons ──────────────────────────────────────
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
                  icon: Icons.chat_rounded,
                  label: 'Chat',
                  color: const Color(0xFF22C55E),
                  onTap: onChat,
                ),
                const SizedBox(width: 8),
                _CardAction(
                  icon: Icons.navigation_rounded,
                  label: 'Navigate',
                  color: const Color(0xFF3B82F6),
                  onTap: onNavigateToCustomer,
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

  void _openNav(double lat, double lng) async {
    final googleUrl = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final fallbackUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    if (await canLaunchUrl(googleUrl)) {
      await launchUrl(googleUrl);
    } else {
      await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
    }
  }
}

// ─── Route Row ─────────────────────────────────────────────────────────────────

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final VoidCallback? onNavigate;

  const _RouteRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(color: Colors.grey[700], fontSize: 11),
                ),
            ],
          ),
        ),
        if (onNavigate != null)
          IconButton(
            onPressed: onNavigate,
            icon: const Icon(Icons.navigation_rounded, size: 20),
            color: AppTheme.primaryColor,
            tooltip: 'Navigate',
          ),
      ],
    );
  }
}

// ─── Mini Map ──────────────────────────────────────────────────────────────────

class _DeliveryMap extends StatelessWidget {
  final double? driverLat;
  final double? driverLng;
  final double restLat;
  final double restLng;
  final double? dropLat;
  final double? dropLng;

  const _DeliveryMap({
    this.driverLat,
    this.driverLng,
    required this.restLat,
    required this.restLng,
    this.dropLat,
    this.dropLng,
  });

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    final allPoints = <LatLng>[];

    // Driver marker (blue car)
    if (driverLat != null && driverLng != null) {
      final driverPos = LatLng(driverLat!, driverLng!);
      allPoints.add(driverPos);
      markers.add(
        Marker(
          point: driverPos,
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blueAccent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.directions_car_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      );
    }

    // Restaurant marker (green store)
    final restPos = LatLng(restLat, restLng);
    allPoints.add(restPos);
    markers.add(
      Marker(
        point: restPos,
        width: 36,
        height: 36,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(Icons.store_rounded, color: Colors.white, size: 18),
        ),
      ),
    );

    // Drop-off marker (red pin)
    if (dropLat != null && dropLng != null) {
      final dropPos = LatLng(dropLat!, dropLng!);
      allPoints.add(dropPos);
      markers.add(
        Marker(
          point: dropPos,
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      );
    }

    final center = _centerOf(allPoints);
    final zoom = _fitZoom(allPoints);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: SizedBox(
        height: 180,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                interactionOptions: const InteractionOptions(
                  flags:
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.drag |
                      InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'sevendash.app',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => _showFullscreenMap(
                  context,
                  center: center,
                  zoom: zoom,
                  markers: markers,
                ),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.fullscreen_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showFullscreenMap(
    BuildContext context, {
    required LatLng center,
    required double zoom,
    required List<Marker> markers,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, __) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'sevendash.app',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
        ),
      ),
    );
  }

  LatLng _centerOf(List<LatLng> points) {
    double lat = 0, lng = 0;
    for (final p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }

  double _fitZoom(List<LatLng> points) {
    if (points.length < 2) return 14;
    double maxDist = 0;
    for (int i = 0; i < points.length; i++) {
      for (int j = i + 1; j < points.length; j++) {
        final d = DeliveryFeeService.haversineKm(
          points[i].latitude,
          points[i].longitude,
          points[j].latitude,
          points[j].longitude,
        );
        if (d > maxDist) maxDist = d;
      }
    }
    if (maxDist < 1) return 15;
    if (maxDist < 3) return 14;
    if (maxDist < 8) return 13;
    if (maxDist < 15) return 12;
    if (maxDist < 30) return 11;
    return 10;
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

// ─── Pulsing Dot ───────────────────────────────────────────────────────────────

class _PulsingDot extends StatelessWidget {
  const _PulsingDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Color(0xFF22C55E),
        shape: BoxShape.circle,
      ),
    );
  }
}
