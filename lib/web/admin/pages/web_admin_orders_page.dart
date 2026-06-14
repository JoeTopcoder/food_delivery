import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../../config/supabase_config.dart';
import '../../../config/app_constants.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _webOrdersRealtimeProvider = Provider.autoDispose<void>((ref) {
  final ch = SupabaseConfig.client
      .channel('web_admin_orders')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        callback: (_) => ref.invalidate(_webAllOrdersProvider),
      )
      .subscribe();
  ref.onDispose(() => SupabaseConfig.client.removeChannel(ch));
});

final _webAllOrdersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await SupabaseConfig.client
      .from('orders')
      .select('*, restaurants(name), users(name, email, phone)')
      .order('ordered_at', ascending: false)
      .limit(300);
  return List<Map<String, dynamic>>.from(data as List);
});

final _webAvailableDriversProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final drivers = List<Map<String, dynamic>>.from(
    await SupabaseConfig.client
        .from('drivers')
        .select('id, user_id, vehicle_type, vehicle_number, rating, completed_deliveries')
        .eq('is_available', true)
        .eq('is_verified', true)
        .order('rating', ascending: false) as List,
  );
  if (drivers.isEmpty) return drivers;
  final userIds = drivers.map((d) => d['user_id'] as String?).whereType<String>().toList();
  final users = await SupabaseConfig.client.from('users').select('id, name, phone').inFilter('id', userIds);
  final userMap = <String, Map<String, dynamic>>{for (final u in users as List) (u as Map<String, dynamic>)['id'] as String: u};
  return drivers.map((d) => {...d, 'user': userMap[d['user_id'] ?? '']}).toList();
});

// ── Page ─────────────────────────────────────────────────────────────────────

class WebAdminOrdersPage extends ConsumerStatefulWidget {
  const WebAdminOrdersPage({super.key});

  @override
  ConsumerState<WebAdminOrdersPage> createState() => _WebAdminOrdersPageState();
}

class _WebAdminOrdersPageState extends ConsumerState<WebAdminOrdersPage> {
  String _search = '';
  String _tabFilter = 'all';

  static const _tabs = [
    ('all', 'All'),
    ('pending', 'Pending'),
    ('active', 'Active'),
    ('delivered', 'Delivered'),
    ('cancelled', 'Cancelled'),
  ];

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> orders) {
    var list = orders;
    if (_tabFilter == 'pending') {
      list = list.where((o) => o['status'] == 'pending').toList();
    } else if (_tabFilter == 'active') {
      const active = ['confirmed', 'preparing', 'ready', 'picked_up', 'out_for_delivery'];
      list = list.where((o) => active.contains(o['status'])).toList();
    } else if (_tabFilter == 'delivered') {
      list = list.where((o) => o['status'] == 'delivered').toList();
    } else if (_tabFilter == 'cancelled') {
      list = list.where((o) => o['status'] == 'cancelled').toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((o) {
        final id = (o['id'] ?? '').toString().toLowerCase();
        final name = ((o['users'] as Map?)?['name'] ?? '').toString().toLowerCase();
        final email = ((o['users'] as Map?)?['email'] ?? '').toString().toLowerCase();
        final rest = ((o['restaurants'] as Map?)?['name'] ?? '').toString().toLowerCase();
        return id.contains(q) || name.contains(q) || email.contains(q) || rest.contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(_webOrdersRealtimeProvider);
    final ordersAsync = ref.watch(_webAllOrdersProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Orders', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('All platform orders with real-time updates', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                onPressed: () => ref.invalidate(_webAllOrdersProvider),
              ),
            ],
          ),
          const SizedBox(height: 24),

          ordersAsync.when(
            loading: () => const SizedBox(height: 300, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(_webAllOrdersProvider)),
            data: (all) {
              final filtered = _filter(all);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Tab chips + search ────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _tabs.map((t) {
                              int count = t.$1 == 'all'
                                  ? all.length
                                  : _filter(all.where((o) {
                                      if (t.$1 == 'active') {
                                        const active = ['confirmed', 'preparing', 'ready', 'picked_up', 'out_for_delivery'];
                                        return active.contains(o['status']);
                                      }
                                      return o['status'] == t.$1;
                                    }).toList()).length;
                              final sel = _tabFilter == t.$1;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () => setState(() => _tabFilter = t.$1),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: sel ? AppTheme.primaryColor : Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(t.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: sel ? Colors.white : const Color(0xFF374151))),
                                        if (count > 0) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: sel ? Colors.white.withValues(alpha: 0.3) : AppTheme.primaryColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sel ? Colors.white : AppTheme.primaryColor)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 260,
                        height: 40,
                        child: TextField(
                          onChanged: (v) => setState(() => _search = v.trim()),
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Search orders…',
                            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                            prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Table ─────────────────────────────────────────
                  if (filtered.isEmpty)
                    _emptyState()
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                        children: [
                          // Table header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(width: 100, child: Text('ORDER', style: _hStyle)),
                                SizedBox(width: 160, child: Text('CUSTOMER', style: _hStyle)),
                                SizedBox(width: 160, child: Text('RESTAURANT', style: _hStyle)),
                                SizedBox(width: 100, child: Text('DATE', style: _hStyle)),
                                SizedBox(width: 80, child: Text('AMOUNT', style: _hStyle)),
                                SizedBox(width: 100, child: Text('STATUS', style: _hStyle)),
                                SizedBox(width: 80, child: Text('PAYMENT', style: _hStyle)),
                                Expanded(child: Text('ACTIONS', style: _hStyle, textAlign: TextAlign.right)),
                              ],
                            ),
                          ),
                          // Table rows
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            itemBuilder: (_, i) => _OrderRow(
                              order: filtered[i],
                              onRefresh: () => ref.invalidate(_webAllOrdersProvider),
                            ),
                          ),
                        ],
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

  Widget _emptyState() => Container(
    height: 200,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFFD1D5DB)),
          SizedBox(height: 12),
          Text('No orders found', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 15)),
        ],
      ),
    ),
  );

  static const _hStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5);
}

// ── Order Row ─────────────────────────────────────────────────────────────────

class _OrderRow extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onRefresh;
  const _OrderRow({required this.order, required this.onRefresh});

  @override
  ConsumerState<_OrderRow> createState() => _OrderRowState();
}

class _OrderRowState extends ConsumerState<_OrderRow> {
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final id = (o['id'] ?? '').toString();
    final shortId = id.length > 8 ? '#${id.substring(0, 8).toUpperCase()}' : '#$id';
    final status = (o['status'] ?? 'unknown').toString();
    final total = (o['total_amount'] ?? 0).toDouble();
    final payStatus = (o['payment_status'] ?? '').toString();
    final payMethod = (o['payment_method'] ?? 'N/A').toString();
    final orderedAt = DateTime.tryParse(o['ordered_at'] ?? '');
    final user = o['users'] as Map?;
    final rest = o['restaurants'] as Map?;
    final customerName = (user?['name'] ?? user?['email'] ?? 'Customer').toString();
    final restaurantName = (rest?['name'] ?? 'Unknown').toString();
    final hasDriver = o['driver_id'] != null;
    final isTerminal = status == 'delivered' || status == 'cancelled';

    final statusColor = _statusColor(status);
    final statusLabel = status.replaceAll('_', ' ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(shortId, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: Color(0xFF1E293B))),
          ),
          SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customerName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis),
                if (user?['email'] != null)
                  Text(user!['email'].toString(), style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          SizedBox(
            width: 160,
            child: Text(restaurantName, style: const TextStyle(fontSize: 13, color: Color(0xFF374151)), overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 100,
            child: Text(orderedAt != null ? _fmtDate(orderedAt) : 'N/A', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ),
          SizedBox(
            width: 80,
            child: Text('${AppConstants.currencySymbol}${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
          ),
          SizedBox(
            width: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(statusLabel[0].toUpperCase() + statusLabel.substring(1),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text('$payMethod\n$payStatus', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isTerminal) ...[
                  // Assign driver
                  Tooltip(
                    message: hasDriver ? 'Reassign driver' : 'Assign driver',
                    child: IconButton(
                      icon: Icon(Icons.delivery_dining_rounded, size: 18, color: hasDriver ? const Color(0xFF10B981) : const Color(0xFF9CA3AF)),
                      onPressed: () => _showAssignDialog(context, id),
                    ),
                  ),
                  // Update status
                  if (!_updating)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF9CA3AF)),
                      onSelected: (next) => _updateStatus(context, id, next, status),
                      itemBuilder: (_) => _nextStatuses(status).map((s) => PopupMenuItem(
                        value: s.$1,
                        child: Row(children: [Icon(s.$3, size: 16, color: s.$2), const SizedBox(width: 8), Text(s.$4)]),
                      )).toList(),
                    )
                  else
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<(String, Color, IconData, String)> _nextStatuses(String current) {
    final List<(String, Color, IconData, String)> options = [];
    const flow = ['confirmed', 'preparing', 'ready', 'picked_up', 'out_for_delivery', 'delivered'];
    final idx = flow.indexOf(current);
    if (idx < flow.length - 1 && idx >= 0) {
      final next = flow[idx + 1];
      options.add((next, AppTheme.primaryColor, Icons.arrow_forward_rounded, 'Mark ${next.replaceAll('_', ' ')}'));
    }
    options.add(('cancelled', Colors.red, Icons.cancel_rounded, 'Cancel Order'));
    return options;
  }

  Future<void> _updateStatus(BuildContext ctx, String orderId, String newStatus, String currentStatus) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(newStatus == 'cancelled' ? 'Cancel Order?' : 'Update Status'),
        content: Text(newStatus == 'cancelled'
            ? 'Cancel this order?'
            : 'Move order to "${newStatus.replaceAll('_', ' ')}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: newStatus == 'cancelled' ? Colors.red : AppTheme.primaryColor, foregroundColor: Colors.white),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (mounted) setState(() => _updating = true);
    try {
      if (newStatus == 'delivered') {
        final res = await SupabaseConfig.client.functions.invoke('complete-delivery', body: {'order_id': orderId});
        if (res.status != 200) throw Exception('Failed (${res.status})');
      } else {
        final updates = <String, dynamic>{'status': newStatus, 'updated_at': DateTime.now().toUtc().toIso8601String()};
        if (newStatus == 'confirmed') updates['confirmed_at'] = DateTime.now().toUtc().toIso8601String();
        if (newStatus == 'cancelled') updates['cancelled_at'] = DateTime.now().toUtc().toIso8601String();
        await SupabaseConfig.client.from('orders').update(updates).eq('id', orderId);
      }
      widget.onRefresh();
      if (ctx.mounted) AppSnackbar.success(ctx, 'Order updated');
    } catch (e) {
      if (ctx.mounted) AppSnackbar.error(ctx, friendlyError(e));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _showAssignDialog(BuildContext ctx, String orderId) {
    showDialog(context: ctx, builder: (_) => _AssignDriverDialog(orderId: orderId, onAssigned: widget.onRefresh));
  }

  static Color _statusColor(String s) {
    switch (s) {
      case 'pending': return const Color(0xFFF59E0B);
      case 'confirmed': case 'preparing': return const Color(0xFF6366F1);
      case 'ready': case 'picked_up': case 'out_for_delivery': return const Color(0xFF3B82F6);
      case 'delivered': return const Color(0xFF10B981);
      case 'cancelled': return const Color(0xFFEF4444);
      default: return const Color(0xFF6B7280);
    }
  }

  static String _fmtDate(DateTime dt) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[dt.month - 1]} ${dt.day}';
  }
}

// ── Assign Driver Dialog ───────────────────────────────────────────────────────

class _AssignDriverDialog extends ConsumerStatefulWidget {
  final String orderId;
  final VoidCallback onAssigned;
  const _AssignDriverDialog({required this.orderId, required this.onAssigned});

  @override
  ConsumerState<_AssignDriverDialog> createState() => _AssignDriverDialogState();
}

class _AssignDriverDialogState extends ConsumerState<_AssignDriverDialog> {
  String _search = '';
  bool _assigning = false;

  Future<void> _assign(Map<String, dynamic> driver) async {
    if (_assigning) return;
    setState(() => _assigning = true);
    try {
      await SupabaseConfig.client.from('orders').update({
        'driver_id': driver['id'] as String,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.orderId);
      widget.onAssigned();
      if (mounted) {
        Navigator.pop(context);
        AppSnackbar.success(context, 'Driver assigned');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driversAsync = ref.watch(_webAvailableDriversProvider);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.two_wheeler_rounded, color: AppTheme.primaryColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Assign Driver', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search drivers…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: driversAsync.when(
                loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e))),
                data: (drivers) {
                  final filtered = _search.isEmpty ? drivers : drivers.where((d) {
                    final user = d['user'] as Map?;
                    return (user?['name'] ?? '').toString().toLowerCase().contains(_search) ||
                        (d['vehicle_type'] ?? '').toString().toLowerCase().contains(_search);
                  }).toList();
                  if (filtered.isEmpty) return const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No available drivers')));
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final d = filtered[i];
                      final user = d['user'] as Map?;
                      final name = (user?['name'] ?? 'Driver').toString();
                      final vehicle = (d['vehicle_type'] ?? '').toString();
                      final vehicleNum = (d['vehicle_number'] ?? '').toString();
                      final rating = (d['rating'] as num?)?.toDouble() ?? 0;
                      return InkWell(
                        onTap: _assigning ? null : () => _assign(d),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(radius: 18, backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12), child: Text(name[0], style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold))),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text(vehicleNum.isNotEmpty ? '$vehicle · $vehicleNum' : vehicle, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                                ]),
                              ),
                              Row(children: [
                                const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 2),
                                Text(rating > 0 ? rating.toStringAsFixed(1) : 'N/A', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
