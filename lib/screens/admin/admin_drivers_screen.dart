import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/driver_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/driver_provider.dart';
import '../../config/app_constants.dart';
import '../../config/supabase_config.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class AdminDriversScreen extends ConsumerStatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  ConsumerState<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends ConsumerState<AdminDriversScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(allDriversAdminProvider);
    ref.invalidate(pendingDriversProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Driver Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'All Drivers'),
            Tab(text: 'Pending'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDriverDialog(context),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text(
          'Add Driver',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DriverList(
            asyncValue: ref.watch(allDriversAdminProvider((0, 100))),
            onRefresh: _refresh,
            showVerifyActions: true,
            ref: ref,
          ),
          _DriverList(
            asyncValue: ref.watch(pendingDriversProvider),
            onRefresh: _refresh,
            showVerifyActions: true,
            ref: ref,
            emptyMessage: 'No drivers pending verification',
            emptyIcon: Icons.check_circle_outline,
          ),
        ],
      ),
    );
  }

  void _showCreateDriverDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _CreateDriverDialog(
        onCreated: () {
          _refresh();
          ref.invalidate(driverStatisticsProvider);
        },
        ref: ref,
      ),
    );
  }
}

class _DriverList extends StatelessWidget {
  final AsyncValue<List<Driver>> asyncValue;
  final Future<void> Function() onRefresh;
  final bool showVerifyActions;
  final WidgetRef ref;
  final String emptyMessage;
  final IconData emptyIcon;

  const _DriverList({
    required this.asyncValue,
    required this.onRefresh,
    required this.showVerifyActions,
    required this.ref,
    this.emptyMessage = 'No drivers found',
    this.emptyIcon = Icons.directions_bike_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.primaryColor,
      child: asyncValue.when(
        data: (drivers) {
          if (drivers.isEmpty) {
            return AppEmptyState(icon: emptyIcon, title: emptyMessage);
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: drivers.length,
            itemBuilder: (context, index) {
              final driver = drivers[index];
              final isVerified = driver.isVerified == true;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Icon
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isVerified
                                  ? const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.12)
                                  : const Color(
                                      0xFFF59E0B,
                                    ).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.directions_bike_rounded,
                              color: isVerified
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driver.vehicleNumber?.isNotEmpty == true
                                      ? driver.vehicleNumber!
                                      : 'No vehicle number',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  driver.vehicleType?.isNotEmpty == true
                                      ? (driver.vehicleType![0].toUpperCase() +
                                            driver.vehicleType!.substring(1))
                                      : 'Unknown type',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _StatusBadge(isVerified: isVerified),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.call_rounded,
                              color: Color(0xFF10B981),
                              size: 20,
                            ),
                            tooltip: 'Call driver',
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                            onPressed: () async {
                              try {
                                final userData = await SupabaseConfig.client
                                    .from('users')
                                    .select('phone')
                                    .eq('id', driver.userId)
                                    .maybeSingle();
                                final phone = userData?['phone'] as String?;
                                if (phone != null && phone.isNotEmpty) {
                                  launchUrl(Uri(scheme: 'tel', path: phone));
                                } else {
                                  if (context.mounted) {
                                    AppSnackbar.warning(
                                      context,
                                      'No phone number on file for this driver',
                                    );
                                  }
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  AppSnackbar.error(
                                    context,
                                    'Could not retrieve driver phone number',
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                      const SizedBox(height: 10),

                      // Stats row
                      Row(
                        children: [
                          _DriverStat(
                            icon: Icons.star_rounded,
                            color: const Color(0xFFF59E0B),
                            value: driver.rating?.toStringAsFixed(1) ?? '0.0',
                            label: 'Rating',
                          ),
                          const SizedBox(width: 16),
                          _DriverStat(
                            icon: Icons.check_circle_rounded,
                            color: const Color(0xFF10B981),
                            value: '${driver.completedDeliveries ?? 0}',
                            label: 'Deliveries',
                          ),
                          const SizedBox(width: 16),
                          _DriverStat(
                            icon: Icons.badge_rounded,
                            color: const Color(0xFF6366F1),
                            value: driver.licenseNumber?.isNotEmpty == true
                                ? driver.licenseNumber!
                                : 'N/A',
                            label: 'License',
                          ),
                        ],
                      ),

                      // Cash Float row
                      if ((driver.cashFloat ?? 0) > 0) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFF87171)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.account_balance_wallet_rounded,
                                color: Color(0xFFDC2626),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Cash Float',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF991B1B),
                                      ),
                                    ),
                                    Text(
                                      '${AppConstants.currencySymbol}${driver.cashFloat!.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 34,
                                child: ElevatedButton.icon(
                                  onPressed: () => _showCollectFloatDialog(
                                    context,
                                    driver,
                                    ref,
                                  ),
                                  icon: const Icon(
                                    Icons.payments_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Collect',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFDC2626),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (!isVerified) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _confirmAction(
                                  context,
                                  driver.id,
                                  driver.vehicleNumber ?? 'this driver',
                                  false,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _confirmAction(
                                  context,
                                  driver.id,
                                  driver.vehicleNumber ?? 'this driver',
                                  true,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text('Verify'),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => _confirmAction(
                              context,
                              driver.id,
                              driver.vehicleNumber ?? 'this driver',
                              false,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Revoke Verification'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const AppLoadingIndicator(message: 'Loading drivers…'),
        error: (e, _) =>
            AppErrorState(message: friendlyError(e), onRetry: onRefresh),
      ),
    );
  }

  void _confirmAction(
    BuildContext context,
    String driverId,
    String driverName,
    bool verify,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(verify ? 'Verify Driver?' : 'Reject/Revoke Driver?'),
        content: Text(
          verify
              ? 'Verify "$driverName"? They will be able to accept deliveries.'
              : 'Remove verification from "$driverName"? They won\'t be able to accept deliveries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await ref
                    .read(adminServiceProvider)
                    .verifyDriver(driverId, verify);
                ref.invalidate(allDriversAdminProvider);
                ref.invalidate(pendingDriversProvider);
                ref.invalidate(driverStatisticsProvider);
                if (context.mounted) {
                  if (verify) {
                    AppSnackbar.success(
                      context,
                      '$driverName verified successfully',
                    );
                  } else {
                    AppSnackbar.warning(
                      context,
                      '$driverName rejected successfully',
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  AppSnackbar.error(context, friendlyError(e));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: verify ? const Color(0xFF10B981) : Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(verify ? 'Verify' : 'Reject'),
          ),
        ],
      ),
    );
  }

  void _showCollectFloatDialog(
    BuildContext context,
    Driver driver,
    WidgetRef ref,
  ) {
    final floatAmount = driver.cashFloat ?? 0.0;
    final amountCtrl = TextEditingController(
      text: floatAmount.toStringAsFixed(0),
    );
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Collect Cash Float'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Driver: ${driver.vehicleNumber ?? driver.id.substring(0, 8)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Outstanding Float: \$${floatAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount to collect',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    helperText: 'Enter partial or full amount',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _FloatQuickBtn(
                      label: 'Full',
                      onTap: () {
                        amountCtrl.text = floatAmount.toStringAsFixed(0);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    _FloatQuickBtn(
                      label: 'Half',
                      onTap: () {
                        amountCtrl.text = (floatAmount / 2).toStringAsFixed(0);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    _FloatQuickBtn(
                      label: 'Quarter',
                      onTap: () {
                        amountCtrl.text = (floatAmount / 4).toStringAsFixed(0);
                        setDialogState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final collectAmt =
                      double.tryParse(amountCtrl.text.trim()) ?? 0;
                  if (collectAmt <= 0) return;
                  if (collectAmt > floatAmount) {
                    AppSnackbar.warning(
                      context,
                      'Amount exceeds outstanding float',
                    );
                    return;
                  }
                  Navigator.of(context).pop();
                  try {
                    final driverService = ref.read(driverServiceProvider);
                    if (collectAmt >= floatAmount) {
                      await driverService.collectFloat(driver.id);
                    } else {
                      await driverService.collectFloat(
                        driver.id,
                        amount: collectAmt,
                      );
                    }
                    ref.invalidate(allDriversAdminProvider);
                    ref.invalidate(pendingDriversProvider);
                    if (context.mounted) {
                      AppSnackbar.success(
                        context,
                        '${AppConstants.currencySymbol}${collectAmt.toStringAsFixed(0)} float collected successfully',
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      AppSnackbar.error(context, friendlyError(e));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Collect'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FloatQuickBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FloatQuickBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isVerified;
  const _StatusBadge({required this.isVerified});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isVerified
            ? const Color(0xFF10B981).withValues(alpha: 0.1)
            : const Color(0xFFF59E0B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVerified ? Icons.verified_rounded : Icons.hourglass_top_rounded,
            size: 12,
            color: isVerified
                ? const Color(0xFF10B981)
                : const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 4),
          Text(
            isVerified ? 'Verified' : 'Pending',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isVerified
                  ? const Color(0xFF10B981)
                  : const Color(0xFFF59E0B),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _DriverStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Create Driver Dialog ─────────────────────────────────────────────────────

class _CreateDriverDialog extends StatefulWidget {
  final VoidCallback onCreated;
  final WidgetRef ref;
  const _CreateDriverDialog({required this.onCreated, required this.ref});

  @override
  State<_CreateDriverDialog> createState() => _CreateDriverDialogState();
}

class _CreateDriverDialogState extends State<_CreateDriverDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _vehicleNumberCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  String _vehicleType = 'motorcycle';
  bool _creating = false;
  bool _obscurePassword = true;

  static const _vehicleTypes = [
    ('motorcycle', 'Motorcycle', Icons.two_wheeler_rounded),
    ('bike', 'Bike', Icons.pedal_bike_rounded),
    ('car', 'Car', Icons.directions_car_rounded),
    ('scooter', 'Scooter', Icons.electric_scooter_rounded),
    ('bicycle', 'Bicycle', Icons.directions_bike_rounded),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _vehicleNumberCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _creating = true);

    try {
      final adminService = widget.ref.read(adminServiceProvider);
      await adminService.createUserWithRole(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        role: AppConstants.roleDriver,
        vehicleType: _vehicleType,
        vehicleNumber: _vehicleNumberCtrl.text.trim(),
        licenseNumber: _licenseCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCreated();

      AppSnackbar.success(
        context,
        'Driver ${_nameCtrl.text.trim()} created successfully',
      );
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.contains('Exception: ')) {
        msg = msg.replaceFirst(RegExp(r'^Exception:\s*'), '');
      }
      AppSnackbar.error(context, 'Error: $msg');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add_rounded,
                      color: AppTheme.primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Create Driver',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Name
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDecoration('Full Name', Icons.person_outline),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),

              // Email
              TextFormField(
                controller: _emailCtrl,
                decoration: _inputDecoration('Email', Icons.email_outlined),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email is required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Password
              TextFormField(
                controller: _passwordCtrl,
                decoration: _inputDecoration('Password', Icons.lock_outline)
                    .copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                obscureText: _obscurePassword,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 6) return 'Minimum 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Phone
              TextFormField(
                controller: _phoneCtrl,
                decoration: _inputDecoration('Phone', Icons.phone_outlined),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),

              // Vehicle Type
              const Text(
                'Vehicle Type',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _vehicleTypes.map((vt) {
                  final selected = _vehicleType == vt.$1;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          vt.$3,
                          size: 16,
                          color: selected
                              ? Colors.white
                              : const Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 4),
                        Text(vt.$2),
                      ],
                    ),
                    selected: selected,
                    selectedColor: AppTheme.primaryColor,
                    backgroundColor: const Color(0xFFF3F4F6),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF374151),
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onSelected: (_) => setState(() => _vehicleType = vt.$1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Vehicle Number
              TextFormField(
                controller: _vehicleNumberCtrl,
                decoration: _inputDecoration(
                  'Vehicle Number',
                  Icons.badge_outlined,
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 14),

              // License
              TextFormField(
                controller: _licenseCtrl,
                decoration: _inputDecoration(
                  'License Number',
                  Icons.card_membership_outlined,
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 24),

              // Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _creating ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _creating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Create Driver',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
