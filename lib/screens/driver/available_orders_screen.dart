import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_constants.dart';
import '../../models/order_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/delivery_fee_service.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import '../../utils/context_extensions.dart';

class AvailableOrdersScreen extends ConsumerWidget {
  const AvailableOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(currentUserIdProvider);
    ref.watch(driverOrderRealtimeProvider);

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

        // ── Offline guard ───────────────────────────────────────────
        if (!driver.isAvailable) {
          return Scaffold(
            backgroundColor: const Color(0xFF0F1117),
            appBar: AppBar(
              backgroundColor: const Color(0xFF0F1117),
              foregroundColor: Colors.white,
              elevation: 0,
              title: Text(
                context.l10n.availableOrders,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
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
                        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        size: 40,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "You're Offline",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Go online from the dashboard to see and accept delivery orders.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await ref
                              .read(
                                driverAvailabilityProvider(driver.id).notifier,
                              )
                              .toggleAvailability();
                          ref.invalidate(driverProfileProvider(currentUserId));
                        },
                        icon: const Icon(Icons.power_settings_new_rounded),
                        label: const Text(
                          'Go Online',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
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

        // ── Online – show available orders ──────────────────────────
        final ordersAsync = ref.watch(availableOrdersProvider(driver.id));
        return Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F1117),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              context.l10n.availableOrders,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2030),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2A2D3E)),
                ),
                child: IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  color: const Color(0xFF9CA3AF),
                  onPressed: () => ref.invalidate(availableOrdersProvider),
                ),
              ),
            ],
          ),
          body: ordersAsync.when(
            data: (orders) {
              if (orders.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'No Orders Available',
                  subtitle: 'Pull down to refresh for new orders',
                );
              }

              return RefreshIndicator(
                color: AppTheme.primaryColor,
                backgroundColor: const Color(0xFF1E2030),
                onRefresh: () async => ref.invalidate(availableOrdersProvider),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: orders.length,
                  itemBuilder: (context, index) => _OrderCard(
                    order: orders[index],
                    driverId: driver.id,
                    driverLat: driver.currentLatitude,
                    driverLng: driver.currentLongitude,
                  ),
                ),
              );
            },
            loading: () => const Center(
              child: AppLoadingIndicator(message: 'Loading orders...'),
            ),
            error: (error, stackTrace) => AppErrorState(
              message: 'Something went wrong. Please try again.',
              onRetry: () => ref.invalidate(availableOrdersProvider),
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: AppLoadingIndicator(message: 'Loading driver profile...'),
      ),
      error: (error, stackTrace) => Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        body: AppErrorState(message: friendlyError(error)),
      ),
    );
  }
}

// ─── Order Card ────────────────────────────────────────────────────────────────

class _OrderCard extends ConsumerWidget {
  final Order order;
  final String driverId;
  final double? driverLat;
  final double? driverLng;

  const _OrderCard({
    required this.order,
    required this.driverId,
    this.driverLat,
    this.driverLng,
  });

  bool get _isReady => order.status == AppConstants.orderReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fetch restaurant info
    final restAsync = ref.watch(restaurantByIdProvider(order.restaurantId));
    final restaurant = restAsync.valueOrNull;

    // Calculate distances & driver pay
    final restLat = restaurant?.latitude;
    final restLng = restaurant?.longitude;
    final dropLat = order.deliveryLatitude;
    final dropLng = order.deliveryLongitude;

    double? totalKm;
    double? driverToRestKm;
    double? restToDropKm;
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
      // Rough estimate: ~3 min/km in city + 5 min pickup wait
      estMinutes = (totalKm * 3 + 5).round();
    }

    // Driver pay = delivery_fee × driver_pay_percent
    final driverPay = order.deliveryFee * AppConstants.driverPayPercent;
    final tipAmount = order.driverTip ?? 0;
    final totalPay = driverPay + tipAmount;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Map ──────────────────────────────────────────────────
          if (restLat != null && restLng != null)
            _OrderMap(
              driverLat: driverLat,
              driverLng: driverLng,
              restLat: restLat,
              restLng: restLng,
              dropLat: dropLat,
              dropLng: dropLng,
            ),

          // ── Pay banner ──────────────────────────────────────────
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
                            color: const Color(0xFF22C55E),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Delivery',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_isReady) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF22C55E,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'READY',
                              style: TextStyle(
                                color: Color(0xFF22C55E),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
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
                // Time + distance summary
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
                        '${totalKm.toStringAsFixed(1)} km',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
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
                      ? () => _openNavigation(restLat, restLng)
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
                  label: order.deliveryAddress ?? 'Drop-off',
                  onNavigate: dropLat != null && dropLng != null
                      ? () => _openNavigation(dropLat, dropLng)
                      : null,
                ),
              ],
            ),
          ),

          // ── Order items summary ─────────────────────────────────
          if (order.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: order.items
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
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

          // ── Notes ───────────────────────────────────────────────
          if (order.notes != null && order.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.sticky_note_2_rounded,
                    size: 14,
                    color: Color(0xFFFBBF24),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.notes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (order.contactlessDelivery)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.contactless_rounded,
                      size: 12,
                      color: Color(0xFF818CF8),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Contactless Delivery',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF818CF8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFF2A2D3E)),

          // ── Action buttons ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () async {
                        try {
                          final driverService = ref.read(driverServiceProvider);
                          await driverService.declineOrder(order.id, driverId);
                          ref.invalidate(availableOrdersProvider);
                          if (context.mounted) {
                            AppSnackbar.info(context, 'Order declined');
                          }
                        } catch (e) {
                          if (context.mounted) {
                            AppSnackbar.error(context, friendlyError(e));
                          }
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFF3A2020)),
                        backgroundColor: const Color(
                          0xFFEF4444,
                        ).withValues(alpha: 0.06),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Decline',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _acceptOrder(context, ref),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Accept',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

  void _acceptOrder(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Accept this delivery?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'You will be assigned to pick up from the restaurant and deliver to the customer.',
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[500])),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final driverService = ref.read(driverServiceProvider);
                await driverService.acceptDelivery(order.id, driverId);
                ref.invalidate(availableOrdersProvider);
                if (context.mounted) {
                  AppSnackbar.success(context, 'Order accepted!');
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
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Accept',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
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
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
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

class _OrderMap extends StatelessWidget {
  final double? driverLat;
  final double? driverLng;
  final double restLat;
  final double restLng;
  final double? dropLat;
  final double? dropLng;

  const _OrderMap({
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

    // Calculate bounds
    final center = _centerOf(allPoints);
    final zoom = _fitZoom(allPoints);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: SizedBox(
        height: 180,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.foodhub.delivery',
            ),
            MarkerLayer(markers: markers),
          ],
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
