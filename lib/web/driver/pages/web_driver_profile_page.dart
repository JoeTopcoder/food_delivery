import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_constants.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/driver_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebDriverProfilePage extends ConsumerStatefulWidget {
  final String userId;
  final String driverId;
  const WebDriverProfilePage({super.key, required this.userId, required this.driverId});

  @override
  ConsumerState<WebDriverProfilePage> createState() => _WebDriverProfilePageState();
}

class _WebDriverProfilePageState extends ConsumerState<WebDriverProfilePage> {
  final _vehicleTypeCtrl  = TextEditingController();
  final _vehicleNumCtrl   = TextEditingController();
  final _licenseCtrl      = TextEditingController();
  bool _editing = false;
  bool _saving  = false;
  bool _init    = false;

  @override
  void dispose() {
    _vehicleTypeCtrl.dispose();
    _vehicleNumCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  void _initControllers(dynamic driver) {
    if (_init) return;
    _init = true;
    _vehicleTypeCtrl.text  = driver.vehicleType  ?? '';
    _vehicleNumCtrl.text   = driver.vehicleNumber ?? '';
    _licenseCtrl.text      = driver.licenseNumber ?? '';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final svc = ref.read(driverServiceProvider);
      await svc.updateDriverProfile(
        driverId: widget.driverId,
        vehicleType: _vehicleTypeCtrl.text.trim(),
        vehicleNumber: _vehicleNumCtrl.text.trim(),
        licenseNumber: _licenseCtrl.text.trim(),
      );
      if (!mounted) return;
      ref.invalidate(driverProfileProvider(widget.userId));
      setState(() { _editing = false; _saving = false; });
      AppSnackbar.success(context, 'Profile updated successfully');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState   = ref.watch(authNotifierProvider);
    final driverAsync = ref.watch(driverProfileProvider(widget.userId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My Profile', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const Text('Your driver account information', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
          const SizedBox(height: 28),

          driverAsync.when(
            loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(driverProfileProvider(widget.userId))),
            data: (driver) {
              if (driver == null) return const AppErrorState(message: 'Driver profile not found');
              _initControllers(driver);

              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Profile header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      child: Text(
                        (authState.user?.name ?? 'D').substring(0, 1).toUpperCase(),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF6366F1)),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(authState.user?.name ?? 'Driver', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                      const SizedBox(height: 2),
                      Text(authState.user?.email ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                      const SizedBox(height: 8),
                      Row(children: [
                        _Badge(driver.isAvailable ? 'Online' : 'Offline', driver.isAvailable ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                        const SizedBox(width: 8),
                        if (driver.rating != null) _Badge('${driver.rating!.toStringAsFixed(1)} ★', const Color(0xFFF59E0B)),
                        const SizedBox(width: 8),
                        _Badge('${driver.completedDeliveries ?? 0} deliveries', const Color(0xFF6366F1)),
                      ]),
                    ])),
                  ]),
                ),
                const SizedBox(height: 20),

                // Vehicle info card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Text('Vehicle Information', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                      const Spacer(),
                      if (!_editing)
                        TextButton.icon(
                          onPressed: () => setState(() => _editing = true),
                          icon: const Icon(Icons.edit_rounded, size: 16),
                          label: const Text('Edit'),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF6366F1)),
                        ),
                    ]),
                    const Divider(height: 20),
                    if (_editing) ...[
                      _Field('Vehicle Type', _vehicleTypeCtrl, 'e.g. Motorcycle, Car, Bicycle'),
                      const SizedBox(height: 14),
                      _Field('Vehicle Number', _vehicleNumCtrl, 'License plate number'),
                      const SizedBox(height: 14),
                      _Field('Driver\'s License', _licenseCtrl, 'License number'),
                      const SizedBox(height: 20),
                      Row(children: [
                        TextButton(
                          onPressed: _saving ? null : () => setState(() { _editing = false; _init = false; }),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _saving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Save Changes'),
                        ),
                      ]),
                    ] else ...[
                      _InfoRow(Icons.directions_car_rounded, 'Vehicle Type', driver.vehicleType ?? '—'),
                      const Divider(height: 20, color: Color(0xFFF1F5F9)),
                      _InfoRow(Icons.pin_rounded, 'Vehicle Number', driver.vehicleNumber ?? '—'),
                      const Divider(height: 20, color: Color(0xFFF1F5F9)),
                      _InfoRow(Icons.badge_rounded, 'Driver\'s License', driver.licenseNumber ?? '—'),
                    ],
                  ]),
                ),
                const SizedBox(height: 20),

                // Earnings summary card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Earnings Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                    const Divider(height: 20),
                    _InfoRow(Icons.account_balance_wallet_rounded, 'Total Paid Out',
                        '${AppConstants.currencySymbol}${(driver.totalPaidOut ?? 0).toStringAsFixed(2)}'),
                    const Divider(height: 20, color: Color(0xFFF1F5F9)),
                    _InfoRow(Icons.money_rounded, 'Cash Float',
                        '${AppConstants.currencySymbol}${(driver.cashFloat ?? 0).toStringAsFixed(2)}'),
                    const Divider(height: 20, color: Color(0xFFF1F5F9)),
                    _InfoRow(Icons.local_shipping_rounded, 'Completed Deliveries',
                        '${driver.completedDeliveries ?? 0}'),
                  ]),
                ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
    const SizedBox(width: 10),
    Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
    const Spacer(),
    Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
  ]);
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String hint;
  const _Field(this.label, this.ctrl, this.hint);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
    const SizedBox(height: 6),
    TextField(
      controller: ctrl,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
  ]);
}
