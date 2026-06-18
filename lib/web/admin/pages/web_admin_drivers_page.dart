import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/app_constants.dart';
import '../../../config/supabase_config.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/driver_provider.dart';
import '../../../models/driver_model.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebAdminDriversPage extends ConsumerStatefulWidget {
  const WebAdminDriversPage({super.key});

  @override
  ConsumerState<WebAdminDriversPage> createState() => _WebAdminDriversPageState();
}

class _WebAdminDriversPageState extends ConsumerState<WebAdminDriversPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  static const _tabs = ['All', 'Pending', 'Approved', 'Review'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(allDriversAdminProvider);
    ref.invalidate(pendingDriversProvider);
    ref.invalidate(approvedDriversProvider);
    ref.invalidate(rejectedDriversProvider);
    ref.invalidate(pendingVerificationDriversProvider);
  }

  Future<void> _verify(Driver d, bool approve) async {
    try {
      await ref.read(adminServiceProvider).verifyDriver(d.id, approve);
      _refresh();
      if (mounted) {
        AppSnackbar.show(
          context,
          message: approve ? 'Driver approved' : 'Driver rejected',
          type: approve ? AppSnackbarType.success : AppSnackbarType.warning,
        );
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  void _showVerifyConfirm(Driver d, bool approve) {
    final name = d.fullName ?? 'this driver';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(approve ? 'Approve Driver?' : d.isVerified == true ? 'Revoke Driver?' : 'Reject Driver?'),
        content: Text(approve
            ? 'Approve "$name"? They will be able to accept orders.'
            : d.isVerified == true
                ? 'Revoke approval for "$name"? They won\'t be able to accept orders.'
                : 'Reject "$name"? They will be notified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _verify(d, approve); },
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? const Color(0xFF10B981) : Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(approve ? 'Approve' : d.isVerified == true ? 'Revoke' : 'Reject'),
          ),
        ],
      ),
    );
  }

  void _showDetails(Driver d) {
    showDialog(
      context: context,
      builder: (_) => _DriverDetailsDialog(
        driver: d,
        onApprove: () => _showVerifyConfirm(d, true),
        onReject: () => _showVerifyConfirm(d, false),
        onCollect: () => _showCollectFloat(d),
      ),
    );
  }

  void _showCollectFloat(Driver d) {
    double? collectAmt;
    final float = d.cashFloat ?? 0;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Collect Cash Float'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current float: ${AppConstants.currencySymbol}${float.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 16),
              Row(children: [
                _QuickFloatBtn(label: 'Full', onTap: () => setS(() => collectAmt = null)),
                const SizedBox(width: 8),
                _QuickFloatBtn(label: '½', onTap: () => setS(() => collectAmt = float / 2)),
                const SizedBox(width: 8),
                _QuickFloatBtn(label: '¼', onTap: () => setS(() => collectAmt = float / 4)),
              ]),
              const SizedBox(height: 12),
              TextField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Custom amount',
                  prefixText: AppConstants.currencySymbol,
                  hintText: 'Full float if empty',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (v) => setS(() => collectAmt = double.tryParse(v)),
              ),
              if (collectAmt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Will collect: ${AppConstants.currencySymbol}${collectAmt!.toStringAsFixed(2)}',
                      style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  final driverService = ref.read(driverServiceProvider);
                  if (collectAmt != null) {
                    await driverService.collectFloat(d.id, amount: collectAmt);
                  } else {
                    await driverService.collectFloat(d.id);
                  }
                  _refresh();
                  if (mounted) AppSnackbar.success(context, 'Cash float collected');
                } catch (e) {
                  if (mounted) AppSnackbar.error(context, friendlyError(e));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Collect'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callDriver(Driver d) async {
    String? phone = d.phoneNumber;
    if (phone == null || phone.isEmpty) {
      // fallback: look up phone from users table
      try {
        final row = await SupabaseConfig.client
            .from('users')
            .select('phone')
            .eq('id', d.userId)
            .maybeSingle();
        phone = row?['phone'] as String?;
      } catch (_) {}
    }
    if (phone == null || phone.isEmpty) {
      if (mounted) AppSnackbar.show(context, message: 'No phone number on file', type: AppSnackbarType.warning);
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  void _showAddDriver() {
    showDialog(
      context: context,
      builder: (_) => _AddDriverDialog(
        onSaved: () { _refresh(); },
      ),
    );
  }

  Future<void> _reviewApplication(Map<String, dynamic> row, bool approve, {String? reason}) async {
    final driverId = row['id'] as String;
    try {
      await SupabaseConfig.client.rpc(
        'admin_review_driver_application',
        params: {
          'p_driver_id': driverId,
          'p_approved': approve,
          'p_approve_food_delivery': approve,
          'p_approve_ride_sharing': false,
          if (!approve && reason != null) 'p_rejection_reason': reason,
        },
      );
      // Fire-and-forget FCM notification
      SupabaseConfig.client.functions.invoke(
        'admin-review-driver',
        body: {
          'driver_id': driverId,
          'approved': approve,
          if (!approve && reason != null) 'rejection_reason': reason,
          'approve_food_delivery': approve,
          'approve_ride_sharing': false,
        },
      );
      _refresh();
      if (mounted) AppSnackbar.show(context, message: approve ? 'Application approved' : 'Application rejected', type: approve ? AppSnackbarType.success : AppSnackbarType.warning);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  void _showRejectReasonDialog(Map<String, dynamic> row) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rejection Reason'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Enter reason for rejection...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final reason = ctrl.text.trim();
              Navigator.pop(context);
              _reviewApplication(row, false, reason: reason.isEmpty ? null : reason);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allDriversAdminProvider((0, 200)));
    final pendingAsync = ref.watch(pendingDriversProvider);
    final approvedAsync = ref.watch(approvedDriversProvider);
    final reviewAsync = ref.watch(pendingVerificationDriversProvider);

    Widget body;
    if (_tab.index == 3) {
      body = reviewAsync.when(
        loading: () => const AppLoadingIndicator(),
        error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: _refresh),
        data: (rows) => rows.isEmpty
            ? const Center(child: Text('No pending applications', style: TextStyle(color: Color(0xFF94A3B8))))
            : _ReviewList(
                rows: rows,
                onApprove: (row) => _reviewApplication(row, true),
                onReject: (row) => _showRejectReasonDialog(row),
              ),
      );
    } else {
      final current = _tab.index == 0 ? allAsync : _tab.index == 1 ? pendingAsync : approvedAsync;
      body = current.when(
        loading: () => const AppLoadingIndicator(),
        error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: _refresh),
        data: (drivers) => drivers.isEmpty
            ? const Center(child: Text('No drivers found', style: TextStyle(color: Color(0xFF94A3B8))))
            : _DriversTable(
                drivers: drivers,
                onApprove: (d) => _showVerifyConfirm(d, true),
                onReject: (d) => _showVerifyConfirm(d, false),
                onDetails: _showDetails,
                onCall: _callDriver,
                onCollect: _showCollectFloat,
              ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Drivers', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                  Text('Manage delivery drivers', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: _refresh),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showAddDriver,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Driver'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Tabs ──────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
            ),
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(10)),
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              padding: const EdgeInsets.all(6),
              tabs: _tabs.map((t) => Tab(text: t)).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // ── Content ───────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Drivers Table (All / Pending / Approved tabs) ─────────────────────────────

class _DriversTable extends StatelessWidget {
  final List<Driver> drivers;
  final ValueChanged<Driver> onApprove;
  final ValueChanged<Driver> onReject;
  final ValueChanged<Driver> onDetails;
  final ValueChanged<Driver> onCall;
  final ValueChanged<Driver> onCollect;

  const _DriversTable({
    required this.drivers,
    required this.onApprove,
    required this.onReject,
    required this.onDetails,
    required this.onCall,
    required this.onCollect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          ),
          child: const Row(
            children: [
              Expanded(flex: 2, child: _Th('Driver')),
              Expanded(child: _Th('Vehicle')),
              SizedBox(width: 70, child: _Th('Rating')),
              SizedBox(width: 80, child: _Th('Trips')),
              SizedBox(width: 80, child: _Th('Float')),
              SizedBox(width: 90, child: _Th('Status')),
              SizedBox(width: 48),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        Expanded(
          child: ListView.separated(
            itemCount: drivers.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
            itemBuilder: (_, i) {
              final d = drivers[i];
              final hasFloat = (d.cashFloat ?? 0) > 0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    // Name + phone
                    Expanded(
                      flex: 2,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          d.fullName ?? 'Driver',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (d.phoneNumber != null && d.phoneNumber!.isNotEmpty)
                          InkWell(
                            onTap: () => onCall(d),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.call_rounded, size: 12, color: Color(0xFF10B981)),
                              const SizedBox(width: 3),
                              Text(d.phoneNumber!, style: const TextStyle(fontSize: 11, color: Color(0xFF10B981))),
                            ]),
                          ),
                      ]),
                    ),
                    // Vehicle
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(d.vehicleType ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B))),
                        if (d.vehicleNumber != null || d.plateNumber != null || d.licensePlate != null)
                          Text(d.vehicleNumber ?? d.plateNumber ?? d.licensePlate ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                      ]),
                    ),
                    // Rating
                    SizedBox(
                      width: 70,
                      child: Row(children: [
                        const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(d.rating?.toStringAsFixed(1) ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ]),
                    ),
                    SizedBox(width: 80, child: Text('${d.completedDeliveries ?? 0}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
                    // Cash float
                    SizedBox(
                      width: 80,
                      child: hasFloat
                          ? Text(
                              '${AppConstants.currencySymbol}${(d.cashFloat!).toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                            )
                          : const Text('—', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    ),
                    SizedBox(width: 90, child: _DriverStatusBadge(isAvailable: d.isAvailable, isVerified: d.isVerified ?? false)),
                    SizedBox(
                      width: 48,
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF9CA3AF)),
                        onSelected: (action) {
                          switch (action) {
                            case 'details': onDetails(d); break;
                            case 'call': onCall(d); break;
                            case 'collect': onCollect(d); break;
                            case 'approve': onApprove(d); break;
                            case 'reject': onReject(d); break;
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'details', child: Row(children: [Icon(Icons.info_outline_rounded, size: 18), SizedBox(width: 8), Text('View Details')])),
                          const PopupMenuItem(value: 'call', child: Row(children: [Icon(Icons.call_rounded, size: 18, color: Color(0xFF10B981)), SizedBox(width: 8), Text('Call', style: TextStyle(color: Color(0xFF10B981)))])),
                          if (hasFloat)
                            const PopupMenuItem(value: 'collect', child: Row(children: [Icon(Icons.payments_rounded, size: 18, color: Color(0xFF0EA5E9)), SizedBox(width: 8), Text('Collect Float', style: TextStyle(color: Color(0xFF0EA5E9)))])),
                          if (d.isVerified != true)
                            const PopupMenuItem(value: 'approve', child: Row(children: [Icon(Icons.verified_rounded, size: 18, color: Color(0xFF10B981)), SizedBox(width: 8), Text('Approve', style: TextStyle(color: Color(0xFF10B981)))])),
                          PopupMenuItem(
                            value: 'reject',
                            child: Row(children: [
                              const Icon(Icons.block_rounded, size: 18, color: Colors.red),
                              const SizedBox(width: 8),
                              Text(d.isVerified == true ? 'Revoke Approval' : 'Reject', style: const TextStyle(color: Colors.red)),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Review Tab (pending verification applications) ─────────────────────────────

class _ReviewList extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final ValueChanged<Map<String, dynamic>> onApprove;
  final ValueChanged<Map<String, dynamic>> onReject;

  const _ReviewList({required this.rows, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          ),
          child: const Row(
            children: [
              Expanded(flex: 2, child: _Th('Applicant')),
              Expanded(child: _Th('Service Type')),
              Expanded(child: _Th('Status')),
              SizedBox(width: 160),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
            itemBuilder: (_, i) {
              final row = rows[i];
              final user = row['users'] as Map<String, dynamic>?;
              final name = (user?['name'] as String?) ?? 'Unknown';
              final email = (user?['email'] as String?) ?? '';
              final status = (row['driver_status'] as String?) ?? 'pending_review';
              final serviceType = (row['service_type'] as String?) ?? 'food_delivery';

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis),
                        Text(email, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)), overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                    Expanded(child: Text(serviceType.replaceAll('_', ' '), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
                    Expanded(child: _ReviewStatusBadge(status: status)),
                    SizedBox(
                      width: 160,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => onReject(row),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Reject', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => onApprove(row),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Approve', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Driver Details Dialog ──────────────────────────────────────────────────────

class _DriverDetailsDialog extends StatelessWidget {
  final Driver driver;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onCollect;

  const _DriverDetailsDialog({
    required this.driver,
    required this.onApprove,
    required this.onReject,
    required this.onCollect,
  });

  @override
  Widget build(BuildContext context) {
    final d = driver;
    final isVerified = d.isVerified == true;
    final hasFloat = (d.cashFloat ?? 0) > 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
              child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: isVerified ? const Color(0xFF10B981).withValues(alpha: 0.12) : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.person_rounded, color: isVerified ? const Color(0xFF10B981) : const Color(0xFFF59E0B), size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.fullName ?? 'Driver', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B))),
                    Text(d.vehicleType ?? 'N/A', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                  ]),
                ),
                _DriverStatusBadge(isAvailable: d.isAvailable, isVerified: isVerified),
                const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('Driver Info', [
                      _item('Phone', d.phoneNumber ?? 'N/A'),
                      _item('Home Address', d.homeAddress ?? 'N/A'),
                      _item('License Number', d.licenseNumber ?? 'N/A'),
                      _item('Service Type', d.serviceType),
                      _item('Status', d.driverStatus),
                    ]),
                    const SizedBox(height: 12),
                    _section('Vehicle', [
                      _item('Type', d.vehicleType ?? 'N/A'),
                      _item('Number', d.vehicleNumber ?? 'N/A'),
                      _item('Plate', d.plateNumber ?? d.licensePlate ?? 'N/A'),
                      _item('Brand / Make', d.vehicleBrand ?? d.vehicleMake ?? 'N/A'),
                      _item('Model', d.vehicleModel ?? 'N/A'),
                      _item('Color', d.vehicleColor ?? 'N/A'),
                    ]),
                    const SizedBox(height: 12),
                    _section('Performance', [
                      _item('Rating', d.rating?.toStringAsFixed(2) ?? '0.00'),
                      _item('Completed Trips', '${d.completedDeliveries ?? 0}'),
                      _item('Cancelled Trips', '${d.cancelledDeliveries ?? 0}'),
                      _item('Total Earnings', '${AppConstants.currencySymbol}${d.totalEarnings?.toStringAsFixed(2) ?? "0.00"}'),
                      _item('Total Paid Out', '${AppConstants.currencySymbol}${d.totalPaidOut?.toStringAsFixed(2) ?? "0.00"}'),
                      _item('Cash Float', '${AppConstants.currencySymbol}${(d.cashFloat ?? 0).toStringAsFixed(2)}'),
                    ]),
                    const SizedBox(height: 12),
                    _section('Banking', [
                      _item('Bank', d.bankName ?? 'N/A'),
                      _item('Branch', d.bankBranch ?? 'N/A'),
                      _item('Account Holder', d.bankAccountHolder ?? 'N/A'),
                      _item('Account Number', d.bankAccountNumber ?? 'N/A'),
                      _item('Account Type', d.bankAccountType ?? 'N/A'),
                    ]),
                    const SizedBox(height: 12),
                    _section('Stripe', [
                      _item('Account ID', d.stripeAccountId ?? 'N/A'),
                      _item('Payouts Enabled', d.payoutsEnabled ? 'Yes' : 'No'),
                      _item('Debit Card Added', d.stripeDebitCardAdded ? 'Yes' : 'No'),
                      _item('Account Status', d.stripeAccountStatus ?? 'N/A'),
                    ]),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                if (hasFloat) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(context); onCollect(); },
                      icon: const Icon(Icons.payments_rounded, size: 16),
                      label: const Text('Collect Float'),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF0EA5E9), side: const BorderSide(color: Color(0xFF0EA5E9)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: () { Navigator.pop(context); onReject(); },
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: Text(isVerified ? 'Revoke' : 'Reject'),
                  ),
                ),
                if (!isVerified) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () { Navigator.pop(context); onApprove(); },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: const Text('Approve Driver'),
                    ),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
          child: Column(children: List.generate(rows.length, (i) => Column(children: [
            rows[i],
            if (i < rows.length - 1) const Divider(height: 1, color: Color(0xFFE2E8F0), indent: 16),
          ]))),
        ),
      ],
    );
  }

  Widget _item(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)), textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ── Add Driver Dialog ──────────────────────────────────────────────────────────

class _AddDriverDialog extends ConsumerStatefulWidget {
  final VoidCallback onSaved;
  const _AddDriverDialog({required this.onSaved});

  @override
  ConsumerState<_AddDriverDialog> createState() => _AddDriverDialogState();
}

class _AddDriverDialogState extends ConsumerState<_AddDriverDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _vehicleNumCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  String _vehicleType = 'motorcycle';
  bool _loading = false;

  static const _vehicleTypes = ['motorcycle', 'car', 'bicycle', 'scooter', 'truck', 'van'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _vehicleNumCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(adminServiceProvider).createUserWithRole(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        role: AppConstants.roleDriver,
        vehicleType: _vehicleType,
        vehicleNumber: _vehicleNumCtrl.text.trim(),
        licenseNumber: _licenseCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        AppSnackbar.success(context, 'Driver account created');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
              child: Row(children: [
                const Expanded(child: Text('Add Driver', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Divider(height: 20),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: Column(children: [
                    _field(_nameCtrl, 'Full Name', required: true),
                    const SizedBox(height: 12),
                    _field(_emailCtrl, 'Email', keyboardType: TextInputType.emailAddress, required: true),
                    const SizedBox(height: 12),
                    _field(_passwordCtrl, 'Password', obscure: true, required: true),
                    const SizedBox(height: 12),
                    _field(_phoneCtrl, 'Phone Number', keyboardType: TextInputType.phone),
                    const SizedBox(height: 16),
                    Align(alignment: Alignment.centerLeft, child: Text('Vehicle Type', style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w600))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: _vehicleTypes.map((t) {
                        final selected = _vehicleType == t;
                        return ChoiceChip(
                          label: Text(t, style: TextStyle(fontSize: 12, color: selected ? Colors.white : const Color(0xFF64748B))),
                          selected: selected,
                          selectedColor: const Color(0xFF10B981),
                          onSelected: (_) => setState(() => _vehicleType = t),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _field(_vehicleNumCtrl, 'Vehicle Number / Plate'),
                    const SizedBox(height: 12),
                    _field(_licenseCtrl, 'License Number'),
                    const SizedBox(height: 20),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create Driver Account', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {
    TextInputType? keyboardType,
    bool obscure = false,
    bool required = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _QuickFloatBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickFloatBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _DriverStatusBadge extends StatelessWidget {
  final bool isAvailable;
  final bool isVerified;
  const _DriverStatusBadge({required this.isAvailable, required this.isVerified});

  @override
  Widget build(BuildContext context) {
    final label = !isVerified ? 'Pending' : isAvailable ? 'Available' : 'Busy';
    final color = !isVerified ? const Color(0xFFF59E0B) : isAvailable ? const Color(0xFF10B981) : const Color(0xFF6366F1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _ReviewStatusBadge extends StatelessWidget {
  final String status;
  const _ReviewStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final label = status == 'under_review' ? 'Under Review' : 'Pending Review';
    final color = status == 'under_review' ? const Color(0xFF6366F1) : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _Th extends StatelessWidget {
  final String text;
  const _Th(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.5));
}
