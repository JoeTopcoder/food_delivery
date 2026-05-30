// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../config/app_constants.dart';
import '../../config/supabase_config.dart';
import '../../core/utils/responsive.dart';
import '../../models/address_model.dart';
import '../../models/saved_card_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/address_provider.dart';
import '../../providers/feature_providers.dart';
import '../../providers/payment_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/driver/delivery_fee_service.dart';
import '../../providers/delivery_region_provider.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_logger.dart';
import '../../utils/app_theme.dart';
import '../../utils/safe_state_mixin.dart';
import 'order_success_screen.dart';

class MultiRestaurantCheckoutScreen extends ConsumerStatefulWidget {
  const MultiRestaurantCheckoutScreen({super.key});

  @override
  ConsumerState<MultiRestaurantCheckoutScreen> createState() =>
      _MultiRestaurantCheckoutScreenState();
}

class _MultiRestaurantCheckoutScreenState
    extends ConsumerState<MultiRestaurantCheckoutScreen>
    with SafeConsumerStateMixin<MultiRestaurantCheckoutScreen> {
  final _notesCtrl = TextEditingController();
  final _customTipCtrl = TextEditingController();
  String _selectedPayment = 'stripe';
  SavedCard? _selectedSavedCard;
  bool _agreeToTerms = false;
  bool _addressConfirmed = false;
  bool _contactlessDelivery = false;
  bool _placingOrder = false;
  double _driverTip = 0;
  DateTime? _scheduledAt;

  final List<double> _presetTips = AppConstants.presetTips;

  @override
  void dispose() {
    _notesCtrl.dispose();
    _customTipCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_addressConfirmed) {
      final selectedAddress = ref.read(selectedAddressProvider);
      final currentUser = ref.read(currentUserProvider);
      if (selectedAddress != null || currentUser?.address != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _addressConfirmed = true);
        });
      }
    }
  }

  Future<Map<String, String>> _freshAuthHeader() async {
    String? token;
    try {
      final res = await SupabaseConfig.client.auth.refreshSession();
      token = res.session?.accessToken;
    } catch (_) {}
    token ??= SupabaseConfig.client.auth.currentSession?.accessToken;
    return (token != null && token.isNotEmpty)
        ? {'Authorization': 'Bearer $token'}
        : {};
  }

  /// Calls create-multi-restaurant-order with JWT retry logic.
  /// Returns the master_order_id on success or throws.
  Future<String> _invokeCreateOrder(Map<String, dynamic> body) async {
    final authHeader = await _freshAuthHeader();
    late FunctionResponse response;
    try {
      response = await SupabaseConfig.client.functions
          .invoke('create-multi-restaurant-order', body: body, headers: authHeader);
    } on FunctionException catch (fe) {
      final raw = fe.details?.toString() ?? '';
      AppLogger.error('_invokeCreateOrder FunctionException: status=${fe.status}, details=$raw');
      String extracted = raw;
      if (fe.details is Map) extracted = (fe.details as Map)['error']?.toString() ?? raw;
      final isJwt = fe.status == 401 || fe.status == 403 ||
          raw.contains('LEGACY_JWT') || raw.contains('ES256') || raw.contains('JWT');
      if (isJwt) {
        AppLogger.info('JWT error — retrying...');
        final retryHeader = await _freshAuthHeader();
        try {
          response = await SupabaseConfig.client.functions
              .invoke('create-multi-restaurant-order', body: body, headers: retryHeader);
        } on FunctionException catch (fe2) {
          final raw2 = fe2.details?.toString() ?? fe2.toString();
          String extracted2 = raw2;
          if (fe2.details is Map) extracted2 = (fe2.details as Map)['error']?.toString() ?? raw2;
          throw Exception(extracted2);
        }
      } else {
        throw Exception(extracted);
      }
    }

    AppLogger.info('_invokeCreateOrder: status=${response.status}');
    final data = response.data is String
        ? jsonDecode(response.data as String) as Map<String, dynamic>
        : (response.data as Map<String, dynamic>? ?? {});

    if (data['error'] != null) throw Exception(data['error'].toString());

    final mid = data['master_order_id'] as String? ?? data['order_group_id'] as String?;
    if (mid == null) throw Exception('Order could not be created.');
    return mid;
  }

  Future<void> _placeOrder({
    required String userId,
    required double subtotal,
    required double deliveryFee,
    required double extraStopFee,
    required double total,
    required String deliveryAddress,
    required double deliveryLat,
    required double deliveryLng,
    String? customerEmail,
    String? customerName,
  }) async {
    if (_placingOrder) return;

    if (!_agreeToTerms) {
      AppSnackbar.error(context, 'Please agree to the terms and conditions.');
      return;
    }

    if (!_addressConfirmed) {
      AppSnackbar.error(context, 'Please confirm your delivery address first.');
      return;
    }

    if (_selectedPayment == 'wallet') {
      final balance =
          ref.read(walletBalanceStreamProvider).valueOrNull?.availableBalance ?? 0;
      if (balance < total) {
        AppSnackbar.error(
          context,
          'Insufficient wallet balance (${AppConstants.currencySymbol}${balance.toStringAsFixed(2)}). '
          'Top up ${AppConstants.currencySymbol}${(total - balance).toStringAsFixed(2)} more.',
        );
        return;
      }
    }

    setState(() => _placingOrder = true);

    // ── Delivery region check ──────────────────────────────────────────
    if (deliveryLat != 0.0 && deliveryLng != 0.0) {
      final regionService = ref.read(deliveryRegionServiceProvider);
      final insideRegion =
          await regionService.isInsideActiveRegion(deliveryLat, deliveryLng);
      if (!insideRegion) {
        setState(() => _placingOrder = false);
        AppSnackbar.error(
          context,
          'Your delivery address is outside our delivery regions. '
          'Please choose an address within a supported area.',
        );
        return;
      }
    }

    try {
      final cartNotifier = ref.read(cartProvider.notifier);
      final itemsByRestaurant = cartNotifier.itemsByRestaurant;

      final restaurantOrders = itemsByRestaurant.entries.map((entry) {
        return {
          'restaurant_id': entry.key,
          'items': entry.value
              .map((ci) => {
                    'menu_item_id': ci.menuItem.id,
                    'quantity': ci.quantity,
                    'side_ids': ci.selectedSides.map((s) => s.id).toList(),
                    'notes': ci.notes,
                  })
              .toList(),
        };
      }).toList();

      // ── Base order body (no payment fields yet) ─────────────────────────
      final baseBody = <String, dynamic>{
        'customer_id': userId,
        'restaurant_orders': restaurantOrders,
        'delivery_address': deliveryAddress,
        'delivery_latitude': deliveryLat,
        'delivery_longitude': deliveryLng,
        'payment_method': _selectedPayment,
        'client_delivery_fee': deliveryFee,
        'contactless_delivery': _contactlessDelivery,
        if (_driverTip > 0) 'driver_tip': _driverTip,
        if (_scheduledAt != null) 'scheduled_for': _scheduledAt!.toIso8601String(),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      };

      String? masterOrderId;

      // ── PAYMENT FIRST — order is only created after payment is confirmed ──

      if (_selectedPayment == 'wallet') {
        // Wallet: edge function deducts + creates in one call
        masterOrderId = await _invokeCreateOrder(baseBody);

      } else if (_selectedPayment == 'stripe') {
        final paymentService = ref.read(paymentServiceProvider);
        final savedCard = _selectedSavedCard;
        final pmId = savedCard?.stripePaymentMethodId;

        if (savedCard != null && pmId != null && pmId.isNotEmpty) {
          // ── Saved card: edge function charges card + creates order atomically ─
          masterOrderId = await _invokeCreateOrder({
            ...baseBody,
            'saved_card_payment_method_id': pmId,
          });

        } else {
          // ── Payment sheet: get PI → show sheet → pass confirmed PI to edge fn ─
          final session = await paymentService.createStripeCheckout(
            orderId: userId,  // temp ref — no order exists yet
            amount: total,
            customerEmail: customerEmail ?? '',
            customerName: customerName ?? '',
            type: 'multi_restaurant_order',
          );

          if (Stripe.publishableKey.isEmpty) {
            final key = AppConstants.stripePublishableKey;
            if (key.isNotEmpty) {
              Stripe.publishableKey = key;
              Stripe.merchantIdentifier = AppConstants.stripeMerchantId;
              await Stripe.instance.applySettings();
            }
          }

          await Stripe.instance.initPaymentSheet(
            paymentSheetParameters: SetupPaymentSheetParameters(
              paymentIntentClientSecret: session.clientSecret,
              customerId: session.customerId,
              customerEphemeralKeySecret: session.ephemeralKey,
              merchantDisplayName: AppConstants.appName,
              style: ThemeMode.system,
            ),
          );

          try {
            await Stripe.instance.presentPaymentSheet();
          } on StripeException catch (e) {
            if (e.error.code == FailureCode.Canceled) {
              setState(() => _placingOrder = false);
              return;   // user cancelled — no order created, no charge
            }
            rethrow;
          }

          // Payment confirmed — now create the order with the confirmed PI
          masterOrderId = await _invokeCreateOrder({
            ...baseBody,
            'payment_intent_id': session.paymentIntentId,
          });
        }
      }

      if (masterOrderId == null) throw Exception('Order could not be created.');

      // ── Success ───────────────────────────────────────────────────────────
      ref.read(cartProvider.notifier).clearCart();
      if (_selectedPayment == 'wallet') {
        ref.invalidate(walletBalanceStreamProvider);
        ref.invalidate(walletTransactionsStreamProvider);
      }
      ref.invalidate(userOrdersProvider(userId));
      ref.invalidate(customerMasterOrdersProvider(userId));

      if (!mounted) return;
      setState(() => _placingOrder = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderSuccessScreen(orderId: masterOrderId!, isMultiRestaurant: true),
        ),
      );
    } on FunctionException catch (fe) {
      final raw = fe.details?.toString() ?? fe.toString();
      AppLogger.error('multi-order outer FunctionException: status=${fe.status}, details=$raw');
      String msg = raw;
      if (fe.details is Map) msg = (fe.details as Map)['error']?.toString() ?? raw;
      AppSnackbar.error(context, msg.isNotEmpty ? msg : 'Something went wrong. Please try again.');
      setState(() => _placingOrder = false);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      AppLogger.error('multi-order catch: $msg');
      AppSnackbar.error(context, msg.isNotEmpty ? msg : 'Something went wrong. Please try again.');
      setState(() => _placingOrder = false);
    }
  }

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
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: earliest.hour, minute: earliest.minute),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final cartItems = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final subtotal = ref.watch(cartSubtotalProvider);
    final restaurantCount = cartItems.map((i) => i.menuItem.restaurantId).toSet().length;
    final extraStopFee = ref.watch(extraStopFeeProvider).valueOrNull ?? 2.0;
    final totalExtraStopFee = extraStopFee * (restaurantCount - 1).clamp(0, 99);

    final savedCardsAsync = currentUserId != null
        ? ref.watch(savedCardsProvider(currentUserId))
        : const AsyncValue<List<SavedCard>>.data([]);
    final savedCards = savedCardsAsync.valueOrNull ?? [];
    // Address
    final addressAsync = currentUserId != null
        ? ref.watch(userAddressesProvider(currentUserId))
        : null;
    final selectedAddress = ref.watch(selectedAddressProvider);
    final defaultAddrAsync = currentUserId != null
        ? ref.watch(defaultAddressProvider(currentUserId))
        : null;
    final deliveryAddress =
        selectedAddress?.address ??
        defaultAddrAsync?.valueOrNull?.address ??
        currentUser?.address ??
        'No address saved';
    final deliveryLat =
        selectedAddress?.latitude ??
        defaultAddrAsync?.valueOrNull?.latitude ??
        currentUser?.latitude ??
        0.0;
    final deliveryLng =
        selectedAddress?.longitude ??
        defaultAddrAsync?.valueOrNull?.longitude ??
        currentUser?.longitude ??
        0.0;

    // Per-restaurant delivery fee calculation
    final hasCoords = deliveryLat != 0.0 && deliveryLng != 0.0;
    final cartRestaurantIds =
        cartItems.map((i) => i.menuItem.restaurantId).toSet();
    double totalDeliveryFee = 0.0;
    bool deliveryFeeLoading = false;
    final perRestFees = <String, double>{};

    for (final restId in cartRestaurantIds) {
      final restInfo = ref.watch(restaurantByIdProvider(restId)).valueOrNull;
      final feeKey = hasCoords && restInfo != null
          ? '$restId|$deliveryLat|$deliveryLng|${restInfo.latitude ?? ''}|${restInfo.longitude ?? ''}|${restInfo.deliveryFee ?? ''}'
          : '';
      final feeAsync = feeKey.isNotEmpty
          ? ref.watch(deliveryFeeProvider(feeKey))
          : const AsyncValue<DeliveryFeeResult?>.data(null);
      if (feeAsync.isLoading) deliveryFeeLoading = true;
      final fee = feeAsync.valueOrNull?.deliveryFee ?? AppConstants.defaultDeliveryFee;
      perRestFees[restId] = fee;
      totalDeliveryFee += fee;
    }

    final platformFee = subtotal * AppConstants.platformServiceFeeRate;
    final total = subtotal + totalDeliveryFee + totalExtraStopFee + platformFee + _driverTip;

    if (cartItems.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: const Center(child: Text('Your cart is empty.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Checkout',
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

                // ── Delivery Address ───────────────────────────────────────
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
                                              .read(selectedAddressIdProvider.notifier)
                                              .state = sel ? null : a.id;
                                          setState(() => _addressConfirmed = false);
                                        },
                                        child: _AddressChip(address: a, isSelected: sel),
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
                            Icon(Icons.place_rounded, color: AppTheme.primaryColor, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                deliveryAddress,
                                style: TextStyle(
                                  fontSize: Responsive.smallText(context),
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pushNamed(context, '/address-book'),
                              child: const Text('Manage', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _AddressSlider(
                        confirmed: _addressConfirmed,
                        onConfirmed: () => setState(() => _addressConfirmed = true),
                        onReset: () => setState(() => _addressConfirmed = false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── Delivery Time ──────────────────────────────────────────
                _Section(
                  title: 'Delivery Time',
                  icon: Icons.schedule_rounded,
                  child: Row(
                    children: [
                      Expanded(
                        child: _TimeChip(
                          label: 'ASAP',
                          subtitle: '20–35 min',
                          selected: _scheduledAt == null,
                          onTap: () => setState(() => _scheduledAt = null),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TimeChip(
                          label: 'Schedule',
                          subtitle: _scheduledAt != null
                              ? DateFormat('MMM d, h:mm a').format(_scheduledAt!)
                              : 'Pick time',
                          selected: _scheduledAt != null,
                          onTap: _pickSchedule,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── Payment Method ─────────────────────────────────────────
                _Section(
                  title: 'Payment Method',
                  icon: Icons.payment_rounded,
                  child: Column(
                    children: [
                      Consumer(
                        builder: (context, ref, _) {
                          final walletAsync = ref.watch(walletBalanceStreamProvider);
                          final bal = walletAsync.valueOrNull?.availableBalance ?? 0;
                          return _PaymentTile(
                            icon: Icons.account_balance_wallet_rounded,
                            label: 'Wallet',
                            subtitle: bal > 0
                                ? 'Balance: ${AppConstants.currencySymbol}${bal.toStringAsFixed(2)}'
                                : 'No funds — top up in your profile',
                            selected: _selectedPayment == 'wallet',
                            onTap: () {
                              if (bal > 0) setState(() => _selectedPayment = 'wallet');
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
                        onTap: () => setState(() => _selectedPayment = 'stripe'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CardBrandChip('VISA', const Color(0xFF1A1F71)),
                            const SizedBox(width: 4),
                            _CardBrandChip('MC', const Color(0xFFEB001B)),
                          ],
                        ),
                      ),
                      if (_selectedPayment == 'stripe' && savedCards.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...savedCards.map((card) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _SavedCardTile(
                            card: card,
                            selected: _selectedSavedCard?.id == card.id,
                            onTap: () => setState(() => _selectedSavedCard = card),
                            onDelete: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Remove Card'),
                                  content: Text('Remove card ending in ${card.lastFour}?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Remove',
                                          style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && currentUserId != null) {
                                await ref.read(paymentServiceProvider).deleteSavedCard(card.id);
                                if (_selectedSavedCard?.id == card.id) {
                                  setState(() => _selectedSavedCard = null);
                                }
                                ref.invalidate(savedCardsProvider(currentUserId));
                              }
                            },
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── Contactless Delivery ───────────────────────────────────
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
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
                        onChanged: (v) => setState(() => _contactlessDelivery = v),
                        activeThumbColor: AppTheme.primaryColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── Tip Your Driver ────────────────────────────────────────
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
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: ChoiceChip(
                                label: const Text('No Tip',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                selected: _driverTip == 0,
                                selectedColor: AppTheme.primaryColor,
                                backgroundColor:
                                    Theme.of(context).colorScheme.surfaceContainerHighest,
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
                            final isSelected = _driverTip == amount;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: ChoiceChip(
                                  label: Text(
                                    '${AppConstants.currencySymbol}${amount.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  selected: isSelected,
                                  selectedColor: const Color(0xFF10B981),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.surfaceContainerHighest,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Theme.of(context).colorScheme.onSurface,
                                  ),
                                  onSelected: (_) => setState(() {
                                    _driverTip = isSelected ? 0 : amount;
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
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          hintText: 'Custom amount',
                          prefixText: AppConstants.currencySymbol,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.all(10),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          final parsed = double.tryParse(v);
                          setState(() {
                            _driverTip =
                                (parsed != null && parsed > 0) ? parsed : 0;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── Special Instructions ───────────────────────────────────
                _Section(
                  title: 'Special Instructions',
                  icon: Icons.notes_rounded,
                  child: TextField(
                    controller: _notesCtrl,
                    maxLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Allergies, ring bell, gate code…',
                      border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.all(10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Order Summary (multi-restaurant) ───────────────────────
                Container(
                  padding: EdgeInsets.all(Responsive.cardPadding(context)),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius:
                        BorderRadius.circular(Responsive.cardRadius(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Items grouped by restaurant
                      ...cartNotifier.itemsByRestaurant.entries.map((entry) {
                        final restId = entry.key;
                        final items = entry.value;
                        final restName = ref
                                .watch(restaurantByIdProvider(restId))
                                .valueOrNull
                                ?.name ??
                            'Restaurant';
                        final restSubtotal =
                            cartNotifier.subtotalForRestaurant(restId);
                        final restFee = perRestFees[restId] ??
                            AppConstants.defaultDeliveryFee;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Restaurant header
                              Row(
                                children: [
                                  Icon(Icons.store_rounded,
                                      size: 13,
                                      color: AppTheme.primaryColor),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      restName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: Responsive.smallText(context),
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Items
                              ...items.map((ci) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 2),
                                    child: Row(
                                      children: [
                                        Text(
                                          '${ci.quantity}×',
                                          style: TextStyle(
                                            fontSize:
                                                Responsive.smallText(context),
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primaryColor,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            ci.menuItem.name,
                                            style: TextStyle(
                                              fontSize:
                                                  Responsive.smallText(context),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${AppConstants.currencySymbol}${(ci.menuItem.discountedPrice * ci.quantity).toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize:
                                                Responsive.smallText(context),
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                              const SizedBox(height: 4),
                              // Per-restaurant subtotal + delivery
                              _SummaryRow(
                                'Subtotal',
                                '${AppConstants.currencySymbol}${restSubtotal.toStringAsFixed(2)}',
                              ),
                              _SummaryRow(
                                deliveryFeeLoading
                                    ? 'Delivery (calculating…)'
                                    : 'Delivery',
                                deliveryFeeLoading
                                    ? '…'
                                    : '${AppConstants.currencySymbol}${restFee.toStringAsFixed(2)}',
                              ),
                              Divider(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                  height: 12),
                            ],
                          ),
                        );
                      }),

                      // Totals
                      if (totalExtraStopFee > 0)
                        _SummaryRow(
                          'Multi-stop Fee (${restaurantCount - 1} stop${restaurantCount - 1 > 1 ? "s" : ""})',
                          '${AppConstants.currencySymbol}${totalExtraStopFee.toStringAsFixed(2)}',
                        ),
                      _SummaryRow(
                        'Service Fee',
                        '${AppConstants.currencySymbol}${platformFee.toStringAsFixed(2)}',
                      ),
                      if (_driverTip > 0)
                        _SummaryRow(
                          'Driver Tip',
                          '${AppConstants.currencySymbol}${_driverTip.toStringAsFixed(2)}',
                          valueColor: const Color(0xFF10B981),
                        ),
                      Divider(
                          color:
                              Theme.of(context).colorScheme.outlineVariant,
                          height: 16),
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

          // ── Sticky Place Order button ──────────────────────────────────
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _agreeToTerms &&
                                _addressConfirmed &&
                                !_placingOrder &&
                                cartItems.isNotEmpty &&
                                currentUserId != null
                            ? () => _placeOrder(
                                  userId: currentUserId,
                                  subtotal: subtotal,
                                  deliveryFee: totalDeliveryFee,
                                  extraStopFee: totalExtraStopFee,
                                  total: total,
                                  deliveryAddress: deliveryAddress,
                                  deliveryLat: deliveryLat,
                                  deliveryLng: deliveryLng,
                                  customerEmail: currentUser?.email,
                                  customerName: currentUser?.name,
                                )
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[300],
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
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
                                    ? 'Pay Now — ${AppConstants.currencySymbol}${total.toStringAsFixed(2)}'
                                    : 'Place Order — ${AppConstants.currencySymbol}${total.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
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
}

// ─── Shared widgets (mirrors checkout_screen.dart) ────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Section({required this.title, required this.icon, required this.child});

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
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant, width: 0.5),
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
      margin: EdgeInsets.only(
          right: Responsive.spacing(context) * 0.5,
          bottom: Responsive.spacing(context) * 0.5),
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.spacingSmall(context),
        vertical: Responsive.spacingSmall(context) * 0.5,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primaryColor
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? AppTheme.primaryColor
              : Theme.of(context).colorScheme.outlineVariant,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(Responsive.spacingSmall(context)),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius:
              BorderRadius.circular(Responsive.cardRadius(context) - 2),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : Theme.of(context).colorScheme.outlineVariant,
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
              style: TextStyle(
                fontSize: Responsive.bodyText(context) * 0.75,
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
          borderRadius:
              BorderRadius.circular(Responsive.cardRadius(context) - 2),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : Theme.of(context).colorScheme.outlineVariant,
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
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
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
              Icon(Icons.check_circle_rounded,
                  color: AppTheme.primaryColor, size: 20),
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
            color: selected
                ? AppTheme.primaryColor
                : Theme.of(context).colorScheme.outlineVariant,
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
                border:
                    Border.all(color: brandColor.withValues(alpha: 0.2), width: 0.5),
              ),
              alignment: Alignment.center,
              child: Text(
                card.displayBrand,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: brandColor,
                    letterSpacing: 0.5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.maskedNumber,
                      style: TextStyle(
                          fontSize: Responsive.bodyText(context),
                          fontWeight: FontWeight.w600)),
                  Text(card.cardholderName,
                      style: TextStyle(
                          fontSize: Responsive.smallText(context),
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (card.isDefault)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color:
                      const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Default',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981))),
              ),
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.delete_outline_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            if (selected)
              Icon(Icons.check_circle_rounded,
                  color: AppTheme.primaryColor, size: 18),
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
            letterSpacing: 0.5),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;
  const _SummaryRow(this.label, this.value,
      {this.isBold = false, this.valueColor});

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
                fontSize: isBold
                    ? Responsive.headingSmall(context)
                    : Responsive.smallText(context),
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: isBold ? 1.0 : 0.75),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: isBold
                  ? Responsive.headingSmall(context)
                  : Responsive.smallText(context),
              color: valueColor ?? Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

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
                        _dragPosition =
                            (_dragPosition + d.delta.dx).clamp(0.0, maxDrag);
                      });
                      if (_dragPosition >= maxDrag) widget.onConfirmed();
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
                              color: AppTheme.primaryColor
                                  .withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.chevron_right_rounded,
                            color: Colors.white, size: 22),
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
