import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_constants.dart';
import '../../models/admin_metrics_model.dart';
import '../../providers/admin_metrics_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';

/// Admin operating dashboard: what the platform earned, and whether today is on
/// target.
///
/// Every figure is computed in Postgres and arrives as minor units. Nothing on
/// this screen does business arithmetic — it divides nothing, sums nothing, and
/// applies no rate. If a number looks wrong, the RPC is where it is wrong.
class AdminOperatingDashboardScreen extends ConsumerStatefulWidget {
  const AdminOperatingDashboardScreen({super.key});

  @override
  ConsumerState<AdminOperatingDashboardScreen> createState() =>
      _AdminOperatingDashboardScreenState();
}

class _AdminOperatingDashboardScreenState
    extends ConsumerState<AdminOperatingDashboardScreen> {
  Timer? _kpiTimer;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    // Two cadences, both bounded and both cancelled in dispose. The financial
    // aggregates do not change fast enough to justify 15 seconds; the target
    // card does.
    _kpiTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) ref.read(adminKpiTickProvider.notifier).state++;
    });
    _liveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.read(adminLiveTickProvider.notifier).state++;
    });
  }

  @override
  void dispose() {
    _kpiTimer?.cancel();
    _liveTimer?.cancel();
    super.dispose();
  }

  String get _sym => AppConstants.currencySymbol;

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(adminPeriodProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operating Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(adminKpiTickProvider.notifier).state++;
              ref.read(adminLiveTickProvider.notifier).state++;
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(adminKpiTickProvider.notifier).state++;
          ref.read(adminLiveTickProvider.notifier).state++;
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _PeriodSelector(
              selected: period,
              onSelected: (p) =>
                  ref.read(adminPeriodProvider.notifier).state = p,
            ),
            const SizedBox(height: 16),

            _TargetCard(vertical: 'food', label: 'Food', symbol: _sym),
            const SizedBox(height: 12),
            _TargetCard(vertical: 'grocery', label: 'Grocery', symbol: _sym),
            const SizedBox(height: 20),

            _SectionHeader('Food · ${period.label}'),
            const SizedBox(height: 8),
            _FoodCard(symbol: _sym),
            const SizedBox(height: 20),

            _SectionHeader('Grocery · ${period.label}'),
            const SizedBox(height: 8),
            _GroceryCard(symbol: _sym),
            const SizedBox(height: 20),

            _SectionHeader('Combined'),
            const SizedBox(height: 8),
            _CombinedCard(symbol: _sym),
            const SizedBox(height: 20),

            const _SectionHeader('In flight now'),
            const SizedBox(height: 8),
            const _LiveOpsCard(),
            const SizedBox(height: 20),

            _SectionHeader('Where the time goes · ${period.label}'),
            const SizedBox(height: 8),
            const _SlaAttributionCard(),
            const SizedBox(height: 20),

            _SectionHeader('Leaderboard · ${period.label}'),
            const SizedBox(height: 8),
            _LeaderboardCard(symbol: _sym),
          ],
        ),
      ),
    );
  }
}

// ── Shared chrome ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.accent});
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent ?? scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// One consistent treatment of loading / error / empty for every card, so a
/// failure never renders as a zero — which is indistinguishable from a real
/// zero on a financial dashboard.
class _AsyncCard<T> extends StatelessWidget {
  const _AsyncCard({required this.value, required this.builder, this.accent});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      accent: accent,
      child: value.when(
        loading: () => const SizedBox(
          height: 84,
          child: Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (e, _) => SizedBox(
          height: 84,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 18, color: Colors.red.shade400),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    friendlyError(e),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        data: builder,
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.emphasise = false, this.color});
  final String label;
  final String value;
  final bool emphasise;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: emphasise ? 14 : 13,
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasise ? 17 : 13.5,
              fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600,
              color: color ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Period ──────────────────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onSelected});
  final MetricsPeriod selected;
  final ValueChanged<MetricsPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        // 'Month to date' and 'Year to date' plus the custom-range button
        // overflow a 360dp screen. The presets scroll rather than being
        // abbreviated, so the labels stay readable and match the section
        // headers below, which use the same strings.
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in MetricsPeriod.presets) ...[
                  GestureDetector(
                    onTap: () => onSelected(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected.key == p.key
                            ? AppTheme.primaryColor
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        p.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected.key == p.key
                              ? Colors.white
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () async {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2025),
              lastDate: DateTime.now(),
            );
            if (range == null) return;
            onSelected(
              MetricsPeriod(
                'custom',
                'Custom',
                from: range.start,
                // End of the chosen day: the RPC range is half-open, so a
                // same-day pick would otherwise cover zero seconds.
                to: DateTime(
                  range.end.year,
                  range.end.month,
                  range.end.day,
                ).add(const Duration(days: 1)),
              ),
            );
          },
          icon: const Icon(Icons.date_range, size: 17),
          label: const Text('Custom', style: TextStyle(fontSize: 12.5)),
        ),
      ],
    );
  }
}

// ── KPI cards ───────────────────────────────────────────────────────────────

class _FoodCard extends ConsumerWidget {
  const _FoodCard({required this.symbol});
  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AsyncCard<FoodMetrics>(
      value: ref.watch(adminFoodMetricsProvider),
      builder: (m) {
        if (m.ordersCount == 0)
          return const _EmptyState('No food orders in this period');
        return Column(
          children: [
            _Metric('Orders', '${m.ordersCount}'),
            _Metric('GMV', formatMinor(m.gmv, symbol)),
            _Metric(
              'Restaurant commission',
              formatMinor(m.restaurantCommissionTotal, symbol),
            ),
            _Metric('Delivery fees', formatMinor(m.deliveryFeeTotal, symbol)),
            _Metric(
              'Rider payout',
              '-${formatMinor(m.riderPayoutTotal, symbol)}',
            ),
            const Divider(height: 18),
            _Metric(
              'Contribution',
              formatMinor(m.contributionTotal, symbol),
              emphasise: true,
              color: m.contributionTotal >= 0
                  ? const Color(0xFF12B76A)
                  : Colors.red.shade400,
            ),
            _Metric('Average order', formatMinor(m.avgOrderValue, symbol)),
            const SizedBox(height: 12),
            _BreakevenBar(m: m),
          ],
        );
      },
    );
  }
}

class _BreakevenBar extends StatelessWidget {
  const _BreakevenBar({required this.m});
  final FoodMetrics m;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (m.breakevenUnconfigured) {
      // A 0% bar would read as "failing". Unset is not failing.
      return Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Break-even needs monthly_ops_cost set in Pricing',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    final pct = (m.breakevenProgressPct / 100).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Break-even progress',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            Text(
              '${m.ordersCount} / ${m.breakevenOrdersRequired} orders',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
              pct >= 1 ? const Color(0xFF12B76A) : AppTheme.primaryColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _GroceryCard extends ConsumerWidget {
  const _GroceryCard({required this.symbol});
  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AsyncCard<GroceryMetrics>(
      value: ref.watch(adminGroceryMetricsProvider),
      builder: (m) {
        if (m.ordersCount == 0) {
          return const _EmptyState('No grocery orders in this period');
        }
        return Column(
          children: [
            _Metric('Orders', '${m.ordersCount}'),
            _Metric('GMV', formatMinor(m.gmv, symbol)),
            _Metric('Service fees', formatMinor(m.serviceFeeTotal, symbol)),
            _Metric(
              'Supermarket commission',
              formatMinor(m.supermarketCommissionTotal, symbol),
            ),
            _Metric(
              'Delivery margin',
              formatMinor(m.deliveryMarginTotal, symbol),
            ),
            const Divider(height: 18),
            _Metric(
              'Contribution',
              formatMinor(m.contributionTotal, symbol),
              emphasise: true,
              color: m.contributionTotal >= 0
                  ? const Color(0xFF12B76A)
                  : Colors.red.shade400,
            ),
            _Metric('Average order', formatMinor(m.avgOrderValue, symbol)),
          ],
        );
      },
    );
  }
}

class _CombinedCard extends ConsumerWidget {
  const _CombinedCard({required this.symbol});
  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AsyncCard<CombinedMetrics>(
      value: ref.watch(adminCombinedMetricsProvider),
      builder: (m) => Column(
        children: [
          _Metric(
            'Total contribution',
            formatMinor(m.totalContribution, symbol),
          ),
          _Metric(
            'Ops cost (prorated)',
            '-${formatMinor(m.opsCostProrated, symbol)}',
          ),
          const Divider(height: 18),
          _Metric(
            'Operating profit',
            formatMinor(m.operatingProfit, symbol),
            emphasise: true,
            color: m.operatingProfit >= 0
                ? const Color(0xFF12B76A)
                : Colors.red.shade400,
          ),
          if (m.opsCostUnconfigured) ...[
            const SizedBox(height: 8),
            Text(
              'Ops cost is unset, so profit here is contribution only.',
              style: TextStyle(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 72,
    child: Center(
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

// ── Target card ─────────────────────────────────────────────────────────────

class _TargetCard extends ConsumerWidget {
  const _TargetCard({
    required this.vertical,
    required this.label,
    required this.symbol,
  });

  final String vertical;
  final String label;
  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return _AsyncCard<DailyTarget?>(
      accent: AppTheme.primaryColor.withValues(alpha: 0.35),
      value: ref.watch(adminDailyTargetProvider(vertical)),
      builder: (t) {
        if (t == null || !t.hasTarget) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's $label target",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'No target set for today. The nightly job sets one at 00:05, '
                'or you can set it now.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () =>
                      _showOverrideDialog(context, ref, vertical, null),
                  child: const Text('Set target'),
                ),
              ),
            ],
          );
        }

        final pct = (t.progressPct / 100).clamp(0.0, 1.0);
        final paceColor = switch (t.pace) {
          PaceStatus.ahead => const Color(0xFF12B76A),
          PaceStatus.onTrack => AppTheme.primaryColor,
          PaceStatus.behind => const Color(0xFFF79009),
          PaceStatus.noTarget => scheme.onSurfaceVariant,
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  "Today's $label target",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                if (t.isOverride)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'manual',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  switch (t.pace) {
                    PaceStatus.ahead => 'Ahead',
                    PaceStatus.onTrack => 'On track',
                    PaceStatus.behind => 'Behind',
                    PaceStatus.noTarget => '',
                  },
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: paceColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${t.actualOrders}',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: paceColor,
                  ),
                ),
                Text(
                  ' / ${t.targetOrders}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  'Projected ${t.projectedEodOrders}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(paceColor),
              ),
            ),
            const SizedBox(height: 14),
            _PerOrderRow('AOV', t.aov, t.aovDelta7d, symbol),
            _PerOrderRow(
              'Gross rev / order',
              t.grossRevenuePerOrder,
              t.grossPerOrderDelta7d,
              symbol,
            ),
            _PerOrderRow(
              'Net contribution / order',
              t.netContributionPerOrder,
              t.netPerOrderDelta7d,
              symbol,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(
                  onPressed: () => _showHistory(context, ref, vertical),
                  child: const Text(
                    'View target history',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _showOverrideDialog(
                    context,
                    ref,
                    vertical,
                    t.targetOrders,
                  ),
                  child: const Text(
                    'Override',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A value with its 7-day delta. The colour is decoration; the number is the
/// point, and nothing keys off the colour.
class _PerOrderRow extends StatelessWidget {
  const _PerOrderRow(this.label, this.value, this.delta, this.symbol);
  final String label;
  final int value;
  final int delta;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final up = delta > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
          Text(
            formatMinor(value, symbol),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Text(
              delta == 0
                  ? '—'
                  : '${up ? '+' : ''}${formatMinor(delta, symbol)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: delta == 0
                    ? scheme.onSurfaceVariant
                    : (up ? const Color(0xFF12B76A) : Colors.red.shade400),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showOverrideDialog(
  BuildContext context,
  WidgetRef ref,
  String vertical,
  int? current,
) async {
  final ordersCtrl = TextEditingController(text: current?.toString() ?? '');
  final notesCtrl = TextEditingController();
  var forTomorrow = true;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: Text('Override $vertical target'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                forTomorrow ? 'Tomorrow' : 'Today',
                style: const TextStyle(fontSize: 14),
              ),
              value: forTomorrow,
              onChanged: (v) => setSt(() => forTomorrow = v),
            ),
            TextField(
              controller: ordersCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Target orders',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Why (recorded in the audit log)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'This supersedes the automatic target for that day and is kept '
              'in the change log. The previous target is not deleted.',
              style: TextStyle(fontSize: 11.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Set target'),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true || !context.mounted) return;
  final orders = int.tryParse(ordersCtrl.text.trim());
  if (orders == null || orders < 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enter a whole number of orders')),
    );
    return;
  }

  try {
    final now = DateTime.now();
    await ref
        .read(adminMetricsServiceProvider)
        .setDailyTarget(
          date: forTomorrow ? now.add(const Duration(days: 1)) : now,
          vertical: vertical,
          targetOrders: orders,
          notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        );
    if (!context.mounted) return;
    ref.invalidate(adminDailyTargetProvider(vertical));
    ref.invalidate(adminTargetHistoryProvider(vertical));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Target set')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(friendlyError(e)),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }
}

Future<void> _showHistory(
  BuildContext context,
  WidgetRef ref,
  String vertical,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Consumer(
      builder: (ctx, r, _) {
        final async = r.watch(adminTargetHistoryProvider(vertical));
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: async.when(
              loading: () => const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SizedBox(
                height: 160,
                child: Center(child: Text(friendlyError(e))),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: Text('No target history yet')),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$vertical target history',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.6,
                      ),
                      child: SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 18,
                          columns: const [
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Target')),
                            DataColumn(label: Text('Actual')),
                            DataColumn(label: Text('Hit')),
                            DataColumn(label: Text('Source')),
                          ],
                          rows: [
                            for (final r in rows)
                              DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      (r['target_date'] ?? '').toString(),
                                      style: TextStyle(
                                        decoration: r['superseded'] == true
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text('${r['target_orders'] ?? '-'}'),
                                  ),
                                  DataCell(Text('${r['actual_orders'] ?? 0}')),
                                  DataCell(
                                    Text(
                                      r['hit'] == null
                                          ? '—'
                                          : (r['hit'] == true ? 'yes' : 'no'),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      (r['source'] ?? '').toString(),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    ),
  );
}

// ── Live ops ────────────────────────────────────────────────────────────────

/// Orders in flight, grouped by status. This panel is on the 15-second tick,
/// and it is the one meant to make someone get up: an order past the last
/// threshold is already late, not about to be.
class _LiveOpsCard extends ConsumerWidget {
  const _LiveOpsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final rows = ref.watch(adminLiveOpsProvider);
    final breaching =
        rows.asData?.value.fold<int>(0, (a, r) => a + r.breachCount) ?? 0;

    return _AsyncCard<List<LiveOpsRow>>(
      value: rows,
      accent: breaching > 0 ? Colors.red.shade300 : null,
      builder: (data) {
        if (data.isEmpty) {
          return const _EmptyState('Nothing in flight right now.');
        }
        final total = data.fold<int>(0, (a, r) => a + r.ordersCount);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$total in flight',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (breaching > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$breaching past SLA',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // The bucket labels arrive from the RPC because the edges are
            // configurable. Writing "30-35" here would start lying the day
            // someone retunes the SLA.
            Text(
              'Minutes since ordered: ${data.first.bucketLabels.join('  ·  ')}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            for (final r in data) ...[
              _LiveOpsRowTile(row: r),
              if (r != data.last) const Divider(height: 18),
            ],
          ],
        );
      },
    );
  }
}

class _LiveOpsRowTile extends StatelessWidget {
  const _LiveOpsRowTile({required this.row});
  final LiveOpsRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = row.bucketCounts.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${row.ordersCount}',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'oldest ${row.oldestMinutes.round()}m',
              style: TextStyle(
                fontSize: 11.5,
                color: row.breachCount > 0
                    ? Colors.red.shade600
                    : scheme.onSurfaceVariant,
                fontWeight: row.breachCount > 0
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i <= last; i++)
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i == last ? 0 : 4),
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    // Only the final bucket is a breach; the two before it are
                    // warnings, and the rest are simply orders in progress.
                    color: row.bucketCounts[i] == 0
                        ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
                        : i == last
                        ? Colors.red.shade50
                        : i >= last - 1
                        ? Colors.orange.shade50
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${row.bucketCounts[i]}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: row.bucketCounts[i] == 0
                          ? scheme.onSurfaceVariant
                          : i == last
                          ? Colors.red.shade700
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── SLA attribution ─────────────────────────────────────────────────────────

class _SlaAttributionCard extends ConsumerWidget {
  const _SlaAttributionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return _AsyncCard<List<SlaAttributionRow>>(
      value: ref.watch(adminSlaAttributionProvider),
      builder: (data) {
        if (data.isEmpty) {
          return const _EmptyState('No completed stages in this period yet.');
        }
        final samples = data.fold<int>(0, (a, r) => a + r.sampleSize);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in data) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${r.medianMinutes.round()}m median',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (r.shareOfTimePct / 100).clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${r.shareOfTimePct.toStringAsFixed(0)}% of total time  ·  '
                'p90 ${r.p90Minutes.round()}m  ·  worst ${r.maxMinutes.round()}m'
                '  ·  n=${r.sampleSize}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              if (r != data.last) const SizedBox(height: 14),
            ],
            const SizedBox(height: 10),
            // Stage timing only started recording on 2026-09-09, so a thin
            // sample says so rather than being presented as a trend.
            if (samples < 20)
              Text(
                'Based on $samples completed '
                '${samples == 1 ? 'stage' : 'stages'} — too few to read as a '
                'trend yet.',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Leaderboards ────────────────────────────────────────────────────────────

class _LeaderboardCard extends ConsumerWidget {
  const _LeaderboardCard({required this.symbol});
  final String symbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final kind = ref.watch(adminPartnerKindProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final k in PartnerKind.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(k.label),
                    selected: k == kind,
                    onSelected: (_) =>
                        ref.read(adminPartnerKindProvider.notifier).state = k,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _AsyncCard<List<PartnerRow>>(
          value: ref.watch(adminTopPartnersProvider),
          builder: (data) {
            if (data.isEmpty) {
              return _EmptyState(
                'No ${kind.label.toLowerCase()} with orders in this period.',
              );
            }
            return Column(
              children: [
                for (var i = 0; i < data.length; i++) ...[
                  _PartnerTile(rank: i + 1, row: data[i], symbol: symbol),
                  if (i != data.length - 1)
                    Divider(height: 16, color: scheme.outlineVariant),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PartnerTile extends StatelessWidget {
  const _PartnerTile({
    required this.rank,
    required this.row,
    required this.symbol,
  });

  final int rank;
  final PartnerRow row;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Null on-time is not 0%: it means nothing in this period has been
    // delivered yet, and rendering it as zero would accuse a partner of
    // failing at something that has not happened.
    final onTime = row.onTimePct == null
        ? ''
        : '  ·  ${row.onTimePct!.toStringAsFixed(0)}% on time '
              'of ${row.deliveredCount}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.partnerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${row.ordersCount} '
                '${row.ordersCount == 1 ? 'order' : 'orders'}'
                '  ·  GMV ${formatMinor(row.gmv, symbol)}$onTime',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMinor(row.contribution, symbol),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: row.contribution < 0
                    ? Colors.red.shade600
                    : scheme.onSurface,
              ),
            ),
            Text(
              'contribution',
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}
