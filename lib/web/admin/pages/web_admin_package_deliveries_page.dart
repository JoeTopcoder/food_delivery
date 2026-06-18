import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/app_constants.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _webPackageOverviewProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final client = Supabase.instance.client;
  final midnight = DateTime.now();
  final midnightStr = DateTime(midnight.year, midnight.month, midnight.day).toIso8601String();

  final activeRes = await client
      .from('package_delivery_requests')
      .select('id')
      .not('delivery_status', 'in', '("delivered","cancelled","failed")');
  final activeCount = (activeRes as List).length;

  final deliveredRes = await client
      .from('package_delivery_requests')
      .select('id')
      .eq('delivery_status', 'delivered')
      .gte('delivered_at', midnightStr);
  final deliveredToday = (deliveredRes as List).length;

  final revenueRes = await client
      .from('package_delivery_requests')
      .select('delivery_fee')
      .eq('delivery_status', 'delivered')
      .gte('delivered_at', midnightStr);
  double revenueToday = 0;
  for (final row in (revenueRes as List)) {
    revenueToday += ((row['delivery_fee'] as num?) ?? 0).toDouble();
  }

  return {
    'active_count': activeCount,
    'delivered_today': deliveredToday,
    'revenue_today': revenueToday,
  };
});

final _webPackageDeliveriesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await Supabase.instance.client
      .from('package_delivery_requests')
      .select('*, shipping_companies(name)')
      .order('created_at', ascending: false)
      .limit(200);
  return List<Map<String, dynamic>>.from(data as List);
});

// ── Page ─────────────────────────────────────────────────────────────────────

class WebAdminPackageDeliveriesPage extends ConsumerStatefulWidget {
  const WebAdminPackageDeliveriesPage({super.key});

  @override
  ConsumerState<WebAdminPackageDeliveriesPage> createState() => _WebAdminPackageDeliveriesPageState();
}

class _WebAdminPackageDeliveriesPageState extends ConsumerState<WebAdminPackageDeliveriesPage> {
  String _statusFilter = 'all';
  String _search = '';

  static const _statuses = [
    ('all', 'All'),
    ('pending', 'Pending'),
    ('picked_up', 'Picked Up'),
    ('in_transit', 'In Transit'),
    ('delivered', 'Delivered'),
    ('cancelled', 'Cancelled'),
    ('failed', 'Failed'),
  ];

  @override
  Widget build(BuildContext context) {
    final overviewAsync = ref.watch(_webPackageOverviewProvider);
    final deliveriesAsync = ref.watch(_webPackageDeliveriesProvider);
    final sym = AppConstants.currencySymbol;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Package Deliveries', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Track all package and courier deliveries', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () {
              ref.invalidate(_webPackageOverviewProvider);
              ref.invalidate(_webPackageDeliveriesProvider);
            }),
          ]),
          const SizedBox(height: 24),

          // ── KPI strip ──────────────────────────────────────────────────
          overviewAsync.when(
            loading: () => const SizedBox(height: 80, child: AppLoadingIndicator()),
            error: (_, __) => const SizedBox.shrink(),
            data: (d) => Row(children: [
              _KpiTile(icon: Icons.local_shipping_rounded, color: const Color(0xFF7C3AED), label: 'Active', value: '${d['active_count']}'),
              const SizedBox(width: 16),
              _KpiTile(icon: Icons.check_circle_rounded, color: const Color(0xFF10B981), label: 'Delivered Today', value: '${d['delivered_today']}'),
              const SizedBox(width: 16),
              _KpiTile(icon: Icons.attach_money_rounded, color: const Color(0xFFF59E0B), label: "Today's Revenue", value: '$sym${(d['revenue_today'] as double).toStringAsFixed(2)}'),
            ]),
          ),
          const SizedBox(height: 24),

          // ── Filters ────────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Search by tracking ID, sender, recipient…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                  filled: true, fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 2)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: _statuses.map((s) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(s.$2),
                selected: _statusFilter == s.$1,
                onSelected: (_) => setState(() => _statusFilter = s.$1),
                selectedColor: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: _statusFilter == s.$1 ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                ),
              ),
            )).toList()),
          ),
          const SizedBox(height: 16),

          // ── Table ──────────────────────────────────────────────────────
          deliveriesAsync.when(
            loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(_webPackageDeliveriesProvider)),
            data: (all) {
              var list = all;
              if (_statusFilter != 'all') list = list.where((d) => d['delivery_status'] == _statusFilter).toList();
              if (_search.isNotEmpty) {
                final q = _search.toLowerCase();
                list = list.where((d) {
                  return (d['tracking_number'] ?? '').toString().toLowerCase().contains(q)
                    || (d['sender_name'] ?? '').toString().toLowerCase().contains(q)
                    || (d['recipient_name'] ?? '').toString().toLowerCase().contains(q);
                }).toList();
              }
              if (list.isEmpty) {
                return Container(
                  height: 200,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: const AppEmptyState(icon: Icons.inventory_2_rounded, title: 'No deliveries found'),
                );
              }
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
                    child: const Row(children: [
                      Expanded(flex: 2, child: Text('Tracking #', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 2, child: Text('Sender', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 2, child: Text('Recipient', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 2, child: Text('Company', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 1, child: Text('Fee', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 2, child: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                      Expanded(flex: 2, child: Text('Created', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF64748B)))),
                    ]),
                  ),
                  const Divider(height: 1),
                  ...list.asMap().entries.map((e) => _DeliveryRow(delivery: e.value, isLast: e.key == list.length - 1, sym: sym)),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── KPI Tile ──────────────────────────────────────────────────────────────────

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _KpiTile({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        ]),
      ]),
    ),
  );
}

// ── Delivery Row ──────────────────────────────────────────────────────────────

class _DeliveryRow extends StatelessWidget {
  final Map<String, dynamic> delivery;
  final bool isLast;
  final String sym;
  const _DeliveryRow({required this.delivery, required this.isLast, required this.sym});

  @override
  Widget build(BuildContext context) {
    final status = delivery['delivery_status'] ?? 'unknown';
    final createdAt = DateTime.tryParse(delivery['created_at'] ?? '');
    final fee = (delivery['delivery_fee'] as num?)?.toDouble() ?? 0;
    final companyName = (delivery['shipping_companies'] as Map?)?['name'] ?? '—';

    return Container(
      decoration: BoxDecoration(border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(children: [
          Expanded(flex: 2, child: Text(
            delivery['tracking_number'] ?? '—',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF7C3AED)),
            overflow: TextOverflow.ellipsis,
          )),
          Expanded(flex: 2, child: Text(delivery['sender_name'] ?? '—',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(delivery['recipient_name'] ?? '—',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(companyName,
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 1, child: Text('$sym${fee.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)))),
          Expanded(flex: 2, child: _StatusBadge(status: status)),
          Expanded(flex: 2, child: Text(
            createdAt != null ? DateFormat('MMM d, h:mm a').format(createdAt.toLocal()) : '—',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          )),
        ]),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  static const _colors = <String, (Color, Color)>{
    'pending':     (Color(0xFFF59E0B), Color(0xFFFFFBEB)),
    'picked_up':   (Color(0xFF6366F1), Color(0xFFEEF2FF)),
    'in_transit':  (Color(0xFF0EA5E9), Color(0xFFF0F9FF)),
    'delivered':   (Color(0xFF10B981), Color(0xFFECFDF5)),
    'cancelled':   (Color(0xFF94A3B8), Color(0xFFF1F5F9)),
    'failed':      (Color(0xFFEF4444), Color(0xFFFEF2F2)),
  };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _colors[status] ?? (const Color(0xFF94A3B8), const Color(0xFFF1F5F9));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status.replaceAll('_', ' '),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
