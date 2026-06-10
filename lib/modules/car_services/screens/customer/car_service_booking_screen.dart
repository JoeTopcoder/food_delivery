import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/modules/car_services/models/car_service_offering.dart';
import 'package:food_driver/modules/car_services/models/car_service_provider.dart';
import 'package:food_driver/modules/car_services/models/customer_vehicle.dart';
import 'package:food_driver/modules/car_services/models/service_booking_item.dart';
import 'package:food_driver/modules/car_services/providers/car_services_providers.dart';
import 'package:food_driver/config/app_constants.dart';
import 'package:food_driver/models/address_model.dart';
import 'package:food_driver/providers/address_provider.dart';
import 'package:food_driver/providers/auth_provider.dart';
import 'package:food_driver/screens/customer/payment_screen.dart';
import 'package:food_driver/providers/wallet_provider.dart';
import 'package:food_driver/config/supabase_config.dart';
import 'package:food_driver/widgets/outstanding_debt_banner.dart';
import 'package:food_driver/utils/app_logger.dart';
import 'package:food_driver/services/notification_service.dart';
import 'package:intl/intl.dart';
import 'add_edit_vehicle_screen.dart';

const _kBlue     = Color(0xFF1D4ED8);
const _kBlueDark = Color(0xFF1E3A8A);
const _kAmber    = Color(0xFFF59E0B);

class CarServiceBookingScreen extends ConsumerStatefulWidget {
  const CarServiceBookingScreen({super.key});

  @override
  ConsumerState<CarServiceBookingScreen> createState() =>
      _CarServiceBookingScreenState();
}

class _CarServiceBookingScreenState
    extends ConsumerState<CarServiceBookingScreen> {
  int _currentStep = 0;
  bool _isSubmitting = false;

  // Step 0 — Select Cars
  final List<CustomerVehicle> _selectedVehicles = [];

  // Step 1 — Assign Services per vehicle
  final Map<String, List<CarServiceOffering>> _vehicleServices = {};

  // Step 2 — Service Location
  UserAddress? _selectedAddress;
  bool _mobileService = false;

  // Step 3 — When
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // Step 4 — Review
  String _paymentMethod = 'card';
  final _notesCtrl = TextEditingController();

  static const _stepLabels = ['Cars', 'Services', 'Location', 'When', 'Review'];

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Computed ─────────────────────────────────────────────────────────────

  List<VehicleServiceGroup> get _groups => _selectedVehicles
      .map((v) => VehicleServiceGroup(
            vehicle: v,
            services: _vehicleServices[v.id] ?? [],
          ))
      .toList();

  bool get _allVehiclesHaveServices =>
      _selectedVehicles.isNotEmpty &&
      _selectedVehicles.every((v) => (_vehicleServices[v.id] ?? []).isNotEmpty);

  double get _mobileFee =>
      _mobileService ? AppConstants.carServiceMobileFee : 0.0;

  double get _itemsSubtotal {
    double s = _mobileFee;
    for (final g in _groups) s += g.subtotal;
    return s;
  }

  double get _platformFee => double.parse(
      (_itemsSubtotal * AppConstants.carServicePlatformFeePct)
          .toStringAsFixed(2));
  double get _serviceFee => AppConstants.carServiceServiceFee;
  double get _total => _itemsSubtotal + _platformFee + _serviceFee;

  DateTime? get _scheduledAt {
    if (_selectedDate == null || _selectedTime == null) return null;
    return DateTime(
      _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
      _selectedTime!.hour, _selectedTime!.minute,
    );
  }

  bool _stepValid(int step) {
    switch (step) {
      case 0: return _selectedVehicles.isNotEmpty;
      case 1: return _allVehiclesHaveServices;
      case 2: return !_mobileService || _selectedAddress != null;
      case 3: return _scheduledAt != null;
      case 4: return true;
      default: return false;
    }
  }

  String _stepErrorMsg(int step) {
    switch (step) {
      case 0: return 'Select at least one vehicle.';
      case 1: return 'Each vehicle needs at least one service.';
      case 2: return 'Select a service address or disable mobile service.';
      case 3: return 'Choose a date and time.';
      default: return 'Complete all fields.';
    }
  }

  void _next() {
    if (!_stepValid(_currentStep)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_stepErrorMsg(_currentStep)),
        backgroundColor: Colors.red.shade700,
      ));
      return;
    }
    setState(() => _currentStep++);
  }

  void _back() {
    if (_currentStep == 0) Navigator.pop(context);
    else setState(() => _currentStep--);
  }

  // ── Confirm & Book ────────────────────────────────────────────────────────

  Future<void> _confirmBooking(CarServiceProvider provider) async {
    if (_isSubmitting) return;

    final outstandingDebt = ref.read(outstandingDebtProvider);

    // Pre-flight wallet balance check
    if (_paymentMethod == 'wallet') {
      final totalAmount = _groups.fold<double>(
        0,
        (sum, g) => sum + g.subtotal,
      ) + (_mobileService ? AppConstants.carServiceMobileFee : 0.0) + outstandingDebt;
      final walletBalance =
          ref.read(walletBalanceStreamProvider).valueOrNull?.availableBalance ?? 0.0;
      if (walletBalance < totalAmount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Insufficient wallet balance '
              '(\$${walletBalance.toStringAsFixed(2)}). '
              'Top up or choose card payment.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final svc = ref.read(carServicesServiceProvider);

      final addr = _selectedAddress;
      final serviceAddress = _mobileService && addr != null
          ? addr.address
          : (provider.baseLocationAddress ?? addr?.address ?? '');
      final serviceLat = _mobileService ? addr?.latitude : provider.baseLocationLat;
      final serviceLng = _mobileService ? addr?.longitude : provider.baseLocationLng;

      final booking = await svc.createMultiBooking(
        providerId: provider.id,
        groups: _groups,
        scheduledAt: _scheduledAt!,
        serviceAddress: serviceAddress,
        serviceLat: serviceLat,
        serviceLng: serviceLng,
        selectedAddressId: addr?.id,
        mobileFee: _mobileFee,
        paymentMethod: _paymentMethod,
        customerNotes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      if (!mounted) return;

      if (_paymentMethod == 'card') {
        final currentUser = ref.read(currentUserProvider);
        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentScreen(
              orderId: booking.id,
              amount: booking.totalAmount + outstandingDebt,
              currency: AppConstants.currencyCode,
              customerEmail: currentUser?.email ?? '',
              customerName: currentUser?.name ?? '',
              type: 'car_service',
            ),
          ),
        );
        if (!mounted) return;
        if (result?['status'] == 'paid') {
          await svc.updateBookingPayment(
            booking.id,
            paymentStatus: 'paid',
            stripePaymentIntentId: result?['paymentIntentId'] as String?,
          );
          if (outstandingDebt > 0) {
            try {
              final userId = SupabaseConfig.client.auth.currentUser!.id;
              // Card charged (totalAmount + outstandingDebt) via Stripe —
              // wallet balance untouched; just zero out debt_balance.
              await SupabaseConfig.client.rpc(
                'checkout_clear_debt_direct',
                params: {
                  'p_user_id': userId,
                  'p_amount': outstandingDebt,
                  'p_reference': booking.id,
                },
              );
              ref.invalidate(walletBalanceStreamProvider);
            } catch (_) {}
          }
        } else {
          setState(() => _isSubmitting = false);
          return;
        }
      } else if (_paymentMethod == 'wallet') {
        final userId = SupabaseConfig.client.auth.currentUser!.id;
        try {
          // payWithWallet deducts (totalAmount + outstandingDebt) from balance.
          await ref.read(walletServiceProvider).payWithWallet(
            userId,
            booking.totalAmount + outstandingDebt,
            booking.id,
          );
        } catch (e) {
          final msg = e.toString().toLowerCase();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(msg.contains('insufficient')
                  ? 'Insufficient wallet balance. Top up and try again.'
                  : 'Wallet payment failed. Please try again.'),
              backgroundColor: Colors.red,
            ));
            setState(() => _isSubmitting = false);
          }
          return;
        }
        await svc.updateBookingPayment(booking.id, paymentStatus: 'paid');
        if (outstandingDebt > 0) {
          try {
            // Wallet already deducted the debt; just zero out debt_balance.
            await SupabaseConfig.client.rpc(
              'checkout_clear_debt_direct',
              params: {
                'p_user_id': userId,
                'p_amount': outstandingDebt,
                'p_reference': booking.id,
              },
            );
          } catch (_) {}
        }
        ref.invalidate(walletBalanceStreamProvider);
        ref.invalidate(walletTransactionsStreamProvider);
      }

      if (!mounted) return;
      ref.invalidate(myCarServiceBookingsProvider);
      NotificationService().showNotification(
        title: '🔧 Booking Confirmed!',
        body: 'Your car service booking #${booking.bookingNumber} is confirmed.',
        data: {'type': 'car_service_booked', 'booking_id': booking.id},
      );
      Navigator.pushReplacementNamed(
        context, '/car-services/booking-summary',
        arguments: booking,
      );
    } catch (e) {
      AppLogger.error('createMultiBooking: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking failed: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final provider = args?['provider'] as CarServiceProvider?;
    final offerings = (args?['offerings'] as List<CarServiceOffering>?) ?? [];

    if (provider == null) {
      return const Scaffold(body: Center(child: Text('No provider selected')));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          _StepHeader(
            step: _currentStep,
            steps: _stepLabels,
            providerName: provider.businessName,
            onBack: _back,
          ),
          Expanded(child: _buildStep(provider, offerings)),
          _BottomBar(
            step: _currentStep,
            lastStep: _stepLabels.length - 1,
            isSubmitting: _isSubmitting,
            onBack: _back,
            onNext: _currentStep < _stepLabels.length - 1
                ? _next
                : () => _confirmBooking(provider),
            total: _currentStep == _stepLabels.length - 1
                ? _total + ref.watch(outstandingDebtProvider)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStep(CarServiceProvider provider, List<CarServiceOffering> offerings) {
    switch (_currentStep) {
      case 0:
        return _SelectCarsStep(
          selectedVehicles: _selectedVehicles,
          onToggle: (v) => setState(() {
            if (_selectedVehicles.any((x) => x.id == v.id)) {
              _selectedVehicles.removeWhere((x) => x.id == v.id);
              _vehicleServices.remove(v.id);
            } else {
              _selectedVehicles.add(v);
            }
          }),
          onAddNew: () async {
            await Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AddEditVehicleScreen(),
            ));
            ref.invalidate(myVehiclesProvider);
          },
        );
      case 1:
        return _AssignServicesStep(
          groups: _groups,
          availableOfferings: offerings,
          vehicleServices: _vehicleServices,
          onToggleService: (vehicleId, offering) => setState(() {
            final list = List<CarServiceOffering>.from(_vehicleServices[vehicleId] ?? []);
            if (list.any((s) => s.id == offering.id)) {
              list.removeWhere((s) => s.id == offering.id);
            } else {
              list.add(offering);
            }
            _vehicleServices[vehicleId] = list;
          }),
        );
      case 2:
        return _SelectLocationStep(
          selectedAddress: _selectedAddress,
          onSelect: (addr) => setState(() => _selectedAddress = addr),
          mobileService: _mobileService,
          onMobileToggle: (v) => setState(() {
            _mobileService = v;
            if (!v) _selectedAddress = null;
          }),
        );
      case 3:
        return _SelectWhenStep(
          selectedDate: _selectedDate,
          selectedTime: _selectedTime,
          onDateSelected: (d) {
            setState(() {
              _selectedDate = d;
              if (_selectedTime != null) {
                final min = DateTime.now().add(const Duration(hours: 2));
                final slotDt = DateTime(d.year, d.month, d.day, _selectedTime!.hour, _selectedTime!.minute);
                if (slotDt.isBefore(min)) _selectedTime = null;
              }
            });
          },
          onTimeSelected: (t) => setState(() => _selectedTime = t),
        );
      case 4:
        return _ReviewStep(
          groups: _groups,
          address: _selectedAddress,
          mobileService: _mobileService,
          scheduledAt: _scheduledAt,
          itemsSubtotal: _itemsSubtotal,
          mobileFee: _mobileFee,
          platformFee: _platformFee,
          serviceFee: _serviceFee,
          total: _total,
          paymentMethod: _paymentMethod,
          notesCtrl: _notesCtrl,
          onPaymentMethodChanged: (m) => setState(() => _paymentMethod = m),
        );
      default:
        return const SizedBox();
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEP 0 — SELECT CARS
// ═════════════════════════════════════════════════════════════════════════════

class _SelectCarsStep extends ConsumerWidget {
  final List<CustomerVehicle> selectedVehicles;
  final void Function(CustomerVehicle) onToggle;
  final VoidCallback onAddNew;

  const _SelectCarsStep({
    required this.selectedVehicles,
    required this.onToggle,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesAsync = ref.watch(myVehiclesProvider);
    return vehiclesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _NoVehiclesPrompt(onAdd: onAddNew),
      data: (vehicles) {
        if (vehicles.isEmpty) {
          return _NoVehiclesPrompt(onAdd: onAddNew);
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionTitle('Select your vehicle(s)', 'Tap to select — you can pick multiple'),
            const SizedBox(height: 12),
            ...vehicles.map((v) => _VehicleSelectCard(
              vehicle: v,
              selected: selectedVehicles.any((x) => x.id == v.id),
              onTap: () => onToggle(v),
            )),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, color: _kBlue),
              label: const Text('Add New Vehicle', style: TextStyle(color: _kBlue, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kBlue),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onAddNew,
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _VehicleSelectCard extends StatelessWidget {
  final CustomerVehicle vehicle;
  final bool selected;
  final VoidCallback onTap;
  const _VehicleSelectCard({required this.vehicle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? _kBlue.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _kBlue : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          _VehicleThumb(photoUrl: vehicle.photoUrl, type: vehicle.vehicleType),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(vehicle.displayName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
            if (vehicle.color != null)
              Text(vehicle.color!, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (vehicle.licensePlate != null)
              Text(vehicle.licensePlate!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontFamily: 'monospace')),
          ])),
          if (vehicle.isDefault)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _kAmber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
              child: const Text('Default', style: TextStyle(color: _kAmber, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? _kBlue : Colors.transparent,
              border: Border.all(
                color: selected ? _kBlue : Theme.of(context).colorScheme.outlineVariant,
                width: 2,
              ),
            ),
            child: selected ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEP 1 — ASSIGN SERVICES
// ═════════════════════════════════════════════════════════════════════════════

class _AssignServicesStep extends StatelessWidget {
  final List<VehicleServiceGroup> groups;
  final List<CarServiceOffering> availableOfferings;
  final Map<String, List<CarServiceOffering>> vehicleServices;
  final void Function(String vehicleId, CarServiceOffering) onToggleService;

  const _AssignServicesStep({
    required this.groups,
    required this.availableOfferings,
    required this.vehicleServices,
    required this.onToggleService,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle('Assign Services', 'Select services for each vehicle'),
        const SizedBox(height: 12),
        ...groups.map((g) => _VehicleServiceBlock(
          group: g,
          availableOfferings: availableOfferings,
          selectedServices: vehicleServices[g.vehicle.id] ?? [],
          onToggle: (o) => onToggleService(g.vehicle.id, o),
        )),
      ],
    );
  }
}

class _VehicleServiceBlock extends StatelessWidget {
  final VehicleServiceGroup group;
  final List<CarServiceOffering> availableOfferings;
  final List<CarServiceOffering> selectedServices;
  final void Function(CarServiceOffering) onToggle;

  const _VehicleServiceBlock({
    required this.group,
    required this.availableOfferings,
    required this.selectedServices,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            _VehicleThumb(photoUrl: group.vehicle.photoUrl, type: group.vehicle.vehicleType, size: 40),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group.vehicle.displayName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
              if (group.vehicle.licensePlate != null)
                Text(group.vehicle.licensePlate!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ])),
            if (group.subtotal > 0)
              Text('\$${group.subtotal.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: _kBlue, fontSize: 15)),
          ]),
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        ...availableOfferings.map((o) {
          final sel = selectedServices.any((s) => s.id == o.id);
          return _ServiceCheckTile(offering: o, selected: sel, onTap: () => onToggle(o));
        }),
        const SizedBox(height: 4),
      ]),
    );
  }
}

class _ServiceCheckTile extends StatelessWidget {
  final CarServiceOffering offering;
  final bool selected;
  final VoidCallback onTap;
  const _ServiceCheckTile({required this.offering, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: selected ? _kBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? _kBlue : Theme.of(context).colorScheme.outlineVariant,
                width: 2,
              ),
            ),
            child: selected ? const Icon(Icons.check, color: Colors.white, size: 13) : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(offering.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Theme.of(context).colorScheme.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (offering.description != null)
              Text(offering.description!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${offering.durationMinutes} min', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 8),
          Text('\$${offering.basePrice.toStringAsFixed(2)}',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEP 2 — SELECT LOCATION
// ═════════════════════════════════════════════════════════════════════════════

class _SelectLocationStep extends ConsumerWidget {
  final UserAddress? selectedAddress;
  final void Function(UserAddress) onSelect;
  final bool mobileService;
  final void Function(bool) onMobileToggle;

  const _SelectLocationStep({
    required this.selectedAddress,
    required this.onSelect,
    required this.mobileService,
    required this.onMobileToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    final addressesAsync = userId != null ? ref.watch(userAddressesProvider(userId)) : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle('Service Location', 'Where should the washer come to?'),
        const SizedBox(height: 16),

        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: SwitchListTile(
            title: Text('Mobile Service (+\$15)', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
            subtitle: Text('Washer comes to your location', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            value: mobileService,
            activeThumbColor: _kBlue,
            activeTrackColor: _kBlue.withValues(alpha: 0.4),
            onChanged: onMobileToggle,
          ),
        ),
        const SizedBox(height: 16),

        if (!mobileService)
          _InfoNote('Provider\'s location will be used. Enable mobile service to have the washer come to you.'),

        if (mobileService) ...[
          Text('Select Address', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 10),
          if (addressesAsync != null)
            addressesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error loading addresses: $e'),
              data: (addresses) {
                if (addresses.isEmpty) {
                  return _AddAddressPrompt(
                    onAdd: () => Navigator.pushNamed(context, '/address-book'),
                  );
                }
                return Column(
                  children: addresses.map((a) => _AddressCard(
                    address: a,
                    selected: selectedAddress?.id == a.id,
                    onTap: () => onSelect(a),
                  )).toList(),
                );
              },
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_location_alt, color: _kBlue),
            label: const Text('Add New Address', style: TextStyle(color: _kBlue, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _kBlue),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pushNamed(context, '/address-book'),
          ),
        ],
      ],
    );
  }
}

class _AddressCard extends StatelessWidget {
  final UserAddress address;
  final bool selected;
  final VoidCallback onTap;
  const _AddressCard({required this.address, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? _kBlue.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _kBlue : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Icon(_labelIcon(address.label), color: selected ? _kBlue : Theme.of(context).colorScheme.onSurfaceVariant, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(address.label, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? _kBlue : Theme.of(context).colorScheme.onSurface)),
            Text(address.address, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
          if (address.isDefault)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF16A34A).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: const Text('Default', style: TextStyle(fontSize: 11, color: Color(0xFF16A34A), fontWeight: FontWeight.w600)),
            ),
          if (selected)
            const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_circle, color: _kBlue, size: 20)),
        ]),
      ),
    );
  }

  IconData _labelIcon(String label) {
    switch (label.toLowerCase()) {
      case 'home': return Icons.home_rounded;
      case 'work': return Icons.work_rounded;
      default: return Icons.location_on_rounded;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEP 3 — SELECT WHEN
// ═════════════════════════════════════════════════════════════════════════════

class _SelectWhenStep extends StatelessWidget {
  final DateTime? selectedDate;
  final TimeOfDay? selectedTime;
  final void Function(DateTime) onDateSelected;
  final void Function(TimeOfDay) onTimeSelected;

  const _SelectWhenStep({
    required this.selectedDate,
    required this.selectedTime,
    required this.onDateSelected,
    required this.onTimeSelected,
  });

  String _formatTime(TimeOfDay t) {
    final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  bool _isSlotDisabled(TimeOfDay t, DateTime minBookingTime) {
    if (selectedDate == null) return false;
    final slotDt = DateTime(
      selectedDate!.year, selectedDate!.month, selectedDate!.day,
      t.hour, t.minute,
    );
    return slotDt.isBefore(minBookingTime);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final minBookingTime = now.add(const Duration(hours: 2));
    final firstDate = DateTime(minBookingTime.year, minBookingTime.month, minBookingTime.day);
    final lastDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 30));
    final timeSlots = [
      for (int h = 8; h <= 19; h++)
        for (int m in [0, 30])
          if (!(h == 19 && m == 30)) TimeOfDay(hour: h, minute: m),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle('Select Date & Time', 'Available slots shown below'),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: CalendarDatePicker(
            initialDate: selectedDate ?? firstDate,
            firstDate: firstDate,
            lastDate: lastDate,
            onDateChanged: onDateSelected,
          ),
        ),
        const SizedBox(height: 20),
        Text('Select Time', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: timeSlots.map((t) {
            final disabled = _isSlotDisabled(t, minBookingTime);
            final sel = !disabled &&
                selectedTime?.hour == t.hour &&
                selectedTime?.minute == t.minute;
            return GestureDetector(
              onTap: disabled ? null : () => onTimeSelected(t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: disabled
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : (sel ? _kBlue : Theme.of(context).colorScheme.surfaceContainerLow),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: disabled
                        ? Theme.of(context).colorScheme.outlineVariant
                        : (sel ? _kBlue : Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
                child: Text(
                  _formatTime(t),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: disabled
                        ? Theme.of(context).colorScheme.outlineVariant
                        : (sel ? Colors.white : Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEP 4 — REVIEW
// ═════════════════════════════════════════════════════════════════════════════

class _ReviewStep extends ConsumerWidget {
  final List<VehicleServiceGroup> groups;
  final UserAddress? address;
  final bool mobileService;
  final DateTime? scheduledAt;
  final double itemsSubtotal;
  final double mobileFee;
  final double platformFee;
  final double serviceFee;
  final double total;
  final String paymentMethod;
  final TextEditingController notesCtrl;
  final void Function(String) onPaymentMethodChanged;

  const _ReviewStep({
    required this.groups,
    required this.address,
    required this.mobileService,
    required this.scheduledAt,
    required this.itemsSubtotal,
    required this.mobileFee,
    required this.platformFee,
    required this.serviceFee,
    required this.total,
    required this.paymentMethod,
    required this.notesCtrl,
    required this.onPaymentMethodChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletBalance =
        ref.watch(walletBalanceStreamProvider).valueOrNull?.availableBalance ?? 0.0;
    final outstandingDebt = ref.watch(outstandingDebtProvider);
    final grandTotal = total + outstandingDebt;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle('Review & Pay', 'Confirm your booking'),
        const SizedBox(height: 12),

        _Card(children: [
          if (scheduledAt != null)
            _Row(icon: Icons.schedule, label: 'Date & Time',
              value: DateFormat('EEE, MMM d · h:mm a').format(scheduledAt!)),
          if (mobileService && address != null)
            _Row(icon: Icons.location_on_rounded, label: address!.label, value: address!.address)
          else
            const _Row(icon: Icons.store_rounded, label: 'Location', value: 'Provider\'s location'),
        ]),
        const SizedBox(height: 12),

        ...groups.map((g) => _VehicleGroupCard(group: g)),
        const SizedBox(height: 12),

        _Card(children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Price Breakdown', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
          ),
          ...groups.map((g) => _PriceRow(label: g.vehicle.displayName, value: g.subtotal)),
          if (mobileFee > 0) _PriceRow(label: 'Mobile Service', value: mobileFee),
          _PriceRow(label: 'Platform Fee (${(AppConstants.carServicePlatformFeePct * 100).toStringAsFixed(0)}%)', value: platformFee),
          _PriceRow(label: 'Service Fee', value: serviceFee),
          if (outstandingDebt > 0)
            _PriceRow(label: 'Outstanding Balance', value: outstandingDebt, color: const Color(0xFFEA580C)),
          Divider(height: 20, color: Theme.of(context).colorScheme.outlineVariant),
          _PriceRow(label: 'Total', value: grandTotal, bold: true, color: _kBlue),
        ]),
        const SizedBox(height: 12),

        OutstandingDebtBanner(debtAmount: outstandingDebt),
        TextField(
          controller: notesCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Notes for provider (optional)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 12),

        _Card(children: [
          Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          _PaymentOption(label: 'Credit / Debit Card', icon: Icons.credit_card, value: 'card', groupValue: paymentMethod, onChanged: onPaymentMethodChanged),
          Opacity(
            opacity: walletBalance > 0 ? 1.0 : 0.4,
            child: IgnorePointer(
              ignoring: walletBalance <= 0,
              child: _PaymentOption(
                label: walletBalance > 0
                    ? '7Dash Wallet (\$${walletBalance.toStringAsFixed(2)})'
                    : '7Dash Wallet (no funds)',
                icon: Icons.account_balance_wallet_rounded,
                value: 'wallet',
                groupValue: paymentMethod,
                onChanged: onPaymentMethodChanged,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _VehicleGroupCard extends StatelessWidget {
  final VehicleServiceGroup group;
  const _VehicleGroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _VehicleThumb(photoUrl: group.vehicle.photoUrl, type: group.vehicle.vehicleType, size: 36),
          const SizedBox(width: 10),
          Expanded(child: Text(group.vehicle.displayName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Theme.of(context).colorScheme.onSurface))),
          Text('\$${group.subtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, color: _kBlue)),
        ]),
        const SizedBox(height: 8),
        ...group.services.map((s) => Padding(
          padding: const EdgeInsets.only(left: 46, bottom: 4),
          child: Row(children: [
            const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF16A34A)),
            const SizedBox(width: 6),
            Expanded(child: Text(s.name, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface))),
            Text('\$${s.basePrice.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        )),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class _StepHeader extends StatelessWidget {
  final int step;
  final List<String> steps;
  final String providerName;
  final VoidCallback onBack;

  const _StepHeader({required this.step, required this.steps, required this.providerName, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 16, left: 16, right: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_kBlueDark, _kBlue], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(onTap: onBack, child: const Icon(Icons.arrow_back, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Book Service', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
            Text(providerName, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ])),
        ]),
        const SizedBox(height: 16),
        Row(children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            return Expanded(child: Container(height: 2, color: i ~/ 2 < step ? Colors.white : Colors.white38));
          }
          final idx = i ~/ 2;
          final done = idx < step;
          final active = idx == step;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 30, height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? Colors.white : (active ? Colors.white : Colors.white24),
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check, size: 15, color: _kBlue)
                    : Text('${idx + 1}', style: TextStyle(color: active ? _kBlue : Colors.white70, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
            const SizedBox(height: 4),
            Text(steps[idx], style: TextStyle(color: active ? Colors.white : Colors.white60, fontSize: 10, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
          ]);
        })),
      ]),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int step;
  final int lastStep;
  final bool isSubmitting;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final double? total;

  const _BottomBar({
    required this.step, required this.lastStep, required this.isSubmitting,
    required this.onBack, required this.onNext, this.total,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = step == lastStep;
    return Container(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onBack,
          child: Text('Back', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: isSubmitting ? null : onNext,
            child: isSubmitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(
                    isLast ? (total != null ? 'Pay \$${total!.toStringAsFixed(2)}' : 'Confirm Booking') : 'Continue',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String sub;
  const _SectionTitle(this.title, this.sub);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
    const SizedBox(height: 2),
    Text(sub, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
  ]);
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Row({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: _kBlue),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
      ])),
    ]),
  );
}

class _PriceRow extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  final Color? color;
  const _PriceRow({required this.label, required this.value, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontSize: bold ? 15 : 13, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant))),
      Text('\$${value.toStringAsFixed(2)}', style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: bold ? 16 : 13, color: color ?? Theme.of(context).colorScheme.onSurface)),
    ]),
  );
}

class _PaymentOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final String groupValue;
  final void Function(String) onChanged;

  const _PaymentOption({required this.label, required this.icon, required this.value, required this.groupValue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _kBlue : Theme.of(context).colorScheme.outlineVariant,
                  width: 2,
                ),
                color: selected ? _kBlue : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface)),
          ],
        ),
      ),
    );
  }
}

class _VehicleThumb extends StatelessWidget {
  final String? photoUrl;
  final String type;
  final double size;
  const _VehicleThumb({this.photoUrl, required this.type, this.size = 50});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(photoUrl!, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(context)),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: _kBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
    child: Icon(type == 'bike' ? Icons.two_wheeler : Icons.directions_car, color: _kBlue, size: size * 0.55),
  );
}

class _InfoNote extends StatelessWidget {
  final String text;
  const _InfoNote(this.text);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFED7AA))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF92400E)))),
    ]),
  );
}

class _NoVehiclesPrompt extends StatelessWidget {
  final VoidCallback onAdd;
  const _NoVehiclesPrompt({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.directions_car_outlined, size: 64, color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(height: 16),
        Text('No vehicles saved', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 8),
        Text('Add a vehicle to continue booking', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _kBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          icon: const Icon(Icons.add),
          label: const Text('Add Vehicle'),
          onPressed: onAdd,
        ),
      ]),
    ),
  );
}

class _AddAddressPrompt extends StatelessWidget {
  final VoidCallback onAdd;
  const _AddAddressPrompt({required this.onAdd});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(children: [
      Icon(Icons.location_off, size: 40, color: Theme.of(context).colorScheme.outlineVariant),
      const SizedBox(height: 8),
      Text('No saved addresses', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
      const SizedBox(height: 4),
      TextButton(onPressed: onAdd, child: const Text('Add Address', style: TextStyle(color: _kBlue))),
    ]),
  );
}
