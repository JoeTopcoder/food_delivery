import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../config/supabase_config.dart';
import '../../../config/app_constants.dart';
import '../../../providers/admin/admin_provider.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

/// Super-admin accounting export.
///
/// Pulls a per-order financial breakdown (food + grocery) for a chosen date
/// range from `admin_accounting_rows` and lets the admin download it as a CSV
/// — one line per order with goods price, delivery fee, GCT, driver pay,
/// processor fee and platform profit — so taxes can be filed from a spreadsheet.
class AdminAccountingExportScreen extends ConsumerStatefulWidget {
  const AdminAccountingExportScreen({super.key});

  @override
  ConsumerState<AdminAccountingExportScreen> createState() =>
      _AdminAccountingExportScreenState();
}

class _AdminAccountingExportScreenState
    extends ConsumerState<AdminAccountingExportScreen> {
  late DateTime _from;
  late DateTime _to;
  bool _loading = false;
  List<Map<String, dynamic>> _rows = [];
  bool _ran = false;

  // Column order used for both the on-screen list and the CSV.
  static const _cols = <String>[
    'order_date', 'receipt', 'order_type', 'store_name', 'payment_method',
    'goods_subtotal', 'delivery_fee', 'service_fee', 'tax_gct', 'tip',
    'discount', 'total_charged', 'commission', 'restaurant_payout',
    'driver_pay', 'processor_fee', 'platform_profit',
  ];
  static const _headers = <String>[
    'Date', 'Receipt', 'Type', 'Store', 'Payment',
    'Goods Price', 'Delivery Fee', 'Service Fee', 'GCT (Tax)', 'Tip',
    'Discount', 'Total Charged', 'Commission', 'Restaurant Payout',
    'Driver Pay', 'Processor Fee', 'Platform Profit',
  ];

  String get _sym => AppConstants.currencySymbol;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day);
    _from = _to.subtract(const Duration(days: 29));
  }

  Future<void> _pick(bool isFrom) async {
    final init = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_from.isAfter(_to)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    try {
      // Inclusive of the whole 'to' day: query is [from 00:00, to+1 00:00).
      final fromTs = DateTime(_from.year, _from.month, _from.day);
      final toTs =
          DateTime(_to.year, _to.month, _to.day).add(const Duration(days: 1));
      final res = await SupabaseConfig.client.rpc(
        'admin_accounting_rows',
        params: {
          'p_from': fromTs.toUtc().toIso8601String(),
          'p_to': toTs.toUtc().toIso8601String(),
        },
      );
      final rows = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _rows = rows;
        _ran = true;
      });
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _n(Map r, String k) => (r[k] as num?)?.toDouble() ?? 0;

  String _csvField(Object? v) {
    final s = (v ?? '').toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  String _buildCsv() {
    final b = StringBuffer();
    b.writeln(_headers.map(_csvField).join(','));
    for (final r in _rows) {
      final cells = _cols.map((c) {
        final v = r[c];
        if (c == 'order_date' && v != null) {
          final dt = DateTime.tryParse(v.toString())?.toLocal();
          return _csvField(dt == null
              ? v
              : '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}');
        }
        if (v is num) return v.toStringAsFixed(2);
        return _csvField(v);
      });
      b.writeln(cells.join(','));
    }
    // Totals row.
    b.writeln([
      'TOTALS', '', '', '', '',
      for (final c in _cols.sublist(5)) _rows.fold<double>(0, (s, r) => s + _n(r, c)).toStringAsFixed(2),
    ].join(','));
    return b.toString();
  }

  Future<void> _export() async {
    if (_rows.isEmpty) {
      AppSnackbar.info(context, 'Nothing to export for this range.');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      String d(DateTime x) =>
          '${x.year}${x.month.toString().padLeft(2, '0')}${x.day.toString().padLeft(2, '0')}';
      final file = File('${dir.path}/HotBite-Accounting-${d(_from)}-${d(_to)}.csv');
      await file.writeAsString(_buildCsv());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'HotBite Accounting ${d(_from)}–${d(_to)}',
          text:
              'HotBite sales & accounting — ${_rows.length} orders, ${d(_from)} to ${d(_to)}.',
        ),
      );
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuper = ref.watch(adminIsSuperAdminProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounting Export')),
      body: isSuper.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not verify access.')),
        data: (ok) => ok ? _body() : _denied(),
      ),
    );
  }

  Widget _denied() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Super-admin access is required to view company financials.',
            textAlign: TextAlign.center,
          ),
        ),
      );

  Widget _body() {
    final scheme = Theme.of(context).colorScheme;
    String fmtDate(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _dateBtn('From', fmtDate(_from), () => _pick(true)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dateBtn('To', fmtDate(_to), () => _pick(false)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in const [
                    ['Today', 0],
                    ['7 days', 6],
                    ['30 days', 29],
                    ['90 days', 89],
                  ])
                    OutlinedButton(
                      onPressed: () {
                        final now = DateTime.now();
                        setState(() {
                          _to = DateTime(now.year, now.month, now.day);
                          _from = _to.subtract(Duration(days: q[1] as int));
                        });
                      },
                      child: Text(q[0] as String),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _run,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.assessment_rounded),
                  label: Text(_loading ? 'Loading…' : 'Generate report'),
                ),
              ),
            ],
          ),
        ),
        if (_ran) _summary(scheme),
        const Divider(height: 1),
        Expanded(child: _list(scheme)),
        if (_rows.isNotEmpty)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor),
                  onPressed: _export,
                  icon: const Icon(Icons.download_rounded),
                  label: Text('Download CSV (${_rows.length} orders)'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dateBtn(String label, String value, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _summary(ColorScheme scheme) {
    double sum(String k) => _rows.fold(0, (s, r) => s + _n(r, k));
    final cards = <List<String>>[
      ['Orders', '${_rows.length}'],
      ['Total Sales', '$_sym${sum('total_charged').toStringAsFixed(2)}'],
      ['GCT (Tax)', '$_sym${sum('tax_gct').toStringAsFixed(2)}'],
      ['Driver Pay', '$_sym${sum('driver_pay').toStringAsFixed(2)}'],
      ['Platform Profit', '$_sym${sum('platform_profit').toStringAsFixed(2)}'],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in cards)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c[0],
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  Text(c[1],
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _list(ColorScheme scheme) {
    if (!_ran) {
      return const Center(
        child: Text('Pick a date range and generate the report.'),
      );
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('No delivered orders in this range.'));
    }
    return ListView.separated(
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = _rows[i];
        final dt = DateTime.tryParse('${r['order_date']}')?.toLocal();
        final isGrocery = r['order_type'] == 'grocery';
        final profit = _n(r, 'platform_profit');
        return ListTile(
          dense: true,
          leading: Icon(
            isGrocery ? Icons.local_grocery_store_rounded : Icons.restaurant_rounded,
            color: isGrocery ? Colors.purple : AppTheme.primaryColor,
          ),
          title: Text('${r['store_name']}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${dt == null ? '' : '${dt.day}/${dt.month}/${dt.year}'} · '
            '${r['payment_method']} · Goods $_sym${_n(r, 'goods_subtotal').toStringAsFixed(0)} · '
            'Deliv $_sym${_n(r, 'delivery_fee').toStringAsFixed(0)} · '
            'Driver $_sym${_n(r, 'driver_pay').toStringAsFixed(0)} · '
            'Tax $_sym${_n(r, 'tax_gct').toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 11.5),
          ),
          trailing: Text(
            '$_sym${profit.toStringAsFixed(0)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: profit >= 0 ? Colors.green[700] : Colors.red,
            ),
          ),
        );
      },
    );
  }
}
