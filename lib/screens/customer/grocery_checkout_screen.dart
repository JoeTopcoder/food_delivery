import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../config/app_constants.dart';
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
import '../../services/payment_service.dart';
import '../../config/supabase_config.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import 'order_success_screen.dart';

class GroceryCheckoutScreen extends ConsumerStatefulWidget {
  const GroceryCheckoutScreen({super.key});

  @override
  ConsumerState<GroceryCheckoutScreen> createState() =>
      _GroceryCheckoutScreenState();
}

class _GroceryCheckoutScreenState extends ConsumerState<GroceryCheckoutScreen> {
  final _promoCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _cvcCtrl = TextEditingController();
  String _selectedPayment = 'cash';
  SavedCard? _selectedSavedCard;
  bool _agreeToTerms = false;
  bool _applyingPromo = false;
  bool _placingOrder = false;
  String? _promoError;
  DateTime? _scheduledAt;
  double _driverTip = 0;
  final _customTipCtrl = TextEditingController();
  final List<double> _presetTips = AppConstants.presetTips;

  @override
  void dispose() {
    _promoCtrl.dispose();
    _notesCtrl.dispose();
    _cvcCtrl.dispose();
    _customTipCtrl.dispose();
    super.dispose();
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
      setState(() => _promoError = friendlyError(e));
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

    // Admin-configured delivery fee via Edge Function (per store)
    final delLat = selectedAddress?.latitude ?? currentUser?.latitude ?? 0.0;
    final delLng = selectedAddress?.longitude ?? currentUser?.longitude ?? 0.0;

    // Accumulate fee across all stores
    double activeFee = 0;
    for (final sid in storeIds) {
      final s = storeData[sid];
      if (isPickup) {
        activeFee += s?.serviceFee ?? AppConstants.pickupServiceFee;
      } else if (s != null) {
        final feeKey =
            '$sid|${delLat ?? ''}|${delLng ?? ''}|${s.latitude ?? ''}|${s.longitude ?? ''}|${s.deliveryFee ?? ''}';
        final feeAsync = ref.watch(deliveryFeeProvider(feeKey));
        activeFee +=
            feeAsync.valueOrNull?.deliveryFee ??
            AppConstants.defaultDeliveryFee;
      } else {
        activeFee += AppConstants.defaultDeliveryFee;
      }
    }
    final tax = subtotal * AppConstants.taxRate;
    final orderTotal =
        (subtotal - promoDiscount - loyaltyDiscount + activeFee + tax).clamp(
          activeFee,
          double.infinity,
        );
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
                          const Icon(
                            Icons.storefront_rounded,
                            color: AppTheme.primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              storeData[sid]!.name,
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
                        subtitle: 'Pay when your groceries arrive',
                        selected: _selectedPayment == 'cash',
                        onTap: () => setState(() => _selectedPayment = 'cash'),
                      ),
                      const SizedBox(height: 8),
                      Consumer(
                        builder: (context, ref, _) {
                          final walletAsync = ref.watch(walletNotifierProvider);
                          final balance =
                              walletAsync.valueOrNull?.totalAvailable ?? 0;
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
                        subtitle: 'Visa, Mastercard, KeyCard accepted',
                        selected: _selectedPayment == 'card',
                        onTap: () => setState(() => _selectedPayment = 'card'),
                      ),
                      if (_selectedPayment == 'card') ...[
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
                                children: verified
                                    .map(
                                      (card) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: _SavedCardTile(
                                          card: card,
                                          selected:
                                              _selectedSavedCard?.id == card.id,
                                          onTap: () => setState(() {
                                            _selectedSavedCard = card;
                                            _cvcCtrl.clear();
                                          }),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                        if (_selectedSavedCard != null) ...[
                          const SizedBox(height: 12),
                          _CvcInputCard(
                            card: _selectedSavedCard!,
                            controller: _cvcCtrl,
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
                    error: (_, __) => const SizedBox.shrink(),
                    data: (account) {
                      if (account == null || account.points == 0) {
                        return const SizedBox.shrink();
                      }
                      final maxRedeem = account.maxRedeemable(subtotal);
                      final maxPts =
                          (maxRedeem / AppConstants.loyaltyPointValue).floor();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
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

                // ── Driver Tip (delivery only) ────────────────────────
                if (!isPickup) ...[
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
                                    backgroundColor: Colors.grey.shade100,
                                    labelStyle: TextStyle(
                                      color: sel
                                          ? Colors.white
                                          : Colors.black87,
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
                      contentPadding: const EdgeInsets.all(12),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Order Summary ─────────────────────────────────────
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
                          'Delivery${storeIds.length > 1 ? ' (${storeIds.length} stores)' : ''}',
                          '${AppConstants.currencySymbol}${activeFee.toStringAsFixed(2)}',
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

                // ── Terms ─────────────────────────────────────────────
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
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Place Order Button ──────────────────────────────────────
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
                          '${isPickup ? "Place Pickup Order" : "Place Grocery Order"} — \$${total.toStringAsFixed(2)}',
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

    if (_selectedPayment == 'card') {
      // Stripe handles card input natively via Payment Sheet
    }

    if (_selectedPayment == 'wallet') {
      final walletBalance =
          ref.read(walletNotifierProvider).valueOrNull?.totalAvailable ?? 0;
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
      final paymentService = ref.read(paymentServiceProvider);
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
        if (!promoApplied && appliedPromo != null) promoApplied = true;
      }

      // ── Wallet payment (total across all orders) ────────────────────
      if (_selectedPayment == 'wallet') {
        try {
          // Pay the full total; link to first order
          await ref
              .read(walletNotifierProvider.notifier)
              .payWithWallet(runningTotal, orderIds.first);
        } catch (e) {
          for (final oid in orderIds) {
            await _deleteOrder(oid);
          }
          rethrow;
        }
      }

      // ── Card payment (total across all orders) ──────────────────────
      if (_selectedPayment == 'card') {
        StripePaymentSession stripeSession;
        try {
          final authUser = Supabase.instance.client.auth.currentUser;
          final email = authUser?.email ?? '';
          final name = authUser?.userMetadata?['name'] as String? ?? 'Customer';

          stripeSession = await paymentService.createStripeCheckout(
            orderId: orderIds.first,
            amount: runningTotal,
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
            for (final oid in orderIds) {
              await _deleteOrder(oid);
            }
            setState(() => _placingOrder = false);
            return;
          }

          // Confirm server-side
          await paymentService.confirmStripePayment(
            paymentIntentId: stripeSession.paymentIntentId,
            orderId: orderIds.first,
          );
        } catch (e) {
          for (final oid in orderIds) {
            await _deleteOrder(oid);
          }
          rethrow;
        }
      }

      // Mark promo used
      if (appliedPromo != null) {
        await ref.read(promoServiceProvider).markUsed(appliedPromo.id);
      }

      // Loyalty: redeem + earn (link to first order)
      if (redeemPts > 0) {
        await ref
            .read(loyaltyServiceProvider)
            .redeemPoints(
              userId: userId,
              orderId: orderIds.first,
              points: redeemPts,
            );
      }
      await ref
          .read(loyaltyServiceProvider)
          .earnPoints(
            userId: userId,
            orderId: orderIds.first,
            orderTotal: runningTotal,
          );

      // Track for AI (each order)
      for (final oid in orderIds) {
        ref
            .read(behaviorTrackingProvider)
            .trackOrderCompleted(userId, oid, runningTotal / orderIds.length);
      }

      // Clear grocery state
      ref.read(groceryCartProvider.notifier).clearCart();
      ref.read(appliedPromoProvider.notifier).clear();
      ref.read(redeemPointsProvider.notifier).state = 0;
      ref.read(selectedAddressIdProvider.notifier).state = null;
      ref.read(groceryIsPickupProvider.notifier).state = false;

      if (userId.isNotEmpty) {
        ref.invalidate(loyaltyAccountProvider(userId));
      }
      ref.invalidate(brainEngineProvider);
      // Ensure the new order shows in order history immediately
      ref.invalidate(userOrdersProvider(userId));

      if (!mounted) return;

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
    } catch (e) {
      if (!mounted) return;
      String message = e.toString();
      if (message.contains('Exception: ')) {
        message = message.replaceFirst(RegExp(r'^Exception:\s*'), '');
      }
      AppSnackbar.error(context, message);
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
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

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
    this.onTap,
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
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _PaymentTile({
    required this.icon,
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? AppTheme.primaryColor
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: selected
                          ? AppTheme.primaryColor
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.primaryColor,
                size: 20,
              )
            else
              Icon(
                Icons.radio_button_unchecked,
                color: Colors.grey.shade300,
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
  const _SavedCardTile({
    required this.card,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.credit_card_rounded,
              size: 20,
              color: selected
                  ? AppTheme.primaryColor
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${card.displayBrand} •••• ${card.lastFour}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: selected
                          ? AppTheme.primaryColor
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    card.cardholderName,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.primaryColor,
                size: 20,
              )
            else
              Icon(
                Icons.radio_button_unchecked,
                color: Colors.grey.shade300,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _CvcInputCard extends StatelessWidget {
  final SavedCard card;
  final TextEditingController controller;
  const _CvcInputCard({required this.card, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Expanded(
                child: Text(
                  'Paying with ${card.displayBrand} •••• ${card.lastFour}',
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
              controller: controller,
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
                  color: Colors.white.withValues(alpha: 0.3),
                  letterSpacing: 6,
                ),
                counterText: '',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.primaryColor),
                ),
              ),
            ),
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
                const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFF10B981),
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
              fontSize: isBold ? 15 : 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 15 : 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
