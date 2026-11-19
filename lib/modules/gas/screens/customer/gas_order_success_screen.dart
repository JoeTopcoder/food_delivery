import 'package:flutter/material.dart';
import 'gas_orders_screen.dart';
import '../../widgets/gas_ui.dart';

/// "Order Placed!" confirmation with a progress tracker — matches the mockup,
/// adapted to the upfront-payment flow (payment is already done when paid).
class GasOrderSuccessScreen extends StatelessWidget {
  const GasOrderSuccessScreen({super.key, required this.supplierName, this.paid = true});
  final String supplierName;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GasBrand.appBar(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(color: GasBrand.green.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_rounded, color: GasBrand.green, size: 64),
              ),
              const SizedBox(height: 18),
              const Text('Order Placed!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('Your gas order has been sent to $supplierName.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Theme.of(context).hintColor, height: 1.3)),
              const SizedBox(height: 28),
              _Step(done: true, title: 'Order received',
                  subtitle: 'We\'ve sent your order to the supplier.', first: true),
              _Step(done: paid, title: paid ? 'Payment received' : 'Make payment',
                  subtitle: paid
                      ? 'Your wallet was charged for this order.'
                      : 'Top up your wallet and pay from My Orders.'),
              const _Step(done: false, title: 'Supplier confirmation',
                  subtitle: 'The supplier will confirm availability.'),
              const _Step(done: false, title: 'Out for delivery',
                  subtitle: 'Your gas will be delivered to you.', last: true),
              const Spacer(),
              SizedBox(
                width: double.infinity, height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: GasBrand.orange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: () => Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const GasOrdersScreen())),
                  child: const Text('View My Orders',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                child: const Text('Continue Shopping',
                    style: TextStyle(fontWeight: FontWeight.w700, color: GasBrand.orange)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.done, required this.title, required this.subtitle, this.first = false, this.last = false});
  final bool done;
  final String title;
  final String subtitle;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = done ? GasBrand.orange : Theme.of(context).hintColor;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: done ? GasBrand.orange : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: done
                    ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                    : null,
              ),
              if (!last)
                Expanded(child: Container(width: 2, color: Theme.of(context).dividerColor.withValues(alpha: 0.5))),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18, top: first ? 1 : 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5,
                      color: done ? null : Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
