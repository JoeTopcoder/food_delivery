import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';

final survivalMetricsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final res = await Supabase.instance.client.rpc(
        'admin_survival_metrics',
        params: {'p_days': 30},
      );
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    });

/// Break-even and survival metrics.
///
/// Two kinds of number live here and the screen keeps them visibly apart:
/// figures MEASURED from real orders, and figures that rest on ASSUMPTIONS the
/// operator supplies (rent, retainers, marketing, cash in the bank). Costs like
/// those exist outside this system entirely, so break-even cannot be derived
/// from order data alone — and presenting a guess as a measurement is how a
/// dashboard talks someone into believing they are solvent.
class AdminSurvivalScreen extends ConsumerWidget {
  const AdminSurvivalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(survivalMetricsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Break-even & Survival')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(friendlyError(e), textAlign: TextAlign.center),
          ),
        ),
        data: (m) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(survivalMetricsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _BreakEvenHeader(m: m),
              const SizedBox(height: 14),
              if (m['assumptions_set'] != true) _AssumptionsPrompt(),
              if (m['profit_is_measured'] != true) ...[
                const SizedBox(height: 10),
                _Warning(
                  title: 'Profit per order is estimated, not measured',
                  body:
                      'No order has recorded its driver pay and processor fee, '
                      'so profit is inferred from order value instead of known. '
                      'Break-even, burn and LTV below all inherit that estimate. '
                      'They become real once orders store what was paid out.',
                ),
              ],
              const SizedBox(height: 18),
              _SectionTitle('Demand'),
              _Metric(
                label: 'Orders per day',
                value: _num(m['orders_per_day']),
                target: m['breakeven_orders'] == null
                    ? 'break-even unknown'
                    : 'break-even ${m['breakeven_orders']}',
                ok:
                    _d(m['orders_per_day']) >= _d(m['breakeven_orders']) &&
                    m['breakeven_orders'] != null,
              ),
              _Metric(
                label: 'Average order value',
                value: _money(m['aov']),
                target: 'higher is better',
                ok: null,
              ),
              _Metric(
                label: 'Orders per customer',
                value: _num(m['orders_per_customer']),
                target: 'repeat business',
                ok: null,
              ),

              const SizedBox(height: 18),
              _SectionTitle('Operations'),
              _Metric(
                label: 'Fulfilment rate',
                value: m['fulfilment_pct'] == null
                    ? '—'
                    : '${_num(m['fulfilment_pct'])}%',
                target: '95%+',
                ok: m['fulfilment_pct'] == null
                    ? null
                    : _d(m['fulfilment_pct']) >= 95,
              ),
              _Metric(
                label: 'Driver utilisation',
                value: m['driver_utilisation'] == null
                    ? '—'
                    : '${_num(m['driver_utilisation'])}/day',
                target: '8–12 per driver per day',
                ok: m['driver_utilisation'] == null
                    ? null
                    : _d(m['driver_utilisation']) >= 8 &&
                          _d(m['driver_utilisation']) <= 12,
              ),
              _Metric(
                label: 'Active drivers',
                value: '${m['active_drivers'] ?? 0}',
                target: 'last 30 days',
                ok: null,
              ),

              const SizedBox(height: 18),
              _SectionTitle('Runway'),
              _Metric(
                label: 'Burn per day',
                value: _money(m['burn_per_day']),
                target: 'revenue should exceed costs',
                ok: _d(m['burn_per_day']) <= 0,
              ),
              _Metric(
                label: 'Runway',
                value: m['runway_days'] == null
                    ? 'not burning'
                    : '${m['runway_days']} days',
                target: '90+ days',
                ok: m['runway_days'] == null
                    ? true
                    : _d(m['runway_days']) >= 90,
              ),

              const SizedBox(height: 18),
              _SectionTitle('Customer economics'),
              _Metric(
                label: 'Acquisition cost (CAC)',
                value: m['cac'] == null
                    ? 'set marketing spend'
                    : _money(m['cac']),
                target: 'lower is better',
                ok: null,
              ),
              _Metric(
                label: 'Lifetime value (LTV)',
                value: _money(m['ltv']),
                target: 'at least 3× CAC',
                ok: m['ltv_to_cac'] == null ? null : _d(m['ltv_to_cac']) >= 3,
              ),
              _Metric(
                label: 'LTV to CAC ratio',
                value: m['ltv_to_cac'] == null
                    ? '—'
                    : '${_num(m['ltv_to_cac'])}×',
                target: '3×+',
                ok: m['ltv_to_cac'] == null ? null : _d(m['ltv_to_cac']) >= 3,
              ),

              const SizedBox(height: 20),
              _AssumptionsEditor(
                current: Map<String, dynamic>.from(
                  (m['assumptions'] as Map?) ?? {},
                ),
                onSaved: () => ref.invalidate(survivalMetricsProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _d(dynamic v) => v is num ? v.toDouble() : 0.0;
  static String _num(dynamic v) => v is num ? v.toString() : '—';
  static String _money(dynamic v) => v is num
      ? '${AppConstants.currencySymbol}${v.toDouble().toStringAsFixed(2)}'
      : '—';
}

class _BreakEvenHeader extends StatelessWidget {
  const _BreakEvenHeader({required this.m});
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final be = m['breakeven_orders'];
    final perDay = AdminSurvivalScreen._d(m['orders_per_day']);
    final surviving = be != null && perDay >= AdminSurvivalScreen._d(be);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Orders per day to break even',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            be == null ? 'Set your costs' : '$be',
            style: TextStyle(
              fontSize: 40,
              height: 1.05,
              fontWeight: FontWeight.w800,
              color: be == null
                  ? scheme.onSurfaceVariant
                  : (surviving
                        ? Colors.green.shade600
                        : Colors.orange.shade700),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            be == null
                ? 'Enter your daily fixed costs below and this becomes a real number.'
                : 'Currently running ${m['orders_per_day']} per day — '
                      '${surviving ? "above break-even" : "below break-even"}.',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AssumptionsPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _Warning(
    title: 'Your costs are not entered yet',
    body:
        'Fixed costs, marketing spend and cash reserve live outside this app, '
        'so break-even, burn, runway and CAC cannot be computed until you enter '
        'them below. Everything above that line is measured from real orders.',
  );
}

class _Warning extends StatelessWidget {
  const _Warning({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade400),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Colors.orange.shade800,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: Colors.orange.shade900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.target,
    required this.ok,
  });

  final String label;
  final String value;
  final String target;

  /// null when there is no pass/fail judgement to make — an unknown is shown
  /// as unknown rather than dressed up as a pass.
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          if (ok != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(
                ok! ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 18,
                color: ok! ? Colors.green.shade600 : Colors.orange.shade700,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  target,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssumptionsEditor extends StatefulWidget {
  const _AssumptionsEditor({required this.current, required this.onSaved});

  final Map<String, dynamic> current;
  final VoidCallback onSaved;

  @override
  State<_AssumptionsEditor> createState() => _AssumptionsEditorState();
}

class _AssumptionsEditorState extends State<_AssumptionsEditor> {
  late final Map<String, TextEditingController> _c = {
    'biz_daily_fixed_costs': TextEditingController(
      text: _init('daily_fixed_costs'),
    ),
    'biz_variable_cost_order': TextEditingController(
      text: _init('variable_cost_order'),
    ),
    'biz_monthly_marketing': TextEditingController(
      text: _init('monthly_marketing'),
    ),
    'biz_cash_reserve': TextEditingController(text: _init('cash_reserve')),
  };
  bool _saving = false;

  String _init(String k) {
    final v = widget.current[k];
    return v is num && v != 0 ? v.toString() : '';
  }

  static const _labels = {
    'biz_daily_fixed_costs': 'Daily fixed costs',
    'biz_variable_cost_order': 'Extra cost per delivery',
    'biz_monthly_marketing': 'Monthly marketing spend',
    'biz_cash_reserve': 'Cash reserve',
  };

  static const _hints = {
    'biz_daily_fixed_costs':
        'Retainers, insurance, tooling — paid at zero orders',
    'biz_variable_cost_order':
        'Fuel and consumables beyond recorded driver pay',
    'biz_monthly_marketing': 'Used to compute customer acquisition cost',
    'biz_cash_reserve': 'What you can absorb losses with, for runway',
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      for (final e in _c.entries) {
        final raw = e.value.text.trim();
        final parsed = double.tryParse(raw) ?? 0;
        await client
            .from('app_config')
            .update({'value': parsed.toString()})
            .eq('key', e.key);
      }
      if (!mounted) return;
      AppSnackbar.success(context, 'Assumptions saved');
      widget.onSaved();
    } catch (err) {
      if (mounted) AppSnackbar.error(context, friendlyError(err));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your costs',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'These are assumptions, not measurements — the app cannot see your '
            'rent or your bank balance. Everything that depends on them is '
            'labelled above.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final e in _c.entries) ...[
            TextField(
              controller: e.value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _labels[e.key],
                helperText: _hints[e.key],
                helperMaxLines: 2,
                prefixText: '${AppConstants.currencySymbol} ',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save assumptions'),
            ),
          ),
        ],
      ),
    );
  }
}
