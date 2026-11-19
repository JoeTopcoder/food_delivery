import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/app_constants.dart';
import '../../../../models/money/saved_card_model.dart';
import '../../../../providers/auth_user/auth_provider.dart';
import '../../../../providers/money/payment_provider.dart';
import '../../../../providers/money/wallet_provider.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/gas_ui.dart';
import 'gas_order_success_screen.dart';

/// Gas checkout — pick wallet, card, or cash (same options as the main
/// checkout) for an already-placed gas order, then confirm.
class GasCheckoutScreen extends ConsumerStatefulWidget {
  const GasCheckoutScreen({super.key, required this.orderId, required this.supplierName});
  final String orderId;
  final String supplierName;
  @override
  ConsumerState<GasCheckoutScreen> createState() => _GasCheckoutScreenState();
}

class _GasCheckoutScreenState extends ConsumerState<GasCheckoutScreen> {
  String _method = 'wallet';
  SavedCard? _card;
  bool _busy = false;
  String? _error;

  Future<void> _confirm(GasOrder order) async {
    setState(() { _busy = true; _error = null; });
    try {
      final svc = ref.read(gasServiceProvider);
      if (_method == 'wallet') {
        await svc.payFromWallet(widget.orderId);
      } else if (_method == 'stripe') {
        if (_card?.stripePaymentMethodId == null) {
          setState(() { _error = 'Select a verified card first.'; _busy = false; });
          return;
        }
        await svc.payByCard(widget.orderId, _card!.stripePaymentMethodId!);
      } else {
        await svc.setCashOnDelivery(widget.orderId);
      }
      if (!mounted) return;
      ref.invalidate(myGasOrdersProvider);
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => GasOrderSuccessScreen(supplierName: widget.supplierName, method: _method),
      ));
    } catch (e) {
      setState(() => _error = _friendly('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(String raw) {
    if (raw.contains('insufficient wallet')) return 'Not enough wallet balance — choose another method or top up.';
    if (raw.contains('not configured')) return 'Card payments aren\'t available right now. Try wallet or cash.';
    return raw.replaceAll('PostgrestException', '').replaceAll('Exception:', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(gasOrderProvider(widget.orderId));
    final uid = ref.watch(currentUserIdProvider);
    final savedCardsAsync = uid == null ? null : ref.watch(savedCardsProvider(uid));

    return Scaffold(
      appBar: GasBrand.appBar(context),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load order.\n$e', textAlign: TextAlign.center)),
        data: (order) {
          if (order == null) return const Center(child: Text('Order not found.'));
          return Stack(children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
              children: [
                const Text('Checkout', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 14),
                _SummaryCard(order: order, supplierName: widget.supplierName),
                const SizedBox(height: 18),
                const Text('Payment Method', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                // Wallet
                Consumer(builder: (context, ref, _) {
                  final bal = ref.watch(walletBalanceStreamProvider).valueOrNull?.availableBalance ?? 0;
                  return _PayTile(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Wallet',
                    subtitle: bal > 0
                        ? 'Balance: ${AppConstants.currencySymbol}${bal.toStringAsFixed(2)}'
                        : 'No funds — top up in your profile',
                    selected: _method == 'wallet',
                    onTap: () => setState(() => _method = 'wallet'),
                  );
                }),
                const SizedBox(height: 8),
                // Card
                _PayTile(
                  icon: Icons.credit_card_rounded,
                  label: 'Credit / Debit Card',
                  subtitle: 'Visa, Mastercard, and more',
                  selected: _method == 'stripe',
                  onTap: () => setState(() => _method = 'stripe'),
                ),
                if (_method == 'stripe' && savedCardsAsync != null)
                  savedCardsAsync.when(
                    loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (cards) {
                      final verified = cards.where((c) => c.isVerified).toList();
                      _card ??= verified.isNotEmpty ? verified.first : null;
                      if (verified.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Text('No verified card on file. Add one in your profile, or use wallet/cash.',
                              style: TextStyle(fontSize: 12.5, color: Colors.redAccent)),
                        );
                      }
                      return Column(children: [
                        for (final c in verified)
                          InkWell(
                            onTap: () => setState(() => _card = c),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                              child: Row(children: [
                                Icon(_card?.id == c.id
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    size: 20, color: _card?.id == c.id ? GasBrand.orange : Theme.of(context).hintColor),
                                const SizedBox(width: 10),
                                Text('${c.cardBrand} •••• ${c.lastFour}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                              ]),
                            ),
                          ),
                      ]);
                    },
                  ),
                const SizedBox(height: 8),
                // Cash
                _PayTile(
                  icon: Icons.payments_rounded,
                  label: 'Cash on Delivery',
                  subtitle: 'Pay with cash when your order arrives',
                  selected: _method == 'cash',
                  onTap: () => setState(() => _method = 'cash'),
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _ConfirmBar(
                order: order,
                method: _method,
                busy: _busy,
                error: _error,
                onConfirm: () => _confirm(order),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.order, required this.supplierName});
  final GasOrder order;
  final String supplierName;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.propane_tank_rounded, color: GasBrand.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(supplierName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
        ]),
        if (order.deliveryAddress != null) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(order.deliveryAddress!, style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor)),
        ),
        const Divider(height: 18),
        _row(context, 'Items', gasMoney(order.itemsCents)),
        if (order.depositCents > 0) _row(context, 'Refundable deposit', gasMoney(order.depositCents)),
        _row(context, 'Delivery', gasMoney(order.deliveryCents)),
        if (order.serviceFeeCents > 0) _row(context, 'Service fee', gasMoney(order.serviceFeeCents)),
        const Divider(height: 18),
        _row(context, 'Total', gasMoney(order.totalCents), bold: true),
      ]),
    );
  }

  Widget _row(BuildContext c, String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
              fontSize: bold ? 16 : 13.5, color: bold ? null : Theme.of(c).hintColor)),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600, fontSize: bold ? 16 : 13.5)),
        ]),
      );
}

class _PayTile extends StatelessWidget {
  const _PayTile({required this.icon, required this.label, required this.subtitle, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? GasBrand.orange.withValues(alpha: 0.08) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? GasBrand.orange : Theme.of(context).dividerColor.withValues(alpha: 0.4),
              width: selected ? 1.6 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: selected ? GasBrand.orange : Theme.of(context).hintColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            ]),
          ),
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? GasBrand.orange : Theme.of(context).hintColor),
        ]),
      ),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({required this.order, required this.method, required this.busy, required this.error, required this.onConfirm});
  final GasOrder order;
  final String method;
  final bool busy;
  final String? error;
  final VoidCallback onConfirm;
  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    final cta = method == 'cash' ? 'Confirm Order (Cash)' : 'Pay ${gasMoney(order.totalCents)}';
    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + pad),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, -4))],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12.5))),
        SizedBox(
          width: double.infinity, height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GasBrand.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: busy ? null : onConfirm,
            child: busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(cta, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
