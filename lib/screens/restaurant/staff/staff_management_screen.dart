import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/restaurant/staff_service.dart';
import '../../../utils/app_theme.dart';
import '../../../providers/auth_user/user_provider.dart';
import '../../../providers/auth_user/auth_provider.dart';

final _svc = StaffService();
String _money(int? cents) => cents == null ? '—' : 'J\$${(cents / 100).toStringAsFixed(2)}';

/// Owner/manager staff management for one restaurant: staff, pending invites,
/// live cashier status + shift approvals.
class StaffManagementScreen extends ConsumerStatefulWidget {
  final String restaurantId;
  const StaffManagementScreen({super.key, required this.restaurantId});
  @override
  ConsumerState<StaffManagementScreen> createState() => _S();
}

class _S extends ConsumerState<StaffManagementScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Management'),
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(text: 'Staff'), Tab(text: 'Invites'), Tab(text: 'Live / Shifts'),
        ]),
      ),
      body: TabBarView(controller: _tabs, children: [
        _StaffTab(restaurantId: widget.restaurantId),
        _InvitesTab(restaurantId: widget.restaurantId),
        _LiveTab(restaurantId: widget.restaurantId),
      ]),
    );
  }
}

// ───────────────────────── Staff tab ─────────────────────────
class _StaffTab extends StatefulWidget {
  final String restaurantId;
  const _StaffTab({required this.restaurantId});
  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  late Future<List<Map<String, dynamic>>> _f;
  @override
  void initState() { super.initState(); _f = _svc.listMembers(widget.restaurantId); }
  void _reload() => setState(() => _f = _svc.listMembers(widget.restaurantId));

  Future<void> _invite() async {
    final emailC = TextEditingController();
    String role = 'cashier';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Invite staff'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: emailC, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Role: '),
            ChoiceChip(label: const Text('Cashier'), selected: role == 'cashier', onSelected: (_) => setD(() => role = 'cashier')),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('Manager'), selected: role == 'manager', onSelected: (_) => setD(() => role = 'manager')),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send invite')),
        ],
      ),
    ));
    if (ok != true || !mounted) return;
    final res = await _svc.invite(widget.restaurantId, emailC.text.trim(), role);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      res.ok ? (res.emailed ? 'Invitation emailed' : 'Invitation created (email delivery failed)') : 'Failed: ${res.reason}')));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _f,
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snap.data!;
          if (rows.isEmpty) return const Center(child: Text('No staff yet — invite someone'));
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _memberCard(rows[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _invite, icon: const Icon(Icons.person_add), label: const Text('Invite')),
    );
  }

  Widget _memberCard(Map<String, dynamic> m) {
    final active = m['is_active'] == true;
    final role = (m['role'] ?? '').toString();
    final uid = m['user_id'] as String;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(m['name'] ?? m['email'] ?? 'Staff', style: const TextStyle(fontWeight: FontWeight.w700))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(role, style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold))),
        ]),
        Text(m['email'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          if (role != 'owner')
            OutlinedButton(onPressed: () async {
              final r = await _svc.setActive(widget.restaurantId, uid, !active);
              if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.ok ? 'Updated' : 'Failed: ${r.reason}'))); _reload(); }
            }, child: Text(active ? 'Deactivate' : 'Reactivate')),
          if (role != 'owner')
            OutlinedButton(onPressed: () async {
              final newRole = role == 'cashier' ? 'manager' : 'cashier';
              final r = await _svc.setRole(widget.restaurantId, uid, newRole);
              if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.ok ? 'Role → $newRole' : 'Failed: ${r.reason}'))); _reload(); }
            }, child: Text('Make ${role == 'cashier' ? 'Manager' : 'Cashier'}')),
          OutlinedButton(onPressed: () async {
            final ok = await _svc.passwordReset(widget.restaurantId, uid);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Password reset emailed' : 'Failed')));
          }, child: const Text('Reset password')),
        ]),
      ]),
    );
  }
}

// ───────────────────────── Invites tab ─────────────────────────
class _InvitesTab extends StatefulWidget {
  final String restaurantId;
  const _InvitesTab({required this.restaurantId});
  @override
  State<_InvitesTab> createState() => _InvitesTabState();
}

class _InvitesTabState extends State<_InvitesTab> {
  late Future<List<Map<String, dynamic>>> _f;
  @override
  void initState() { super.initState(); _f = _svc.pendingInvites(widget.restaurantId); }
  void _reload() => setState(() => _f = _svc.pendingInvites(widget.restaurantId));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        if (rows.isEmpty) return const Center(child: Text('No pending invitations'));
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.all(12), itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final inv = rows[i];
              return ListTile(
                tileColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text(inv['email'] ?? ''),
                subtitle: Text('${inv['role']} • expires ${(inv['expires_at'] ?? '').toString().substring(0, 10)}'),
                trailing: TextButton(onPressed: () async {
                  await _svc.revokeInvite(inv['id'] as String);
                  if (mounted) _reload();
                }, child: const Text('Revoke')),
              );
            },
          ),
        );
      },
    );
  }
}

// ───────────────────────── Live / Shifts tab ─────────────────────────
class _LiveTab extends StatefulWidget {
  final String restaurantId;
  const _LiveTab({required this.restaurantId});
  @override
  State<_LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<_LiveTab> {
  Map<String, dynamic>? _counts;
  List<Map<String, dynamic>> _presence = [];
  List<Map<String, dynamic>> _submitted = [];
  Timer? _poll;
  bool _error = false;

  @override
  void initState() { super.initState(); _refresh(); _poll = Timer.periodic(const Duration(seconds: 20), (_) => _refresh()); }
  @override
  void dispose() { _poll?.cancel(); super.dispose(); }

  Future<void> _refresh() async {
    try {
      final c = await _svc.dashboardCounts(widget.restaurantId);
      final p = await _svc.presenceList(widget.restaurantId);
      final s = await _svc.shiftsByStatus(widget.restaurantId, ['submitted']);
      if (mounted) setState(() { _counts = c; _presence = p; _submitted = s; _error = c == null || c['ok'] != true; });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _review(Map<String, dynamic> sh) async {
    final approve = await showDialog<bool?>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Shift — ${(sh['users']?['name']) ?? 'Cashier'}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Expected: ${_money((sh['expected_cash_cents'] as num?)?.toInt())}'),
        Text('Counted: ${_money((sh['counted_cash_cents'] as num?)?.toInt())}'),
        Text('Variance: ${_money((sh['variance_cents'] as num?)?.toInt())}',
          style: TextStyle(fontWeight: FontWeight.bold, color: ((sh['variance_cents'] as num?) ?? 0) < 0 ? Colors.red : Colors.green)),
        if (sh['variance_explanation'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Note: ${sh['variance_explanation']}')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Return')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
      ],
    ));
    if (approve == null || !mounted) return;
    String? reason;
    if (approve == false) {
      final rc = TextEditingController();
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Return reason'),
        content: TextField(controller: rc, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Return'))]));
      if (ok != true) return;
      reason = rc.text.trim();
    }
    final r = await _svc.approveShift(sh['id'] as String, approve, reason);
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.ok ? 'Done (${r.status})' : 'Failed: ${r.reason}'))); _refresh(); }
  }

  @override
  Widget build(BuildContext context) {
    final c = _counts;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (_error)
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: const Text('Status unavailable — pull to retry.', style: TextStyle(color: Colors.orange))),
        if (c != null && c['ok'] == true) Wrap(spacing: 10, runSpacing: 10, children: [
          _stat('Active cashiers', c['active_cashiers']),
          _stat('Online', c['online'], color: const Color(0xFF22C55E)),
          _stat('Open shifts', c['open_shifts']),
          _stat('Awaiting approval', c['submitted_awaiting_approval'], color: AppTheme.primaryColor),
          _stat('Needs closure', c['needs_manager_closure'], color: Colors.orange),
          _stat('Long open', c['long_open'], color: Colors.red),
        ]),
        const SizedBox(height: 16),
        const Text('Cashiers', style: TextStyle(fontWeight: FontWeight.bold)),
        ..._presence.map((p) => ListTile(
          leading: Icon(Icons.circle, size: 12, color: p['online'] == true ? const Color(0xFF22C55E) : Colors.grey),
          title: Text(p['name'] ?? 'Cashier'),
          subtitle: Text(p['online'] == true ? 'Online' : 'Offline • last seen ${(p['last_seen_at'] ?? '—').toString()}'),
          trailing: p['is_active'] == true ? null : const Text('inactive', style: TextStyle(color: Colors.red, fontSize: 11)),
        )),
        const SizedBox(height: 16),
        const Text('Submitted — awaiting approval', style: TextStyle(fontWeight: FontWeight.bold)),
        if (_submitted.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('None', style: TextStyle(color: Colors.black54))),
        ..._submitted.map((s) => Card(child: ListTile(
          title: Text('${s['users']?['name'] ?? 'Cashier'} — variance ${_money((s['variance_cents'] as num?)?.toInt())}'),
          subtitle: Text('Expected ${_money((s['expected_cash_cents'] as num?)?.toInt())} • Counted ${_money((s['counted_cash_cents'] as num?)?.toInt())}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _review(s),
        ))),
      ]),
    );
  }

  Widget _stat(String label, dynamic val, {Color color = Colors.black87}) => Container(
    width: 150, padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${val ?? '—'}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ]),
  );
}

/// Owner entry point: resolves the owner's restaurant then shows management.
class StaffManagementEntry extends ConsumerWidget {
  const StaffManagementEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const Scaffold(body: Center(child: Text('Not signed in')));
    final restAsync = ref.watch(restaurantByOwnerProvider(uid));
    return restAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('Error: $e'))),
      data: (r) => r == null
          ? const Scaffold(body: Center(child: Text('No restaurant found for this account')))
          : StaffManagementScreen(restaurantId: r.id),
    );
  }
}
