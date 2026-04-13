import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';
import '../providers/user_provider.dart';
import '../providers/payment_provider.dart';
import '../config/supabase_config.dart';
import '../screens/customer/ncb_payment_screen.dart';
import '../utils/friendly_error.dart';
import '../utils/app_feedback_widgets.dart';

/// Bottom sheet that lets a customer rate a driver (1-5 stars)
/// and optionally tip them via card payment.
class RateAndTipDriverSheet extends ConsumerStatefulWidget {
  final Order order;

  const RateAndTipDriverSheet({super.key, required this.order});

  static Future<bool?> show(BuildContext context, Order order) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RateAndTipDriverSheet(order: order),
    );
  }

  @override
  ConsumerState<RateAndTipDriverSheet> createState() =>
      _RateAndTipDriverSheetState();
}

class _RateAndTipDriverSheetState extends ConsumerState<RateAndTipDriverSheet> {
  int _rating = 0;
  double _tipAmount = 0;
  bool _isSubmitting = false;
  final _customTipController = TextEditingController();
  final List<double> _presetTips = [50, 100, 200, 500];

  @override
  void dispose() {
    _customTipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          const Text(
            'Rate Your Driver',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'How was your delivery experience?',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // Star rating
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starNum = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _rating = starNum),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    starNum <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 44,
                    color: starNum <= _rating
                        ? const Color(0xFFF59E0B)
                        : Colors.grey.shade300,
                  ),
                ),
              );
            }),
          ),
          if (_rating > 0) ...[
            const SizedBox(height: 6),
            Text(
              _ratingLabel,
              style: TextStyle(
                color: const Color(0xFFF59E0B),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Tip section
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Add a Tip',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Show your appreciation — 100% goes to your driver',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),

          // Preset tip amounts
          Row(
            children: [
              ..._presetTips.map((amount) {
                final isSelected = _tipAmount == amount;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Text(
                        '\$${amount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: const Color(0xFF10B981),
                      backgroundColor: Colors.grey.shade100,
                      onSelected: (_) {
                        setState(() {
                          _tipAmount = isSelected ? 0 : amount;
                          _customTipController.clear();
                        });
                      },
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 10),

          // Custom tip input
          TextField(
            controller: _customTipController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: '\$ ',
              hintText: 'Custom amount',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            onChanged: (val) {
              final parsed = double.tryParse(val);
              setState(() {
                _tipAmount = parsed ?? 0;
              });
            },
          ),
          const SizedBox(height: 20),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _rating == 0 || _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _tipAmount > 0
                          ? 'Submit Rating & Tip \$${_tipAmount.toStringAsFixed(0)}'
                          : 'Submit Rating',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String get _ratingLabel {
    switch (_rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Great';
      case 5:
        return 'Excellent!';
      default:
        return '';
    }
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    try {
      final orderService = ref.read(orderServiceProvider);

      // 1. Save driver rating
      await orderService.rateDriver(orderId: widget.order.id, rating: _rating);

      // 2. If tip amount > 0, open NCB card checkout
      if (_tipAmount > 0) {
        final paymentService = ref.read(paymentServiceProvider);

        // Get user info from Supabase auth
        final authUser = SupabaseConfig.client.auth.currentUser;
        final email = authUser?.email ?? '';
        final phone = authUser?.phone ?? '';
        final name = authUser?.userMetadata?['name'] as String? ?? 'Customer';

        final session = await paymentService.createCardCheckout(
          orderId: widget.order.id,
          amount: _tipAmount,
          customerEmail: email,
          customerPhone: phone,
          customerName: name,
        );

        if (!mounted) return;

        // Close the bottom sheet before opening payment screen
        Navigator.of(context).pop();

        final paymentCompleted = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => NcbPaymentScreen(session: session)),
        );

        if (paymentCompleted == true) {
          // Record tip in order after successful payment
          await orderService.tipDriver(
            orderId: widget.order.id,
            tipAmount: _tipAmount,
          );
        }

        if (mounted) {
          if (paymentCompleted == true) {
            AppSnackbar.success(
              context,
              'Driver rated! Tip of \$${_tipAmount.toStringAsFixed(0)} sent',
            );
          } else {
            AppSnackbar.warning(
              context,
              'Driver rated! Tip payment was cancelled',
            );
          }
        }
        return; // Already popped + shown snackbar
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        AppSnackbar.success(context, 'Driver rated! Thank you');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
