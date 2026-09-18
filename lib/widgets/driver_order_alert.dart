import 'dart:async';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';

/// Uber-Eats-style in-app alert shown to a driver when a new order becomes
/// available — pops in over whatever screen they're on (dashboard included),
/// stays ~8 seconds, then slides away. If missed, the order is still in the
/// Orders screen (until another rider accepts it).
class DriverOrderAlert {
  static OverlayEntry? _entry;

  static void show({
    required String orderId,
    required String title,
    required String body,
  }) {
    final overlay = NotificationService.navigatorKey?.currentState?.overlay;
    if (overlay == null) return;

    // Only one alert at a time — replace any existing one.
    _remove();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _OrderAlertCard(
        title: title,
        body: body,
        onView: () {
          _remove();
          NotificationService.navigatorKey?.currentState
              ?.pushNamed('/driver-orders');
        },
        onDismiss: _remove,
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

class _OrderAlertCard extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onView;
  final VoidCallback onDismiss;
  const _OrderAlertCard({
    required this.title,
    required this.body,
    required this.onView,
    required this.onDismiss,
  });

  @override
  State<_OrderAlertCard> createState() => _OrderAlertCardState();
}

class _OrderAlertCardState extends State<_OrderAlertCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    // Auto-dismiss after 8 seconds.
    _timer = Timer(const Duration(seconds: 8), _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (mounted) {
      await _c.reverse();
    }
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
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
          child: GestureDetector(
            onTap: widget.onView,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2030),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delivery_dining_rounded,
                      color: Color(0xFF22C55E),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: widget.onView,
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'View',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
