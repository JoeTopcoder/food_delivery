import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';
import '../providers/driver_provider.dart';
import '../providers/auth_provider.dart';
import '../config/app_constants.dart';
import '../utils/friendly_error.dart';
import '../utils/app_feedback_widgets.dart';

/// Uber-Eats-style order card that pops in over whatever screen the driver is
/// on (dashboard included) when a new order is available. Stays ~8 seconds with
/// Accept / Decline; if missed, the order is still in the Orders screen until
/// another rider accepts it.
class DriverOrderAlert {
  static OverlayEntry? _entry;

  static void show({
    required String orderId,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) {
    final overlay = NotificationService.navigatorKey?.currentState?.overlay;
    if (overlay == null || orderId.isEmpty) return;
    _remove();
    final entry = OverlayEntry(
      builder: (_) => _OrderAlertCard(
        orderId: orderId,
        storeName: (data['store_name'] ?? title).toString(),
        address: (data['address'] ?? '').toString(),
        deliveryFee: double.tryParse((data['delivery_fee'] ?? '').toString()) ?? 0,
        tip: double.tryParse((data['tip'] ?? '').toString()) ?? 0,
        etaMin: int.tryParse((data['eta'] ?? '').toString()),
        distanceKm: double.tryParse((data['distance_km'] ?? '').toString()),
        onClose: _remove,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void _remove() {
    _entry?.remove();
    _entry = null;
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
  final VoidCallback onClose;
  const _OrderAlertCard({
    required this.orderId,
    required this.storeName,
    required this.address,
    required this.deliveryFee,
    required this.tip,
    required this.etaMin,
    required this.distanceKm,
    required this.onClose,
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

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (mounted) await _c.reverse();
    widget.onClose();
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
      await ref.read(driverServiceProvider).acceptDelivery(widget.orderId, driver.id);
      ref.invalidate(availableOrdersProvider);
      ref.invalidate(activeDeliveriesProvider(driver.id));
      widget.onClose();
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
    final media = MediaQuery.of(context);
    final sym = AppConstants.currencySymbol;
    return Positioned(
      top: media.padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.4),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
        child: Material(
          color: Colors.transparent,
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
                        _row(Icons.location_on_rounded,
                            const Color(0xFFEF4444), widget.address),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (widget.etaMin != null)
                            _chip(Icons.schedule_rounded,
                                '${widget.etaMin} min'),
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
                          onPressed: _accepting ? null : _dismiss,
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
            Text(text,
                style: TextStyle(color: Colors.grey[400], fontSize: 11)),
          ],
        ),
      );
}
