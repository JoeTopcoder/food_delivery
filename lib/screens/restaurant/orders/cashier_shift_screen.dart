import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/restaurant/staff_service.dart';

final _svc = StaffService();
int _toCents(String s) => ((double.tryParse(s.trim()) ?? 0) * 100).round();
String _money(int? c) => c == null ? '—' : 'J\$${(c / 100).toStringAsFixed(2)}';

/// Cashier shift workflow for a restaurant the user is a member of, with a live
/// presence heartbeat. Open → record cash → submit count. Online status is
/// independent of the shift (going offline never closes it).
class CashierShiftScreen extends ConsumerStatefulWidget {
  const CashierShiftScreen({super.key});
  @override
  ConsumerState<CashierShiftScreen> createState() => _S();
}

class _S extends ConsumerState<CashierShiftScreen> with WidgetsBindingObserver {
  final String _session = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 31)}';
  List<Map<String, dynamic>> _memberships = [];
  String? _restaurantId;
  Map<String, dynamic>? _shift;
  List<Map<String, dynamic>> _movements = [];
  int _expected = 0;
  Timer? _heartbeat;
  bool _loading = true;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _boot(); }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    if (_restaurantId != null) _svc.endPresence(_restaurantId!, _session);
    super.dispose();
  }

  Future<void> _boot() async {
    final m = await _svc.myMemberships();
    if (!mounted) return;
    setState(() { _memberships = m; _loading = false; });
    if (m.length == 1) _select(m.first['restaurant_id'] as String);
  }

  Future<void> _select(String rid) async {
    setState(() => _restaurantId = rid);
    _startHeartbeat();
    await _loadShift();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    if (_restaurantId == null) return;
    _svc.heartbeat(_restaurantId!, _session);
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_restaurantId != null) _svc.heartbeat(_restaurantId!, _session);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding does NOT close the shift; we just pause heartbeats.
    if (state == AppLifecycleState.resumed) { _startHeartbeat(); _loadShift(); }
    else { _heartbeat?.cancel(); }
  }

  Future<void> _loadShift() async {
    if (_restaurantId == null) return;
    final s = await _svc.myOpenShift(_restaurantId!);
    List<Map<String, dynamic>> mv = [];
    int expected = 0;
    if (s != null) {
      mv = await _svc.shiftMovements(s['id'] as String);
      expected = (s['opening_float_cents'] as num? ?? 0).toInt();
      for (final m in mv) {
        final a = (m['amount_cents'] as num? ?? 0).toInt();
        expected += (m['kind'] == 'refund' || m['kind'] == 'withdrawal') ? -a : a;
      }
    }
    if (mounted) setState(() { _shift = s; _movements = mv; _expected = expected; });
  }

  Future<void> _openShift() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Open shift'),
      content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Opening cash float (J\$)', border: OutlineInputBorder())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open'))]));
    if (ok != true || !mounted) return;
    final r = await _svc.openShift(_restaurantId!, _toCents(c.text));
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.ok ? 'Shift opened' : 'Failed: ${r.reason}'))); _loadShift(); }
  }

  Future<void> _recordCash() async {
    final amt = TextEditingController();
    String kind = 'receipt';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      title: const Text('Record cash'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: kind,
          decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'receipt', child: Text('Cash received (sale)')),
            DropdownMenuItem(value: 'rider_cash_received', child: Text('Rider cash handed in')),
            DropdownMenuItem(value: 'deposit', child: Text('Cash deposit in')),
            DropdownMenuItem(value: 'refund', child: Text('Cash refund out')),
            DropdownMenuItem(value: 'withdrawal', child: Text('Cash withdrawal out')),
          ], onChanged: (v) => setD(() => kind = v ?? 'receipt')),
        const SizedBox(height: 12),
        TextField(controller: amt, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount (J\$)', border: OutlineInputBorder())),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Record'))])));
    if (ok != true || !mounted) return;
    final r = await _svc.recordCash(_shift!['id'] as String, kind, _toCents(amt.text));
    if (mounted) { if (!r.ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${r.reason}'))); _loadShift(); }
  }

  Future<void> _submit() async {
    final counted = TextEditingController();
    final expl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Submit closing count'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Expected in drawer: ${_money(_expected)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        TextField(controller: counted, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Counted cash (J\$)', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: expl, decoration: const InputDecoration(labelText: 'Explanation (required if variance)', border: OutlineInputBorder())),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit'))]));
    if (ok != true || !mounted) return;
    final r = await _svc.submitShift(_shift!['id'] as String, _toCents(counted.text), expl.text.trim().isEmpty ? null : expl.text.trim());
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      r.ok ? 'Submitted (variance ${_money(r.variance)})' : 'Failed: ${r.reason}'))); _loadShift(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Shift')),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _memberships.isEmpty ? const Center(child: Padding(padding: EdgeInsets.all(24),
            child: Text('You are not an active staff member of any restaurant.', textAlign: TextAlign.center)))
        : _restaurantId == null ? _picker()
        : _shiftBody(),
    );
  }

  Widget _picker() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Select restaurant', style: TextStyle(fontWeight: FontWeight.bold)),
    ..._memberships.map((m) => Card(child: ListTile(
      title: Text(m['restaurants']?['name'] ?? 'Restaurant'),
      subtitle: Text(m['role'] ?? ''),
      onTap: () => _select(m['restaurant_id'] as String)))),
  ]);

  Widget _shiftBody() {
    final s = _shift;
    final name = _memberships.firstWhere((m) => m['restaurant_id'] == _restaurantId,
        orElse: () => const {})['restaurants']?['name'] ?? '';
    if (s == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('No open shift.'),
        const SizedBox(height: 12),
        ElevatedButton.icon(onPressed: _openShift, icon: const Icon(Icons.play_arrow), label: const Text('Open shift')),
      ]));
    }
    final submitted = s['status'] == 'submitted';
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('$name — ${submitted ? 'Submitted (awaiting approval)' : 'Shift open'}',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 4),
      Text('Opening float: ${_money((s['opening_float_cents'] as num?)?.toInt())}'),
      Text('Expected now: ${_money(_expected)}', style: const TextStyle(fontWeight: FontWeight.bold)),
      if (s['return_reason'] != null) Padding(padding: const EdgeInsets.only(top: 6),
        child: Text('Returned: ${s['return_reason']}', style: const TextStyle(color: Colors.orange))),
      const Divider(height: 24),
      const Text('Cash movements', style: TextStyle(fontWeight: FontWeight.bold)),
      if (_movements.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('None yet', style: TextStyle(color: Colors.black54))),
      ..._movements.map((m) => ListTile(dense: true,
        title: Text(m['kind'].toString().replaceAll('_', ' ')),
        trailing: Text('${(m['kind'] == 'refund' || m['kind'] == 'withdrawal') ? '-' : '+'}${_money((m['amount_cents'] as num?)?.toInt())}'))),
      const SizedBox(height: 16),
      if (!submitted) Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: _recordCash, icon: const Icon(Icons.add), label: const Text('Record cash'))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton.icon(onPressed: _submit, icon: const Icon(Icons.check), label: const Text('Submit count'))),
      ]),
    ]);
  }
}
