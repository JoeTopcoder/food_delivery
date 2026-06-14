import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/admin_provider.dart';
import '../../../models/driver_model.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebAdminDriversPage extends ConsumerStatefulWidget {
  const WebAdminDriversPage({super.key});

  @override
  ConsumerState<WebAdminDriversPage> createState() => _WebAdminDriversPageState();
}

class _WebAdminDriversPageState extends ConsumerState<WebAdminDriversPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allDriversAdminProvider((0, 100)));
    final pendingAsync = ref.watch(pendingDriversProvider);
    final approvedAsync = ref.watch(approvedDriversProvider);

    final current = _tab.index == 0 ? allAsync : _tab.index == 1 ? pendingAsync : approvedAsync;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Drivers', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const Text('Manage delivery drivers', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
          const SizedBox(height: 20),

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
              tabs: const [Tab(text: 'All'), Tab(text: 'Pending'), Tab(text: 'Approved')],
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: current.when(
                loading: () => const AppLoadingIndicator(),
                error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () {
                  ref.invalidate(allDriversAdminProvider);
                  ref.invalidate(pendingDriversProvider);
                }),
                data: (drivers) => drivers.isEmpty
                    ? const Center(child: Text('No drivers found', style: TextStyle(color: Color(0xFF94A3B8))))
                    : _DriversTable(
                        drivers: drivers,
                        showActions: _tab.index == 1,
                        onApprove: (d) => _verify(d, true),
                        onReject: (d) => _verify(d, false),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verify(Driver d, bool approve) async {
    try {
      await ref.read(adminServiceProvider).verifyDriver(d.id, approve);
      ref.invalidate(allDriversAdminProvider);
      ref.invalidate(pendingDriversProvider);
      ref.invalidate(approvedDriversProvider);
      if (mounted) AppSnackbar.show(context, message: approve ? 'Driver approved' : 'Driver rejected', type: approve ? AppSnackbarType.success : AppSnackbarType.error);
    } catch (e) {
      if (mounted) AppSnackbar.show(context, message: friendlyError(e), type: AppSnackbarType.error);
    }
  }
}

class _DriversTable extends StatelessWidget {
  final List<Driver> drivers;
  final bool showActions;
  final ValueChanged<Driver> onApprove;
  final ValueChanged<Driver> onReject;

  const _DriversTable({required this.drivers, required this.showActions, required this.onApprove, required this.onReject});

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
          child: Row(
            children: [
              const Expanded(child: _Th('User ID')),
              const Expanded(child: _Th('Vehicle')),
              const Expanded(child: _Th('Rating')),
              const Expanded(child: _Th('Deliveries')),
              const Expanded(child: _Th('Status')),
              if (showActions) const SizedBox(width: 120),
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
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: Text(d.userId.substring(0, 8), style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFF1E293B)))),
                    Expanded(child: Text(d.vehicleType ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)))),
                    Expanded(child: Row(children: [
                      const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      Text(d.rating?.toStringAsFixed(1) ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                    ])),
                    Expanded(child: Text('${d.completedDeliveries ?? 0}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)))),
                    Expanded(child: _DriverStatusBadge(isAvailable: d.isAvailable, isVerified: d.isVerified ?? false)),
                    if (showActions) SizedBox(
                      width: 120,
                      child: Row(
                        children: [
                          _ActionBtn(label: '✓', color: const Color(0xFF10B981), onTap: () => onApprove(d)),
                          const SizedBox(width: 6),
                          _ActionBtn(label: '✕', color: const Color(0xFFEF4444), onTap: () => onReject(d)),
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

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }
}

class _Th extends StatelessWidget {
  final String text;
  const _Th(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.5));
}
