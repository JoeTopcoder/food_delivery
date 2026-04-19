import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
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
import '../../utils/context_extensions.dart';
import '../../providers/wallet_provider.dart';
import 'order_success_screen.dart';
import '../../utils/est_datetime.dart';
import '../../utils/friendly_error.dart';
import '../../providers/delivery_region_provider.dart';
import '../../providers/feature_providers.dart';
import '../../services/delivery_fee_service.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../providers/recommendation_provider.dart';
import 'home_screen.dart' show activeAdForOrderProvider, clearActiveAd;

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
  final _cvcCtrl = TextEditingController();
  String _selectedPayment = 'cash';
  SavedCard? _selectedSavedCard;
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
    _cvcCtrl.dispose();
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
    final isPickup = ref.watch(isPickupProvider);
    final restaurantId = cart.isNotEmpty
        ? cart.first.menuItem.restaurantId
        : null;
    final restaurantAsync = restaurantId != null
        ? ref.watch(restaurantByIdProvider(restaurantId))
        : const AsyncValue<Restaurant?>.data(null);
    final restaurant = restaurantAsync.valueOrNull;

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

    // Admin-configured delivery fee via Edge Function
    final delLat = selectedAddress?.latitude ?? currentUser?.latitude;
    final delLng = selectedAddress?.longitude ?? currentUser?.longitude;
    final hasCoords = delLat != null && delLng != null && restaurantId != null;
    final feeKey = hasCoords
        ? '$restaurantId|$delLat|$delLng|${restaurant?.latitude ?? ''}|${restaurant?.longitude ?? ''}|${restaurant?.deliveryFee ?? ''}'
        : '';
    final feeAsync = feeKey.isNotEmpty && !isPickup
        ? ref.watch(deliveryFeeProvider(feeKey))
        : const AsyncValue<DeliveryFeeResult?>.data(null);
    final feeLoading = hasCoords && !isPickup && feeAsync.isLoading;
    final feeResult = feeAsync.valueOrNull;
    final deliveryFee =
        feeResult?.deliveryFee ?? AppConstants.defaultDeliveryFee;
    final distanceKm = feeResult?.distanceKm;

    final pickupServiceFee =
        restaurant?.serviceFee ?? AppConstants.pickupServiceFee;

    // ── MealHub+ subscription benefit ──────────────────────────────
    final activeSub = ref.watch(activeSubscriptionProvider).valueOrNull;
    debugPrint(
      '[CHECKOUT] activeSub: ${activeSub?.id}, status: ${activeSub?.status}, '
      'deliveries: ${activeSub?.deliveriesRemaining}, isPickup: $isPickup, '
      'subtotal: $subtotal, minCart: ${AppConstants.subscriptionMinCart}',
    );
    final subEligible =
        activeSub != null &&
        activeSub.isActive &&
        activeSub.hasDeliveries &&
        !isPickup &&
        subtotal >= AppConstants.subscriptionMinCart;
    final subDeliveryFree = subEligible; // zero delivery fee
    final subServiceDiscount = subEligible
        ? (pickupServiceFee * (activeSub.serviceFeeDiscount))
        : 0.0;

    final rawFee = isPickup
        ? (pickupServiceFee - subServiceDiscount).clamp(0.0, double.infinity)
        : deliveryFee;
    final activeFee = subDeliveryFree ? 0.0 : rawFee;
    final tax = subtotal * AppConstants.taxRate;
    final orderTotal =
        (subtotal - promoDiscount - loyaltyDiscount + activeFee + tax).clamp(
          activeFee,
          double.infinity,
        );
    final total = orderTotal + _driverTip;

    final deliveryAddress =
        selectedAddress?.address ?? currentUser?.address ?? 'No address saved';

    _hydratePaymentFields(currentUser);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          context.l10n.checkout,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(
              bottom: 110,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Delivery Address / Pickup Location ────────────────
                if (isPickup)
                  _Section(
                    title: 'Pickup Location',
                    icon: Icons.store_rounded,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(
                            0xFF10B981,
                          ).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.store_rounded,
                            color: Color(0xFF10B981),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  restaurant?.name ?? 'Restaurant',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                if (restaurant?.address != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    restaurant!.address!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  _Section(
                    title: 'Delivery Address',
                    icon: Icons.location_on_rounded,
                    child: Column(
                      children: [
                        // Saved address book
                        if (addressAsync != null)
                          addressAsync.when(
                            loading: () => const SizedBox.shrink(),
                            error: (error, stackTrace) =>
                                const SizedBox.shrink(),
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
                                                    selectedAddressIdProvider
                                                        .notifier,
                                                  )
                                                  .state = sel
                                              ? null
                                              : a.id,
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
                            color: Theme.of(context).cardColor,
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
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pushNamed(
                                  context,
                                  '/address-book',
                                ),
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

                // ── Schedule (optional / forced when closed) ─────────
                Builder(
                  builder: (context) {
                    final restaurant = restaurantAsync.valueOrNull;
                    final isClosed =
                        restaurant != null && !restaurant.isCurrentlyOpen;

                    // Auto-set schedule when restaurant is closed
                    if (isClosed && _scheduledAt == null) {
                      final earliest = restaurant.nextSchedulableTime;
                      if (earliest != null) {
                        Future.microtask(
                          () => setState(() => _scheduledAt = earliest),
                        );
                      }
                    }

                    return _Section(
                      title: isPickup ? 'Pickup Time' : 'Delivery Time',
                      icon: Icons.schedule_rounded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isClosed) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.accentColor.withValues(
                                  alpha: 0.08,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppTheme.accentColor.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Text(
                                'This restaurant is currently closed. '
                                '${restaurant.nextOpenLabel}. '
                                'Your order will be scheduled.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.accentColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: _TimeChip(
                                  label: 'ASAP',
                                  subtitle: '20-35 min',
                                  selected: _scheduledAt == null && !isClosed,
                                  onTap: isClosed
                                      ? null
                                      : () =>
                                            setState(() => _scheduledAt = null),
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
                                  selected: _scheduledAt != null || isClosed,
                                  onTap: () =>
                                      _pickSchedule(restaurant: restaurant),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
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
                      // Wallet payment option
                      Consumer(
                        builder: (context, ref, _) {
                          final walletAsync = ref.watch(walletNotifierProvider);
                          final walletBalance =
                              walletAsync.valueOrNull?.totalAvailable ?? 0;
                          return _PaymentTile(
                            icon: Icons.account_balance_wallet_rounded,
                            label: 'Wallet',
                            subtitle: walletBalance > 0
                                ? 'Balance: \$${walletBalance.toStringAsFixed(2)}'
                                : 'No funds \u2014 top up in your profile',
                            selected: _selectedPayment == 'wallet',
                            onTap: () {
                              if (walletBalance > 0) {
                                setState(() => _selectedPayment = 'wallet');
                              }
                            },
                          );
                        },
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
                        // ── Saved Cards (verified only) ──
                        if (savedCardsAsync != null)
                          savedCardsAsync.when(
                            loading: () => const AppLoadingIndicator(),
                            error: (_, _) => const SizedBox.shrink(),
                            data: (savedCards) {
                              final verifiedCards = savedCards
                                  .where((c) => c.isVerified)
                                  .toList();
                              if (verifiedCards.isEmpty) {
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.credit_card_off_outlined,
                                        size: 32,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No saved cards',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Add a card from your Wallet first',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ...verifiedCards.map(
                                    (card) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _SavedCardTile(
                                        card: card,
                                        selected:
                                            _selectedSavedCard?.id == card.id,
                                        onTap: () {
                                          setState(() {
                                            _selectedSavedCard = card;
                                            _cardholderCtrl.text =
                                                card.cardholderName;
                                            _paymentEmailCtrl.text = card.email;
                                            _paymentPhoneCtrl.text = card.phone;
                                            _cvcCtrl.clear();
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
                                                  child: Text(
                                                    context.l10n.cancel,
                                                  ),
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
                                ],
                              );
                            },
                          ),
                        // CVC field when a saved card is selected
                        if (_selectedSavedCard != null) ...[
                          const SizedBox(height: 12),
                          Container(
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
                                  color: const Color(
                                    0xFF111827,
                                  ).withValues(alpha: 0.3),
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
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.lock_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Paying with ${_selectedSavedCard!.displayBrand} •••• ${_selectedSavedCard!.lastFour}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Enter your CVC to confirm payment',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: _cvcCtrl,
                                    keyboardType: TextInputType.number,
                                    maxLength: 4,
                                    obscureText: true,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 6,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: '•••',
                                      hintStyle: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.3,
                                        ),
                                        letterSpacing: 6,
                                      ),
                                      counterText: '',
                                      filled: true,
                                      fillColor: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: 0.15,
                                          ),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.2),
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
                                          'Your CVC is never stored and is used only for this transaction',
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
                          ),
                        ],
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
                                  '"${appliedPromo.code}" — saved \$${promoDiscount.toStringAsFixed(2)}',
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
                                  '(= \$${account.redemptionValue.toStringAsFixed(2)})',
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
                                  '${AppConstants.currencySymbol}${loyaltyDiscount.toStringAsFixed(2)} off',
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

                // ── Contactless Delivery (hidden for pickup) ──────────
                if (!isPickup)
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

                // ── Driver Tip (hidden for pickup) ────────────────────
                if (!isPickup)
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
                                      '${AppConstants.currencySymbol}${amount.toStringAsFixed(0)}',
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
                            prefixText: '\$ ',
                            hintText: 'Custom tip amount',
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
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
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(
                        context.l10n.subtotal,
                        '${AppConstants.currencySymbol}${subtotal.toStringAsFixed(2)}',
                      ),
                      if (promoDiscount > 0)
                        _SummaryRow(
                          'Promo (${appliedPromo!.code})',
                          '−\$${promoDiscount.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF10B981),
                        ),
                      if (loyaltyDiscount > 0)
                        _SummaryRow(
                          'Loyalty points',
                          '−\$${loyaltyDiscount.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF6366F1),
                        ),
                      if (isPickup)
                        _SummaryRow(
                          subServiceDiscount > 0
                              ? 'Service Fee (MealHub+ ${(activeSub!.serviceFeeDiscount * 100).toInt()}% off)'
                              : 'Service Fee',
                          '${AppConstants.currencySymbol}${rawFee.toStringAsFixed(2)}',
                          valueColor: subServiceDiscount > 0
                              ? const Color(0xFF6C63FF)
                              : const Color(0xFF10B981),
                        )
                      else
                        _SummaryRow(
                          subDeliveryFree
                              ? 'Delivery (MealHub+ FREE)'
                              : 'Delivery${feeResult?.calculation == 'distance_based'
                                    ? ' (KM)'
                                    : feeResult?.restaurantOverride != null
                                    ? ' (Store)'
                                    : ' (Base)'}${distanceKm != null ? ' – ${distanceKm.toStringAsFixed(1)} km' : ''}',
                          feeLoading
                              ? 'Calculating…'
                              : subDeliveryFree
                              ? '\$0.00'
                              : '${AppConstants.currencySymbol}${deliveryFee.toStringAsFixed(2)}',
                          valueColor: subDeliveryFree
                              ? const Color(0xFF6C63FF)
                              : null,
                        ),
                      _SummaryRow(
                        'Tax (10%)',
                        '${AppConstants.currencySymbol}${tax.toStringAsFixed(2)}',
                      ),
                      if (_driverTip > 0)
                        _SummaryRow(
                          'Driver Tip',
                          '${AppConstants.currencySymbol}${_driverTip.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF10B981),
                        ),
                      Divider(color: Colors.grey[200], height: 16),
                      _SummaryRow(
                        'Total',
                        '${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
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
                          deliveryFee: activeFee,
                          tax: tax,
                          total: total,
                          deliveryAddress: deliveryAddress,
                          currentUser: currentUser,
                          promoDiscount: promoDiscount,
                          loyaltyDiscount: loyaltyDiscount,
                          driverTip: isPickup ? 0 : _driverTip,
                          isPickup: isPickup,
                          pickupFee: isPickup ? pickupServiceFee : null,
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
                          '${isPickup ? "Place Pickup Order" : "Place Order"} \u2014 \$${total.toStringAsFixed(2)}',
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

  Future<void> _pickSchedule({Restaurant? restaurant}) async {
    final now = EstDateTime.now();
    final isClosed = restaurant != null && !restaurant.isCurrentlyOpen;
    final earliest = isClosed
        ? restaurant.nextSchedulableTime ?? now.add(const Duration(hours: 1))
        : now.add(const Duration(hours: 1));

    // firstDate must be at least the earliest schedulable time
    final firstDate = isClosed
        ? DateTime(earliest.year, earliest.month, earliest.day)
        : DateTime(now.year, now.month, now.day);

    final date = await showDatePicker(
      context: context,
      initialDate: earliest,
      firstDate: firstDate,
      lastDate: now.add(const Duration(days: 7)),
    );
    if (date == null || !mounted) return;

    final initialTime =
        (date.year == earliest.year &&
            date.month == earliest.month &&
            date.day == earliest.day)
        ? TimeOfDay(hour: earliest.hour, minute: earliest.minute)
        : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1)));

    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (time == null) return;

    var chosen = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    // Clamp to earliest if user picked too early
    if (chosen.isBefore(earliest)) {
      chosen = earliest;
      if (mounted) {
        AppSnackbar.info(
          context,
          'Earliest available time is '
          '${DateFormat('MMM d, h:mm a').format(earliest)}. '
          'Adjusted automatically.',
        );
      }
    }

    setState(() => _scheduledAt = chosen);
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
    bool isPickup = false,
    double? pickupFee,
  }) async {
    if (_placingOrder) {
      return;
    }

    if (_selectedPayment == 'card') {
      // Stripe handles card input natively via Payment Sheet
      // No need to pre-select a saved card or enter CVC
    }

    // Wallet: block order if balance is too low
    if (_selectedPayment == 'wallet') {
      final walletBalance =
          ref.read(walletNotifierProvider).valueOrNull?.totalAvailable ?? 0;
      if (walletBalance < total) {
        AppSnackbar.error(
          context,
          'Insufficient wallet balance (\$${walletBalance.toStringAsFixed(2)}). '
          'Top up \$${(total - walletBalance).toStringAsFixed(2)} more or choose another payment method.',
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
      final restaurantObj = ref
          .read(restaurantByIdProvider(restaurantId))
          .valueOrNull;
      final delLat = selectedAddress?.latitude ?? currentUser?.latitude ?? 0.0;
      final delLng =
          selectedAddress?.longitude ?? currentUser?.longitude ?? 0.0;

      // ── Delivery region check (skip for pickup) ─────────────────────
      if (!isPickup && delLat != 0.0 && delLng != 0.0) {
        final regionService = ref.read(deliveryRegionServiceProvider);
        final insideRegion = await regionService.isInsideActiveRegion(
          delLat,
          delLng,
        );
        if (!insideRegion) {
          setState(() => _placingOrder = false);
          if (!mounted) return;
          AppSnackbar.error(
            context,
            'Your delivery address is outside our delivery regions. '
            'Please choose an address within a supported area.',
          );
          return;
        }
      }

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

      // Check if order came from a featured ad
      final activeAd = ref.read(activeAdForOrderProvider);
      final isFromAd =
          activeAd != null && activeAd.restaurantId == restaurantId;

      final order = await orderService.createOrder(
        userId: userId,
        restaurantId: restaurantId,
        items: orderItems,
        subtotal: verifiedSubtotal,
        deliveryFee: verifiedDeliveryFee,
        taxAmount: verifiedTax,
        discount: verifiedDiscount,
        totalAmount: verifiedTotal,
        deliveryAddress: isPickup
            ? (restaurantObj?.name ?? 'Pickup')
            : deliveryAddress,
        deliveryLatitude: delLat,
        deliveryLongitude: delLng,
        notes: _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : null,
        paymentMethod: _selectedPayment,
        contactlessDelivery: isPickup ? false : _contactlessDelivery,
        driverTip: driverTip > 0 ? driverTip : null,
        scheduledFor: _scheduledAt,
        isPickup: isPickup,
        pickupFee: pickupFee,
        fromAd: isFromAd,
        adId: isFromAd ? activeAd.id : null,
      );

      // Clear active ad after order placed
      if (isFromAd) clearActiveAd(ref);

      if (order == null) {
        throw Exception('Order could not be created.');
      }

      // Wallet payment: deduct from wallet balance
      if (_selectedPayment == 'wallet') {
        try {
          await ref
              .read(walletNotifierProvider.notifier)
              .payWithWallet(verifiedTotal, order.id);
        } catch (e) {
          await _deleteOrder(order.id);
          rethrow;
        }
      }

      if (_selectedPayment == 'card') {
        StripePaymentSession stripeSession;
        try {
          final authUser = Supabase.instance.client.auth.currentUser;
          final email = _selectedSavedCard?.email.isNotEmpty == true
              ? _selectedSavedCard!.email
              : (authUser?.email ?? _paymentEmailCtrl.text.trim());
          final name = _selectedSavedCard?.cardholderName.isNotEmpty == true
              ? _selectedSavedCard!.cardholderName
              : (authUser?.userMetadata?['name'] as String? ?? 'Customer');

          stripeSession = await paymentService.createStripeCheckout(
            orderId: order.id,
            amount: verifiedTotal,
            customerEmail: email,
            customerName: name,
          );

          if (!mounted) return;

          final paymentCompleted = await paymentService
              .presentStripePaymentSheet(
                session: stripeSession,
                customerEmail: email,
                customerName: name,
              );

          if (!mounted) return;

          if (!paymentCompleted) {
            await _deleteOrder(order.id);
            setState(() => _placingOrder = false);
            return;
          }

          // Confirm server-side
          await paymentService.confirmStripePayment(
            paymentIntentId: stripeSession.paymentIntentId,
            orderId: order.id,
          );
        } catch (e) {
          await _deleteOrder(order.id);
          rethrow;
        }
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

      // Use a MealHub+ subscription delivery if applicable
      final currentSub = ref.read(activeSubscriptionProvider).valueOrNull;
      if (currentSub != null &&
          currentSub.isActive &&
          currentSub.hasDeliveries &&
          !isPickup) {
        await ref
            .read(subscriptionServiceProvider)
            .useSubscriptionDelivery(
              subscriptionId: currentSub.id,
              orderId: order.id,
            );
        ref.invalidate(activeSubscriptionProvider);
      }

      // Track order completion for AI engine
      ref
          .read(behaviorTrackingProvider)
          .trackOrderCompleted(userId, order.id, verifiedTotal);

      ref.read(cartProvider.notifier).clearCart();
      ref.read(appliedPromoProvider.notifier).clear();
      ref.read(redeemPointsProvider.notifier).state = 0;
      ref.read(selectedAddressIdProvider.notifier).state = null;
      ref.read(isPickupProvider.notifier).state = false;
      // Refresh loyalty balance so it reflects redeemed/earned points.
      if (userId.isNotEmpty) {
        ref.invalidate(loyaltyAccountProvider(userId));
      }
      // Refresh brain engine so coupon/recommendations update after order
      ref.invalidate(brainEngineProvider);
      // Ensure the new order shows in order history immediately
      ref.invalidate(userOrdersProvider(userId));

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderSuccessScreen(
            orderId: order.id,
            contactlessDelivery: order.contactlessDelivery,
            deliveryOtp: order.deliveryOtp,
            isPickup: order.isPickup,
            receiptNumber: order.receiptNumber,
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

      AppSnackbar.error(context, message);
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
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
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
          color: isSelected
              ? Colors.white
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  const _TimeChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
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
                          : Theme.of(context).colorScheme.onSurfaceVariant,
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
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
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.w400,
                fontSize: isBold ? 15 : 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: isBold ? 15 : 13,
              color: valueColor ?? Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
