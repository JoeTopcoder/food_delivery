import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

/// ⚡ Priority Delivery — admin configuration + live metrics. Enable/disable the
/// customer upgrade and set its fee (both stored in app_config, so no app
/// release is needed). Revenue/volume come from the real `priority_delivery_stats`
/// view — no mock analytics.
class AdminPriorityDeliveryScreen extends ConsumerStatefulWidget {
  const AdminPriorityDeliveryScreen({super.key});

  @override
  ConsumerState<AdminPriorityDeliveryScreen> createState() =>
      _AdminPriorityDeliveryScreenState();
}

class _AdminPriorityDeliveryScreenState
    extends ConsumerState<AdminPriorityDeliveryScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  final _feeCtrl = TextEditingController();
  Map<String, dynamic>? _todayStats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final cfg = await Supabase.instance.client
          .from('app_config')
          .select('key, value')
          .inFilter('key', ['priority_delivery_enabled', 'priority_delivery_fee']);
      for (final r in (cfg as List)) {
        if (r['key'] == 'priority_delivery_enabled') {
          _enabled = r['value'] == 'true' || r['value'] == '1';
        } else if (r['key'] == 'priority_delivery_fee') {
          _feeCtrl.text = (r['value']?.toString() ?? '0');
        }
      }
      // Today's priority metrics from the real view.
      final stats = await Supabase.instance.client
          .from('priority_delivery_stats')
          .select()
          .gte('day', DateTime.now().toUtc().toIso8601String().substring(0, 10))
          .maybeSingle();
      _todayStats = stats;
    } catch (_) {/* fresh install — defaults */}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final fee = double.tryParse(_feeCtrl.text.trim()) ?? 0;
      if (_enabled && fee <= 0) {
        AppSnackbar.error(context,
            'Set a positive fee, or turn Priority Delivery off. Free priority is not enabled.');
        setState(() => _saving = false);
        return;
      }
      await Supabase.instance.client.from('app_config').upsert([
        {'key': 'priority_delivery_enabled', 'value': _enabled ? 'true' : 'false'},
        {'key': 'priority_delivery_fee', 'value': fee.toStringAsFixed(0)},
      ]);
      if (mounted) AppSnackbar.success(context, 'Priority Delivery settings saved');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sym = AppConstants.currencySymbol;
    return Scaffold(
      appBar: AppBar(title: const Text('⚡ Priority Delivery')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Priority Delivery',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: const Text(
                              'Let customers pay extra for prioritised handling.'),
                          value: _enabled,
                          activeThumbColor: const Color(0xFFEA580C),
                          onChanged: (v) => setState(() => _enabled = v),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _feeCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Priority Fee ($sym)',
                            border: const OutlineInputBorder(),
                            prefixText: '$sym ',
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child: Text(_saving ? 'Saving…' : 'Save settings'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Today',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        _stat('Priority orders',
                            '${(_todayStats?['priority_orders'] as num?)?.toInt() ?? 0}'),
                        _stat('Priority revenue',
                            '$sym${((_todayStats?['priority_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'),
                        _stat('Delivery revenue',
                            '$sym${((_todayStats?['delivery_revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}'),
                        _stat('Priority cancellations',
                            '${(_todayStats?['priority_cancellations'] as num?)?.toInt() ?? 0}'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );
}
