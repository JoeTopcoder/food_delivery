import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_constants.dart';

/// Admin report for the HotBite+ Shared Member Savings model. Reads the two
/// admin-gated RPCs (admin_member_savings_summary / _by_store) over a chosen
/// date window and shows platform totals + a per-store breakdown.
///
/// All money is server-computed (net of refunds); this screen only renders it.
class AdminMemberSavingsReportScreen extends ConsumerStatefulWidget {
  const AdminMemberSavingsReportScreen({super.key});

  @override
  ConsumerState<AdminMemberSavingsReportScreen> createState() =>
      _AdminMemberSavingsReportScreenState();
}

class _AdminMemberSavingsReportScreenState
    extends ConsumerState<AdminMemberSavingsReportScreen> {
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  late Future<_ReportData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ReportData> _load() async {
    final client = Supabase.instance.client;
    // Inclusive end: push to the start of the next day.
    final from = DateTime(_range.start.year, _range.start.month, _range.start.day)
        .toUtc()
        .toIso8601String();
    final to = DateTime(_range.end.year, _range.end.month, _range.end.day)
        .add(const Duration(days: 1))
        .toUtc()
        .toIso8601String();

    final summaryRes = await client.rpc('admin_member_savings_summary',
        params: {'p_from': from, 'p_to': to});
    final storesRes = await client.rpc('admin_member_savings_by_store',
        params: {'p_from': from, 'p_to': to});
    final ledgerRes = await client.rpc('admin_platform_revenue',
        params: {'p_from': from, 'p_to': to});

    final summaryRow = (summaryRes is List && summaryRes.isNotEmpty)
        ? summaryRes.first as Map<String, dynamic>
        : <String, dynamic>{};
    final stores = (storesRes is List)
        ? storesRes.map((e) => e as Map<String, dynamic>).toList()
        : <Map<String, dynamic>>[];
    final ledgerRow = (ledgerRes is List && ledgerRes.isNotEmpty)
        ? ledgerRes.first as Map<String, dynamic>
        : <String, dynamic>{};
    return _ReportData(summary: summaryRow, stores: stores, ledger: ledgerRow);
  }

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() => _range = picked);
      _reload();
    }
  }

  String _money(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('${v ?? 0}') ?? 0;
    return '${AppConstants.currencySymbol}${n.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${_range.start.toString().substring(0, 10)} → ${_range.end.toString().substring(0, 10)}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Member Savings Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: const Color(0xFFFFF3EC),
            child: InkWell(
              onTap: _pickRange,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.date_range, color: Color(0xFFFF5A1F)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(dateLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const Text('Change',
                        style: TextStyle(color: Color(0xFFFF5A1F))),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<_ReportData>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load report:\n${snap.error}',
                          textAlign: TextAlign.center),
                    ),
                  );
                }
                final data = snap.data!;
                final s = data.summary;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _summaryGrid(s),
                    const SizedBox(height: 8),
                    _netCard(s),
                    const SizedBox(height: 12),
                    _ledgerCard(data.ledger),
                    const SizedBox(height: 20),
                    const Text('By store',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (data.stores.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: Text('No member orders in this period.')),
                      )
                    else
                      ...data.stores.map(_storeTile),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid(Map<String, dynamic> s) {
    final cards = <Widget>[
      _statCard('Member orders', '${s['member_orders'] ?? 0}',
          Icons.receipt_long, Colors.indigo),
      _statCard('Gross member sales', _money(s['gross_member_sales']),
          Icons.storefront, Colors.blueGrey),
      _statCard('Customer savings', _money(s['customer_savings']),
          Icons.savings, Colors.green),
      _statCard('HotBite share revenue', _money(s['hotbite_share_rev']),
          Icons.workspace_premium_rounded, const Color(0xFFFF5A1F)),
      _statCard('Store payout base', _money(s['store_payout_base']),
          Icons.account_balance_wallet, Colors.teal),
      _statCard('Commission', _money(s['commission_total']),
          Icons.percent, Colors.purple),
      _statCard('Delivery fees', _money(s['delivery_fees']),
          Icons.delivery_dining, Colors.brown),
      _statCard('Service fees', _money(s['service_fees']),
          Icons.room_service, Colors.orange),
      _statCard('Refunds', _money(s['refunds_total']),
          Icons.undo, Colors.red),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.7,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: cards,
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _netCard(Map<String, dynamic> s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFFF7A45), Color(0xFFFF5A1F)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Net HotBite contribution',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(_money(s['net_contribution']),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('HotBite share + commission + service fees − refunds',
              style: TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _ledgerCard(Map<String, dynamic> l) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 18, color: Colors.indigo),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Platform revenue (recorded ledger)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              Text('${l['entries'] ?? 0} entries',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Itemized per delivered order in platform_revenue_ledger — the HotBite '
            'share is banked here alongside commission, not left implicit.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const Divider(height: 18),
          _ledgerRow('Restaurant commission', l['restaurant_commission']),
          _ledgerRow('Delivery fee (platform share)', l['delivery_fee_platform_share']),
          _ledgerRow('HotBite+ member share', l['hotbite_savings_share'], highlight: true),
          _ledgerRow('Service fee', l['service_fee']),
          const Divider(height: 18),
          _ledgerRow('Total platform revenue', l['total'], bold: true),
        ],
      ),
    );
  }

  Widget _ledgerRow(dynamic label, dynamic value,
      {bool bold = false, bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  color: highlight ? const Color(0xFFFF5A1F) : Colors.black87)),
          Text(_money(value),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: highlight ? const Color(0xFFFF5A1F) : Colors.black87)),
        ],
      ),
    );
  }

  Widget _storeTile(Map<String, dynamic> st) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (st['restaurant_name'] as String?) ?? 'Unknown store',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text('${st['member_orders'] ?? 0} orders',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _kv('HotBite share', _money(st['hotbite_share_rev'])),
                _kv('Customer saved', _money(st['customer_savings'])),
                _kv('Store payout base', _money(st['store_payout_base'])),
                _kv('Refunds', _money(st['refunds_total'])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(k, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      );
}

class _ReportData {
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> stores;
  final Map<String, dynamic> ledger;
  _ReportData({required this.summary, required this.stores, required this.ledger});
}
