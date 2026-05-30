// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../config/app_constants.dart';
import '../../core/utils/responsive.dart';
import '../../models/restaurant_model.dart';
import '../../models/user_model.dart';
import '../../models/address_model.dart';
import '../../models/saved_card_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/promo_provider.dart';
import '../../providers/loyalty_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/payment_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/grocery_provider.dart';
import '../../providers/feature_providers.dart';
import '../../providers/delivery_region_provider.dart';
import '../../providers/recommendation_provider.dart';
import '../../providers/decision_engine_provider.dart';
import '../../config/supabase_config.dart';
import '../../utils/app_theme.dart';
import 'dart:async' show unawaited;
import '../../utils/friendly_error.dart';
import '../../utils/safe_state_mixin.dart';
import '../../utils/app_feedback_widgets.dart';
import 'order_success_screen.dart';
import 'payment_screen.dart';

class GroceryCheckoutScreen extends ConsumerStatefulWidget {
  const GroceryCheckoutScreen({super.key});

  @override
  ConsumerState<GroceryCheckoutScreen> createState() =>
      _GroceryCheckoutScreenState();
}

class _GroceryCheckoutScreenState extends ConsumerState<GroceryCheckoutScreen>
    with SafeConsumerStateMixin<GroceryCheckoutScreen> {
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
    if (!_addressConfirmed) {
      final isPickup = ref.read(groceryIsPickupProvider);
      final selectedAddress = ref.read(selectedAddressProvider);
      if (isPickup || selectedAddress != null || currentUser?.address != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _addressConfirmed = true);
        });
      }
    }
  }

  void _hydratePaymentFields(User? currentUser) {
    if (_paymentFieldsHydrated || currentUser == null) return;
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
      if (!mounted) return;
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
    final cart = ref.watch(groceryCartProvider);
    final subtotal = ref.watch(groceryCartSubtotalProvider);
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final isPickup = ref.watch(groceryIsPickupProvider);

    final storeIds = cart.map((c) => c.menuItem.restaurantId).toSet().toList();
    final storeData = <String, Restaurant?>{};
    for (final sid in storeIds) {
      final sAsync = ref.watch(restaurantByIdProvider(sid));
      storeData[sid] = sAsync.valueOrNull;
    }

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

    final delLat = selectedAddress?.latitude ?? currentUser?.latitude;
    final delLng = selectedAddress?.longitude ?? currentUser?.longitude;
    final hasDeliveryCoords = delLat != null && delLng != null;

    double activeFee = 0;
    final feeTypes = <String>{};
    bool anyFeeLoading = false;
    for (final sid in storeIds) {
      final s = storeData[sid];
      if (isPickup) {
        activeFee += s?.serviceFee ?? AppConstants.pickupServiceFee;
      } else if (s != null && hasDeliveryCoords) {
        final feeKey =
            '$sid|$delLat|$delLng|${s.latitude ?? ''}|${s.longitude ?? ''}|${s.deliveryFee ?? ''}';
        final feeAsync = ref.watch(deliveryFeeProvider(feeKey));
        if (feeAsync.isLoading) anyFeeLoading = true;
        final fr = feeAsync.valueOrNull;
        activeFee += fr?.deliveryFee ?? AppConstants.defaultDeliveryFee;
        if (fr != null) {
          if (fr.restaurantOverride != null) {
            feeTypes.add('Store');
          } else if (fr.calculation == 'distance_based') {
            feeTypes.add('KM');
          } else {
            feeTypes.add('Base');
          }
        }
      } else {
        activeFee += AppConstants.defaultDeliveryFee;
      }
    }
    final feeTypeLabel = feeTypes.isNotEmpty ? ' (${feeTypes.join(', ')})' : '';

    final activeSub = ref.watch(activeSubscriptionProvider).valueOrNull;
    final subEligible =
        activeSub != null &&
        activeSub.isActive &&
        activeSub.hasDeliveries &&
        !isPickup;
    final subDeliveryFree = subEligible;
    if (subDeliveryFree) activeFee = 0.0;

    final platformServiceFee = subtotal * AppConstants.platformServiceFeeRate;

    // Zone-based tax: look up by delivery coords (no tax for pickup).
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Grocery Checkout',
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
              bottom: 180,
              left: Responsive.horizontalPadding(context),
              right: Responsive.horizontalPadding(context),
              top: 8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Store info ────────────────────────────────────────
                for (final sid in storeIds)
                  if (storeData[sid] != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.storefront_rounded,
                            color: AppTheme.primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              storeData[sid]!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Text(
                            '${cart.where((c) => c.menuItem.restaurantId == sid).fold(0, (s, c) => s + c.quantity)} items',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                if (storeIds.isNotEmpty) const SizedBox(height: 4),

                // ── Delivery / Pickup ─────────────────────────────────
                if (isPickup)
                  _Section(
                    title: 'Pickup Location',
                    icon: Icons.store_rounded,
                    child: Column(
                      children: [
                        for (final sid in storeIds)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF10B981,
                              ).withValues(alpha: 0.08),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        storeData[sid]?.name ?? 'Store',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                      if (storeData[sid]?.address != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          storeData[sid]!.address!,
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
                      ],
                    ),
                  )
                else
                  _Section(
                    title: 'Delivery Address',
                    icon: Icons.location_on_rounded,
                    child: Column(
                      children: [
                        if (addressAsync != null)
                          addressAsync.when(
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
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
                                                .state = sel ? null : a.id;
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
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(10),
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

                // ── Schedule ──────────────────────────────────────────
                _Section(
                  title: isPickup ? 'Pickup Time' : 'Delivery Time',
                  icon: Icons.schedule_rounded,
                  child: Row(
                    children: [
                      Expanded(
                        child: _TimeChip(
                          label: 'ASAP',
                          subtitle: '25-40 min',
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
                          onTap: () => _pickSchedule(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── Payment ───────────────────────────────────────────
                _Section(
                  title: 'Payment Method',
                  icon: Icons.payment_rounded,
                  child: Column(
                    children: [
                      Consumer(
                        builder: (context, ref, _) {
                          final walletAsync = ref.watch(walletBalanceStreamProvider);
                          final balance =
                              walletAsync.valueOrNull?.availableBalance ?? 0;
                          return _PaymentTile(
                            icon: Icons.account_balance_wallet_rounded,
                            label: 'Wallet',
                            subtitle: balance > 0
                                ? 'Balance: \$${balance.toStringAsFixed(2)}'
                                : 'No funds — top up in your profile',
                            selected: _selectedPayment == 'wallet',
                            onTap: () {
                              if (balance > 0) {
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
                        if (savedCardsAsync != null)
                          savedCardsAsync.when(
                            loading: () => const AppLoadingIndicator(),
                            error: (_, __) => const SizedBox.shrink(),
                            data: (savedCards) {
                              final verified = savedCards
                                  .where((c) => c.isVerified)
                                  .toList();
                              if (verified.isEmpty) {
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
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
                                          fontSize: 12,
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
                                  ...verified.map(
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
                                          final confirm =
                                              await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text(
                                                    'Remove Card',
                                                  ),
                                                  content: Text(
                                                    'Remove card ending in ${card.lastFour}?',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            ctx,
                                                            false,
                                                          ),
                                                      child: const Text(
                                                        'Cancel',
                                                      ),
                                                    ),
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            ctx,
                                                            true,
                                                          ),
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
                                                () =>
                                                    _selectedSavedCard = null,
                                              );
                                            }
                                            ref.invalidate(
                                              savedCardsProvider(currentUserId!),
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
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── AI-Assigned Promo Banner ───────────────────────────
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
                const SizedBox(height: 8),

                // ── Loyalty Points ────────────────────────────────────
                if (loyaltyAsync != null)
                  loyaltyAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (account) {
                      if (account == null || account.points == 0) {
                        return const SizedBox.shrink();
                      }
                      final maxRedeem = account.maxRedeemable(subtotal);
                      final maxPts =
                          (maxRedeem / AppConstants.loyaltyPointValue).floor();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _Section(
                          title: 'Loyalty Points',
                          icon: Icons.stars_rounded,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'You have ${account.points} pts (= \$${account.redemptionValue.toStringAsFixed(2)})',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const Spacer(),
                                  Switch(
                                    value: redeemPoints > 0,
                                    onChanged: (v) {
                                      ref
                                          .read(redeemPointsProvider.notifier)
                                          .state = v ? maxPts : 0;
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
                                    'Redeeming $redeemPoints pts = \$${loyaltyDiscount.toStringAsFixed(2)} off',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6366F1),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
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

                // ── Driver Tip (delivery only) ────────────────────────
                if (!isPickup) ...[
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
                                  onSelected: (_) => setState(() {
                                    _driverTip = 0;
                                    _customTipCtrl.clear();
                                  }),
                                ),
                              ),
                            ),
                            ..._presetTips.map((amount) {
                              final sel = _driverTip == amount;
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
                                    selected: sel,
                                    selectedColor: const Color(0xFF10B981),
                                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    labelStyle: TextStyle(
                                      color: sel
                                          ? Colors.white
                                          : Theme.of(context).colorScheme.onSurface,
                                    ),
                                    onSelected: (_) => setState(() {
                                      _driverTip = sel ? 0 : amount;
                                      _customTipCtrl.clear();
                                    }),
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
                ],

                // ── Special Instructions ──────────────────────────────
                _Section(
                  title: 'Special Instructions',
                  icon: Icons.notes_rounded,
                  child: TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText:
                          'Leave at door, ring bell, substitution preferences…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.all(10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Order Summary ─────────────────────────────────────
                Container(
                  padding: EdgeInsets.all(Responsive.cardPadding(context)),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(
                        'Subtotal',
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
                          'Service Fee${storeIds.length > 1 ? ' (${storeIds.length} stores)' : ''}',
                          '${AppConstants.currencySymbol}${activeFee.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF10B981),
                        )
                      else
                        _SummaryRow(
                          subDeliveryFree
                              ? 'Delivery (MealHub+ FREE)'
                              : 'Delivery$feeTypeLabel${storeIds.length > 1 ? ' – ${storeIds.length} stores' : ''}',
                          anyFeeLoading
                              ? 'Calculating…'
                              : subDeliveryFree
                              ? '\$0.00'
                              : '${AppConstants.currencySymbol}${activeFee.toStringAsFixed(2)}',
                          valueColor: subDeliveryFree
                              ? const Color(0xFF6C63FF)
                              : null,
                        ),
                      _SummaryRow(
                        'Service Fee (5%)',
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
                      Divider(color: Theme.of(context).colorScheme.outlineVariant, height: 16),
                      _SummaryRow(
                        'Total',
                        '${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
                        isBold: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Place Order Button + Terms ────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Theme.of(context).cardColor,
              padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context), 8, Responsive.horizontalPadding(context), 16),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                              fontSize: 12,
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
                              ? () => _placeGroceryOrder(
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
                                  _selectedPayment == 'stripe'
                                      ? 'Pay Now — \$${total.toStringAsFixed(2)}'
                                      : '${isPickup ? "Place Pickup Order" : "Place Grocery Order"} — \$${total.toStringAsFixed(2)}',
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

  // ── Schedule picker ─────────────────────────────────────────────────────

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final earliest = now.add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: earliest,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 7)),
    );
    if (date == null || !mounted) return;

    final initialTime =
        (date.year == earliest.year &&
            date.month == earliest.month &&
            date.day == earliest.day)
        ? TimeOfDay(hour: earliest.hour, minute: earliest.minute)
        : TimeOfDay.fromDateTime(earliest);

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
    if (chosen.isBefore(earliest)) {
      chosen = earliest;
      if (mounted) {
        AppSnackbar.info(
          context,
          'Earliest time is ${DateFormat('MMM d, h:mm a').format(earliest)}. Adjusted.',
        );
      }
    }
    setState(() => _scheduledAt = chosen);
  }

  // ── Place grocery order (one per store) ──────────────────────────────────

  Future<void> _placeGroceryOrder({
    required String userId,
    required double subtotal,
    required double deliveryFee,
    required double tax,
    required double total,
    required String deliveryAddress,
    required User? currentUser,
    required double promoDiscount,
    required double loyaltyDiscount,
    required double driverTip,
    required bool isPickup,
  }) async {
    if (_placingOrder) return;

    if (_selectedPayment == 'wallet') {
      final walletBalance =
          ref.read(walletBalanceStreamProvider).valueOrNull?.availableBalance ?? 0;
      if (walletBalance < total) {
        AppSnackbar.error(
          context,
          'Insufficient wallet balance (\$${walletBalance.toStringAsFixed(2)}). Top up or choose another payment method.',
        );
        return;
      }
    }

    // Delivery region check
    final selectedAddress = ref.read(selectedAddressProvider);
    final delLat = selectedAddress?.latitude ?? currentUser?.latitude;
    final delLng = selectedAddress?.longitude ?? currentUser?.longitude;

    if (!isPickup && delLat != null && delLng != null) {
      final regionService = ref.read(deliveryRegionServiceProvider);
      final inside = await regionService.isInsideActiveRegion(delLat, delLng);
      if (!inside) {
        if (mounted) {
          AppSnackbar.error(
            context,
            'Your delivery address is outside our delivery regions.',
          );
        }
        return;
      }
    }

    setState(() => _placingOrder = true);

    try {
      final groceryService = ref.read(groceryServiceProvider);
      final cart = ref.read(groceryCartProvider);
      final appliedPromo = ref.read(appliedPromoProvider);
      final redeemPts = ref.read(redeemPointsProvider);

      // Group items by store
      final Map<String, List<CartItem>> grouped = {};
      for (final item in cart) {
        grouped.putIfAbsent(item.menuItem.restaurantId, () => []).add(item);
      }

      final orderIds = <String>[];
      String? lastDeliveryOtp;
      String? lastPickupCode;
      String? firstReceiptNumber;
      double runningTotal = 0;
      bool promoApplied = false;
      bool subscriptionUsedOnAnyOrder = false;

      // Place one order per store
      for (final entry in grouped.entries) {
        final storeId = entry.key;
        final storeItems = entry.value;

        final items = storeItems
            .map(
              (c) => <String, dynamic>{
                'menu_item_id': c.menuItem.id,
                'quantity': c.quantity,
              },
            )
            .toList();

        // Promo on first order only, tip split proportionally
        final storeSubtotal = storeItems.fold(
          0.0,
          (sum, c) => sum + c.subtotal,
        );
        final tipShare = subtotal > 0
            ? driverTip * (storeSubtotal / subtotal)
            : driverTip / grouped.length;

        final result = await groceryService.placeGroceryOrder(
          storeId: storeId,
          userId: userId,
          items: items,
          isPickup: isPickup,
          paymentMethod: _selectedPayment,
          deliveryAddress: isPickup ? null : deliveryAddress,
          deliveryLatitude: isPickup ? null : delLat,
          deliveryLongitude: isPickup ? null : delLng,
          driverTip: double.parse(tipShare.toStringAsFixed(2)),
          specialInstructions: _notesCtrl.text.trim().isNotEmpty
              ? _notesCtrl.text.trim()
              : null,
          promoCode: !promoApplied ? appliedPromo?.code : null,
        );

        final orderId =
            result['order_id'] as String? ??
            (result['order'] is Map
                ? (result['order'] as Map)['id']?.toString() ?? ''
                : '');
        if (orderId.isEmpty) {
          throw Exception('Order could not be created for one of your stores.');
        }

        orderIds.add(orderId);
        if (firstReceiptNumber == null) {
          firstReceiptNumber =
              result['receipt_number'] as String? ??
              (result['order'] is Map
                  ? (result['order'] as Map)['receipt_number']?.toString()
                  : null);
        }
        lastDeliveryOtp =
            result['delivery_otp'] as String? ??
            (result['order'] is Map
                ? (result['order'] as Map)['delivery_otp']?.toString()
                : null);
        lastPickupCode =
            result['pickup_code'] as String? ??
            (result['order'] is Map
                ? (result['order'] as Map)['pickup_code']?.toString()
                : null);
        final serverTotal =
            (result['total'] as num?)?.toDouble() ??
            (result['order'] is Map
                ? ((result['order'] as Map)['total'] as num?)?.toDouble()
                : null) ??
            0;
        runningTotal += serverTotal;
        final orderMap = result['order'] is Map
            ? (result['order'] as Map)
            : null;
        if ((result['subscription_delivery_free'] == true) ||
            (orderMap != null &&
                orderMap['subscription_delivery_free'] == true)) {
          subscriptionUsedOnAnyOrder = true;
        }
        if (!promoApplied && appliedPromo != null) promoApplied = true;
      }

      // Wallet payment is now handled atomically inside the grocery-order edge
      // function before the order row is inserted — nothing to do here.

      // ── Stripe payment (total across all orders) ──────────────────────
      if (_selectedPayment == 'stripe') {
        final paymentService = ref.read(paymentServiceProvider);
        final savedCard = _selectedSavedCard;
        final pmId = savedCard?.stripePaymentMethodId;

        if (savedCard != null && pmId != null && pmId.isNotEmpty) {
          // Off-session charge via saved card — no intermediate UI.
          try {
            final ok = await paymentService.chargeWithSavedCard(
              orderId: orderIds.first,
              amount: runningTotal,
              paymentMethodId: pmId,
            );
            if (!mounted) return;
            if (!ok) {
              for (final oid in orderIds) {
                await _deleteOrder(oid);
              }
              setState(() => _placingOrder = false);
              AppSnackbar.error(
                context,
                'Card payment failed. Please try again.',
              );
              return;
            }
          } catch (e) {
            for (final oid in orderIds) {
              await _deleteOrder(oid);
            }
            rethrow;
          }
        } else {
          // No saved card — open PaymentScreen for new card entry.
          try {
            final authUser = Supabase.instance.client.auth.currentUser;
            final email = authUser?.email ?? '';
            final name =
                authUser?.userMetadata?['name'] as String? ?? 'Customer';

            final result = await Navigator.push<Map<String, dynamic>>(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentScreen(
                  orderId: orderIds.first,
                  amount: runningTotal,
                  currency: AppConstants.currencyCode,
                  customerEmail: email,
                  customerName: name,
                ),
              ),
            );

            if (!mounted) return;

            if (result == null || result['status'] != 'paid') {
              if (await _isOrderPaid(orderIds.first)) {
                // Webhook pre-confirmed — fall through to success.
              } else {
                for (final oid in orderIds) {
                  await _deleteOrder(oid);
                }
                setState(() => _placingOrder = false);
                if (mounted) {
                  AppSnackbar.warning(
                    context,
                    'Payment was cancelled. Your order was not placed.',
                  );
                }
                return;
              }
            } else {
              final activated = await _waitForOrderActivation(orderIds.first);
              if (!activated) {
                // Webhook delayed — proceed; it will complete in the background.
              }
            }
          } catch (e) {
            for (final oid in orderIds) {
              await _deleteOrder(oid);
            }
            rethrow;
          }
        }
      }

      // Navigate to success immediately — do this before any post-order
      // bookkeeping so the user is never left staring at a loading spinner.
      ref.read(groceryCartProvider.notifier).clearCart();
      ref.read(appliedPromoProvider.notifier).clear();
      ref.read(redeemPointsProvider.notifier).state = 0;
      ref.read(selectedAddressIdProvider.notifier).state = null;
      ref.read(groceryIsPickupProvider.notifier).state = false;
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
            orderId: orderIds.first,
            isPickup: isPickup,
            deliveryOtp: isPickup ? lastPickupCode : lastDeliveryOtp,
            receiptNumber: firstReceiptNumber,
          ),
        ),
      );

      // Post-order bookkeeping (fire-and-forget — errors must never surface
      // to the user after a successful order).
      unawaited(
        Future(() async {
          if (appliedPromo != null) {
            try {
              await ref.read(promoServiceProvider).markUsed(appliedPromo.id);
            } catch (_) {}
          }
          if (redeemPts > 0) {
            try {
              await ref.read(loyaltyServiceProvider).redeemPoints(
                userId: userId,
                orderId: orderIds.first,
                points: redeemPts,
              );
            } catch (_) {}
          }
          try {
            await ref.read(loyaltyServiceProvider).earnPoints(
              userId: userId,
              orderId: orderIds.first,
              orderTotal: runningTotal,
            );
          } catch (_) {}
          if (subscriptionUsedOnAnyOrder) {
            ref.invalidate(activeSubscriptionProvider);
          }
          for (final oid in orderIds) {
            ref.read(behaviorTrackingProvider).trackOrderCompleted(
              userId,
              oid,
              runningTotal / orderIds.length,
            );
          }
          if (userId.isNotEmpty) ref.invalidate(loyaltyAccountProvider(userId));
          ref.invalidate(brainEngineProvider);
          ref.invalidate(activeCouponsProvider);
          ref.invalidate(userOrdersProvider(userId));
        }),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }

  Future<void> _deleteOrder(String orderId) async {
    try {
      final client = SupabaseConfig.client;
      await client.from('order_items').delete().eq('order_id', orderId);
      await client.from('payments').delete().eq('order_id', orderId);
      await client.from('orders').delete().eq('id', orderId);
    } catch (_) {}
  }

  Future<bool> _isOrderPaid(String orderId) async {
    try {
      final row = await SupabaseConfig.client
          .from('orders')
          .select('payment_status')
          .eq('id', orderId)
          .maybeSingle();
      return row?['payment_status'] == 'completed';
    } catch (_) {
      return false;
    }
  }

  Future<bool> _waitForOrderActivation(
    String orderId, {
    int attempts = 15,
    Duration interval = const Duration(seconds: 2),
  }) async {
    for (var i = 0; i < attempts; i++) {
      try {
        final row = await SupabaseConfig.client
            .from('orders')
            .select('status, payment_status')
            .eq('id', orderId)
            .maybeSingle();
        if (row != null &&
            row['payment_status'] == 'completed' &&
            row['status'] != 'draft') {
          return true;
        }
      } catch (_) {}
      if (i < attempts - 1) await Future.delayed(interval);
    }
    return false;
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

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
                      await ref
                          .read(decisionEngineServiceProvider)
                          .markPromoUsed(promo.id);
                      ref.invalidate(userPromoProvider(userId));
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
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
                  fontSize: 13,
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
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                : Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
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
                  fontSize: 13,
                  color: selected
                      ? AppTheme.primaryColor
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.06)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
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
                      fontSize: 14,
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
                        fontSize: 11,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.06)
              : Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
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
                    style: TextStyle(
                      fontSize: 11,
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
                fontSize: isBold ? 15 : 13,
                color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: isBold ? 1.0 : 0.75,
                ),
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
