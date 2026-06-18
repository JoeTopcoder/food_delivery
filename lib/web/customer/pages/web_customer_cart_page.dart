import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_constants.dart';
import '../../../providers/user_provider.dart';

class WebCustomerCartPage extends ConsumerWidget {
  final VoidCallback onCheckout;
  const WebCustomerCartPage({super.key, required this.onCheckout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    const deliveryFee = 3.00;
    const tax = 0.0;
    final total = subtotal + deliveryFee + tax;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('My Cart', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Review your items before checkout', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            if (cart.isNotEmpty)
              TextButton.icon(
                onPressed: () => _confirmClear(context, ref),
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                label: const Text('Clear Cart', style: TextStyle(color: Colors.red)),
              ),
          ]),
          const SizedBox(height: 20),
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.shopping_cart_outlined, size: 64, color: Color(0xFFE2E8F0)),
                      const SizedBox(height: 12),
                      const Text('Your cart is empty', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                      const SizedBox(height: 4),
                      const Text('Browse restaurants and add items to your cart', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                    ]),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cart items
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                          ),
                          child: Column(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                              ),
                              child: Row(children: [
                                const Text('Items', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                                const Spacer(),
                                Text('${cart.length} item${cart.length == 1 ? "" : "s"}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                              ]),
                            ),
                            const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: cart.length,
                                separatorBuilder: (_, __) => const Divider(height: 20),
                                itemBuilder: (_, i) => _CartItemRow(
                                  item: cart[i],
                                  onIncrement: () => ref.read(cartProvider.notifier).updateQuantity(cart[i].menuItem.id, cart[i].quantity + 1),
                                  onDecrement: () => ref.read(cartProvider.notifier).updateQuantity(cart[i].menuItem.id, cart[i].quantity - 1),
                                  onRemove: () => ref.read(cartProvider.notifier).removeItem(cart[i].menuItem.id),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Summary
                      SizedBox(
                        width: 280,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            const Text('Order Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                            const SizedBox(height: 16),
                            _summaryRow('Subtotal', '${AppConstants.currencySymbol}${subtotal.toStringAsFixed(2)}'),
                            const SizedBox(height: 8),
                            _summaryRow('Delivery Fee', '${AppConstants.currencySymbol}${deliveryFee.toStringAsFixed(2)}'),
                            const SizedBox(height: 8),
                            _summaryRow('Tax', '${AppConstants.currencySymbol}${tax.toStringAsFixed(2)}'),
                            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                            Row(children: [
                              const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                              const Spacer(),
                              Text('${AppConstants.currencySymbol}${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFFF6B35))),
                            ]),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: onCheckout,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF6B35),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Proceed to Checkout', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(children: [
      Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
      const Spacer(),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
    ]);
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Cart?'),
        content: const Text('Remove all items from your cart?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); ref.read(cartProvider.notifier).clearCart(); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _CartItemRow extends StatelessWidget {
  final dynamic item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  const _CartItemRow({required this.item, required this.onIncrement, required this.onDecrement, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3ED),
          borderRadius: BorderRadius.circular(10),
          image: item.menuItem.imageUrl != null
              ? DecorationImage(image: NetworkImage(item.menuItem.imageUrl!), fit: BoxFit.cover)
              : null,
        ),
        child: item.menuItem.imageUrl == null ? const Icon(Icons.fastfood_rounded, color: Color(0xFFFF6B35), size: 24) : null,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.menuItem.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
          if (item.optionsSummary.isNotEmpty)
            Text(item.optionsSummary, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          Text('${AppConstants.currencySymbol}${item.subtotal.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFFF6B35))),
        ]),
      ),
      Row(children: [
        _QtyBtn(icon: Icons.remove_rounded, onTap: onDecrement),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('${item.quantity}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
        ),
        _QtyBtn(icon: Icons.add_rounded, onTap: onIncrement),
      ]),
      const SizedBox(width: 8),
      IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFF94A3B8)), onPressed: onRemove),
    ]);
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 16, color: const Color(0xFF475569)),
      ),
    );
  }
}
