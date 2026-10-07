import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/supabase_config.dart';
import '../../utils/est_datetime.dart';

/// Admin-only, read-only view of a customer's wallet: balances + transaction
/// history (via admin_wallet_history RPC). Ledger convention: amount > 0 is a
/// credit, amount < 0 is a debit.
class AdminWalletHistoryScreen extends ConsumerStatefulWidget {
  final String userId;
  final String userName;
  const AdminWalletHistoryScreen({super.key, required this.userId, this.userName = 'Customer'});
  @override
  ConsumerState<AdminWalletHistoryScreen> createState() => _S();
}

class _S extends ConsumerState<AdminWalletHistoryScreen> {
  late Future<Map<String, dynamic>> _f;
  @override
  void initState() { super.initState(); _f = _load(); }

  Future<Map<String, dynamic>> _load() async {
    final r = await SupabaseConfig.client
        .rpc('admin_wallet_history', params: {'p_user': widget.userId, 'p_limit': 200});
    return (r as Map?)?.cast<String, dynamic>() ?? {'ok': false};
  }

  String _money(num v, String cur) => '$cur ${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.userName} — Wallet')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final d = snap.data!;
          if (d['ok'] != true) {
            return Center(child: Text(d['reason'] == 'not_authorized' ? 'Not authorized' : 'Could not load wallet'));
          }
          final cur = (d['currency'] ?? 'JMD').toString();
          final txns = (d['transactions'] as List?) ?? [];
          return RefreshIndicator(
            onRefresh: () async => setState(() => _f = _load()),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Wrap(spacing: 10, runSpacing: 10, children: [
                _bal('Balance', (d['balance'] as num? ?? 0), cur, const Color(0xFF2563EB)),
                _bal('Cashback', (d['cashback_balance'] as num? ?? 0), cur, const Color(0xFF22C55E)),
                if ((d['debt_balance'] as num? ?? 0) != 0)
                  _bal('Debt', (d['debt_balance'] as num? ?? 0), cur, Colors.red),
                if ((d['reserved_balance'] as num? ?? 0) != 0)
                  _bal('Reserved', (d['reserved_balance'] as num? ?? 0), cur, Colors.orange),
              ]),
              const SizedBox(height: 18),
              const Text('Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              if (txns.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No transactions', style: TextStyle(color: Colors.black54))),
              ...txns.map((t) => _txnRow((t as Map).cast<String, dynamic>(), cur)),
            ]),
          );
        },
      ),
    );
  }

  Widget _bal(String label, num v, String cur, Color c) => Container(
    width: 160, padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_money(v, cur), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ]),
  );

  Widget _txnRow(Map<String, dynamic> t, String cur) {
    final amt = (t['amount'] as num? ?? 0).toDouble();
    final credit = amt > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black12)),
      child: Row(children: [
        Icon(credit ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: credit ? const Color(0xFF22C55E) : Colors.red, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((t['type'] ?? 'transaction').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (t['description'] != null) Text(t['description'].toString(), style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text('${t['created_at'] != null ? DateTime.parse(t['created_at'].toString()).jmFormat('MMM d, y · h:mm a') : ''}'
              '${t['status'] != null ? ' • ${t['status']}' : ''}',
              style: const TextStyle(fontSize: 11, color: Colors.black38)),
        ])),
        Text('${credit ? '+' : ''}${_money(amt, cur)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: credit ? const Color(0xFF22C55E) : Colors.red)),
      ]),
    );
  }
}
