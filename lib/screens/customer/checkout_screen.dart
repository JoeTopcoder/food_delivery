import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../models/order_model.dart';
import '../../models/address_model.dart';
import '../../models/restaurant_model.dart';
import '../../models/user_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/promo_provider.dart';
import '../../providers/loyalty_provider.dart';
import '../../providers/address_provider.dart';
import '../../models/saved_card_model.dart';
import '../../providers/payment_provider.dart';
import '../../config/supabase_config.dart';
import '../../services/payment_service.dart';
import '../../utils/app_theme.dart';
import 'ncb_payment_screen.dart';
import 'order_success_screen.dart';
import '../../utils/friendly_error.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _promoCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _cardholderCtrl = TextEditingController();
  final _paymentEmailCtrl = TextEditingController();
  final _paymentPhoneCtrl = TextEditingController();
  String _selectedPayment = 'cash';
  SavedCard? _selectedSavedCard;
  bool _useNewCard = false;
  bool _agreeToTerms = false;
  bool _applyingPromo = false;
  bool _placingOrder = false;
  bool _paymentFieldsHydrated = false;
  bool _contactlessDelivery = false;
  String? _promoError;
  DateTime? _scheduledAt;
  double _driverTip = 0;
  final _customTipCtrl = TextEditingController();
  final List<double> _presetTips = AppConstants.presetTips;

  @override
  void dispose() {
    _promoCtrl.dispose();
    _notesCtrl.dispose();
    _cardholderCtrl.dispose();
    _paymentEmailCtrl.dispose();
    _paymentPhoneCtrl.dispose();
    _customTipCtrl.dispose();
    super.dispose();
  }

  void _hydratePaymentFields(User? currentUser) {
    if (_paymentFieldsHydrated || currentUser == null) {
      return;
    }

    _paymentFieldsHydrated = true;
    _cardholderCtrl.text = currentUser.name ?? '';
    _paymentEmailCtrl.text = currentUser.email;
    _paymentPhoneCtrl.text = currentUser.phone ?? '';
  }

  Future<void> _applyPromo(double subtotal) async {
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _applyingPromo = true;
      _promoError = null;
    });
    try {
      final service = ref.read(promoServiceProvider);
      final promo = await service.validateCode(code, subtotal);
      if (!mounted) {
        return;
      }
      if (promo == null) {
        setState(() => _promoError = 'Invalid or expired code');
        ref.read(appliedPromoProvider.notifier).clear();
      } else {
        ref.read(appliedPromoProvider.notifier).apply(promo);
        FocusScope.of(context).unfocus();
      }
    } catch (e) {
      setState(() => _promoError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _applyingPromo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final restaurantId = cart.isNotEmpty
        ? cart.first.menuItem.restaurantId
        : null;
    final restaurantAsync = restaurantId != null
        ? ref.watch(restaurantByIdProvider(restaurantId))
        : const AsyncValue<Restaurant?>.data(null);

    final appliedPromo = ref.watch(appliedPromoProvider);
    final redeemPoints = currentUserId != null
        ? ref.watch(redeemPointsProvider)
        : 0;
    final loyaltyAsync = currentUserId != null
        ? ref.watch(loyaltyAccountProvider(currentUserId))
        : null;
    final selectedAddress = ref.watch(selectedAddressProvider);
    final addressAsync = currentUserId != null
        ? ref.watch(userAddressesProvider(currentUserId))
        : null;
    final savedCardsAsync = currentUserId != null
        ? ref.watch(savedCardsProvider(currentUserId))
        : null;

    final promoDiscount = appliedPromo?.computeDiscount(subtotal) ?? 0.0;
    final loyaltyDiscount = redeemPoints * AppConstants.loyaltyPointValue;
    final deliveryFee =
        restaurantAsync.valueOrNull?.deliveryFee ??
        AppConstants.defaultDeliveryFee;
    final tax = subtotal * AppConstants.taxRate;
    final orderTotal =
        (subtotal - promoDiscount - loyaltyDiscount + deliveryFee + tax).clamp(
          deliveryFee,
          double.infinity,
        );
    final total = orderTotal + _driverTip;

    final deliveryAddress =
        selectedAddress?.address ?? currentUser?.address ?? 'No address saved';

    _hydratePaymentFields(currentUser);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Checkout',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(
              bottom: 110,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Delivery Address ──────────────────────────────────
                _Section(
                  title: 'Delivery Address',
                  icon: Icons.location_on_rounded,
                  child: Column(
                    children: [
                      // Saved address book
                      if (addressAsync != null)
                        addressAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (error, stackTrace) => const SizedBox.shrink(),
                          data: (addresses) => addresses.isEmpty
                              ? const SizedBox.shrink()
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: addresses.map((a) {
                                      final sel = selectedAddress?.id == a.id;
                                      return GestureDetector(
                                        onTap: () =>
                                            ref
                                                .read(
                                                  selectedAddressProvider
                                                      .notifier,
                                                )
                                                .state = sel
                                            ? null
                                            : a,
                                        child: _AddressChip(
                                          address: a,
                                          isSelected: sel,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                        ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.place_rounded,
                              color: AppTheme.primaryColor,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                deliveryAddress,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/address-book'),
                              child: const Text(
                                'Manage',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Schedule (optional) ───────────────────────────────
                _Section(
                  title: 'Delivery Time',
                  icon: Icons.schedule_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _TimeChip(
                              label: 'ASAP',
                              subtitle: '20-35 min',
                              selected: _scheduledAt == null,
                              onTap: () => setState(() => _scheduledAt = null),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _TimeChip(
                              label: 'Schedule',
                              subtitle: _scheduledAt != null
                                  ? DateFormat(
                                      'MMM d, h:mm a',
                                    ).format(_scheduledAt!)
                                  : 'Pick time',
                              selected: _scheduledAt != null,
                              onTap: _pickSchedule,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Payment ───────────────────────────────────────────
                _Section(
                  title: 'Payment Method',
                  icon: Icons.payment_rounded,
                  child: Column(
                    children: [
                      _PaymentTile(
                        icon: Icons.money_rounded,
                        label: 'Cash on Delivery',
                        subtitle: 'Pay the driver when your order arrives',
                        selected: _selectedPayment == 'cash',
                        onTap: () => setState(() => _selectedPayment = 'cash'),
                      ),
                      const SizedBox(height: 8),
                      _PaymentTile(
                        icon: Icons.credit_card_rounded,
                        label: 'Credit / Debit Card',
                        subtitle: 'Visa, Mastercard, KeyCard accepted',
                        selected: _selectedPayment == 'card',
                        onTap: () => setState(() => _selectedPayment = 'card'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CardBrandChip('VISA', const Color(0xFF1A1F71)),
                            const SizedBox(width: 4),
                            _CardBrandChip('MC', const Color(0xFFEB001B)),
                          ],
                        ),
                      ),
                      if (_selectedPayment == 'card') ...[
                        const SizedBox(height: 12),
                        // ── Saved Cards ──
                        if (savedCardsAsync != null)
                          savedCardsAsync.when(
                            loading: () => const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                            error: (_, _) => const SizedBox.shrink(),
                            data: (savedCards) {
                              if (savedCards.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ...savedCards.map(
                                    (card) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _SavedCardTile(
                                        card: card,
                                        selected:
                                            _selectedSavedCard?.id == card.id &&
                                            !_useNewCard,
                                        onTap: () {
                                          setState(() {
                                            _selectedSavedCard = card;
                                            _useNewCard = false;
                                            _cardholderCtrl.text =
                                                card.cardholderName;
                                            _paymentEmailCtrl.text = card.email;
                                            _paymentPhoneCtrl.text = card.phone;
                                          });
                                        },
                                        onDelete: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Remove Card'),
                                              content: Text(
                                                'Remove card ending in ${card.lastFour}?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const Text('Cancel'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child: const Text(
                                                    'Remove',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            final svc = ref.read(
                                              paymentServiceProvider,
                                            );
                                            await svc.deleteSavedCard(card.id);
                                            if (_selectedSavedCard?.id ==
                                                card.id) {
                                              setState(
                                                () => _selectedSavedCard = null,
                                              );
                                            }
                                            ref.invalidate(
                                              savedCardsProvider(
                                                currentUserId!,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  // "Use a new card" option
                                  _PaymentTile(
                                    icon: Icons.add_card_rounded,
                                    label: 'Use a new card',
                                    subtitle: 'Enter new card details',
                                    selected: _useNewCard,
                                    onTap: () {
                                      setState(() {
                                        _useNewCard = true;
                                        _selectedSavedCard = null;
                                      });
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        // Show card panel if no saved cards exist, or user chose "new card"
                        if (savedCardsAsync == null ||
                            savedCardsAsync.valueOrNull?.isEmpty == true ||
                            _useNewCard)
                          _CardPaymentPanel(
                            cardholderController: _cardholderCtrl,
                            emailController: _paymentEmailCtrl,
                            phoneController: _paymentPhoneCtrl,
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Promo Code ────────────────────────────────────────
                _Section(
                  title: 'Promo Code',
                  icon: Icons.discount_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (appliedPromo != null)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(
                                0xFF10B981,
                              ).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF10B981),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '"${appliedPromo.code}" — saved JMD\$${promoDiscount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  ref
                                      .read(appliedPromoProvider.notifier)
                                      .clear();
                                  _promoCtrl.clear();
                                },
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _promoCtrl,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: InputDecoration(
                                  hintText: 'Enter promo code',
                                  errorText: _promoError,
                                  border: const OutlineInputBorder(),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _applyingPromo
                                  ? null
                                  : () => _applyPromo(subtotal),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              child: _applyingPromo
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Apply'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Loyalty Points ────────────────────────────────────
                if (loyaltyAsync != null)
                  loyaltyAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (error, stackTrace) => const SizedBox.shrink(),
                    data: (account) {
                      if (account == null || account.points == 0) {
                        return const SizedBox.shrink();
                      }
                      final maxRedeem = account.maxRedeemable(subtotal);
                      final maxPts =
                          (maxRedeem / AppConstants.loyaltyPointValue).floor();
                      return _Section(
                        title: 'Loyalty Points',
                        icon: Icons.stars_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'You have ${account.points} pts '
                                  '(= JMD\$${account.redemptionValue.toStringAsFixed(2)})',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const Spacer(),
                                Switch(
                                  value: redeemPoints > 0,
                                  onChanged: (v) {
                                    ref
                                        .read(redeemPointsProvider.notifier)
                                        .state = v
                                        ? maxPts
                                        : 0;
                                  },
                                  activeThumbColor: const Color(0xFF6366F1),
                                ),
                              ],
                            ),
                            if (redeemPoints > 0)
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF6366F1,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Redeeming $redeemPoints pts = '
                                  'JMD\$${loyaltyDiscount.toStringAsFixed(2)} off',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6366F1),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 12),

                // ── Contactless Delivery ──────────────────────────────
                _Section(
                  title: 'Contactless Delivery',
                  icon: Icons.contactless_rounded,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Leave order at door',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Driver will verify with a one-time PIN',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _contactlessDelivery,
                        onChanged: (v) =>
                            setState(() => _contactlessDelivery = v),
                        activeThumbColor: AppTheme.primaryColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Driver Tip ────────────────────────────────────────
                _Section(
                  title: 'Tip Your Driver',
                  icon: Icons.volunteer_activism_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '100% of your tip goes directly to the driver',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          // No-tip chip
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: ChoiceChip(
                                label: const Text(
                                  'No Tip',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                selected: _driverTip == 0,
                                selectedColor: AppTheme.primaryColor,
                                backgroundColor: Colors.grey.shade100,
                                labelStyle: TextStyle(
                                  color: _driverTip == 0
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                                onSelected: (_) {
                                  setState(() {
                                    _driverTip = 0;
                                    _customTipCtrl.clear();
                                  });
                                },
                              ),
                            ),
                          ),
                          ..._presetTips.map((amount) {
                            final isSelected = _driverTip == amount;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: ChoiceChip(
                                  label: Text(
                                    'JMD\$${amount.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: const Color(0xFF10B981),
                                  backgroundColor: Colors.grey.shade100,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  onSelected: (_) {
                                    setState(() {
                                      _driverTip = isSelected ? 0 : amount;
                                      _customTipCtrl.clear();
                                    });
                                  },
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _customTipCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          prefixText: 'JMD\$ ',
                          hintText: 'Custom tip amount',
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
                          isDense: true,
                        ),
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          setState(() {
                            _driverTip = (parsed != null && parsed > 0)
                                ? parsed
                                : 0;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Notes ─────────────────────────────────────────────
                _Section(
                  title: 'Special Instructions',
                  icon: Icons.notes_rounded,
                  child: TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Allergies, ring bell, gate code…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Order Summary ──────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(
                        'Subtotal',
                        'JMD\$${subtotal.toStringAsFixed(2)}',
                      ),
                      if (promoDiscount > 0)
                        _SummaryRow(
                          'Promo (${appliedPromo!.code})',
                          '−JMD\$${promoDiscount.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF10B981),
                        ),
                      if (loyaltyDiscount > 0)
                        _SummaryRow(
                          'Loyalty points',
                          '−JMD\$${loyaltyDiscount.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF6366F1),
                        ),
                      _SummaryRow(
                        'Delivery',
                        'JMD\$${deliveryFee.toStringAsFixed(2)}',
                      ),
                      _SummaryRow(
                        'Tax (10%)',
                        'JMD\$${tax.toStringAsFixed(2)}',
                      ),
                      if (_driverTip > 0)
                        _SummaryRow(
                          'Driver Tip',
                          'JMD\$${_driverTip.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF10B981),
                        ),
                      Divider(color: Colors.grey[200], height: 16),
                      _SummaryRow(
                        'Total',
                        'JMD\$${total.toStringAsFixed(2)}',
                        isBold: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Terms
                Row(
                  children: [
                    Checkbox(
                      value: _agreeToTerms,
                      onChanged: (v) =>
                          setState(() => _agreeToTerms = v ?? false),
                      activeColor: AppTheme.primaryColor,
                    ),
                    Expanded(
                      child: Text(
                        'I agree to FoodHub terms and conditions',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Place Order button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SafeArea(
                top: false,
                child: ElevatedButton(
                  onPressed:
                      _agreeToTerms &&
                          !_placingOrder &&
                          cart.isNotEmpty &&
                          currentUserId != null
                      ? () => _placeOrder(
                          userId: currentUserId,
                          subtotal: subtotal,
                          deliveryFee: deliveryFee,
                          tax: tax,
                          total: total,
                          deliveryAddress: deliveryAddress,
                          currentUser: currentUser,
                          promoDiscount: promoDiscount,
                          loyaltyDiscount: loyaltyDiscount,
                          driverTip: _driverTip,
                        )
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _placingOrder
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Place Order \u2014 JMD\$${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 7)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _placeOrder({
    required String userId,
    required double subtotal,
    required double deliveryFee,
    required double tax,
    required double total,
    required String deliveryAddress,
    required dynamic currentUser,
    required double promoDiscount,
    required double loyaltyDiscount,
    required double driverTip,
  }) async {
    if (_placingOrder) {
      return;
    }

    if (_selectedPayment == 'card') {
      final cardholder = _cardholderCtrl.text.trim();
      final email = _paymentEmailCtrl.text.trim();
      final phone = _paymentPhoneCtrl.text.trim();

      if (cardholder.isEmpty || email.isEmpty || phone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter cardholder name, email, and phone before continuing to NCB payment.',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() => _placingOrder = true);

    try {
      final orderService = ref.read(orderServiceProvider);
      final orderCalcService = ref.read(orderCalculationServiceProvider);
      final paymentService = ref.read(paymentServiceProvider);
      final cart = ref.read(cartProvider);
      final appliedPromo = ref.read(appliedPromoProvider);
      final selectedAddress = ref.read(selectedAddressProvider);
      final redeemPts = ref.read(redeemPointsProvider);

      final restaurantId = cart.first.menuItem.restaurantId;
      final delLat = selectedAddress?.latitude ?? currentUser?.latitude ?? 0.0;
      final delLng =
          selectedAddress?.longitude ?? currentUser?.longitude ?? 0.0;

      // ── Server-verified total ───────────────────────────────────────────
      final serverItems = cart
          .map(
            (c) => <String, dynamic>{
              'menu_item_id': c.menuItem.id,
              'quantity': c.quantity,
              'side_ids': c.selectedSides.map((s) => s.id).toList(),
            },
          )
          .toList();

      final breakdown = await orderCalcService.calculate(
        restaurantId: restaurantId,
        userId: userId,
        items: serverItems,
        promoCode: appliedPromo?.code,
        redeemPoints: redeemPts,
        driverTip: driverTip,
        paymentMethod: _selectedPayment,
        deliveryLatitude: delLat != 0.0 ? delLat : null,
        deliveryLongitude: delLng != 0.0 ? delLng : null,
      );

      // Use server amounts if available, otherwise fall back to client math
      final verifiedSubtotal = breakdown?.subtotal ?? subtotal;
      final verifiedDeliveryFee = breakdown?.deliveryFee ?? deliveryFee;
      final verifiedTax = breakdown?.taxAmount ?? tax;
      final verifiedDiscount =
          (breakdown?.promoDiscount ?? promoDiscount) +
          (breakdown?.loyaltyDiscount ?? loyaltyDiscount);
      final verifiedTotal = breakdown?.grandTotal ?? total;

      final orderItems = cart
          .map(
            (c) => OrderItem(
              id: '',
              menuItemId: c.menuItem.id,
              itemName: c.menuItem.name,
              price: c.menuItem.discountedPrice,
              quantity: c.quantity,
              notes: c.notes,
              sides: c.selectedSides
                  .map(
                    (s) => OrderItemSide(
                      id: '',
                      sideName: s.name,
                      sidePrice: s.price,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList();

      final order = await orderService.createOrder(
        userId: userId,
        restaurantId: restaurantId,
        items: orderItems,
        subtotal: verifiedSubtotal,
        deliveryFee: verifiedDeliveryFee,
        taxAmount: verifiedTax,
        discount: verifiedDiscount,
        totalAmount: verifiedTotal,
        deliveryAddress: deliveryAddress,
        deliveryLatitude: delLat,
        deliveryLongitude: delLng,
        notes: _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : null,
        paymentMethod: _selectedPayment,
        contactlessDelivery: _contactlessDelivery,
        driverTip: driverTip > 0 ? driverTip : null,
        scheduledFor: _scheduledAt,
      );

      if (order == null) {
        throw Exception('Order could not be created.');
      }

      if (_selectedPayment == 'card') {
        NcbPaymentSession checkoutSession;
        try {
          checkoutSession = await paymentService.createCardCheckout(
            orderId: order.id,
            amount: verifiedTotal,
            customerEmail: _paymentEmailCtrl.text.trim(),
            customerPhone: _paymentPhoneCtrl.text.trim(),
            customerName: _cardholderCtrl.text.trim(),
            billingAddress: deliveryAddress,
          );
        } catch (e) {
          // Payment session failed – delete the order so nothing lingers.
          await _deleteOrder(order.id);
          rethrow;
        }

        if (!mounted) {
          return;
        }

        final paymentCompleted = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (routeContext) =>
                NcbPaymentScreen(session: checkoutSession),
          ),
        );

        if (!mounted) {
          return;
        }

        if (paymentCompleted != true) {
          // User dismissed or payment was not completed – remove the order entirely.
          await _deleteOrder(order.id);
          setState(() => _placingOrder = false);
          return;
        }

        // Refresh saved cards (callback saves card info server-side)
        ref.invalidate(savedCardsProvider(userId));
      }

      // Mark promo as used
      if (appliedPromo != null) {
        await ref.read(promoServiceProvider).markUsed(appliedPromo.id);
      }

      // Redeem loyalty points if selected
      if (redeemPts > 0) {
        await ref
            .read(loyaltyServiceProvider)
            .redeemPoints(userId: userId, orderId: order.id, points: redeemPts);
      }
      // Earn loyalty points from this order
      await ref
          .read(loyaltyServiceProvider)
          .earnPoints(userId: userId, orderId: order.id, orderTotal: total);

      ref.read(cartProvider.notifier).clearCart();
      ref.read(appliedPromoProvider.notifier).clear();
      ref.read(redeemPointsProvider.notifier).state = 0;
      ref.read(selectedAddressProvider.notifier).state = null;
      // Refresh loyalty balance so it reflects redeemed/earned points.
      if (userId.isNotEmpty) {
        ref.invalidate(loyaltyAccountProvider(userId));
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderSuccessScreen(
            orderId: order.id,
            contactlessDelivery: order.contactlessDelivery,
            deliveryOtp: order.deliveryOtp,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      String message = e.toString();
      if (message.contains('NOT_FOUND') || message.contains('404')) {
        message =
            'Card payments are not available yet. The payment service has not been deployed.';
      } else if (message.contains('Exception: ')) {
        message = message.replaceFirst(RegExp(r'^Exception:\s*'), '');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _placingOrder = false);
      }
    }
  }

  /// Silently delete an unpaid order so nothing lingers in the database.
  Future<void> _deleteOrder(String orderId) async {
    try {
      final client = SupabaseConfig.client;
      await client.from('order_items').delete().eq('order_id', orderId);
      await client.from('payments').delete().eq('order_id', orderId);
      await client.from('orders').delete().eq('id', orderId);
    } catch (_) {
      // Best-effort cleanup – don't block the user.
    }
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AddressChip extends StatelessWidget {
  final UserAddress address;
  final bool isSelected;
  const _AddressChip({required this.address, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryColor : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppTheme.primaryColor : Colors.grey.shade200,
        ),
      ),
      child: Text(
        address.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _CardPaymentPanel extends StatelessWidget {
  final TextEditingController cardholderController;
  final TextEditingController emailController;
  final TextEditingController phoneController;

  const _CardPaymentPanel({
    required this.cardholderController,
    required this.emailController,
    required this.phoneController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF1F2937)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF111827).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Secure Card Payment',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              // Accepted card brands
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MiniCardBrand('VISA', const Color(0xFF1A1F71)),
                    const SizedBox(width: 6),
                    _MiniCardBrand('MC', const Color(0xFFFF5F00)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'You\'ll enter your card details on the secure NCB payment page. We never store your card information.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _CardField(
            controller: cardholderController,
            label: 'Cardholder Name',
            icon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          _CardField(
            controller: emailController,
            label: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          _CardField(
            controller: phoneController,
            label: 'Phone Number',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: const Color(0xFF10B981),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your payment is processed securely by NCB Jamaica',
                    style: TextStyle(
                      color: const Color(0xFF10B981),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
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

class _MiniCardBrand extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniCardBrand(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w900,
        color: color,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _CardField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  const _CardField({
    required this.controller,
    required this.label,
    this.icon,
    this.keyboardType,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 13,
        ),
        prefixIcon: icon != null
            ? Icon(icon, color: Colors.white.withValues(alpha: 0.4), size: 18)
            : null,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primaryColor),
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _TimeChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: selected
                    ? AppTheme.primaryColor
                    : const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  const _PaymentTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primaryColor.withValues(alpha: 0.12)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: selected
                    ? AppTheme.primaryColor
                    : const Color(0xFF9CA3AF),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? const Color(0xFF1F2937)
                          : AppTheme.textSecondary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.primaryColor,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _SavedCardTile extends StatelessWidget {
  final SavedCard card;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SavedCardTile({
    required this.card,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final brandColor = switch (card.cardBrand.toLowerCase()) {
      'visa' => const Color(0xFF1A1F71),
      'mastercard' => const Color(0xFFEB001B),
      _ => const Color(0xFF6B7280),
    };

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Card brand icon
            Container(
              width: 42,
              height: 28,
              decoration: BoxDecoration(
                color: brandColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: brandColor.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                card.displayBrand,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: brandColor,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Card details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.maskedNumber,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    card.cardholderName,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (card.isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Default',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            // Delete button
            GestureDetector(
              onTap: onDelete,
              child: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Color(0xFFD1D5DB),
              ),
            ),
            const SizedBox(width: 4),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.primaryColor,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

class _CardBrandChip extends StatelessWidget {
  final String label;
  final Color color;
  const _CardBrandChip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;
  const _SummaryRow(
    this.label,
    this.value, {
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w400,
              fontSize: isBold ? 15 : 13,
              color: const Color(0xFF6B7280),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: isBold ? 15 : 13,
              color: valueColor ?? const Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }
}
