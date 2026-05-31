import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/index.dart';
import '../../providers/laundry_providers.dart';
import '../../../../models/address_model.dart';
import '../../../../providers/address_provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/wallet_provider.dart';
import '../../../../utils/app_theme.dart';
import '../../../../utils/app_feedback_widgets.dart';
import '../../../../utils/friendly_error.dart';
import '../../../../config/app_constants.dart';
import '../../../../utils/app_logger.dart';

const _kNavy = Color(0xFF0B3D6B);
const _kBlue = Color(0xFF1565C0);

class LaundryBookingScreen extends ConsumerStatefulWidget {
  final LaundryProvider provider;
  const LaundryBookingScreen({super.key, required this.provider});

  @override
  ConsumerState<LaundryBookingScreen> createState() => _LaundryBookingScreenState();
}

class _LaundryBookingScreenState extends ConsumerState<LaundryBookingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  // Step 1 — Services
  final Set<String> _selectedServiceIds = {};

  // Step 2 — Address
  final _pickupAddrCtrl = TextEditingController();
  final _returnAddrCtrl = TextEditingController();
  bool _sameAddress = true;
  UserAddress? _selectedPickupAddress;

  // Step 3 — Schedule
  DateTime? _pickupDate;
  String? _pickupSlot;

  // Step 4 — Details
  final _weightCtrl = TextEditingController();
  final _bagsCtrl   = TextEditingController(text: '1');
  final _notesCtrl  = TextEditingController();

  bool _isSubmitting = false;
  String? _error;

  static const _timeSlots = [
    '07:00 – 09:00', '09:00 – 11:00', '11:00 – 13:00',
    '13:00 – 15:00', '15:00 – 17:00', '17:00 – 19:00',
  ];

  @override
  void initState() {
    super.initState();
    // Load the customer's default saved address on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) return;
      final defaultAddr = await ref.read(defaultAddressProvider(userId).future);
      if (defaultAddr != null && mounted) {
        setState(() {
          _selectedPickupAddress = defaultAddr;
          _pickupAddrCtrl.text = defaultAddr.address;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _pickupAddrCtrl.dispose();
    _returnAddrCtrl.dispose();
    _weightCtrl.dispose();
    _bagsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Validation ──────────────────────────────────────────────────────────────

  String? _validateCurrentPage() {
    switch (_page) {
      case 0: return _selectedServiceIds.isEmpty ? 'Select at least one service' : null;
      case 1: return _pickupAddrCtrl.text.trim().isEmpty ? 'Enter your pickup address' : null;
      case 2:
        if (_pickupDate == null) return 'Select a pickup date';
        if (_pickupSlot == null) return 'Select a time slot';
        return null;
      case 3: return null;
    }
    return null;
  }

  void _next() {
    final err = _validateCurrentPage();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() => _error = null);
    if (_page < 3) {
      _pageCtrl.animateToPage(
        _page + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _submit();
    }
  }

  void _back() {
    if (_page > 0) {
      _pageCtrl.animateToPage(
        _page - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Rough estimate: weight × avg price/kg across selected services.
  double _estimateTotal() {
    final kg = double.tryParse(_weightCtrl.text);
    if (kg == null || kg <= 0) return 0;
    final preloaded = widget.provider.services ?? [];
    final selected  = preloaded.where((s) => _selectedServiceIds.contains(s.serviceId));
    if (selected.isEmpty) return 0;
    final avgRate = selected
        .map((s) => s.effectivePricePerKg ?? 0)
        .fold<double>(0, (a, b) => a + b) / selected.length;
    return double.parse((kg * avgRate).toStringAsFixed(2));
  }

  Future<void> _showInsufficientBalanceDialog({
    required double required,
    required double available,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Insufficient Wallet Balance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You need ${AppConstants.currencySymbol}${required.toStringAsFixed(2)} '
                'but only have ${AppConstants.currencySymbol}${available.toStringAsFixed(2)} available.'),
            const SizedBox(height: 10),
            const Text('Please top up your wallet to continue.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/wallet');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Top Up Wallet'),
          ),
        ],
      ),
    );
  }

  // ── Submit ──────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    setState(() { _isSubmitting = true; _error = null; });

    // Demo providers: simulate booking locally, no Supabase write
    if (widget.provider.id.startsWith('demo-')) {
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      final demoNum = 'LDY-${(Random().nextInt(89999) + 10000)}';
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => _BookingConfirmedScreen(
            provider: widget.provider,
            bookingNumber: demoNum,
            pickupAddress: _pickupAddrCtrl.text,
            pickupDate: _pickupDate!,
            pickupSlot: _pickupSlot!,
            selectedServiceIds: Set.from(_selectedServiceIds),
          ),
        ),
      );
      return;
    }

    // Real providers: wallet check → Supabase booking → reserve payment
    try {
      final svc         = ref.read(laundryServiceProvider);
      final pricing     = widget.provider.pricing;
      final pickupFee   = pricing?.pickupFee ?? 0;
      final estimatedAmt = double.tryParse(_weightCtrl.text) != null
          ? _estimateTotal() : 0.0;

      AppLogger.info('[Booking] provider=${widget.provider.id} pickupFee=$pickupFee estimatedAmt=$estimatedAmt');

      // 1. Check wallet balance before booking.
      // Use maybeWhen so a not-yet-emitted stream (value == null) is treated as
      // 0 rather than crashing, while a loaded wallet returns its actual balance.
      final available = ref.read(walletBalanceStreamProvider).maybeWhen(
        data: (w) => w?.availableBalance ?? 0.0,
        orElse: () => 0.0,
      );
      AppLogger.info('[Booking] walletAvailable=$available minNeeded=${pickupFee + estimatedAmt}');
      final minNeeded  = pickupFee + estimatedAmt;
      if (minNeeded > 0 && available < minNeeded) {
        if (!mounted) return;
        setState(() { _isSubmitting = false; });
        await _showInsufficientBalanceDialog(
          required: minNeeded, available: available);
        return;
      }

      // 2. Build service items
      final preloaded  = widget.provider.services;
      final allServices = (preloaded != null && preloaded.isNotEmpty)
          ? preloaded
          : (ref.read(laundryProviderServicesProvider(widget.provider.id)).valueOrNull ?? []);
      final selected   = allServices
          .where((s) => _selectedServiceIds.contains(s.serviceId))
          .toList();
      final items = selected.map((s) => {
        'service_id':   s.serviceId,
        'service_name': s.serviceName ?? '',
        'quantity':     1,
        'unit_price':   s.pricePerKg ?? s.pricePerPound ?? 0.0,
        'total_price':  s.pricePerKg ?? s.pricePerPound ?? 0.0,
      }).toList();

      AppLogger.info('[Booking] services=${selected.length} items items=${items.length}');

      final returnAddr = _sameAddress ? _pickupAddrCtrl.text : _returnAddrCtrl.text;
      final user       = ref.read(currentUserProvider);

      // Prefer coordinates from the selected saved address; fall back to user profile
      final pickupLat = _selectedPickupAddress?.latitude ?? user?.latitude;
      final pickupLng = _selectedPickupAddress?.longitude ?? user?.longitude;

      // 3. Create booking in DB
      AppLogger.info('[Booking] calling createBooking…');
      final booking = await svc.createBooking(
        providerId:        widget.provider.id,
        pickupAddress:     _pickupAddrCtrl.text,
        pickupLat:         pickupLat,
        pickupLng:         pickupLng,
        returnAddress:     returnAddr,
        pickupDate:        _pickupDate!,
        pickupTimeSlot:    _pickupSlot!,
        estimatedWeightKg: double.tryParse(_weightCtrl.text),
        estimatedBags:     int.tryParse(_bagsCtrl.text) ?? 1,
        customerNotes:     _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        pickupFee:         pickupFee,
        deliveryFee:       pricing?.deliveryFee ?? 0,
        estimatedTotal:    estimatedAmt > 0 ? estimatedAmt : null,
        items:             items,
      );
      AppLogger.info('[Booking] created bookingId=${booking.id}');

      // 4. Reserve wallet payment (non-fatal if wallet not set up yet)
      if (estimatedAmt > 0 || pickupFee > 0) {
        try {
          await svc.reservePayment(
            bookingId:    booking.id,
            laundryAmount: estimatedAmt,
            pickupFee:    pickupFee,
          );
        } catch (walletErr) {
          AppLogger.error('[Booking] wallet reservation failed (non-fatal): $walletErr');
        }
      }

      if (!mounted) return;
      ref.invalidate(myLaundryBookingsProvider);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => _LiveBookingConfirmedScreen(
            provider:      widget.provider,
            bookingId:     booking.id,
            bookingNumber: booking.bookingNumber,
            pickupDate:    _pickupDate!,
            pickupSlot:    _pickupSlot!,
          ),
        ),
      );
    } catch (e, stack) {
      AppLogger.error('[Booking] SUBMIT FAILED: $e\n$stack');
      if (mounted) setState(() { _error = friendlyError(e); _isSubmitting = false; });
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final steps = ['Services', 'Address', 'Schedule', 'Details'];

    return Scaffold(
      appBar: AppBar(
        title: Text('Book – ${widget.provider.businessName}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _back,
        ),
      ),
      body: Column(
        children: [
          _StepProgressBar(current: _page, steps: steps),

          if (_error != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                ],
              ),
            ),

          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (p) => setState(() => _page = p),
              children: [
                _ServicesPage(
                  provider: widget.provider,
                  selected: _selectedServiceIds,
                  onToggle: (id) => setState(() {
                    if (_selectedServiceIds.contains(id)) _selectedServiceIds.remove(id);
                    else _selectedServiceIds.add(id);
                  }),
                ),
                _AddressPage(
                  pickupCtrl:       _pickupAddrCtrl,
                  returnCtrl:       _returnAddrCtrl,
                  sameAddress:      _sameAddress,
                  selectedAddress:  _selectedPickupAddress,
                  onSameChanged:    (v) => setState(() => _sameAddress = v),
                  onAddressSelected: (addr) => setState(() {
                    _selectedPickupAddress = addr;
                    _pickupAddrCtrl.text   = addr.address;
                  }),
                ),
                _SchedulePage(
                  pickupDate:    _pickupDate,
                  pickupSlot:    _pickupSlot,
                  onDateChanged: (d) {
                    setState(() {
                      _pickupDate = d;
                      // Clear a previously-selected slot if it's now in the past
                      // (e.g. user switches from tomorrow back to today)
                      if (_pickupSlot != null) {
                        final now   = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        final sel   = DateTime(d.year, d.month, d.day);
                        if (sel == today) {
                          final startStr = _pickupSlot!.split('–').first.trim();
                          final parts    = startStr.split(':');
                          if (parts.length >= 2) {
                            final slotStart = DateTime(
                              now.year, now.month, now.day,
                              int.tryParse(parts[0]) ?? 0,
                              int.tryParse(parts[1]) ?? 0,
                            );
                            if (now.isAfter(slotStart)) _pickupSlot = null;
                          }
                        }
                      }
                    });
                  },
                  onSlotChanged: (s) => setState(() => _pickupSlot = s),
                  timeSlots:     _timeSlots,
                ),
                _DetailsPage(
                  weightCtrl:      _weightCtrl,
                  bagsCtrl:        _bagsCtrl,
                  notesCtrl:       _notesCtrl,
                  pricing:         widget.provider.pricing,
                  provider:        widget.provider,
                  selectedSvcIds:  _selectedServiceIds,
                ),
              ],
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(
                          _page < 3 ? 'Continue' : 'Confirm Booking',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 1 — Services
// ─────────────────────────────────────────────────────────────────────────────

class _ServicesPage extends ConsumerWidget {
  final LaundryProvider provider;
  final Set<String> selected;
  final void Function(String) onToggle;

  const _ServicesPage({
    required this.provider,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preloaded = provider.services;
    final servicesAsync = (preloaded != null && preloaded.isNotEmpty)
        ? AsyncValue.data(preloaded)
        : ref.watch(laundryProviderServicesProvider(provider.id));

    return servicesAsync.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e)),
      data: (services) {
        final available = services.where((s) => s.isAvailable).toList();
        if (available.isEmpty) {
          return const AppEmptyState(
            icon: Icons.local_laundry_service_outlined,
            title: 'No services listed yet',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: available.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) {
            final svc = available[i];
            final isSelected = selected.contains(svc.serviceId);
            return GestureDetector(
              onTap: () => onToggle(svc.serviceId),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _kBlue.withValues(alpha: 0.07)
                      : Theme.of(ctx).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? _kBlue : Theme.of(ctx).colorScheme.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: _kBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.local_laundry_service_rounded, color: _kBlue, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            svc.serviceName ?? 'Service',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          if (svc.estimatedHours > 0)
                            Text(
                              '~${svc.estimatedHours}h turnaround',
                              style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                            ),
                          if (svc.effectivePricePerKg != null)
                            Text(
                              '${AppConstants.currencySymbol}${svc.effectivePricePerKg!.toStringAsFixed(2)}/kg',
                              style: const TextStyle(fontSize: 12, color: _kBlue, fontWeight: FontWeight.w600),
                            )
                          else if ((svc.dryCleaningFee) > 0)
                            Text(
                              'from ${AppConstants.currencySymbol}${svc.dryCleaningFee.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12, color: _kBlue, fontWeight: FontWeight.w600),
                            )
                          else if (svc.ironingFee > 0)
                            Text(
                              '${AppConstants.currencySymbol}${svc.ironingFee.toStringAsFixed(2)}/item',
                              style: const TextStyle(fontSize: 12, color: _kBlue, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: isSelected
                          ? Container(
                              key: const ValueKey('check'),
                              width: 28, height: 28,
                              decoration: const BoxDecoration(color: _kBlue, shape: BoxShape.circle),
                              child: const Icon(Icons.check, color: Colors.white, size: 16),
                            )
                          : Container(
                              key: const ValueKey('empty'),
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 — Address
// ─────────────────────────────────────────────────────────────────────────────

class _AddressPage extends ConsumerWidget {
  final TextEditingController pickupCtrl;
  final TextEditingController returnCtrl;
  final bool sameAddress;
  final UserAddress? selectedAddress;
  final ValueChanged<bool> onSameChanged;
  final ValueChanged<UserAddress> onAddressSelected;

  const _AddressPage({
    required this.pickupCtrl,
    required this.returnCtrl,
    required this.sameAddress,
    required this.selectedAddress,
    required this.onSameChanged,
    required this.onAddressSelected,
  });

  IconData _labelIcon(String label) {
    switch (label.toLowerCase()) {
      case 'work':   return Icons.work_rounded;
      case 'other':  return Icons.location_on_rounded;
      default:       return Icons.home_rounded;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId       = ref.watch(currentUserIdProvider);
    final addressAsync = userId != null
        ? ref.watch(userAddressesProvider(userId))
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Pickup Address'),
          const SizedBox(height: 12),

          // Saved address chips from the customer's address book
          if (addressAsync != null)
            addressAsync.when(
              loading: () => const SizedBox(
                height: 40,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (addresses) {
                if (addresses.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: addresses.map((addr) {
                          final isSelected = selectedAddress?.id == addr.id;
                          return GestureDetector(
                            onTap: () => onAddressSelected(addr),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _kBlue
                                    : _kBlue.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? _kBlue
                                      : _kBlue.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _labelIcon(addr.label),
                                    size: 16,
                                    color: isSelected
                                        ? Colors.white
                                        : _kBlue,
                                  ),
                                  const SizedBox(width: 6),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        addr.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? Colors.white
                                              : _kBlue,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 160,
                                        child: Text(
                                          addr.address,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isSelected
                                                ? Colors.white70
                                                : Colors.grey.shade600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isSelected) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.check_circle_rounded,
                                        color: Colors.white, size: 16),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or type a different address',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),

          _AddrField(
            controller: pickupCtrl,
            hint: selectedAddress != null
                ? 'Override pickup address…'
                : 'Where should we pick up your laundry?',
          ),

          const SizedBox(height: 20),
          SwitchListTile.adaptive(
            value: sameAddress,
            onChanged: onSameChanged,
            title: const Text('Return to same address',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Drop off clean laundry at the pickup address'),
            contentPadding: EdgeInsets.zero,
            activeTrackColor: _kBlue,
          ),

          if (!sameAddress) ...[
            const SizedBox(height: 16),
            _SectionTitle('Return Address'),
            const SizedBox(height: 8),
            _AddrField(
                controller: returnCtrl,
                hint: 'Where should we return your clean laundry?'),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 3 — Schedule
// ─────────────────────────────────────────────────────────────────────────────

class _SchedulePage extends StatelessWidget {
  final DateTime? pickupDate;
  final String? pickupSlot;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<String> onSlotChanged;
  final List<String> timeSlots;

  const _SchedulePage({
    required this.pickupDate,
    required this.pickupSlot,
    required this.onDateChanged,
    required this.onSlotChanged,
    required this.timeSlots,
  });

  /// Returns true when [slot] (e.g. "09:00 – 11:00") has already started
  /// and [date] is today. Tomorrow or later → always false (never past).
  bool _isSlotPast(String slot, DateTime? date) {
    if (date == null) return false;
    final now = DateTime.now();
    // Only apply the check when the selected date is today
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(date.year, date.month, date.day);
    if (selected != today) return false;

    // Parse start hour/minute from "HH:MM – HH:MM"
    final startStr = slot.split('–').first.trim(); // e.g. "09:00"
    final parts = startStr.split(':');
    if (parts.length < 2) return false;
    final hour   = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final slotStart = DateTime(now.year, now.month, now.day, hour, minute);
    return now.isAfter(slotStart);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Pickup Date'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: now.add(const Duration(days: 1)),
                firstDate: now,
                lastDate: now.add(const Duration(days: 30)),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: _kBlue),
                  ),
                  child: child!,
                ),
              );
              if (d != null) onDateChanged(d);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: pickupDate != null ? _kBlue : Theme.of(context).colorScheme.outlineVariant,
                  width: pickupDate != null ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
                color: pickupDate != null ? _kBlue.withValues(alpha: 0.05) : null,
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, color: pickupDate != null ? _kBlue : Colors.grey),
                  const SizedBox(width: 12),
                  Text(
                    pickupDate != null
                        ? '${pickupDate!.day}/${pickupDate!.month}/${pickupDate!.year}'
                        : 'Tap to select a date',
                    style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500,
                      color: pickupDate != null ? Theme.of(context).colorScheme.onSurface : Colors.grey,
                    ),
                  ),
                  if (pickupDate != null) ...[
                    const Spacer(),
                    Icon(Icons.edit_calendar_rounded, size: 16, color: _kBlue.withValues(alpha: 0.6)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle('Pickup Time Slot'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: timeSlots.map((slot) {
              final isSelected = slot == pickupSlot;
              final isPast     = _isSlotPast(slot, pickupDate);

              return GestureDetector(
                onTap: isPast ? null : () => onSlotChanged(slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isPast
                        ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                        : isSelected
                            ? _kBlue
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isPast
                            ? Colors.transparent
                            : isSelected
                                ? _kBlue
                                : Colors.transparent),
                  ),
                  child: Text(
                    slot,
                    style: TextStyle(
                      color: isPast
                          ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)
                          : isSelected
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      decoration: isPast ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 4 — Details
// ─────────────────────────────────────────────────────────────────────────────

class _DetailsPage extends ConsumerWidget {
  final TextEditingController weightCtrl;
  final TextEditingController bagsCtrl;
  final TextEditingController notesCtrl;
  final LaundryPricing? pricing;
  final LaundryProvider provider;
  final Set<String> selectedSvcIds;

  const _DetailsPage({
    required this.weightCtrl,
    required this.bagsCtrl,
    required this.notesCtrl,
    required this.provider,
    required this.selectedSvcIds,
    this.pricing,
  });

  double _estimateServiceTotal() {
    final kg = double.tryParse(weightCtrl.text);
    if (kg == null || kg <= 0) return 0;
    final services = provider.services ?? [];
    final selected = services.where((s) => selectedSvcIds.contains(s.serviceId));
    if (selected.isEmpty) return 0;
    return selected.fold(0.0, (sum, s) {
      final rate = s.effectivePricePerKg ?? 0;
      return sum + (kg * rate);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletBalanceStreamProvider);
    final c = AppConstants.currencySymbol;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Weight & bags ────────────────────────────────────────────
          _SectionTitle('Estimated Weight (kg)'),
          const SizedBox(height: 8),
          _InputField(
            controller: weightCtrl,
            hint: 'e.g. 5.0',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            prefix: const Icon(Icons.scale_rounded, size: 18),
          ),
          const SizedBox(height: 16),
          _SectionTitle('Number of Bags'),
          const SizedBox(height: 8),
          _InputField(
            controller: bagsCtrl,
            hint: '1',
            keyboardType: TextInputType.number,
            prefix: const Icon(Icons.shopping_bag_outlined, size: 18),
          ),
          const SizedBox(height: 16),
          _SectionTitle('Special Instructions (optional)'),
          const SizedBox(height: 8),
          TextField(
            controller: notesCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'e.g. Handle delicates with care, no fabric softener…',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),

          const SizedBox(height: 24),

          // ── Order summary (rebuilds live as weight is typed) ─────────
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: weightCtrl,
            builder: (context, _, __) {
              final pickupFee    = pricing?.pickupFee   ?? 0;
              final deliveryFee  = pricing?.deliveryFee ?? 0;
              final serviceTotal = _estimateServiceTotal();
              final estimatedTotal = serviceTotal + pickupFee;

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kBlue.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _kBlue.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Order Summary',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 12),
                        if (serviceTotal > 0)
                          _SummaryRow('Laundry services (est.)', '$c${serviceTotal.toStringAsFixed(2)}'),
                        _SummaryRow('Pickup fee',
                            pickupFee == 0 ? 'Free' : '$c${pickupFee.toStringAsFixed(2)}'),
                        _SummaryRow('Return delivery fee',
                            deliveryFee == 0 ? 'Free (paid later)' : '$c${deliveryFee.toStringAsFixed(2)} (paid on ready)'),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Due Now (estimate)',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            Text(
                              '$c${estimatedTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16, color: _kBlue),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          serviceTotal > 0
                              ? 'Estimate based on weight × service rate'
                              : 'Enter your weight above for a price estimate',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Wallet balance ─────────────────────────────────────
                  walletAsync.when(
                    loading: () => _WalletCard(
                      balance: null,
                      required: estimatedTotal,
                      onTopUp: () => Navigator.pushNamed(context, '/wallet'),
                    ),
                    error: (_, __) => _WalletCard(
                      balance: 0,
                      required: estimatedTotal,
                      onTopUp: () => Navigator.pushNamed(context, '/wallet'),
                    ),
                    data: (wallet) => _WalletCard(
                      balance: wallet?.availableBalance,
                      required: estimatedTotal,
                      onTopUp: () => Navigator.pushNamed(context, '/wallet'),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _WalletCard extends StatelessWidget {
  final double? balance;
  final double required;
  final VoidCallback onTopUp;
  const _WalletCard({this.balance, required this.required, required this.onTopUp});

  @override
  Widget build(BuildContext context) {
    final c = AppConstants.currencySymbol;
    final hasSufficient = balance != null && (required <= 0 || balance! >= required);
    final isLoading = balance == null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasSufficient || required <= 0
            ? Colors.green.shade50
            : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasSufficient || required <= 0
              ? Colors.green.shade300
              : Colors.orange.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                size: 18,
                color: hasSufficient || required <= 0
                    ? Colors.green.shade700
                    : Colors.orange.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                'Wallet Balance',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: hasSufficient || required <= 0
                      ? Colors.green.shade800
                      : Colors.orange.shade800,
                ),
              ),
              const Spacer(),
              if (isLoading)
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  '$c${balance!.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: hasSufficient || required <= 0
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
            ],
          ),
          if (!isLoading && !hasSufficient && required > 0) ...[
            const SizedBox(height: 8),
            Text(
              'You need $c${required.toStringAsFixed(2)} but have $c${balance!.toStringAsFixed(2)}. '
              'Please top up $c${(required - balance!).toStringAsFixed(2)} to continue.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onTopUp,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Top Up Wallet',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
          ] else if (!isLoading && (hasSufficient || required <= 0)) ...[
            const SizedBox(height: 4),
            Text(
              required <= 0
                  ? 'No upfront payment needed for this booking.'
                  : 'You have sufficient balance to confirm this booking.',
              style: TextStyle(fontSize: 12, color: Colors.green.shade700),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Booking Confirmed — real providers (confetti)
// ─────────────────────────────────────────────────────────────────────────────

class _LiveBookingConfirmedScreen extends StatefulWidget {
  final LaundryProvider provider;
  final String bookingId;
  final String bookingNumber;
  final DateTime pickupDate;
  final String pickupSlot;

  const _LiveBookingConfirmedScreen({
    required this.provider,
    required this.bookingId,
    required this.bookingNumber,
    required this.pickupDate,
    required this.pickupSlot,
  });

  @override
  State<_LiveBookingConfirmedScreen> createState() =>
      _LiveBookingConfirmedScreenState();
}

class _LiveBookingConfirmedScreenState
    extends State<_LiveBookingConfirmedScreen>
    with SingleTickerProviderStateMixin {
  late final ConfettiController _confetti;
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 5))
      ..play();

    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut);
    // Slight delay so confetti fires first
    Future.delayed(const Duration(milliseconds: 200), _scaleCtrl.forward);
  }

  @override
  void dispose() {
    _confetti.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day   = widget.pickupDate.day.toString().padLeft(2, '0');
    final month = widget.pickupDate.month.toString().padLeft(2, '0');
    final year  = widget.pickupDate.year;

    return Scaffold(
      backgroundColor: _kNavy,
      body: Stack(
        alignment: Alignment.topCenter,
        children: [
          // ── Confetti ───────────────────────────────────────────────────────
          ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.06,
            numberOfParticles: 18,
            gravity: 0.12,
            shouldLoop: false,
            colors: const [
              Colors.white, Color(0xFF90CAF9), Color(0xFFCE93D8),
              Color(0xFFA5D6A7), Color(0xFFFFCC80), Color(0xFFEF9A9A),
            ],
          ),

          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                    child: Column(
                      children: [
                        // ── Animated checkmark ───────────────────────────────
                        ScaleTransition(
                          scale: _scale,
                          child: Container(
                            width: 120, height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 2.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 64,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        const Text(
                          'You\'re all set!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),

                        // Fun tagline
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'Sit back & relax ☕\nWe\'ll pick up, wash, dry, fold\nand deliver — you just chill.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Booking number pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            widget.bookingNumber,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── Detail cards ─────────────────────────────────────
                        _ConfirmCard(
                          icon: Icons.storefront_rounded,
                          label: 'Laundromat',
                          value: widget.provider.businessName,
                        ),
                        const SizedBox(height: 10),
                        _ConfirmCard(
                          icon: Icons.calendar_today_rounded,
                          label: 'Pickup Schedule',
                          value: '$day/$month/$year  •  ${widget.pickupSlot}',
                        ),
                        const SizedBox(height: 10),

                        // What happens next
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'What happens next?',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _NextStep('1', 'Provider accepts your booking'),
                              _NextStep('2', 'Driver picks up your laundry'),
                              _NextStep('3', 'Washed, dried & folded with care'),
                              _NextStep('4', 'Delivered back to your door'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Buttons ─────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/laundry/tracking',
                            (r) => r.isFirst,
                            arguments: widget.bookingId,
                          ),
                          icon: const Icon(Icons.track_changes_rounded, size: 20),
                          label: const Text('Track My Order',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _kNavy,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pushNamedAndRemoveUntil(
                            context, '/laundry', (r) => r.isFirst,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Done',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                      ),
                    ],
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

class _NextStep extends StatelessWidget {
  final String number;
  final String text;
  const _NextStep(this.number, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(number,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 10),
            Text(text,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Booking Confirmed (demo providers)
// ─────────────────────────────────────────────────────────────────────────────

class _BookingConfirmedScreen extends StatelessWidget {
  final LaundryProvider provider;
  final String bookingNumber;
  final String pickupAddress;
  final DateTime pickupDate;
  final String pickupSlot;
  final Set<String> selectedServiceIds;

  const _BookingConfirmedScreen({
    required this.provider,
    required this.bookingNumber,
    required this.pickupAddress,
    required this.pickupDate,
    required this.pickupSlot,
    required this.selectedServiceIds,
  });

  @override
  Widget build(BuildContext context) {
    final services = provider.services
            ?.where((s) => selectedServiceIds.contains(s.serviceId))
            .toList() ??
        [];

    return Scaffold(
      backgroundColor: _kNavy,
      body: SafeArea(
        child: Column(
          children: [
            // ── Success hero ──────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                child: Column(
                  children: [
                    // Animated checkmark circle
                    Container(
                      width: 110, height: 110,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 60),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Booking Confirmed!',
                      style: TextStyle(
                        color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        bookingNumber,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Detail cards ──────────────────────────────────────
                    _ConfirmCard(icon: Icons.storefront_rounded, label: 'Laundromat', value: provider.businessName),
                    const SizedBox(height: 10),
                    _ConfirmCard(
                      icon: Icons.location_on_rounded,
                      label: 'Pickup Address',
                      value: pickupAddress.isNotEmpty ? pickupAddress : '—',
                    ),
                    const SizedBox(height: 10),
                    _ConfirmCard(
                      icon: Icons.calendar_today_rounded,
                      label: 'Pickup Schedule',
                      value: '${pickupDate.day}/${pickupDate.month}/${pickupDate.year}  •  $pickupSlot',
                    ),
                    if (services.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _ConfirmCard(
                        icon: Icons.local_laundry_service_rounded,
                        label: 'Services',
                        value: services.map((s) => s.serviceName ?? '').join(', '),
                      ),
                    ],
                    if (provider.pricing != null) ...[
                      const SizedBox(height: 10),
                      _ConfirmCard(
                        icon: Icons.local_shipping_rounded,
                        label: 'Delivery Fee',
                        value: provider.pricing!.deliveryFee == 0
                            ? 'Free delivery'
                            : '${AppConstants.currencySymbol}${provider.pricing!.deliveryFee.toStringAsFixed(2)}',
                      ),
                    ],
                    const SizedBox(height: 24),
                    // Info note
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.white.withValues(alpha: 0.6), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'You\'ll receive a confirmation when the provider accepts your booking. '
                              'Track your order in Laundry Orders.',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Action buttons ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                        context, '/laundry', (r) => r.isFirst,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _kNavy,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity, height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                        context, '/laundry/history', (r) => r.isFirst,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('View My Orders', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ConfirmCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 11,
                      fontWeight: FontWeight.w600, letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepProgressBar extends StatelessWidget {
  final int current;
  final List<String> steps;
  const _StepProgressBar({required this.current, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(steps.length, (i) {
          final done   = i < current;
          final active = i == current;
          final color  = done || active ? _kBlue : Colors.grey.shade300;
          return Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    if (i > 0) Expanded(child: Container(height: 2, color: done ? _kBlue : Colors.grey.shade300)),
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      child: done
                          ? const Icon(Icons.check, color: Colors.white, size: 14)
                          : Text(
                              '${i + 1}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: active ? Colors.white : Colors.grey,
                                fontSize: 11, fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                    if (i < steps.length - 1) Expanded(child: Container(height: 2, color: done ? _kBlue : Colors.grey.shade300)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  steps[i],
                  style: TextStyle(
                    fontSize: 10,
                    color: active ? _kBlue : Colors.grey,
                    fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      );
}

class _AddrField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _AddrField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.location_on_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      );
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final Widget? prefix;
  const _InputField({required this.controller, required this.hint, this.keyboardType, this.prefix});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: prefix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
}

