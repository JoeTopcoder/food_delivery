import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../services/company/company_service.dart';
import '../../utils/app_theme.dart';
import 'company_register_screen.dart';
import 'company_members_screen.dart';

/// Company admin dashboard: today's sponsored order counts, flat company charges
/// (JMD 350 delivery + 250 service per order), the running ledger balance, order
/// history and employee management. HotBite admins can also record payments.
class CompanyDashboardScreen extends ConsumerStatefulWidget {
  const CompanyDashboardScreen({super.key, this.companyId});
  /// When a HotBite admin opens a specific company; otherwise the caller's own.
  final String? companyId;
  @override
  ConsumerState<CompanyDashboardScreen> createState() => _CompanyDashboardScreenState();
}

class _CompanyDashboardScreenState extends ConsumerState<CompanyDashboardScreen> {
  Company? _company;
  bool _loading = true;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _orders = [];
  DateTime _date = DateTime.now();

  CompanyService get _svc => ref.read(companyServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (widget.companyId != null) {
        final rows = await _svc.searchCompanies(''); // RLS lets admins read; filter by id
        _company = rows.where((c) => c.id == widget.companyId).cast<Company?>().firstWhere(
            (c) => true, orElse: () => null);
        _company ??= (await _svc.myCompany());
      } else {
        _company = await _svc.myCompany();
      }
      if (_company != null) {
        _summary = await _svc.accountSummary(_company!.id, date: _date);
        _orders = await _svc.companyOrders(_company!.id, date: _date);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _money(num cents) => 'J\$${(cents / 100).toStringAsFixed(2)}';
  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get _isHotbiteAdmin =>
      ref.read(currentUserProvider)?.role == 'admin';

  Future<void> _recordPayment() async {
    final ctrl = TextEditingController();
    final refCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record company payment'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ctrl, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount (J\$)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: refCtrl,
            decoration: const InputDecoration(labelText: 'Reference', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Record')),
        ],
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(ctrl.text.trim());
    if (amt == null || amt <= 0) return;
    try {
      await _svc.recordPayment(_company!.id, (amt * 100).round(),
          reference: refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim());
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Company dashboard'),
        actions: [
          if (_company != null && widget.companyId == null)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              tooltip: 'Company profile',
              onPressed: () async {
                final changed = await Navigator.push<bool>(context,
                    MaterialPageRoute(builder: (_) => CompanyRegisterScreen(existing: _company)));
                if (changed == true) _load();
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _company == null
              ? _noCompany()
              : RefreshIndicator(onRefresh: _load, child: _dashboard()),
    );
  }

  Widget _noCompany() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.business_rounded, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('You don\'t have a company yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Register your company to sponsor employee orders.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                final created = await Navigator.push<bool>(context,
                    MaterialPageRoute(builder: (_) => const CompanyRegisterScreen()));
                if (created == true) _load();
              },
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
              icon: const Icon(Icons.add),
              label: const Text('Register company'),
            ),
          ]),
        ),
      );

  Widget _dashboard() {
    final s = _summary ?? {};
    int g(String k) => (s[k] as num?)?.toInt() ?? 0;
    final outstanding = g('outstanding_cents');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: Text(_company!.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          TextButton.icon(
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: Text(_ymd(_date)),
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: _date,
                  firstDate: DateTime(2026), lastDate: DateTime.now());
              if (d != null) { setState(() => _date = d); _load(); }
            },
          ),
        ]),
        const SizedBox(height: 8),
        // Outstanding balance (all-time ledger)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF3B0764)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(outstanding < 0 ? 'Credit balance' : 'Outstanding balance',
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(_money(outstanding.abs()),
                style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Row(children: [
              _stat('Charges', _money(g('charges_total_cents'))),
              _stat('Paid', _money(g('paid_cents'))),
              _stat('Adjust', _money(g('adjustments_cents'))),
            ]),
            if (_isHotbiteAdmin) ...[
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: _recordPayment,
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF1E3A8A)),
                icon: const Icon(Icons.payments_rounded, size: 18),
                label: const Text('Record payment'),
              )),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        // Today's counts
        Row(children: [
          Expanded(child: _miniCard('Orders today', '${g('orders_today')}', const Color(0xFF16A34A))),
          const SizedBox(width: 10),
          Expanded(child: _miniCard('Cancelled', '${g('cancelled_today')}', const Color(0xFFDC2626))),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => CompanyMembersScreen(companyId: _company!.id))),
          icon: const Icon(Icons.people_rounded),
          label: const Text('Manage employees'),
        ),
        const SizedBox(height: 16),
        const Text('Sponsored orders', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_orders.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No sponsored orders on this day.', style: TextStyle(color: Colors.grey)))
        else
          ..._orders.map(_orderCard),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ]),
      );

  Widget _miniCard(String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ]),
      );

  Widget _orderCard(Map<String, dynamic> o) {
    final total = ((o['total_company_cents'] as num?) ?? 0).toInt();
    return Card(
      child: ListTile(
        title: Text('${o['employee_name'] ?? 'Employee'} · ${o['restaurant_name'] ?? ''}'),
        subtitle: Text('#${o['restaurant_order_number'] ?? ''} · ${o['status'] ?? ''}\n'
            'Delivery ${_money(((o['delivery_cents'] as num?) ?? 0).toInt())} · '
            'Service ${_money(((o['service_cents'] as num?) ?? 0).toInt())}'),
        isThreeLine: true,
        trailing: Text(_money(total), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}
