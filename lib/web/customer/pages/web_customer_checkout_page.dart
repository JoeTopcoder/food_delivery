import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/app_constants.dart';
import '../../../models/address_model.dart';
import '../../../models/order_model.dart';
import '../../../providers/address_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebCustomerCheckoutPage extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onOrderPlaced;

  const WebCustomerCheckoutPage({
    super.key,
    required this.onBack,
    required this.onOrderPlaced,
  });

  @override
  ConsumerState<WebCustomerCheckoutPage> createState() => _WebCustomerCheckoutPageState();
}

class _WebCustomerCheckoutPageState extends ConsumerState<WebCustomerCheckoutPage> {
  String _paymentMethod = 'cash';
  String? _selectedAddressId;
  final _addressCtrl = TextEditingController();
  final _notesCtrl   = TextEditingController();
  final _promoCtrl   = TextEditingController();
  double _tip = 0;
  bool _placingOrder = false;
  bool _promoApplied = false;
  String? _promoError;

  static const _tipOptions = [0.0, 1.0, 2.0, 5.0];

  @override
  void dispose() {
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _promoCtrl.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    final restaurantId = cart.first.menuItem.restaurantId;
    final currentUser  = ref.read(currentUserProvider);

    // Resolve delivery address
    final addresses = ref.read(userAddressesProvider(userId)).valueOrNull ?? [];
    UserAddress? selectedAddr;
    if (_selectedAddressId != null) {
      selectedAddr = addresses.firstWhere((a) => a.id == _selectedAddressId,
          orElse: () => addresses.first);
    } else if (addresses.isNotEmpty) {
      selectedAddr = addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first);
    }
    final deliveryAddress = selectedAddr?.address ?? _addressCtrl.text.trim();
    final deliveryLat     = selectedAddr?.latitude  ?? currentUser?.latitude  ?? 0.0;
    final deliveryLng     = selectedAddr?.longitude ?? currentUser?.longitude ?? 0.0;

    if (deliveryAddress.isEmpty) {
      AppSnackbar.error(context, 'Please enter a delivery address');
      return;
    }

    // Wallet balance check
    if (_paymentMethod == 'wallet') {
      final walletBalance = ref.read(walletBalanceStreamProvider).valueOrNull?.availableBalance ?? 0;
      final subtotal = ref.read(cartSubtotalProvider);
      if (walletBalance < subtotal) {
        AppSnackbar.error(context,
            'Insufficient wallet balance (${AppConstants.currencySymbol}${walletBalance.toStringAsFixed(2)}). '
            'Please top up or choose another payment method.');
        return;
      }
    }

    setState(() => _placingOrder = true);

    try {
      // Refresh session (best-effort, don't block on failure)
      try { await Supabase.instance.client.auth.refreshSession(); } catch (_) {}

      final orderService = ref.read(orderServiceProvider);
      final calcService  = ref.read(orderCalculationServiceProvider);

      // Build items payload for server calculation
      final serverItems = cart.map((c) => <String, dynamic>{
        'menu_item_id': c.menuItem.id,
        'quantity': c.quantity,
        'side_ids': c.selectedSides.map((s) => s.id).toList(),
      }).toList();

      // Server-verified pricing
      final breakdown = await calcService.calculate(
        restaurantId: restaurantId,
        userId: userId,
        items: serverItems,
        promoCode: _promoApplied && _promoCtrl.text.trim().isNotEmpty ? _promoCtrl.text.trim() : null,
        driverTip: _tip,
        paymentMethod: _paymentMethod,
        deliveryLatitude: deliveryLat != 0 ? deliveryLat : null,
        deliveryLongitude: deliveryLng != 0 ? deliveryLng : null,
      );

      final double subtotal    = breakdown?.subtotal    ?? ref.read(cartSubtotalProvider);
      final double deliveryFee = breakdown?.deliveryFee ?? 3.0;
      final double tax         = breakdown?.taxAmount   ?? 0.0;
      final double discount    = breakdown?.promoDiscount ?? 0.0;
      final double total       = breakdown?.grandTotal  ?? (subtotal + deliveryFee + tax - discount + _tip);

      // Build OrderItem list
      const uuid = Uuid();
      final orderItems = cart.map((c) => OrderItem(
        id: uuid.v4(),
        menuItemId: c.menuItem.id,
        itemName: c.menuItem.name,
        price: c.menuItem.discountedPrice,
        quantity: c.quantity,
        notes: c.notes,
      )).toList();

      final order = await orderService.createOrder(
        userId: userId,
        restaurantId: restaurantId,
        items: orderItems,
        subtotal: subtotal,
        deliveryFee: deliveryFee,
        taxAmount: tax,
        discount: discount > 0 ? discount.toDouble() : null,
        totalAmount: total,
        deliveryAddress: deliveryAddress,
        deliveryLatitude: deliveryLat,
        deliveryLongitude: deliveryLng,
        notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
        paymentMethod: _paymentMethod,
        driverTip: _tip > 0 ? _tip : null,
        promoCode: _promoApplied && _promoCtrl.text.trim().isNotEmpty ? _promoCtrl.text.trim() : null,
      );

      if (order == null) throw Exception('Order could not be created. Please try again.');

      ref.read(cartProvider.notifier).clearCart();

      if (!mounted) return;
      setState(() => _placingOrder = false);
      _showSuccess(order.id);

    } catch (e) {
      if (!mounted) return;
      setState(() => _placingOrder = false);
      AppSnackbar.error(context, friendlyError(e));
    }
  }

  void _showSuccess(String orderId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 16),
          const Text('Order Placed!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 8),
          Text('Order #${orderId.substring(0, 8).toUpperCase()}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          const SizedBox(height: 4),
          const Text('Your order has been sent to the restaurant.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
        ]),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () { Navigator.pop(context); widget.onOrderPlaced(); },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Track Order', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId      = ref.watch(currentUserIdProvider);
    final cart        = ref.watch(cartProvider);
    final subtotal    = ref.watch(cartSubtotalProvider);
    final walletAsync = ref.watch(walletBalanceStreamProvider);
    final addrAsync   = userId != null ? ref.watch(userAddressesProvider(userId)) : null;
    const deliveryFee = 3.0;
    const tax         = 0.0;
    final total       = subtotal + deliveryFee + tax + _tip;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: widget.onBack,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 12),
            const Text('Checkout', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          ]),
          const SizedBox(height: 24),

          // Two column layout
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left col
              Expanded(
                flex: 3,
                child: Column(children: [
                  // Cart Items
                  _Section(
                    title: 'Your Items (${cart.length})',
                    child: Column(children: cart.map((c) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3ED),
                            borderRadius: BorderRadius.circular(8),
                            image: c.menuItem.imageUrl != null
                                ? DecorationImage(image: NetworkImage(c.menuItem.imageUrl!), fit: BoxFit.cover)
                                : null,
                          ),
                          child: c.menuItem.imageUrl == null
                              ? const Icon(Icons.fastfood_rounded, color: Color(0xFFFF6B35), size: 22)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.menuItem.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                          if (c.selectedSides.isNotEmpty)
                            Text(c.selectedSides.map((s) => s.name).join(', '),
                                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                        ])),
                        Text('x${c.quantity}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                        const SizedBox(width: 16),
                        Text('${AppConstants.currencySymbol}${(c.menuItem.discountedPrice * c.quantity).toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                      ]),
                    )).toList()),
                  ),
                  const SizedBox(height: 16),

                  // Delivery address
                  _Section(
                    title: 'Delivery Address',
                    child: addrAsync == null
                        ? _addressInput()
                        : addrAsync.when(
                            loading: () => const AppLoadingIndicator(),
                            error: (_, __) => _addressInput(),
                            data: (addrs) => addrs.isEmpty
                                ? _addressInput()
                                : Column(children: [
                                    ...addrs.map((a) {
                                      final effectiveSelected = (_selectedAddressId == a.id) ||
                                          (_selectedAddressId == null && a.isDefault);
                                      return GestureDetector(
                                        onTap: () => setState(() => _selectedAddressId = a.id),
                                        child: Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: effectiveSelected
                                                ? const Color(0xFFFF6B35).withValues(alpha: 0.05)
                                                : const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: effectiveSelected
                                                  ? const Color(0xFFFF6B35)
                                                  : const Color(0xFFE2E8F0),
                                              width: effectiveSelected ? 1.5 : 1,
                                            ),
                                          ),
                                          child: Row(children: [
                                            Icon(Icons.location_on_rounded, size: 18,
                                                color: effectiveSelected ? const Color(0xFFFF6B35) : const Color(0xFF94A3B8)),
                                            const SizedBox(width: 10),
                                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              Text(a.address, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1E293B))),
                                              Text(a.label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                            ])),
                                            if (effectiveSelected) const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFFFF6B35)),
                                          ]),
                                        ),
                                      );
                                    }),
                                    const Divider(height: 16),
                                    _addressInput(hint: 'Or enter a different address...'),
                                  ]),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // Payment method
                  _Section(
                    title: 'Payment Method',
                    child: Column(children: [
                      _PaymentOption(
                        value: 'cash',
                        groupValue: _paymentMethod,
                        label: 'Cash on Delivery',
                        subtitle: 'Pay when your order arrives',
                        icon: Icons.payments_outlined,
                        onChanged: (v) => setState(() => _paymentMethod = v!),
                      ),
                      const SizedBox(height: 8),
                      walletAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (wallet) => _PaymentOption(
                          value: 'wallet',
                          groupValue: _paymentMethod,
                          label: 'Wallet',
                          subtitle: 'Balance: ${AppConstants.currencySymbol}${(wallet?.availableBalance ?? 0).toStringAsFixed(2)}',
                          icon: Icons.account_balance_wallet_outlined,
                          onChanged: (v) => setState(() => _paymentMethod = v!),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Driver tip
                  _Section(
                    title: 'Tip Your Driver',
                    child: Row(children: _tipOptions.map((t) {
                      final selected = _tip == t;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _tip = t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFFFF6B35) : Colors.white,
                              border: Border.all(color: selected ? const Color(0xFFFF6B35) : const Color(0xFFE2E8F0)),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              t == 0 ? 'No tip' : '${AppConstants.currencySymbol}${t.toStringAsFixed(0)}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                  color: selected ? Colors.white : const Color(0xFF475569)),
                            ),
                          ),
                        ),
                      );
                    }).toList()),
                  ),
                  const SizedBox(height: 16),

                  // Promo code
                  _Section(
                    title: 'Promo Code',
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _promoCtrl,
                          onChanged: (_) => setState(() { _promoApplied = false; _promoError = null; }),
                          decoration: InputDecoration(
                            hintText: 'Enter promo code',
                            hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
                            errorText: _promoError,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () {
                          if (_promoCtrl.text.trim().isEmpty) return;
                          setState(() { _promoApplied = true; _promoError = null; });
                          AppSnackbar.show(context, message: 'Promo applied — discount calculated at checkout', type: AppSnackbarType.success);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(_promoApplied ? 'Applied ✓' : 'Apply'),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Notes
                  _Section(
                    title: 'Special Instructions',
                    child: TextField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'e.g. No onions, extra sauce...',
                        hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                ]),
              ),

              const SizedBox(width: 24),

              // Right col — Order summary
              SizedBox(
                width: 300,
                child: _Section(
                  title: 'Order Summary',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _SummaryRow('Subtotal', '${AppConstants.currencySymbol}${subtotal.toStringAsFixed(2)}'),
                    const SizedBox(height: 8),
                    _SummaryRow('Delivery Fee', '${AppConstants.currencySymbol}${deliveryFee.toStringAsFixed(2)}'),
                    const SizedBox(height: 8),
                    _SummaryRow('Tax', '${AppConstants.currencySymbol}${tax.toStringAsFixed(2)}'),
                    if (_tip > 0) ...[
                      const SizedBox(height: 8),
                      _SummaryRow('Driver Tip', '${AppConstants.currencySymbol}${_tip.toStringAsFixed(2)}'),
                    ],
                    if (_promoApplied) ...[
                      const SizedBox(height: 8),
                      const _SummaryRow('Promo', 'Applied ✓', color: Color(0xFF10B981)),
                    ],
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                    Row(children: [
                      const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                      const Spacer(),
                      Text('${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFFF6B35))),
                    ]),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _placingOrder || cart.isEmpty ? null : _placeOrder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B35),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFCBD5E1),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _placingOrder
                            ? const SizedBox(height: 20, width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : const Text('Place Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.lock_outline_rounded, size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text('Secured checkout', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                    ]),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _addressInput({String hint = 'Enter your delivery address'}) {
    return TextField(
      controller: _addressCtrl,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
        prefixIcon: const Icon(Icons.location_on_outlined, color: Color(0xFFFF6B35)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SummaryRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF64748B);
    return Row(children: [
      Text(label, style: TextStyle(fontSize: 13, color: c)),
      const Spacer(),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c)),
    ]);
  }
}

class _PaymentOption extends StatelessWidget {
  final String value;
  final String groupValue;
  final String label;
  final String subtitle;
  final IconData icon;
  final ValueChanged<String?> onChanged;
  const _PaymentOption({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF6B35).withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? const Color(0xFFFF6B35) : const Color(0xFFE2E8F0), width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(icon, size: 22, color: selected ? const Color(0xFFFF6B35) : const Color(0xFF94A3B8)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                color: selected ? const Color(0xFF1E293B) : const Color(0xFF475569))),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ]),
          const Spacer(),
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? const Color(0xFFFF6B35) : const Color(0xFFCBD5E1),
                width: 2,
              ),
            ),
            child: selected ? Center(
              child: Container(
                width: 10, height: 10,
                decoration: const BoxDecoration(color: Color(0xFFFF6B35), shape: BoxShape.circle),
              ),
            ) : null,
          ),
        ]),
      ),
    );
  }
}
