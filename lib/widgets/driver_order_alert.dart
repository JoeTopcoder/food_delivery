import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';
import '../providers/driver_provider.dart';
import '../providers/driver_intelligence_provider.dart';
import '../providers/auth_provider.dart';
import '../config/app_constants.dart';
import '../utils/friendly_error.dart';
import '../utils/app_feedback_widgets.dart';

/// Uber-Eats-style order alert that pops in over whatever screen the driver is
/// on (dashboard included) when new orders are available. Shows every order the
/// driver can still take (capped by the backend to their remaining slots, e.g.
/// 1 active order -> up to 2 offered) stacked in one scrollable popup, each with
/// its own Accept / Decline. Each card auto-dismisses after ~8s; the popup
/// closes when all cards are gone.
class DriverOrderAlert {
  static OverlayEntry? _entry;

  /// Backward-compatible single-order entry point (used by push handlers).
  static void show({
    required String orderId,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
    int retriesLeft = 20,
  }) {
    if (orderId.isEmpty) return;
    showOrders([
      {...data, 'order_id': orderId, 'title': title},
    ], retriesLeft: retriesLeft);
  }

  /// Shows a list of orders in one popup. Each map carries: order_id,
  /// store_name/title, address, delivery_fee, tip, distance_km, eta.
  static void showOrders(
    List<Map<String, dynamic>> orders, {
    int retriesLeft = 20,
  }) {
    final valid = orders
        .where((o) => (o['order_id'] ?? '').toString().isNotEmpty)
        .toList();
    if (valid.isEmpty) return;

    final overlay = NotificationService.navigatorKey?.currentState?.overlay;
    // The overlay can be momentarily unavailable while the app is still on the
    // splash/route transition (e.g. an order-ready scan fired right at launch).
    // Retry briefly rather than dropping the alert.
    if (overlay == null) {
      if (retriesLeft > 0) {
        Future.delayed(const Duration(milliseconds: 300), () {
          showOrders(valid, retriesLeft: retriesLeft - 1);
        });
      }
      return;
    }
    _remove();
    final entry = OverlayEntry(
      builder: (_) => _OrderAlertStack(orders: valid, onEmpty: _remove),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void _remove() {
    _entry?.remove();
    _entry = null;
  }
}

/// Positions and stacks the order cards; removes cards as they're handled and
/// closes the whole popup once none remain.
class _OrderAlertStack extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  final VoidCallback onEmpty;
  const _OrderAlertStack({required this.orders, required this.onEmpty});

  @override
  State<_OrderAlertStack> createState() => _OrderAlertStackState();
}

class _OrderAlertStackState extends State<_OrderAlertStack> {
  late final List<Map<String, dynamic>> _orders =
      List<Map<String, dynamic>>.from(widget.orders);

  void _dismiss(String orderId) {
    setState(() => _orders.removeWhere(
        (o) => (o['order_id'] ?? '').toString() == orderId));
    if (_orders.isEmpty) widget.onEmpty();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      top: media.padding.top + 8,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.8),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_orders.length > 1)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_orders.length} orders available nearby',
                      style: const TextStyle(
                        color: Color(0xFF22C55E),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                for (final o in _orders)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _OrderAlertCard(
                      key: ValueKey(o['order_id']),
                      orderId: (o['order_id'] ?? '').toString(),
                      storeName:
                          (o['store_name'] ?? o['title'] ?? 'New Order')
                              .toString(),
                      address: (o['address'] ?? '').toString(),
                      deliveryFee:
                          double.tryParse((o['delivery_fee'] ?? '').toString()) ??
                              0,
                      tip: double.tryParse((o['tip'] ?? '').toString()) ?? 0,
                      etaMin: int.tryParse((o['eta'] ?? '').toString()),
                      distanceKm:
                          double.tryParse((o['distance_km'] ?? '').toString()),
                      onDismiss: () =>
                          _dismiss((o['order_id'] ?? '').toString()),
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

class _OrderAlertCard extends ConsumerStatefulWidget {
  final String orderId;
  final String storeName;
  final String address;
  final double deliveryFee;
  final double tip;
  final int? etaMin;
  final double? distanceKm;
  final VoidCallback onDismiss;
  const _OrderAlertCard({
    super.key,
    required this.orderId,
    required this.storeName,
    required this.address,
    required this.deliveryFee,
    required this.tip,
    required this.etaMin,
    required this.distanceKm,
    required this.onDismiss,
  });

  @override
  ConsumerState<_OrderAlertCard> createState() => _OrderAlertCardState();
}

class _OrderAlertCardState extends ConsumerState<_OrderAlertCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _timer;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    _timer = Timer(const Duration(seconds: 8), _dismiss);
  }

  /// Auto-dismiss (8s timeout). Not a decline — ignoring an offer must not
  /// count against the driver's decline rate.
  Future<void> _dismiss() async {
    _timer?.cancel();
    if (mounted) await _c.reverse();
    widget.onDismiss();
  }

  /// Explicit Decline tap — record it so it counts toward the decline rate.
  Future<void> _decline() async {
    _timer?.cancel();
    try {
      final uid = ref.read(currentUserIdProvider);
      final driver = uid == null
          ? null
          : ref.read(driverProfileProvider(uid)).valueOrNull;
      if (driver != null) {
        await ref
            .read(driverServiceProvider)
            .declineOrder(widget.orderId, driver.id);
        // declineOrder has already recomputed the stats — refresh any open
        // performance view so the decline rate reflects it immediately.
        ref.invalidate(driverStatsProvider(driver.id));
      }
    } catch (_) {
      // Recording the decline is best-effort; still dismiss the card.
    }
    if (mounted) await _c.reverse();
    widget.onDismiss();
  }

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() => _accepting = true);
    _timer?.cancel();
    final nav = NotificationService.navigatorKey?.currentState;
    try {
      final uid = ref.read(currentUserIdProvider);
      final driver = uid == null
          ? null
          : ref.read(driverProfileProvider(uid)).valueOrNull;
      if (driver == null) throw Exception('Driver profile not loaded');
      await ref
          .read(driverServiceProvider)
          .acceptDelivery(widget.orderId, driver.id);
      ref.invalidate(availableOrdersProvider);
      ref.invalidate(activeDeliveriesProvider(driver.id));
      widget.onDismiss();
      // Jump to the Active Orders tab.
      nav?.pushNamed('/driver-orders', arguments: 1);
    } catch (e) {
      if (mounted) setState(() => _accepting = false);
      final ctx = nav?.context;
      // ignore: use_build_context_synchronously
      if (ctx != null) AppSnackbar.error(ctx, friendlyError(e));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// Driver take-home: 80% of the delivery fee plus 100% of tips.
  double get _earning =>
      widget.deliveryFee * AppConstants.driverPayPercent + widget.tip;

  @override
  Widget build(BuildContext context) {
    final sym = AppConstants.currencySymbol;
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1.4),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E2030),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF22C55E).withValues(alpha: 0.55),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: New order + price + eta/distance
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delivery_dining_rounded,
                        color: Color(0xFF22C55E), size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'New Order Available',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'Your earning (80% of delivery + tips)',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$sym${_earning.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Color(0xFF22C55E),
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
            // Route: store -> address
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(Icons.store_rounded, const Color(0xFF22C55E),
                      widget.storeName),
                  if (widget.address.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _row(Icons.location_on_rounded, const Color(0xFFEF4444),
                        widget.address),
                  ],
                  const SizedBox(height: 6),
                  _row(
                    Icons.person_rounded,
                    const Color(0xFF60A5FA),
                    ref
                        .watch(driverCustomerNameProvider(widget.orderId))
                        .maybeWhen(
                          data: (n) => n,
                          orElse: () => 'Customer',
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (widget.etaMin != null)
                        _chip(Icons.schedule_rounded, '${widget.etaMin} min'),
                      if (widget.distanceKm != null) ...[
                        const SizedBox(width: 8),
                        _chip(Icons.near_me_rounded,
                            '${widget.distanceKm!.toStringAsFixed(1)} km away'),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _accepting ? null : _decline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFF3A2030)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Decline',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _accepting ? null : _accept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _accepting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Accept',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      );

  Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2D3E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.grey[400]),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
          ],
        ),
      );
}
