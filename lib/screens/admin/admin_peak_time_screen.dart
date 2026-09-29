import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/supabase_config.dart';
import '../../config/app_constants.dart';
import '../../providers/peak_time_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

/// Admin management for Dynamic Peak Time. Shows the live authoritative state
/// and lets an admin change the threshold / fee / ETA adjustment via the
/// backend `admin_set_peak_time_config` RPC (which validates, audits and is
/// gated to admins). Values are re-read authoritatively after saving.
class AdminPeakTimeScreen extends ConsumerStatefulWidget {
  const AdminPeakTimeScreen({super.key});

  @override
  ConsumerState<AdminPeakTimeScreen> createState() =>
      _AdminPeakTimeScreenState();
}

class _AdminPeakTimeScreenState extends ConsumerState<AdminPeakTimeScreen> {
  final _thresholdCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _etaCtrl = TextEditingController();
  bool _enabled = true;
  bool _feeEnabled = false;
  bool _hydrated = false;
  bool _saving = false;

  @override
  void dispose() {
    _thresholdCtrl.dispose();
    _feeCtrl.dispose();
    _etaCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final threshold = int.tryParse(_thresholdCtrl.text.trim());
    final fee = double.tryParse(_feeCtrl.text.trim());
    final eta = int.tryParse(_etaCtrl.text.trim());
    if (threshold == null || threshold < 0) {
      AppSnackbar.warning(context, 'Threshold must be 0 or more.');
      return;
    }
    if (fee == null || fee < 0) {
      AppSnackbar.warning(context, 'Fee must be 0 or more.');
      return;
    }
    if (eta == null || eta < 0) {
      AppSnackbar.warning(context, 'ETA adjustment must be 0 or more.');
      return;
    }
    setState(() => _saving = true);
    try {
      await SupabaseConfig.client.rpc('admin_set_peak_time_config', params: {
        'p_enabled': _enabled,
        'p_threshold': threshold,
        'p_fee_enabled': _feeEnabled,
        'p_fee': fee,
        'p_eta_adjustment': eta,
      });
      await ref.read(peakTimeProvider.notifier).refresh();
      if (mounted) AppSnackbar.success(context, 'Peak Time settings saved.');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(peakTimeProvider);
    // Hydrate the editable fields once from the first authoritative load.
    final state = async.valueOrNull;
    if (!_hydrated && state != null) {
      _hydrated = true;
      _enabled = state.enabled;
      _feeEnabled = state.feeEnabled;
      _thresholdCtrl.text = '${state.threshold}';
      _feeCtrl.text = state.fee.toStringAsFixed(2);
      _etaCtrl.text = '${state.etaAdjustmentMinutes}';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Peak Time')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statusCard(s),
            const SizedBox(height: 20),
            const Text('Configuration',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Peak Time enabled'),
              subtitle: const Text('When off, Peak Time never activates.'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            TextField(
              controller: _thresholdCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Order threshold',
                helperText: 'Peak Time turns ON when active orders exceed this.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Peak Time fee enabled'),
              value: _feeEnabled,
              onChanged: (v) => setState(() => _feeEnabled = v),
            ),
            TextField(
              controller: _feeCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Peak Time fee (${AppConstants.currencyCode})',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _etaCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'ETA adjustment (minutes)',
                helperText: 'Added to ETA while Peak Time is ON.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Settings',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(dynamic s) {
    final on = s.isPeakTime as bool;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: on
            ? const Color(0xFFF59E0B).withValues(alpha: 0.10)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: on ? const Color(0xFFF59E0B) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                on
                    ? Icons.local_fire_department_rounded
                    : Icons.check_circle_outline_rounded,
                color: on ? const Color(0xFFB45309) : Colors.green,
              ),
              const SizedBox(width: 8),
              Text(
                on ? 'Peak Time is ON' : 'Peak Time is OFF',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _row('Active orders', '${s.activeOrderCount}'),
          _row('Threshold', '${s.threshold}'),
          _row('Orders to activate', on ? '0 (already active)' : '${s.ordersToActivate}'),
          _row('Fee enabled', s.feeEnabled ? 'Yes' : 'No'),
          _row('Peak fee',
              '${AppConstants.currencySymbol}${(s.fee as double).toStringAsFixed(2)}'),
          _row('ETA adjustment', '${s.etaAdjustmentMinutes} min'),
          if (s.updatedAt != null)
            _row('Last updated', '${s.updatedAt}'.split('.').first),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
