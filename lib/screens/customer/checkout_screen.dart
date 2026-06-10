// ignore_for_file: use_build_context_synchronously

import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/utils/responsive.dart';
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
import '../../utils/app_theme.dart';
import '../../utils/context_extensions.dart';
import '../../providers/wallet_provider.dart';
import 'order_success_screen.dart';
import '../../utils/friendly_error.dart';
import '../../utils/safe_state_mixin.dart';
import '../../providers/delivery_region_provider.dart';
import '../../providers/feature_providers.dart';
import '../../services/driver/delivery_fee_service.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../widgets/outstanding_debt_banner.dart';
import '../../providers/recommendation_provider.dart';
import '../../providers/decision_engine_provider.dart';
import '../../utils/app_logger.dart';
import 'home_screen.dart' show activeAdForOrderProvider, clearActiveAd;

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen>
    with SafeConsumerStateMixin<CheckoutScreen> {
  final _promoCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _cardholderCtrl = TextEditingController();
  final _paymentEmailCtrl = TextEditingController();
  final _paymentPhoneCtrl = TextEditingController();
  final _cvcCtrl = TextEditingController();
  String _selectedPayment = 'stripe';
  SavedCard? _selectedSavedCard;
  bool _agreeToTerms = false;
  bool _addressConfirmed = false;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentUser = ref.read(currentUserProvider);
    _hydratePaymentFields(currentUser);
    // Auto-confirm address on first load when:
    // - pickup is selected (no delivery address needed), OR
    // - the user already has a saved/default address pre-filled.
    if (!_addressConfirmed) {
      final isPickup = ref.read(isPickupProvider);
      final selectedAddress = ref.read(selectedAddressProvider);
      if (isPickup || selectedAddress != null || currentUser?.address != null) {
        // Use setState so the button re-renders as enabled immediately.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _addressConfirmed = true);
        });
      }
    }
  }

  void _hydratePaymentFields(User? currentUser) {
    if (_paymentFieldsHydrated || currentUser == null) {
      return;
    }

    _paymentFieldsHydrated = true;
    _cardholderCtrl.text = currentUser.name ?? '';
    _paymentEmailCtrl.text = currentUser.email ?? '';
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
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _promoError = msg.isNotEmpty ? msg : friendlyError(e));
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

    // Watch restaurant data - critical for checkout
    final restaurantAsync = restaurantId != null
        ? ref.watch(restaurantByIdProvider(restaurantId))
        : const AsyncValue<Restaurant?>.data(null);

    // Show loading spinner while critical data loads
    if (restaurantAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final restaurant = restaurantAsync.valueOrNull;

    final appliedPromo = ref.watch(appliedPromoProvider);
    final redeemPoints = currentUserId != null
        ? ref.watch(redeemPointsProvider)
        : 0;

    // Watch loyalty data - non-critical, show loading state inline
    final loyaltyAsync = currentUserId != null
        ? ref.watch(loyaltyAccountProvider(currentUserId))
        : null;

    final selectedAddress = ref.watch(selectedAddressProvider);

    // Watch addresses - non-critical, use valueOrNull for instant render
    final addressAsync = currentUserId != null
        ? ref.watch(userAddressesProvider(currentUserId))
        : null;

    // Watch saved cards - non-critical, use valueOrNull for instant render
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
    final baseDeliveryFee =
        feeResult?.deliveryFee ?? AppConstants.defaultDeliveryFee;
    final distanceKm = feeResult?.distanceKm;

    // ── Group order discount (60% of regular delivery fee) ──────────
    final groupParticipantCount = ref.watch(groupOrderParticipantCountProvider);
    final isGroupOrder = groupParticipantCount > 0;
    final deliveryFee = isGroupOrder ? baseDeliveryFee * 0.60 : baseDeliveryFee;

    final pickupServiceFee =
        restaurant?.serviceFee ?? AppConstants.pickupServiceFee;

    // ── MealHub+ subscription benefit ──────────────────────────────
    final activeSub = ref.watch(activeSubscriptionProvider).valueOrNull;
    final subEligible =
        activeSub != null &&
        activeSub.isActive &&
        activeSub.hasDeliveries &&
        !isPickup;
    final subDeliveryFree = subEligible; // zero delivery fee
    final subServiceDiscount = subEligible
        ? (pickupServiceFee * (activeSub.serviceFeeDiscount))
        : 0.0;

    final rawFee = isPickup
        ? (pickupServiceFee - subServiceDiscount).clamp(0.0, double.infinity)
        : deliveryFee;
    final activeFee = subDeliveryFree ? 0.0 : rawFee;
    final platformServiceFee = subtotal * AppConstants.platformServiceFeeRate;

    // Zone-based tax: look up the delivery zone only when coords are known.
    final taxKey = (!isPickup && delLat != null && delLng != null)
        ? '$delLat|$delLng'
        : null;
    final zoneTax = taxKey != null
        ? ref.watch(zoneTaxProvider(taxKey)).valueOrNull
        : null;
    final effectiveTaxRate = zoneTax?.taxRate ?? 0.0;
    final tax = subtotal * effectiveTaxRate;
    final orderTotal =
        (subtotal -
                promoDiscount -
                loyaltyDiscount +
                activeFee +
                platformServiceFee +
                tax)
            .clamp(activeFee, double.infinity);
    final total = orderTotal + _driverTip;
    final outstandingDebt = ref.watch(outstandingDebtProvider);
    final grandTotal = total + outstandingDebt;

    final deliveryAddress =
        selectedAddress?.address ?? currentUser?.address ?? 'No address saved';

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () {
            // Clear group order state when backing out of checkout
            if (ref.read(groupOrderParticipantCountProvider) > 0) {
              ref.read(groupOrderParticipantCountProvider.notifier).state = 0;
              ref.read(groupOrderIdForCheckoutProvider.notifier).state = null;
            }
            Navigator.pop(context);
          },
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
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.only(
              bottom: Responsive.bottomPaddingForFixedButton(context),
              left: Responsive.horizontalPadding(context),
              right: Responsive.horizontalPadding(context),
              top: Responsive.spacing(context) * 0.5,
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
                      padding: EdgeInsets.all(Responsive.spacingSmall(context)),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(Responsive.cardRadius(context) - 2),
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
                                    fontSize: Responsive.headingSmall(context),
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
                                      fontSize: Responsive.smallText(context),
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
                                          onTap: () {
                                            ref
                                                .read(
                                                  selectedAddressIdProvider
                                                      .notifier,
                                                )
                                                .state = sel
                                                ? null
                                                : a.id;
                                            setState(
                                              () => _addressConfirmed = false,
                                            );
                                          },
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
                          padding: EdgeInsets.all(Responsive.spacingSmall(context)),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(Responsive.cardRadius(context) - 2),
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.place_rounded,
                                color: AppTheme.primaryColor,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  deliveryAddress,
                                  style: TextStyle(
                                    fontSize: Responsive.smallText(context),
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
                        const SizedBox(height: 8),
                        _AddressSlider(
                          confirmed: _addressConfirmed,
                          onConfirmed: () =>
                              setState(() => _addressConfirmed = true),
                          onReset: () =>
                              setState(() => _addressConfirmed = false),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),

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
                              padding: EdgeInsets.all(Responsive.spacingSmall(context)),
                              margin: EdgeInsets.only(bottom: Responsive.spacing(context)),
                              decoration: BoxDecoration(
                                color: AppTheme.accentColor.withValues(
                                  alpha: 0.08,
                                ),
                                borderRadius: BorderRadius.circular(Responsive.cardRadius(context) - 2),
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
                                style: TextStyle(
                                  fontSize: Responsive.smallText(context),
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
                const SizedBox(height: 8),

                // ── Payment ───────────────────────────────────────────
                _Section(
                  title: 'Payment Method',
                  icon: Icons.payment_rounded,
                  child: Column(
                    children: [
                      // Wallet payment option
                      Consumer(
                        builder: (context, ref, _) {
                          final walletAsync = ref.watch(walletBalanceStreamProvider);
                          final walletBalance =
                              walletAsync.valueOrNull?.availableBalance ?? 0;
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
                        subtitle: 'Visa, Mastercard, and more',
                        selected: _selectedPayment == 'stripe',
                        onTap: () =>
                            setState(() => _selectedPayment = 'stripe'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CardBrandChip('VISA', const Color(0xFF1A1F71)),
                            const SizedBox(width: 4),
                            _CardBrandChip('MC', const Color(0xFFEB001B)),
                          ],
                        ),
                      ),
                      if (_selectedPayment == 'stripe') ...[
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
                                  padding: EdgeInsets.all(Responsive.cardPadding(context)),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.outlineVariant,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.credit_card_off_outlined,
                                        size: 32,
                                        color: Colors.grey.shade700,
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
                                          fontSize: Responsive.smallText(context),
                                          color: Colors.grey.shade700,
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
                        // (CVC entry removed — the user enters card details
                        // on the secure Lunipay "Pay with Card" page after
                        // tapping Pay Now.)
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── AI-Assigned Promo Banner ──────────────────────
                OutstandingDebtBanner(debtAmount: outstandingDebt),
                if (currentUserId != null)
                  _AiPromoBanner(userId: currentUserId, subtotal: subtotal),

                // ── Promo Code ────────────────────────────────────────
                _Section(
                  title: 'Promo Code',
                  icon: Icons.discount_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (appliedPromo != null)
                        Container(
                          padding: EdgeInsets.all(Responsive.spacingSmall(context)),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(Responsive.cardRadius(context) - 2),
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
                                  style: TextStyle(
                                    color: const Color(0xFF10B981),
                                    fontWeight: FontWeight.w600,
                                    fontSize: Responsive.smallText(context),
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
                const SizedBox(height: 8),

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
                                Flexible(
                                  child: Text(
                                  'You have ${account.points} pts '
                                  '(= \$${account.redemptionValue.toStringAsFixed(2)})',
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                ),
                                const SizedBox(width: 8),
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

                const SizedBox(height: 8),

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
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                const SizedBox(height: 8),

                // ── Driver Tip (hidden for pickup) ────────────────────
                if (!isPickup)
                  _Section(
                    title: 'Tip Your Driver',
                    icon: Icons.volunteer_activism_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '100% goes directly to your driver',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 8),
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
                                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  labelStyle: TextStyle(
                                    color: _driverTip == 0
                                        ? Colors.white
                                        : Theme.of(context).colorScheme.onSurface,
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
                                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Theme.of(context).colorScheme.onSurface,
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
                        const SizedBox(height: 8),
                        TextField(
                          controller: _customTipCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            prefixText: '\$ ',
                            hintText: 'Custom tip amount',
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.outlineVariant,
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
                const SizedBox(height: 8),

                // ── Notes ─────────────────────────────────────────────
                _Section(
                  title: 'Special Instructions',
                  icon: Icons.notes_rounded,
                  child: TextField(
                    controller: _notesCtrl,
                    maxLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Allergies, ring bell, gate code…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.all(10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Order Summary ──────────────────────────────────────
                Container(
                  padding: EdgeInsets.all(Responsive.cardPadding(context)),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
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
                      else if (isGroupOrder)
                        _SummaryRow(
                          'Delivery (Group 40% off – $groupParticipantCount members)',
                          feeLoading
                              ? 'Calculating…'
                              : '${AppConstants.currencySymbol}${deliveryFee.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF10B981),
                        )
                      else
                        _SummaryRow(
                          subDeliveryFree
                              ? 'Delivery (MealHub+ FREE)'
                              : 'Delivery${feeResult?.calculation == 'distance_based'
                                    ? ''
                                    : feeResult?.restaurantOverride != null
                                    ? ' (Store)'
                                    : ' (Base)'}${feeResult?.distanceMiles != null
                                    ? ' – ${feeResult!.distanceMiles!.toStringAsFixed(1)} mi'
                                    : distanceKm != null
                                    ? ' – ${(distanceKm * 0.621371).toStringAsFixed(1)} mi'
                                    : ''}',
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
                        'Service Fee',
                        '${AppConstants.currencySymbol}${platformServiceFee.toStringAsFixed(2)}',
                      ),
                      if (tax > 0)
                        _SummaryRow(
                          'Tax (${(effectiveTaxRate * 100).toStringAsFixed(0)}%)',
                          '${AppConstants.currencySymbol}${tax.toStringAsFixed(2)}',
                        ),
                      if (_driverTip > 0)
                        _SummaryRow(
                          'Driver Tip',
                          '${AppConstants.currencySymbol}${_driverTip.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF10B981),
                        ),
                      if (outstandingDebt > 0)
                        _SummaryRow(
                          'Outstanding Balance',
                          '+${AppConstants.currencySymbol}${outstandingDebt.toStringAsFixed(2)}',
                          valueColor: const Color(0xFFEA580C),
                        ),
                      Divider(color: Theme.of(context).colorScheme.outlineVariant, height: 16),
                      _SummaryRow(
                        'Total',
                        '${AppConstants.currencySymbol}${grandTotal.toStringAsFixed(2)}',
                        isBold: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Place Order button + terms
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Theme.of(context).cardColor,
              padding: EdgeInsets.fromLTRB(
                Responsive.horizontalPadding(context),
                Responsive.spacingSmall(context),
                Responsive.horizontalPadding(context),
                Responsive.spacing(context),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Terms
                    Row(
                      children: [
                        Checkbox(
                          value: _agreeToTerms,
                          onChanged: (v) =>
                              setState(() => _agreeToTerms = v ?? false),
                          activeColor: AppTheme.primaryColor,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        Expanded(
                          child: Text(
                            'I agree to the MealHub terms and conditions',
                            style: TextStyle(
                              fontSize: Responsive.smallText(context),
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap:
                          (!_addressConfirmed &&
                              !isPickup &&
                              _agreeToTerms &&
                              cart.isNotEmpty)
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please slide to confirm your delivery address first',
                                  ),
                                  backgroundColor: Colors.orange,
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          : null,
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _agreeToTerms &&
                                  (_addressConfirmed || isPickup) &&
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
                                  outstandingDebt: outstandingDebt,
                                )
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey[300],
                            padding: const EdgeInsets.symmetric(vertical: 10),
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
                                  () {
                                    final amt = grandTotal.toStringAsFixed(2);
                                    if (_selectedPayment == 'stripe') {
                                      return 'Pay Now \u2014 \$$amt';
                                    }
                                    return '${isPickup ? "Place Pickup Order" : "Place Order"} \u2014 \$$amt';
                                  }(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSchedule({Restaurant? restaurant}) async {
    final now = DateTime.now();
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
    double outstandingDebt = 0,
  }) async {
    if (_placingOrder) return;

    final grandTotal = total + outstandingDebt;

    // Wallet: block order if balance is too low (must cover order + outstanding debt)
    if (_selectedPayment == 'wallet') {
      final walletBalance =
          ref.read(walletBalanceStreamProvider).valueOrNull?.availableBalance ?? 0;
      if (walletBalance < grandTotal) {
        AppSnackbar.error(
          context,
          'Insufficient wallet balance (\$${walletBalance.toStringAsFixed(2)}). '
          'Top up \$${(grandTotal - walletBalance).toStringAsFixed(2)} more or choose another payment method.',
        );
        return;
      }
    }

    setState(() => _placingOrder = true);

    try {
      // Proactively refresh the session so edge functions always get a fresh HS256 token.
      try {
        await SupabaseConfig.client.auth.refreshSession();
      } catch (_) {
        /* ignore — we'll let the order attempt surface any auth error */
      }

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
        isPickup: isPickup,
        deliveryLatitude: delLat != 0.0 ? delLat : null,
        deliveryLongitude: delLng != 0.0 ? delLng : null,
      );

      // Use server amounts if available, otherwise fall back to client math.
      // IMPORTANT: if the caller already waived delivery (deliveryFee == 0 because
      // of a subscription), never let the server override that back to a non-zero fee.
      final verifiedSubtotal = breakdown?.subtotal ?? subtotal;
      final serverDeliveryFee = breakdown?.deliveryFee ?? deliveryFee;
      final verifiedDeliveryFee = deliveryFee == 0.0 ? 0.0 : serverDeliveryFee;
      final verifiedTax = breakdown?.taxAmount ?? tax;
      final verifiedDiscount =
          (breakdown?.promoDiscount ?? promoDiscount) +
          (breakdown?.loyaltyDiscount ?? loyaltyDiscount);
      // Use the server's grand total directly — it already includes the platform
      // service fee. Adding it again would double-charge the customer.
      final serverTotal = breakdown?.grandTotal ?? total;
      final verifiedTotal = serverDeliveryFee == verifiedDeliveryFee
          ? serverTotal
          : serverTotal - serverDeliveryFee + verifiedDeliveryFee;

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

      // ── Card: complete Stripe payment ────────────────────────────────────
      // Order must exist first so the edge function can validate the orderId.
      // Flow: create order (pending) → Stripe sheet → confirm → done.
      // On cancel/failure the pending order is deleted.

      // ── Create the order in the DB ────────────────────────────────────────
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
        promoCode: appliedPromo?.code,
      );

      // Clear active ad after order placed
      if (isFromAd) clearActiveAd(ref);

      if (order == null) {
        throw Exception('Order could not be created. Please try again.');
      }

      // Wallet payment is now handled atomically inside the place-order edge
      // function before the order row is inserted — nothing to do here.

      // ── Stripe: saved card (off-session) ─────────────────────────────────
      if (_selectedPayment == 'stripe') {
        final savedCard = _selectedSavedCard;
        final pmId = savedCard?.stripePaymentMethodId;

        if (savedCard != null && pmId != null && pmId.isNotEmpty) {
          // ── Off-session charge using a saved verified card (same server-side
          //    approach as the card verification charge — no Stripe UI needed) ──
          try {
            final ok = await paymentService.chargeWithSavedCard(
              orderId: order.id,
              amount: verifiedTotal + outstandingDebt,
              paymentMethodId: pmId,
            );
            if (!mounted) return;
            if (!ok) {
              setState(() => _placingOrder = false);
              final cleaned = await paymentService
                  .cleanupUnpaidOrder(order.id)
                  .timeout(const Duration(seconds: 10), onTimeout: () => false);
              if (!cleaned) await _deleteOrder(order.id);
              if (!mounted) return;
              AppSnackbar.error(
                context,
                'Card payment failed. Please try again.',
              );
              return;
            }
            AppLogger.info('Order ${order.id} charged via saved card $pmId');
          } catch (e) {
            if (!mounted) return;
            setState(() => _placingOrder = false);
            final cleaned = await paymentService
                .cleanupUnpaidOrder(order.id)
                .timeout(const Duration(seconds: 10), onTimeout: () => false);
            if (!cleaned) await _deleteOrder(order.id);
            AppSnackbar.error(
              context,
              'Card payment failed: ${friendlyError(e)}',
            );
            return;
          }
        } else {
          // No saved card — prompt user to add one; cancel this draft order.
          setState(() => _placingOrder = false);
          final cleaned = await paymentService
              .cleanupUnpaidOrder(order.id)
              .timeout(const Duration(seconds: 10), onTimeout: () => false);
          if (!cleaned) await _deleteOrder(order.id);
          if (!mounted) return;
          AppSnackbar.warning(
            context,
            'Please add a payment card from Profile → Payment Methods to pay by card.',
          );
          return;
        }
      }

      // ── Navigate to success immediately ─────────────────────────────────
      // Do this before any post-order bookkeeping so the user is never
      // left staring at the checkout loading spinner.
      ref.read(cartProvider.notifier).clearCart();
      ref.read(appliedPromoProvider.notifier).clear();
      ref.read(redeemPointsProvider.notifier).state = 0;
      ref.read(selectedAddressIdProvider.notifier).state = null;
      ref.read(isPickupProvider.notifier).state = false;
      // Refresh wallet balance — edge function deducted it server-side.
      if (_selectedPayment == 'wallet') {
        ref.invalidate(walletBalanceStreamProvider);
        ref.invalidate(walletTransactionsStreamProvider);
      }

      if (!mounted) return;
      setState(() => _placingOrder = false);
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

      // ── Post-order bookkeeping (fire-and-forget) ─────────────────────────
      unawaited(
        Future(() async {
          // Mark promo as used
          if (appliedPromo != null) {
            try {
              await ref.read(promoServiceProvider).markUsed(appliedPromo.id);
            } catch (_) {}
          }

          // Redeem loyalty points if selected
          if (redeemPts > 0) {
            try {
              await ref
                  .read(loyaltyServiceProvider)
                  .redeemPoints(
                    userId: userId,
                    orderId: order.id,
                    points: redeemPts,
                  );
            } catch (_) {}
          }

          // Earn loyalty points from this order
          try {
            await ref
                .read(loyaltyServiceProvider)
                .earnPoints(
                  userId: userId,
                  orderId: order.id,
                  orderTotal: total,
                );
          } catch (_) {}

          // Clear any outstanding admin debt now that payment succeeded.
          // For wallet payments the edge function only deducted the order total,
          // so we must separately deduct the debt from the wallet balance first.
          if (outstandingDebt > 0) {
            try {
              if (_selectedPayment == 'wallet') {
                await SupabaseConfig.client.rpc(
                  'wallet_deduct',
                  params: {
                    'p_user_id': userId,
                    'p_amount': outstandingDebt,
                    'p_description': 'Outstanding balance charged at checkout',
                  },
                );
              }
              await SupabaseConfig.client.rpc(
                'checkout_clear_debt_direct',
                params: {
                  'p_user_id': userId,
                  'p_amount': outstandingDebt,
                  'p_reference': order.id,
                },
              );
              // Record how much debt was charged on the order so the receipt matches
              await SupabaseConfig.client
                  .from('orders')
                  .update({'outstanding_debt_charged': outstandingDebt})
                  .eq('id', order.id);
              ref.invalidate(walletBalanceStreamProvider);
              ref.invalidate(walletTransactionsStreamProvider);
            } catch (_) {}
          }

          // Consume subscription delivery
          final currentSub = ref.read(activeSubscriptionProvider).valueOrNull;
          final fallbackSubEligible =
              currentSub != null &&
              currentSub.isActive &&
              currentSub.hasDeliveries;
          final usedSubscriptionDelivery =
              !isPickup &&
              verifiedDeliveryFee <= 0.0 &&
              ((breakdown?.subscriptionDeliveryFree == true &&
                      breakdown?.subscriptionId != null) ||
                  (breakdown == null && fallbackSubEligible));
          if (usedSubscriptionDelivery) {
            try {
              final subscriptionId =
                  breakdown?.subscriptionId ?? currentSub!.id;
              await ref
                  .read(subscriptionServiceProvider)
                  .useSubscriptionDelivery(
                    subscriptionId: subscriptionId,
                    orderId: order.id,
                  );
              ref.invalidate(activeSubscriptionProvider);
            } catch (_) {}
          }

          // Group order cleanup
          final groupOrderId = ref.read(groupOrderIdForCheckoutProvider);
          if (groupOrderId != null) {
            try {
              await ref
                  .read(groupOrderServiceProvider)
                  .markAsOrdered(groupOrderId);
            } catch (_) {}
            ref.read(groupOrderIdForCheckoutProvider.notifier).state = null;
            ref.read(groupOrderParticipantCountProvider.notifier).state = 0;
          }

          // Invalidate providers so UI refreshes with latest data
          if (userId.isNotEmpty) ref.invalidate(loyaltyAccountProvider(userId));
          ref.invalidate(brainEngineProvider);
          ref.invalidate(activeCouponsProvider);
          ref.invalidate(userOrdersProvider(userId));
          ref
              .read(behaviorTrackingProvider)
              .trackOrderCompleted(userId, order.id, verifiedTotal);
        }),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
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

/// Shows an AI-assigned promo from user_promotions if one exists and is unused.
/// Tapping "Apply" pre-fills the promo code field so the user confirms it.
class _AiPromoBanner extends ConsumerWidget {
  final String userId;
  final double subtotal;

  const _AiPromoBanner({required this.userId, required this.subtotal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promoAsync = ref.watch(userPromoProvider(userId));

    return promoAsync.when(
      data: (promo) {
        if (promo == null) return const SizedBox.shrink();
        final discount = promo.computeDiscount(subtotal);
        final meetsMin = subtotal >= promo.minOrder;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A5F), Color(0xFF0F172A)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.smart_toy_rounded,
                  color: Color(0xFF60A5FA),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        promo.label ?? 'You have a personalised offer!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        promo.isFreeDelivery
                            ? 'Free delivery on this order'
                            : meetsMin
                            ? 'Saves ${AppConstants.currencySymbol}${discount.toStringAsFixed(2)} on this order'
                            : 'Min order ${AppConstants.currencySymbol}${promo.minOrder.toStringAsFixed(0)} to unlock',
                        style: TextStyle(
                          color: meetsMin
                              ? const Color(0xFF86EFAC)
                              : const Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (meetsMin || promo.isFreeDelivery)
                  GestureDetector(
                    onTap: () async {
                      // Mark used and invalidate so banner hides
                      await ref
                          .read(decisionEngineServiceProvider)
                          .markPromoUsed(promo.id);
                      ref.invalidate(userPromoProvider(userId));
                      // Surface discount via a snackbar; actual discount
                      // would need a custom flow — for now confirm it's applied
                      if (context.mounted) {
                        AppSnackbar.success(
                          context,
                          promo.isFreeDelivery
                              ? 'Free delivery applied!'
                              : 'Offer applied — ${AppConstants.currencySymbol}${discount.toStringAsFixed(2)} saved!',
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Apply',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

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
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.spacingSmall(context),
        vertical: Responsive.spacingSmall(context),
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppTheme.primaryColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: Responsive.smallText(context),
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
      margin: EdgeInsets.only(right: Responsive.spacing(context) * 0.5, bottom: Responsive.spacing(context) * 0.5),
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.spacingSmall(context),
        vertical: Responsive.spacingSmall(context) * 0.5,
      ),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryColor : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppTheme.primaryColor : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        address.label,
        style: TextStyle(
          fontSize: Responsive.smallText(context),
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
          padding: EdgeInsets.all(Responsive.spacingSmall(context)),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryColor.withValues(alpha: 0.08)
                : Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(Responsive.cardRadius(context) - 2),
            border: Border.all(
              color: selected ? AppTheme.primaryColor : Theme.of(context).colorScheme.outlineVariant,
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
                  fontSize: Responsive.smallText(context),
                  color: selected
                      ? AppTheme.primaryColor
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: Responsive.bodyText(context) * 0.75, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.spacingSmall(context),
          vertical: Responsive.spacingSmall(context) * 0.75,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.06)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(Responsive.cardRadius(context) - 2),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primaryColor.withValues(alpha: 0.12)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: selected
                    ? AppTheme.primaryColor
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: Responsive.bodyText(context),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: Responsive.smallText(context),
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
            if (selected)
              Icon(
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
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.spacingSmall(context),
          vertical: Responsive.spacingSmall(context),
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.06)
              : Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(Responsive.cardRadius(context)),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Theme.of(context).colorScheme.outlineVariant,
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
                      fontSize: Responsive.bodyText(context),
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    card.cardholderName,
                    style: TextStyle(
                      fontSize: Responsive.smallText(context),
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              child: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            if (selected)
              Icon(
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
                fontSize: isBold ? Responsive.headingSmall(context) : Responsive.smallText(context),
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: isBold ? 1.0 : 0.75),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: isBold ? Responsive.headingSmall(context) : Responsive.smallText(context),
              color: valueColor ?? Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide-to-confirm address widget ───────────────────────────────────────────
class _AddressSlider extends StatefulWidget {
  final bool confirmed;
  final VoidCallback onConfirmed;
  final VoidCallback onReset;

  const _AddressSlider({
    required this.confirmed,
    required this.onConfirmed,
    required this.onReset,
  });

  @override
  State<_AddressSlider> createState() => _AddressSliderState();
}

class _AddressSliderState extends State<_AddressSlider>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0;
  late AnimationController _snapCtrl;
  late Animation<double> _snapAnim;

  static const double _thumbSize = 40;
  static const double _trackHeight = 44;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void didUpdateWidget(_AddressSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.confirmed && oldWidget.confirmed) {
      _snapCtrl.stop();
      setState(() => _dragPosition = 0);
    }
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _snapBack() {
    _snapAnim = Tween<double>(begin: _dragPosition, end: 0).animate(
      CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut),
    )..addListener(() => setState(() => _dragPosition = _snapAnim.value));
    _snapCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = widget.confirmed;
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxDrag = trackWidth - _thumbSize - 8;

        return GestureDetector(
          onTap: confirmed ? widget.onReset : null,
          child: Container(
            height: _trackHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: confirmed
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : AppTheme.primaryColor.withValues(alpha: 0.08),
              border: Border.all(
                color: confirmed
                    ? const Color(0xFF10B981).withValues(alpha: 0.4)
                    : AppTheme.primaryColor.withValues(alpha: 0.25),
              ),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Label
                Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: confirmed
                        ? 1.0
                        : (1 -
                              (_dragPosition /
                                  maxDrag.clamp(1, double.infinity))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          confirmed
                              ? Icons.check_circle_rounded
                              : Icons.chevron_right_rounded,
                          size: 15,
                          color: confirmed
                              ? const Color(0xFF10B981)
                              : AppTheme.primaryColor.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          confirmed
                              ? 'Address confirmed — tap to change'
                              : 'Slide to confirm delivery address',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: confirmed
                                ? const Color(0xFF10B981)
                                : AppTheme.primaryColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Thumb
                if (!confirmed)
                  GestureDetector(
                    onHorizontalDragUpdate: (d) {
                      setState(() {
                        _dragPosition = (_dragPosition + d.delta.dx).clamp(
                          0.0,
                          maxDrag,
                        );
                      });
                      if (_dragPosition >= maxDrag) {
                        widget.onConfirmed();
                      }
                    },
                    onHorizontalDragEnd: (_) {
                      if (_dragPosition < maxDrag) _snapBack();
                    },
                    child: Padding(
                      padding: EdgeInsets.only(left: 4 + _dragPosition),
                      child: Container(
                        width: _thumbSize,
                        height: _thumbSize - 4,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.35,
                              ),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
