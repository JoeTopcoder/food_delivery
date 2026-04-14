import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../../models/order_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/sos_button.dart';
import '../../widgets/order_countdown_timer.dart';
import '../../utils/friendly_error.dart';
import '../../providers/wallet_provider.dart';
import '../../utils/app_feedback_widgets.dart';

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String? orderId;
  const OrderTrackingScreen({super.key, this.orderId});

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  final MapController _mapController = MapController();

  int _getStatusIndex(String status) {
    switch (status) {
      case 'pending':
        return 0;
      case 'confirmed':
        return 1;
      case 'preparing':
        return 2;
      case 'ready':
        return 3;
      case 'picked_up':
      case 'out_for_delivery':
        return 4;
      case 'delivered':
        return 5;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderId = widget.orderId;

    if (orderId == null || orderId.isEmpty) {
      final currentUserId = ref.watch(currentUserIdProvider);
      if (currentUserId == null) {
        return const Scaffold(body: Center(child: Text('Not logged in')));
      }
      final ordersAsync = ref.watch(userOrdersProvider(currentUserId));
      return ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Order Tracking'),
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.white,
                foregroundColor: AppTheme.textPrimary,
              ),
              body: const AppEmptyState(
                icon: Icons.receipt_long_rounded,
                title: 'No Orders Found',
                subtitle: 'Your order history will appear here',
              ),
            );
          }
          return _buildContent(orders.first);
        },
        loading: () => const Scaffold(
          body: AppLoadingIndicator(message: 'Loading orders...'),
        ),
        error: (err, _) =>
            Scaffold(body: AppErrorState(message: friendlyError(err))),
      );
    }

    final orderAsync = ref.watch(orderByIdProvider(orderId));
    return orderAsync.when(
      data: (order) {
        if (order == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Order Tracking')),
            body: const AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Order Not Found',
              subtitle: 'This order may have been removed',
            ),
          );
        }
        return _buildContent(order);
      },
      loading: () => const Scaffold(
        body: AppLoadingIndicator(message: 'Loading order...'),
      ),
      error: (err, _) =>
          Scaffold(body: AppErrorState(message: friendlyError(err))),
    );
  }

  Widget _buildContent(Order order) {
    // Watch real-time order updates
    final realtimeAsync = ref.watch(orderRealtimeStreamProvider(order.id));
    final liveOrder = realtimeAsync.when(
      data: (data) {
        if (data == null) return order;
        final updatedStatus = data['status'] as String? ?? order.status;
        return order.copyWith(status: updatedStatus);
      },
      loading: () => order,
      error: (_, _) => order,
    );

    final statusIndex = _getStatusIndex(liveOrder.status);
    final driverId = liveOrder.driverId;

    // Watch live driver location if a driver is assigned
    Map<String, dynamic>? driverLocation;
    if (driverId != null && driverId.isNotEmpty) {
      final locationAsync = ref.watch(driverLocationStreamProvider(driverId));
      driverLocation = locationAsync.asData?.value;
    }

    final hasMap =
        !order.isPickup &&
        driverId != null &&
        driverId.isNotEmpty &&
        statusIndex >= 4 &&
        liveOrder.status != 'delivered';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Order #${order.id.substring(0, 8).toUpperCase()}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: const [SosButton()],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Status banner
            _StatusBanner(status: liveOrder.status, statusIndex: statusIndex),

            // Countdown timer (active orders only)
            if (liveOrder.status != 'delivered' &&
                liveOrder.status != 'cancelled')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: OrderCountdownTimer(
                  orderedAt: order.orderedAt,
                  estimatedMinutes: order.estimatedPrepMinutes,
                ),
              ),

            // Live map (only during delivery)
            if (hasMap)
              _LiveMap(
                driverLocation: driverLocation,
                deliveryLat: order.deliveryLatitude,
                deliveryLng: order.deliveryLongitude,
                mapController: _mapController,
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Delivery PIN card (contactless, not yet delivered)
                  if (!order.isPickup &&
                      order.contactlessDelivery &&
                      order.deliveryOtp != null &&
                      liveOrder.status != 'delivered' &&
                      liveOrder.status != 'cancelled')
                    _DeliveryPinCard(otp: order.deliveryOtp!),

                  if (!order.isPickup &&
                      order.contactlessDelivery &&
                      order.deliveryOtp != null &&
                      liveOrder.status != 'delivered' &&
                      liveOrder.status != 'cancelled')
                    const SizedBox(height: 12),

                  // Pickup code card (pickup orders)
                  if (order.isPickup &&
                      liveOrder.status != 'delivered' &&
                      liveOrder.status != 'cancelled')
                    _PickupCodeCard(pickupCode: order.pickupCode),

                  if (order.isPickup &&
                      liveOrder.status != 'delivered' &&
                      liveOrder.status != 'cancelled')
                    const SizedBox(height: 12),

                  // ETA display
                  if (liveOrder.estimatedDeliveryAt != null &&
                      liveOrder.status != 'delivered' &&
                      liveOrder.status != 'cancelled')
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.schedule,
                            color: Color(0xFF10B981),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Estimated delivery: ${DateFormat.jm().format(liveOrder.estimatedDeliveryAt!)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF10B981),
                              fontSize: 14,
                            ),
                          ),
                          if (liveOrder.estimatedDeliveryAt!.isAfter(
                            DateTime.now(),
                          )) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(${liveOrder.estimatedDeliveryAt!.difference(DateTime.now()).inMinutes} min)',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                  // Timeline card
                  _TimelineCard(order: liveOrder, statusIndex: statusIndex),
                  const SizedBox(height: 12),

                  // Order items card
                  _OrderDetailsCard(order: liveOrder),

                  const SizedBox(height: 12),

                  // Delivery address
                  if (order.deliveryAddress != null)
                    _AddressCard(address: order.deliveryAddress!),

                  const SizedBox(height: 12),

                  // Rate order button (delivered only, not yet rated)
                  if (liveOrder.status == 'delivered' &&
                      liveOrder.userRating == null)
                    _RateButton(order: liveOrder),

                  // Cancel order (only pending or confirmed — not yet preparing)
                  if (liveOrder.status == 'pending' ||
                      liveOrder.status == 'confirmed') ...[
                    const SizedBox(height: 8),
                    _CancelOrderButton(orderId: order.id),
                  ],

                  // Chat with driver (active orders with driver assigned)
                  if (driverId != null &&
                      driverId.isNotEmpty &&
                      liveOrder.status != 'delivered' &&
                      liveOrder.status != 'cancelled') ...[
                    const SizedBox(height: 8),
                    _ChatButton(orderId: order.id, driverId: driverId),
                  ],

                  // Contact Support (all non-cancelled orders)
                  if (liveOrder.status != 'cancelled') ...[
                    const SizedBox(height: 8),
                    _SupportChatButton(orderId: order.id),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Status Banner ────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final String status;
  final int statusIndex;
  const _StatusBanner({required this.status, required this.statusIndex});

  Color get _color {
    switch (status) {
      case 'delivered':
        return const Color(0xFF10B981);
      case 'out_for_delivery':
      case 'picked_up':
        return const Color(0xFF6366F1);
      case 'preparing':
        return const Color(0xFFF59E0B);
      case 'cancelled':
        return Colors.red;
      default:
        return AppTheme.primaryColor;
    }
  }

  IconData get _icon {
    switch (status) {
      case 'delivered':
        return Icons.check_circle_rounded;
      case 'out_for_delivery':
      case 'picked_up':
        return Icons.directions_bike_rounded;
      case 'preparing':
        return Icons.restaurant_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }

  String get _label {
    switch (status) {
      case 'pending':
        return 'Order Placed';
      case 'confirmed':
        return 'Order Confirmed';
      case 'preparing':
        return 'Preparing Your Food';
      case 'ready':
        return 'Ready for Pickup';
      case 'out_for_delivery':
      case 'picked_up':
        return 'Out for Delivery';
      case 'delivered':
        return 'Order Delivered!';
      case 'cancelled':
        return 'Order Cancelled';
      default:
        return status.replaceAll('_', ' ').toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      color: _color,
      child: Column(
        children: [
          Icon(_icon, color: Colors.white, size: 40),
          const SizedBox(height: 8),
          Text(
            _label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Live Map ─────────────────────────────────────────────────────────────────

class _LiveMap extends StatelessWidget {
  final Map<String, dynamic>? driverLocation;
  final double? deliveryLat;
  final double? deliveryLng;
  final MapController mapController;

  const _LiveMap({
    required this.driverLocation,
    required this.deliveryLat,
    required this.deliveryLng,
    required this.mapController,
  });

  @override
  Widget build(BuildContext context) {
    final driverLat =
        (driverLocation?['latitude'] as num?)?.toDouble() ?? 23.8103;
    final driverLng =
        (driverLocation?['longitude'] as num?)?.toDouble() ?? 90.4125;
    final driverPos = LatLng(driverLat, driverLng);

    final markers = <Marker>[
      Marker(
        point: driverPos,
        width: 44,
        height: 44,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.directions_bike_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    ];

    if (deliveryLat != null && deliveryLng != null) {
      markers.add(
        Marker(
          point: LatLng(deliveryLat!, deliveryLng!),
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.home_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 220,
      margin: const EdgeInsets.only(bottom: 4),
      child: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(initialCenter: driverPos, initialZoom: 14),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.foodhub.delivery',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Live',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Timeline Card ─────────────────────────────────────────────────────────────

class _TimelineCard extends StatelessWidget {
  final Order order;
  final int statusIndex;
  const _TimelineCard({required this.order, required this.statusIndex});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('h:mm a');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Timeline',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 14),
          _TimelineRow(
            title: 'Order Placed',
            subtitle: fmt.format(order.orderedAt),
            isCompleted: true,
            isCurrent: statusIndex == 0,
          ),
          _TimelineRow(
            title: 'Confirmed',
            subtitle: order.confirmedAt != null
                ? fmt.format(order.confirmedAt!)
                : 'Pending',
            isCompleted: statusIndex >= 1,
            isCurrent: statusIndex == 1,
          ),
          _TimelineRow(
            title: 'Preparing',
            subtitle: statusIndex >= 2 ? 'In progress' : 'Waiting',
            isCompleted: statusIndex >= 2,
            isCurrent: statusIndex == 2,
          ),
          _TimelineRow(
            title: 'Out for Delivery',
            subtitle: statusIndex >= 4 ? 'On the way' : 'Waiting',
            isCompleted: statusIndex >= 4,
            isCurrent: statusIndex == 3 || statusIndex == 4,
          ),
          _TimelineRow(
            title: 'Delivered',
            subtitle: order.completedAt != null
                ? fmt.format(order.completedAt!)
                : 'Estimated',
            isCompleted: statusIndex >= 5,
            isCurrent: statusIndex == 5,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isCompleted;
  final bool isCurrent;
  final bool isLast;

  const _TimelineRow({
    required this.title,
    required this.subtitle,
    required this.isCompleted,
    required this.isCurrent,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    const orange = AppTheme.primaryColor;
    final dotColor = isCompleted || isCurrent
        ? orange
        : const Color(0xFFD1D5DB);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
              child: isCompleted
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: isCompleted ? orange : const Color(0xFFE5E7EB),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                    color: isCompleted || isCurrent
                        ? const Color(0xFF1F2937)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Order Details Card ────────────────────────────────────────────────────────

class _OrderDetailsCard extends StatelessWidget {
  final Order order;
  const _OrderDetailsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Summary',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.itemName} ×${item.quantity}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF4B5563),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '\$${item.subtotal.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(color: Colors.grey[200], height: 20),
          _Row('Subtotal', '\$${order.subtotal.toStringAsFixed(0)}'),
          _Row('Delivery Fee', '\$${order.deliveryFee.toStringAsFixed(0)}'),
          if (order.taxAmount != null)
            _Row('Tax', '\$${order.taxAmount!.toStringAsFixed(0)}'),
          const SizedBox(height: 4),
          _Row(
            'Total',
            '\$${order.totalAmount.toStringAsFixed(0)}',
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _Row(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.w400,
                color: bold ? const Color(0xFF1F2937) : const Color(0xFF6B7280),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: const Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Address Card ─────────────────────────────────────────────────────────────

class _AddressCard extends StatelessWidget {
  final String address;
  const _AddressCard({required this.address});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: AppTheme.primaryColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Delivering to',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
                const SizedBox(height: 2),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Rate Button ───────────────────────────────────────────────────────────────

class _RateButton extends StatelessWidget {
  final Order order;
  const _RateButton({required this.order});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: () =>
            Navigator.pushNamed(context, '/review', arguments: order),
        icon: const Icon(Icons.star_rounded),
        label: const Text(
          'Rate Your Order',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          foregroundColor: AppTheme.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

// ─── Chat Button ──────────────────────────────────────────────────────────────

class _ChatButton extends StatelessWidget {
  final String orderId;
  final String? driverId;
  const _ChatButton({required this.orderId, this.driverId});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.pushNamed(
          context,
          '/chat',
          arguments: {
            'orderId': orderId,
            'otherPartyName': 'Driver',
            'receiverId': driverId,
          },
        ),
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        label: const Text(
          'Chat with Driver',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF6366F1),
          side: const BorderSide(color: Color(0xFF6366F1)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

// ─── Support Chat Button ──────────────────────────────────────────────────────

class _SupportChatButton extends ConsumerStatefulWidget {
  final String orderId;
  const _SupportChatButton({required this.orderId});

  @override
  ConsumerState<_SupportChatButton> createState() => _SupportChatButtonState();
}

class _SupportChatButtonState extends ConsumerState<_SupportChatButton> {
  bool _loading = false;

  Future<void> _openSupport() async {
    setState(() => _loading = true);
    try {
      final adminId = await ref.read(chatServiceProvider).getAnAdminUserId();
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/chat',
        arguments: {
          'orderId': widget.orderId,
          'otherPartyName': 'Support',
          'receiverId': adminId,
        },
      );
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _openSupport,
        icon: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primaryColor,
                ),
              )
            : const Icon(Icons.headset_mic_rounded),
        label: const Text(
          'Contact Support',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryColor,
          side: const BorderSide(color: AppTheme.primaryColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

// ─── Cancel Order Button ──────────────────────────────────────────────────────

class _CancelOrderButton extends ConsumerWidget {
  final String orderId;
  const _CancelOrderButton({required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: () => _confirmCancel(context, ref),
        icon: const Icon(Icons.cancel_outlined),
        label: const Text(
          'Cancel Order',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  void _confirmCancel(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Order?'),
        content: const Text(
          'Cancellation within 2 minutes is free. '
          'After that, a \$200 fee applies. '
          'If the restaurant is already preparing, a 15% fee may be charged.\n\n'
          'If you paid with your wallet, the order amount will be '
          'refunded minus any cancellation fee.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No, Keep Order'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final result = await ref
                    .read(walletNotifierProvider.notifier)
                    .cancelOrder(orderId);
                ref.invalidate(userOrdersProvider);
                if (context.mounted) {
                  final refund = (result['refund'] as num?)?.toDouble() ?? 0;
                  final penalty = (result['penalty'] as num?)?.toDouble() ?? 0;
                  final message = refund > 0
                      ? 'Order cancelled. \$${refund.toStringAsFixed(2)} refunded to wallet.'
                      : penalty > 0
                      ? 'Order cancelled. \$${penalty.toStringAsFixed(2)} fee applied.'
                      : 'Order cancelled';
                  AppSnackbar.success(context, message);
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  AppSnackbar.error(context, friendlyError(e));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }
}

// ─── Report Issue Button ──────────────────────────────────────────────────────

// ignore: unused_element
class _ReportIssueButton extends StatelessWidget {
  final String orderId;
  const _ReportIssueButton({required this.orderId});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ReportIssueSheet(orderId: orderId),
        ),
        icon: const Icon(Icons.flag_outlined),
        label: const Text(
          'Report an Issue',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

// ─── Report Issue Sheet ───────────────────────────────────────────────────────

class _ReportIssueSheet extends ConsumerStatefulWidget {
  final String orderId;
  const _ReportIssueSheet({required this.orderId});

  @override
  ConsumerState<_ReportIssueSheet> createState() => _ReportIssueSheetState();
}

class _ReportIssueSheetState extends ConsumerState<_ReportIssueSheet> {
  final _descCtrl = TextEditingController();
  String _type = 'missing_item';
  bool _loading = false;

  static const _types = [
    ('missing_item', 'Missing Item'),
    ('wrong_order', 'Wrong Order'),
    ('late_delivery', 'Late Delivery'),
    ('quality_issue', 'Quality Issue'),
    ('other', 'Other'),
  ];

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_descCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final userId = ref.read(currentUserIdProvider) ?? '';
      final chatService = ref.read(chatServiceProvider);
      await chatService.reportIssue(
        orderId: widget.orderId,
        userId: userId,
        issueType: _type,
        description: _descCtrl.text.trim(),
      );

      // Auto-send first chat message with the issue details
      final typeLabel = _types
          .firstWhere((t) => t.$1 == _type, orElse: () => ('other', 'Other'))
          .$2;
      await chatService.sendMessage(
        orderId: widget.orderId,
        senderId: userId,
        senderRole: 'user',
        message: '⚠️ Issue Reported: $typeLabel\n${_descCtrl.text.trim()}',
      );

      if (mounted) {
        Navigator.pop(context); // close sheet
        // Navigate to chat with restaurant
        Navigator.pushNamed(
          context,
          '/chat',
          arguments: {
            'orderId': widget.orderId,
            'otherPartyName': 'Restaurant Support',
          },
        );
        AppSnackbar.success(
          context,
          'Issue reported — chat started with restaurant.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Report an Issue',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 14),
            // Issue type chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _types.map((t) {
                final selected = _type == t.$1;
                return ChoiceChip(
                  label: Text(t.$2),
                  selected: selected,
                  onSelected: (_) => setState(() => _type = t.$1),
                  selectedColor: Colors.red.withValues(alpha: 0.12),
                  labelStyle: TextStyle(
                    color: selected ? Colors.red : const Color(0xFF6B7280),
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Describe the issue...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      )
                    : const Text(
                        'Submit Report',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Delivery PIN Card ────────────────────────────────────────────────────────

class _DeliveryPinCard extends StatelessWidget {
  final String otp;
  const _DeliveryPinCard({required this.otp});

  @override
  Widget build(BuildContext context) {
    final digits = otp.split('');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.contactless_rounded,
                color: Color(0xFF6366F1),
                size: 20,
              ),
              SizedBox(width: 6),
              Text(
                'Contactless Delivery PIN',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6366F1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: digits
                .map(
                  (d) => Container(
                    width: 48,
                    height: 56,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      d,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          const Text(
            'Share this PIN with the driver to confirm delivery',
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Pickup Code Card ─────────────────────────────────────────────────────────

class _PickupCodeCard extends StatelessWidget {
  final String? pickupCode;
  const _PickupCodeCard({this.pickupCode});

  @override
  Widget build(BuildContext context) {
    if (pickupCode == null || pickupCode!.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_bag_rounded,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
                SizedBox(width: 6),
                Text(
                  'Pickup Order',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'The restaurant will provide a pickup code\nonce your order is ready.',
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final digits = pickupCode!.split('');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shopping_bag_rounded,
                color: Color(0xFF10B981),
                size: 20,
              ),
              SizedBox(width: 6),
              Text(
                'Your Pickup Code',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: digits
                .map(
                  (d) => Container(
                    width: 48,
                    height: 56,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      d,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          const Text(
            'Show this code at the restaurant to collect your order',
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
