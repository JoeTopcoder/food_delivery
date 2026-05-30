import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import '../../utils/context_extensions.dart';

class OrderSuccessScreen extends StatefulWidget {
  final String orderId;
  final bool contactlessDelivery;
  final String? deliveryOtp;
  final bool isPickup;
  final String? receiptNumber;
  final bool isMultiRestaurant;
  const OrderSuccessScreen({
    super.key,
    required this.orderId,
    this.contactlessDelivery = false,
    this.deliveryOtp,
    this.isPickup = false,
    this.receiptNumber,
    this.isMultiRestaurant = false,
  });

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen> {
  late final ConfettiController _confettiCtrl;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 3));
    _confettiCtrl.play();
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    super.dispose();
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        body: Stack(
          children: [
            // ── Main content ──
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        size: 64,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      context.l10n.orderPlaced,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Order #${widget.receiptNumber ?? widget.orderId.substring(0, 8).toUpperCase()}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.isPickup
                          ? 'Your pickup order has been placed!\nThe restaurant will provide a pickup code when ready.'
                          : 'Your order has been placed successfully.\nSit back and relax while we prepare it!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),

                    // Contactless delivery PIN
                    if (widget.contactlessDelivery &&
                        widget.deliveryOtp != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF6366F1,
                          ).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFF6366F1,
                            ).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.contactless_rounded,
                                  color: Color(0xFF6366F1),
                                  size: 18,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Your Delivery PIN',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: widget.deliveryOtp!
                                  .split('')
                                  .map(
                                    (d) => Container(
                                      width: 44,
                                      height: 52,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                      ),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: const Color(
                                            0xFF6366F1,
                                          ).withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        d,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF6366F1),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Share this PIN with the driver for contactless delivery',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9CA3AF),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (widget.isMultiRestaurant) {
                            Navigator.of(context).pushReplacementNamed(
                              '/multi-order-detail',
                              arguments: widget.orderId,
                            );
                          } else {
                            Navigator.of(context).pushReplacementNamed(
                              '/order-tracking',
                              arguments: widget.orderId,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Track Order',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _goHome,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        child: const Text(
                          'Back to Home',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Confetti ──
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiCtrl,
                blastDirectionality: BlastDirectionality.explosive,
                numberOfParticles: 30,
                maxBlastForce: 30,
                minBlastForce: 10,
                emissionFrequency: 0.06,
                gravity: 0.2,
                shouldLoop: false,
                colors: [
                  AppTheme.primaryColor,
                  Color(0xFF10B981),
                  Color(0xFF6366F1),
                  Color(0xFFF59E0B),
                  Color(0xFFEC4899),
                  Color(0xFF3B82F6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
