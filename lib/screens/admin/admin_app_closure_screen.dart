import '../../utils/est_datetime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin control to CLOSE THE APP for a day (or specific dates). Customers can
/// still browse + add to cart, but cannot check out for a closed date — they
/// can only schedule for an open date. A red notice shows on the home screen.
class AdminAppClosureScreen extends ConsumerStatefulWidget {
  const AdminAppClosureScreen({super.key});
  @override
  ConsumerState<AdminAppClosureScreen> createState() => _S();
}

class _S extends ConsumerState<AdminAppClosureScreen> {
  final _client = Supabase.instance.client;
  final _msg = TextEditingController();
  Map<String, dynamic> _status = {};
  List<Map<String, dynamic>> _closures = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await _client.rpc('app_closure_status');
      _status = (s is Map) ? Map<String, dynamic>.from(s) : {};
      _msg.text = (_status['message'] as String?) ?? '';
      final rows = await _client.from('app_closures').select().eq('active', true).order('closed_date');
      _closures = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      // RLS: only admins can read app_closures; status RPC still works.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future Function() f, String ok) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _closedToday => _status['closed_today'] == true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Close App / Holidays')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Big status + close-today toggle.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _closedToday ? const Color(0xFFFDECEC) : const Color(0xFFEAF7EE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(_closedToday ? Icons.event_busy_rounded : Icons.event_available_rounded,
                          color: _closedToday ? Colors.red : Colors.green),
                      const SizedBox(width: 8),
                      Text(_closedToday ? 'App is CLOSED today' : 'App is OPEN today',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                              color: _closedToday ? Colors.red.shade700 : Colors.green.shade700)),
                    ]),
                    const SizedBox(height: 6),
                    Text(_closedToday
                        ? 'Checkout is blocked today. Customers can browse, add to cart, and schedule for an open date.'
                        : 'Everything is running normally.',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : () {
                          if (_closedToday) {
                            _run(() => _client.rpc('admin_set_app_closure', params: {
                                  'p_date': DateFormat('yyyy-MM-dd').format(toJamaicaOf(_todayLocal())),
                                  'p_active': false,
                                }), 'Reopened today');
                          } else {
                            _run(() => _client.rpc('admin_close_today', params: {'p_reason': _msg.text.trim()}),
                                'App closed for today');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _closedToday ? Colors.green : Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: Icon(_closedToday ? Icons.lock_open_rounded : Icons.power_settings_new_rounded),
                        label: Text(_closedToday ? 'Reopen the app today' : 'Close the app today'),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),

                // Closure message.
                const Text('Notice message', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                TextField(
                  controller: _msg, minLines: 2, maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Closed for the public holiday. Schedule your order for tomorrow!',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _run(
                        () => _client.rpc('admin_set_closure_message', params: {'p_message': _msg.text.trim()}),
                        'Message saved'),
                    child: const Text('Save message'),
                  ),
                ),
                const SizedBox(height: 18),

                // Schedule specific holiday dates.
                Row(children: [
                  const Expanded(child: Text('Scheduled closures', style: TextStyle(fontWeight: FontWeight.w800))),
                  TextButton.icon(
                    onPressed: _busy ? null : _addClosureDate,
                    icon: const Icon(Icons.add), label: const Text('Add date'),
                  ),
                ]),
                const SizedBox(height: 4),
                if (_closures.isEmpty)
                  Text('No upcoming closures.', style: TextStyle(color: Colors.grey.shade600))
                else
                  ..._closures.map((c) => Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200)),
                        child: ListTile(
                          leading: const Icon(Icons.event_busy_rounded, color: Colors.red),
                          title: Text('${c['closed_date']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text((c['reason'] as String?)?.isNotEmpty == true ? c['reason'] : 'Closed'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: _busy ? null : () => _run(
                                () => _client.rpc('admin_set_app_closure',
                                    params: {'p_date': c['closed_date'], 'p_active': false}),
                                'Closure removed'),
                          ),
                        ),
                      )),
              ],
            ),
    );
  }

  DateTime _todayLocal() => DateTime.now();

  Future<void> _addClosureDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    final reasonCtl = TextEditingController(text: _msg.text.trim());
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Close on ${DateFormat('MMM d, yyyy').format(toJamaicaOf(picked))}'),
        content: TextField(controller: reasonCtl,
            decoration: const InputDecoration(labelText: 'Reason (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close this date')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
        () => _client.rpc('admin_set_app_closure', params: {
              'p_date': DateFormat('yyyy-MM-dd').format(toJamaicaOf(picked)),
              'p_active': true,
              'p_reason': reasonCtl.text.trim(),
            }),
        'Closure added');
  }
}
